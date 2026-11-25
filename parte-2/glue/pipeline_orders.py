from __future__ import annotations

import hashlib
import json
import sys
from datetime import date, datetime, timezone

from pyspark.sql import Window
from pyspark.sql import functions as F
from pyspark.sql import types as T

RAW_SCHEMA = T.StructType(
    [
        T.StructField("order_id", T.StringType()),
        T.StructField("order_item_id", T.StringType()),
        T.StructField("customer_id", T.StringType()),
        T.StructField("order_timestamp", T.StringType()),
        T.StructField("status", T.StringType()),
        T.StructField("quantity", T.StringType()),
        T.StructField("unit_price", T.StringType()),
        T.StructField("city", T.StringType()),
        T.StructField("state", T.StringType()),
        T.StructField("updated_at", T.StringType()),
    ],
)


def normalize(raw):
    order_timestamp = F.to_timestamp(F.trim("order_timestamp"), "yyyy-MM-dd'T'HH:mm:ss'Z'")
    updated_at = F.to_timestamp(F.trim("updated_at"), "yyyy-MM-dd'T'HH:mm:ss'Z'")
    quantity = F.trim("quantity").cast("int")
    unit_price = F.regexp_replace(F.trim("unit_price"), ",", ".").cast(T.DecimalType(10, 2))
    status = F.lower(F.trim("status"))
    state = F.upper(F.trim("state"))

    normalized = raw.select(
        F.trim("order_id").alias("order_id"),
        F.trim("order_item_id").alias("order_item_id"),
        F.trim("customer_id").alias("customer_id"),
        order_timestamp.alias("order_timestamp"),
        status.alias("status"),
        quantity.alias("quantity"),
        unit_price.alias("unit_price"),
        F.trim("city").alias("city"),
        state.alias("state"),
        updated_at.alias("updated_at"),
        F.col("arrival_date").cast("string").alias("arrival_date"),
        F.date_format(order_timestamp, "yyyy-MM-dd").alias("order_date"),
    )

    return normalized


def split_valid(normalized):
    valid_statuses = ["pending", "paid", "shipped", "delivered", "cancelled"]
    valid_states = [
        "AC",
        "AL",
        "AP",
        "AM",
        "BA",
        "CE",
        "DF",
        "ES",
        "GO",
        "MA",
        "MT",
        "MS",
        "MG",
        "PA",
        "PB",
        "PR",
        "PE",
        "PI",
        "RJ",
        "RN",
        "RS",
        "RO",
        "RR",
        "SC",
        "SP",
        "SE",
        "TO",
    ]
    valid = F.coalesce(
        F.col("order_id").isNotNull()
        & (F.length("order_id") > 0)
        & F.col("order_item_id").isNotNull()
        & (F.length("order_item_id") > 0)
        & F.col("customer_id").isNotNull()
        & (F.length("customer_id") > 0)
        & F.col("order_timestamp").isNotNull()
        & F.col("updated_at").isNotNull()
        & F.col("status").isNotNull()
        & F.col("status").isin(valid_statuses)
        & F.col("quantity").isNotNull()
        & (F.col("quantity") > 0)
        & F.col("unit_price").isNotNull()
        & (F.col("unit_price") > 0)
        & F.col("city").isNotNull()
        & (F.length("city") > 0)
        & F.col("state").isNotNull()
        & F.col("state").isin(valid_states),
        F.lit(False),
    )

    return normalized.filter(valid), normalized.filter(~valid)


def deduplicate(clean):
    dedup_source = clean.withColumn(
        "_row_fingerprint",
        F.sha2(
            F.to_json(
                F.struct(
                    "order_id",
                    "order_item_id",
                    "customer_id",
                    "order_timestamp",
                    "status",
                    "quantity",
                    "unit_price",
                    "city",
                    "state",
                    "updated_at",
                    "arrival_date",
                    "order_date",
                ),
            ),
            256,
        ),
    )
    window = Window.partitionBy("order_id", "order_item_id").orderBy(
        F.col("updated_at").desc(),
        F.col("arrival_date").desc(),
        F.col("_row_fingerprint").desc(),
    )
    trusted = (
        dedup_source.withColumn("_row_number", F.row_number().over(window))
        .filter(F.col("_row_number") == 1)
        .drop("_row_number", "_row_fingerprint")
    )
    return trusted


def aggregate(trusted):
    refined = (
        trusted.groupBy("order_date", "status")
        .agg(
            F.countDistinct("order_id").cast("long").alias("order_count"),
            F.count(F.lit(1)).cast("long").alias("item_count"),
            F.sum("quantity").cast("long").alias("quantity_total"),
            F.sum(F.col("quantity") * F.col("unit_price"))
            .cast(T.DecimalType(18, 2))
            .alias("gross_sales"),
        )
    )
    return refined


def validate_selection(mode, days):
    if mode not in {"FULL", "BACKFILL"}:
        raise ValueError("--MODE deve ser FULL ou BACKFILL")
    if mode == "FULL":
        if days != ["all"]:
            raise ValueError("FULL exige --DAYS=all")
    else:
        if not days or len(days) != len(set(days)):
            raise ValueError("BACKFILL exige datas distintas")
        for day in days:
            if date.fromisoformat(day).isoformat() != day:
                raise ValueError("BACKFILL exige datas AAAA-MM-DD válidas")


