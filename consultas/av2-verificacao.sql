SELECT
  COUNT(*) AS trusted_rows,
  COUNT(DISTINCT CONCAT(order_id, '#', order_item_id)) AS distinct_keys,
  COUNT(DISTINCT order_date) AS partitions,
  CAST(SUM(quantity * unit_price) AS DECIMAL(18, 2)) AS gross_sales
FROM "eda262_g09_av2"."trusted_orders"
WHERE order_date BETWEEN '2026-09-01' AND '2026-09-30';


