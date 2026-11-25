group_id          = "g09"
scenario          = "pedidos-ecommerce"
business_question = "Qual foi o valor bruto de vendas por dia e por status dos pedidos?"
grain             = "Uma linha representa um pedido consolidado com um único tipo de item; order_id é a chave natural."

schema_columns = [
  { name = "order_id", type = "string", comment = "Chave natural sintética do pedido" },
  { name = "customer_id", type = "string", comment = "Identificador sintético do cliente, sem PII" },
  { name = "order_timestamp", type = "timestamp", comment = "Data e hora de criação do pedido" },
  { name = "status", type = "string", comment = "Estado atual normalizado do pedido" },
  { name = "quantity", type = "int", comment = "Quantidade de unidades do item no pedido" },
  { name = "unit_price", type = "decimal(10,2)", comment = "Preço unitário em reais" },
  { name = "city", type = "string", comment = "Cidade de destino sem endereço detalhado" },
  { name = "state", type = "string", comment = "UF de destino" },
]

csv_delimiter  = ","
csv_has_header = true

source_objects = {
  pedidos = {
    source       = "../dados/pedidos.csv"
    key          = "trusted/pedidos.csv"
    content_type = "text/csv"
  }
}

athena_bytes_scanned_cutoff = 10485760
extra_tags                  = {}
