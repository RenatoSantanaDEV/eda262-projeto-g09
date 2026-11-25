#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import random
import shutil
from dataclasses import dataclass
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Any

STATUSES = ("pending", "paid", "shipped", "delivered", "cancelled")
STATUS_WEIGHTS = (5, 25, 25, 40, 5)
CITIES = (
    ("Recife", "PE"),
    ("Olinda", "PE"),
    ("Jaboatao dos Guararapes", "PE"),
    ("Caruaru", "PE"),
    ("Paulista", "PE"),
    ("Joao Pessoa", "PB"),
    ("Maceio", "AL"),
    ("Natal", "RN"),
)
VALID_STATES = {state for _, state in CITIES}
BACKFILL_DATE = dt.date(2026, 9, 15)


@dataclass
class Counters:
    base_orders: int = 0
    base_items: int = 0
    emitted_events: int = 0
    duplicate_events: int = 0
    invalid_events: int = 0
    normalizable_events: int = 0
    bytes_written: int = 0


def parse_timestamp(value: Any) -> dt.datetime | None:
    if not isinstance(value, str):
        return None
    try:
        return dt.datetime.strptime(value.strip(), "%Y-%m-%dT%H:%M:%SZ").replace(
            tzinfo=dt.timezone.utc,
        )
    except ValueError:
        return None


def normalize_reference(event: dict[str, Any]) -> dict[str, Any] | None:
    clean = {
        "order_id": str(event.get("order_id") or "").strip(),
        "order_item_id": str(event.get("order_item_id") or "").strip(),
        "customer_id": str(event.get("customer_id") or "").strip(),
        "status": str(event.get("status") or "").strip().lower(),
        "city": str(event.get("city") or "").strip(),
        "state": str(event.get("state") or "").strip().upper(),
    }
    order_ts = parse_timestamp(event.get("order_timestamp"))
    updated_at = parse_timestamp(event.get("updated_at"))
    try:
        quantity = int(str(event.get("quantity") or "").strip())
        price = Decimal(str(event.get("unit_price") or "").strip().replace(",", "."))
    except (InvalidOperation, ValueError):
        return None

    if (
        not clean["order_id"]
        or not clean["order_item_id"]
        or not clean["customer_id"]
        or not clean["city"]
        or clean["state"] not in VALID_STATES
        or clean["status"] not in STATUSES
        or order_ts is None
        or updated_at is None
        or quantity <= 0
        or price <= 0
    ):
        return None

    clean.update(
        {
            "order_timestamp": order_ts,
            "updated_at": updated_at,
            "quantity": quantity,
            "unit_price": price.quantize(Decimal("0.01")),
            "order_date": order_ts.date().isoformat(),
        },
    )
    return clean


def corrupt(event: dict[str, Any], item_number: int) -> tuple[dict[str, Any], bool]:
    dirty = dict(event)
    invalid = False
    if item_number % 31 == 0:
        dirty["status"] = f" {str(dirty['status']).upper()} "
        dirty["city"] = f" {dirty['city']} "
        dirty["state"] = str(dirty["state"]).lower()
    if item_number % 37 == 0:
        dirty["unit_price"] = str(dirty["unit_price"]).replace(".", ",")
    if item_number % 53 == 0:
        dirty["status"] = "payment_unknown"
        invalid = True
    if item_number % 71 == 0:
        dirty["quantity"] = "0"
        invalid = True
    if item_number % 89 == 0:
        dirty["unit_price"] = "-1.00"
        invalid = True
    if item_number % 113 == 0:
        dirty["order_timestamp"] = "31/09/2026 25:61"
        invalid = True
    if item_number % 127 == 0:
        dirty["customer_id"] = ""
        invalid = True
    return dirty, invalid