def select_days(frame, mode, days):
    return frame.filter(F.col("order_date").isin(days)) if mode == "BACKFILL" else frame


def content_digest(frame):
    rows = frame.select(F.sha2(F.to_json(F.struct(*sorted(frame.columns))), 256).alias("hash"))
    digest = hashlib.sha256()
    for row in rows.orderBy("hash").toLocalIterator():
        digest.update((row.hash + "\n").encode("ascii"))
    return digest.hexdigest()


def write_quarantine(rejected, path):
    rejected.write.mode("overwrite").parquet(path)


def run(spark, args, s3):
    mode = args["MODE"].upper()
    days = [day.strip() for day in args["DAYS"].split(",") if day.strip()]
    validate_selection(mode, days)
    spark.conf.set("spark.sql.session.timeZone", "UTC")
    spark.conf.set("spark.sql.sources.partitionOverwriteMode", "dynamic")
    spark.conf.set("spark.sql.sources.partitionColumnTypeInference.enabled", "false")
    spark.conf.set("spark.sql.legacy.timeParserPolicy", "CORRECTED")
    raw_root = f"s3://{args['RAW_BUCKET']}/orders/"
    trusted_root = f"s3://{args['TRUSTED_BUCKET']}/orders/"
    refined_root = f"s3://{args['REFINED_BUCKET']}/daily_sales/"
    raw = spark.read.option("basePath", raw_root).schema(RAW_SCHEMA).json(f"{raw_root}arrival_date=*/").persist()
    normalized = normalize(raw)
    clean, rejected_all = split_valid(normalized)
    unscoped_rejected = rejected_all.filter(F.col("order_date").isNull()).count()
    clean = select_days(clean, mode, days).persist()
    rejected = select_days(rejected_all, mode, days).persist()
    trusted = deduplicate(clean).persist()
    written_days = sorted(row.order_date for row in trusted.select("order_date").distinct().collect())
    if not written_days:
        raise ValueError("Nenhuma linha válida selecionada; destinos preservados e execução não aprovada")
    if mode == "BACKFILL" and set(written_days) != set(days):
        raise ValueError("BACKFILL contém dia sem linhas válidas; destinos preservados")
    overwrite_mode = "static" if mode == "FULL" else "dynamic"
    trusted.repartition("order_date").write.mode("overwrite").option("partitionOverwriteMode", overwrite_mode).partitionBy("order_date").parquet(trusted_root)
    refined = aggregate(trusted).persist()
    refined.repartition("order_date").write.mode("overwrite").option("partitionOverwriteMode", overwrite_mode).partitionBy("order_date").parquet(refined_root)
    rejected_path = f"s3://{args['RAW_BUCKET']}/quality/rejected/mode={mode.lower()}/"
    write_quarantine(rejected, rejected_path)
    trusted_after = spark.read.parquet(trusted_root)
    refined_after = spark.read.parquet(refined_root)
    before_dedup = clean.count()
    trusted_count = trusted.count()
    report = {
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "job_run_id": args["JOB_RUN_ID"],
        "code_sha256": args["CODE_SHA256"],
        "mode": mode,
        "requested_days": days,
        "raw_rows_read": raw.count(),
        "valid_rows_before_dedup_selected": before_dedup,
        "duplicates_removed_selected": before_dedup - trusted_count,
        "rejected_rows_selected": rejected.count(),
        "rejected_rows_without_order_date": unscoped_rejected,
        "trusted_rows_written": trusted_count,
        "partitions_written": len(written_days),
        "written_days": written_days,
        "refined_groups_written": refined.count(),
        "trusted_rows_after_run": trusted_after.count(),
        "trusted_distinct_keys_after_run": trusted_after.select("order_id", "order_item_id").distinct().count(),
        "refined_groups_after_run": refined_after.count(),
        "content_sha256": {
            "trusted": content_digest(trusted_after),
            "refined": content_digest(refined_after),
            "quarantine_selected": content_digest(rejected),
        },
    }
    report_body = (json.dumps(report, indent=2, sort_keys=True) + "\n").encode("utf-8")
    print(report_body.decode("utf-8"))
    s3.put_object(Bucket=args["REPORT_BUCKET"], Key=f"reports/runs/{args['JOB_RUN_ID']}.json", Body=report_body, ContentType="application/json", ServerSideEncryption="AES256")
    for frame in (raw, clean, rejected, trusted, refined):
        frame.unpersist()
    return report


def main():
    import boto3
    from awsglue.context import GlueContext
    from awsglue.utils import getResolvedOptions
    from pyspark.context import SparkContext

    args = getResolvedOptions(sys.argv, ["RAW_BUCKET", "TRUSTED_BUCKET", "REFINED_BUCKET", "REPORT_BUCKET", "CODE_SHA256", "MODE", "DAYS"])
    if not args.get("JOB_RUN_ID"):
        raise ValueError("Glue não forneceu JOB_RUN_ID")
    spark = GlueContext(SparkContext.getOrCreate()).spark_session
    run(spark, args, boto3.client("s3"))


if __name__ == "__main__":
    main()
