SELECT
  order_date,
  status,
  order_count,
  item_count,
  quantity_total,
  gross_sales
FROM "eda262_g09_av2"."refined_daily_sales"
WHERE order_date BETWEEN '2026-09-01' AND '2026-09-30'
ORDER BY order_date, status;