def generate(
    output: Path,
    start_date: dt.date,
    days: int,
    orders_per_day: int,
    seed: int,
) -> dict[str, Any]:
    resolved_output = output.resolve()
    if resolved_output in {Path("/").resolve(), Path.home().resolve()}:
        raise ValueError("--output não pode ser a raiz nem o diretório pessoal")
    marker = output / ".eda262-generated-data"
    if output.exists() and any(output.iterdir()) and not marker.exists():
        raise ValueError(
            "--output não está vazio e não foi criado por este gerador; recusei apagar",
        )
    output.mkdir(parents=True, exist_ok=True)
    generated_raw = output / "raw"
    if generated_raw.exists():
        shutil.rmtree(generated_raw)
    summary_path = output / "generation-summary.json"
    if summary_path.exists():
        summary_path.unlink()
    marker.write_text("eda262-g09-av2\n", encoding="utf-8")

    rnd = random.Random(seed)
    counters = Counters()
    latest_valid: dict[tuple[str, str], tuple[dt.datetime, dict[str, Any]]] = {}
    arrival_handles: dict[str, Any] = {}
    arrival_counts: dict[str, int] = {}
    rejected_by_date: dict[str, int] = {}

    def emit(event: dict[str, Any], arrival_date: dt.date) -> None:
        arrival = arrival_date.isoformat()
        folder = output / "raw" / "orders" / f"arrival_date={arrival}"
        folder.mkdir(parents=True, exist_ok=True)
        if arrival not in arrival_handles:
            arrival_handles[arrival] = (folder / "orders.ndjson").open(
                "w",
                encoding="utf-8",
                newline="\n",
            )
        line = json.dumps(event, ensure_ascii=True, separators=(",", ":")) + "\n"
        arrival_handles[arrival].write(line)
        counters.emitted_events += 1
        counters.bytes_written += len(line.encode("utf-8"))
        arrival_counts[arrival] = arrival_counts.get(arrival, 0) + 1

        normalized = normalize_reference(event)
        if normalized is None:
            counters.invalid_events += 1
            event_date = str(event.get("order_timestamp", "invalid"))[:10]
            rejected_by_date[event_date] = rejected_by_date.get(event_date, 0) + 1
            return
        key = (normalized["order_id"], normalized["order_item_id"])
        previous = latest_valid.get(key)
        if previous is None or normalized["updated_at"] > previous[0]:
            latest_valid[key] = (normalized["updated_at"], normalized)

    item_number = 0
    order_number = 0
    try:
        for offset in range(days):
            order_date = start_date + dt.timedelta(days=offset)
            for _ in range(orders_per_day):
                order_number += 1
                counters.base_orders += 1
                order_id = f"ORD-{order_number:09d}"
                customer_id = f"CUS-{rnd.randrange(1, 50001):06d}"
                second = rnd.randrange(86400)
                created_at = dt.datetime.combine(
                    order_date,
                    dt.time(),
                    tzinfo=dt.timezone.utc,
                ) + dt.timedelta(seconds=second)
                status = rnd.choices(STATUSES, weights=STATUS_WEIGHTS, k=1)[0]
                city, state = rnd.choice(CITIES)
                item_count = rnd.choices((1, 2, 3), weights=(55, 35, 10), k=1)[0]

                for item_id in range(1, item_count + 1):
                    item_number += 1
                    counters.base_items += 1
                    quantity = rnd.randint(1, 5)
                    cents = rnd.randint(500, 200000)
                    updated_at = created_at + dt.timedelta(minutes=rnd.randint(1, 720))
                    event: dict[str, Any] = {
                        "order_id": order_id,
                        "order_item_id": f"ITEM-{item_id:02d}",
                        "customer_id": customer_id,
                        "order_timestamp": created_at.strftime("%Y-%m-%dT%H:%M:%SZ"),
                        "status": status,
                        "quantity": str(quantity),
                        "unit_price": f"{cents / 100:.2f}",
                        "city": city,
                        "state": state,
                        "updated_at": updated_at.strftime("%Y-%m-%dT%H:%M:%SZ"),
                    }
                    event, _ = corrupt(event, item_number)
                    if item_number % 31 == 0 or item_number % 37 == 0:
                        counters.normalizable_events += 1

                    delay = rnd.choices((0, 1, 2), weights=(92, 6, 2), k=1)[0]
                    if order_date == BACKFILL_DATE and item_number % 29 == 0:
                        delay = 5
                    arrival_date = order_date + dt.timedelta(days=delay)
                    emit(event, arrival_date)

                    if item_number % 97 == 0:
                        duplicate = dict(event)
                        parsed_updated = parse_timestamp(duplicate.get("updated_at"))
                        if parsed_updated is not None:
                            duplicate["updated_at"] = (
                                parsed_updated + dt.timedelta(hours=1)
                            ).strftime("%Y-%m-%dT%H:%M:%SZ")
                        emit(duplicate, arrival_date + dt.timedelta(days=1))
                        counters.duplicate_events += 1

    finally:
        for handle in arrival_handles.values():
            handle.close()

    valid_events = counters.emitted_events - counters.invalid_events
    trusted_rows = len(latest_valid)
    refined_groups = {
        (row[1]["order_date"], row[1]["status"]) for row in latest_valid.values()
    }
    gross = sum(
        row[1]["unit_price"] * row[1]["quantity"] for row in latest_valid.values()
    )
    summary: dict[str, Any] = {
        "generator_version": 2,
        "generator_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "seed": seed,
        "start_date": start_date.isoformat(),
        "days": days,
        "orders_per_day": orders_per_day,
        "backfill_date": BACKFILL_DATE.isoformat(),
        "base_orders": counters.base_orders,
        "base_items": counters.base_items,
        "raw_events": counters.emitted_events,
        "raw_bytes": counters.bytes_written,
        "arrival_partitions": len(arrival_counts),
        "duplicate_events": counters.duplicate_events,
        "invalid_events": counters.invalid_events,
        "normalizable_events": counters.normalizable_events,
        "expected_valid_events_before_dedup": valid_events,
        "expected_duplicates_removed": valid_events - trusted_rows,
        "expected_trusted_rows": trusted_rows,
        "expected_refined_groups": len(refined_groups),
        "expected_gross_sales": f"{gross:.2f}",
        "arrival_counts": dict(sorted(arrival_counts.items())),
        "rejected_by_event_date_prefix": dict(sorted(rejected_by_date.items())),
    }
    summary_path.write_text(
        json.dumps(summary, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return summary


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Gera uma raw determinística de pedidos sem PII",
    )
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--start-date", type=dt.date.fromisoformat, default=dt.date(2026, 9, 1))
    parser.add_argument("--days", type=int, default=30)
    parser.add_argument("--orders-per-day", type=int, default=4000)
    parser.add_argument("--seed", type=int, default=20261118)
    args = parser.parse_args()
    if args.days < 1 or args.orders_per_day < 1:
        parser.error("--days e --orders-per-day devem ser positivos")
    summary = generate(args.output, args.start_date, args.days, args.orders_per_day, args.seed)
    print(json.dumps(summary, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

