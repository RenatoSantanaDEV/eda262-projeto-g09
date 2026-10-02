-- Pergunta: Qual foi o valor bruto de vendas por dia e por status dos pedidos?
-- O resultado inclui todos os status, inclusive cancelled, para não esconder
-- valores associados a pedidos posteriormente cancelados.

SELECT
  CAST(order_timestamp AS DATE) AS order_date,
  status,
  CAST(
    SUM(CAST(quantity AS DECIMAL(10, 0)) * unit_price)
    AS DECIMAL(18, 2)
  ) AS gross_sales
FROM "eda262_g09_pedidos_ecommerce_catalog"."trusted"
GROUP BY
  CAST(order_timestamp AS DATE),
  status
ORDER BY
  order_date,
  status;
