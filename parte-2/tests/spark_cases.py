from __future__ import annotations

import importlib.util
import tempfile
import unittest
from decimal import Decimal
from pathlib import Path

from pyspark.sql import SparkSession, functions as F, types as T

SPEC = importlib.util.spec_from_file_location("pipeline_orders", Path(__file__).parents[1] / "glue/pipeline_orders.py")
pipeline = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(pipeline)


class SparkPipelineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.spark = SparkSession.builder.master("local[2]").appName("av2-regression").config("spark.ui.enabled", "false").config("spark.sql.shuffle.partitions", "2").config("spark.sql.session.timeZone", "UTC").config("spark.sql.legacy.timeParserPolicy", "CORRECTED").getOrCreate()
        cls.spark.sparkContext.setLogLevel("ERROR")

    @classmethod
    def tearDownClass(cls):
        cls.spark.stop()

    def frame(self, changes):
        base = dict(order_id=" o1 ", order_item_id=" i1 ", customer_id=" c1 ", order_timestamp="2026-09-15T12:00:00Z", status=" PAID ", quantity="2", unit_price="10,25", city=" Recife ", state=" pe ", updated_at="2026-09-15T13:00:00Z", arrival_date="2026-09-16")
        schema = T.StructType([*pipeline.RAW_SCHEMA.fields, T.StructField("arrival_date", T.StringType())])
        return self.spark.createDataFrame([{**base, **change} for change in changes], schema)

    def test_normalization_and_decimal_aggregation(self):
        normalized = pipeline.normalize(self.frame([{}, {"order_item_id": "i2", "unit_price": "0.10", "quantity": "3"}]))
        clean, rejected = pipeline.split_valid(normalized)
        self.assertEqual(rejected.count(), 0)
        row = clean.first()
        self.assertEqual((row.order_id, row.city, row.state, row.status), ("o1", "Recife", "PE", "paid"))
        totals = pipeline.aggregate(clean).first()
        self.assertEqual((totals.order_count, totals.item_count, totals.quantity_total, totals.gross_sales), (1, 2, 5, Decimal("20.80")))

    def test_invalid_and_null_values_go_to_quarantine(self):
        changes = [{"order_id": None}, {"customer_id": " "}, {"status": "wrong"}, {"state": "XX"}, {"quantity": "0"}, {"unit_price": "-1"}, {"order_timestamp": "bad"}, {"updated_at": "2026-02-30T12:00:00Z"}, {"city": ""}]
        clean, rejected = pipeline.split_valid(pipeline.normalize(self.frame(changes)))
        self.assertEqual(clean.count(), 0)
        self.assertEqual(rejected.count(), len(changes))

    def test_latest_update_wins_before_arrival(self):
        rows = pipeline.normalize(self.frame([{}, {"updated_at": "2026-09-15T14:00:00Z", "arrival_date": "2026-09-15", "status": "shipped"}]))
        self.assertEqual(pipeline.deduplicate(rows).first().status, "shipped")

    def test_latest_arrival_breaks_timestamp_tie(self):
        rows = pipeline.normalize(self.frame([{}, {"arrival_date": "2026-09-17", "status": "shipped"}]))
        self.assertEqual(pipeline.deduplicate(rows).first().status, "shipped")

    def test_hash_tie_break_is_independent_of_input_order(self):
        rows = pipeline.normalize(self.frame([{}, {"status": "shipped"}, {}]))
        a = pipeline.deduplicate(rows.repartition(1)).collect()
        b = pipeline.deduplicate(rows.orderBy(F.desc("status")).repartition(2)).collect()
        self.assertEqual(a, b)
        self.assertEqual(len(a), 1)

    def test_backfill_excludes_other_dates_and_reports_unscoped_rejections(self):
        rows = pipeline.normalize(self.frame([{}, {"order_timestamp": "2026-09-16T12:00:00Z"}, {"order_timestamp": "bad"}]))
        clean, rejected = pipeline.split_valid(rows)
        self.assertEqual(pipeline.select_days(clean, "BACKFILL", ["2026-09-15"]).count(), 1)
        self.assertEqual(pipeline.select_days(rejected, "BACKFILL", ["2026-09-15"]).count(), 0)
        self.assertEqual(rejected.filter(F.col("order_date").isNull()).count(), 1)

    def test_empty_quarantine_replaces_previous_rejections(self):
        _, rejected = pipeline.split_valid(pipeline.normalize(self.frame([{"status": "bad"}])))
        with tempfile.TemporaryDirectory() as tmp:
            path = str(Path(tmp) / "rejected")
            pipeline.write_quarantine(rejected, path)
            self.assertEqual(self.spark.read.parquet(path).count(), 1)
            pipeline.write_quarantine(rejected.limit(0), path)
            self.assertEqual(self.spark.read.parquet(path).count(), 0)

    def test_content_digest_ignores_order_but_detects_changed_rows_and_duplicates(self):
        rows = pipeline.normalize(self.frame([{}, {"order_item_id": "i2"}]))
        digest = pipeline.content_digest(rows)
        self.assertEqual(digest, pipeline.content_digest(rows.orderBy(F.desc("order_item_id")).repartition(2)))
        self.assertNotEqual(digest, pipeline.content_digest(rows.withColumn("status", F.lit("shipped"))))
        self.assertNotEqual(digest, pipeline.content_digest(rows.union(rows.limit(1))))

    def test_backfill_write_preserves_unselected_partition(self):
        rows = pipeline.normalize(self.frame([{}, {"order_timestamp": "2026-09-16T12:00:00Z", "order_item_id": "i2"}]))
        with tempfile.TemporaryDirectory() as tmp:
            path = str(Path(tmp) / "trusted")
            rows.write.partitionBy("order_date").parquet(path)
            unaffected = {p.name: p.read_bytes() for p in (Path(path) / "order_date=2026-09-16").iterdir()}
            pipeline.select_days(rows, "BACKFILL", ["2026-09-15"]).withColumn("status", F.lit("shipped")).write.mode("overwrite").option("partitionOverwriteMode", "dynamic").partitionBy("order_date").parquet(path)
            self.assertEqual(unaffected, {p.name: p.read_bytes() for p in (Path(path) / "order_date=2026-09-16").iterdir()})
            self.assertEqual(self.spark.read.parquet(path).filter("status = 'shipped'").count(), 1)

    def test_selection_rejects_invalid_dates_and_modes(self):
        for mode, days in [("OTHER", ["all"]), ("FULL", ["2026-09-15"]), ("BACKFILL", []), ("BACKFILL", ["2026-02-30"]), ("BACKFILL", ["2026-09-15", "2026-09-15"])]:
            with self.subTest(mode=mode, days=days), self.assertRaises(ValueError):
                pipeline.validate_selection(mode, days)
        pipeline.validate_selection("BACKFILL", ["2026-09-15"])
        pipeline.validate_selection("FULL", ["all"])


if __name__ == "__main__":
    unittest.main()
