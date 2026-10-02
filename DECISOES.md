# Decisões de Engenharia — AV1 — g09

As medições locais abaixo são reproduzíveis sobre os arquivos versionados. As
medições AWS permanecem explicitamente pendentes até um deploy autorizado.

## Identificação

- Grupo: **g09**
- Representante: **Renato Santana**
- Integrantes: **João Augusto Pimentel, Renato Santana, Raphael Barros e Lara
  Pessoa**
- Cenário: **pedidos de e-commerce**
- Pergunta: **Qual foi o valor bruto de vendas por dia e por status dos pedidos?**
- Região obrigatória: **N. Virginia (`us-east-1`)**

## Grão e chave

Uma linha representa **um pedido consolidado com um único tipo de item**. Essa
restrição deixa `quantity * unit_price` semanticamente consistente com o valor
bruto do pedido.

- Chave natural: `order_id`.
- Linhas no arquivo trusted: **12**.
- Valores distintos de `order_id`: **12**.
- Duplicatas da chave no arquivo trusted: **0**.
- Nulos: **0 em todas as oito colunas**.

O `customer_id` é sintético. Não há nome, e-mail, telefone, CPF ou endereço
detalhado no conjunto de demonstração.

## Schema declarado

O schema está em `parte-1/scenario.auto.tfvars` e é aplicado diretamente à
tabela Glue, sem inferência e sem Crawler:

- `order_id string`
- `customer_id string`
- `order_timestamp timestamp`
- `status string`
- `quantity int`
- `unit_price decimal(10,2)`
- `city string`
- `state string`

Usar `decimal(10,2)` evita a imprecisão binária de `double` no cálculo
financeiro. A precisão comporta preços unitários de até R$ 99.999.999,99, muito
acima do maior preço do arquivo sintético, **R$ 999,90**.

## Qualidade dos dados

`dados/pedidos.csv` é a única fonte enviada a `trusted/`. Ela possui:

- **12 linhas de dados** e uma linha de cabeçalho;
- **895 bytes**;
- **4 datas** distintas;
- cinco status normalizados: `pending`, `paid`, `shipped`, `delivered` e
  `cancelled`;
- quantidade mínima **1** e máxima **5**;
- preço unitário mínimo **R$ 19,99** e máximo **R$ 999,90**.

`dados/exemplos-sujeira.csv` possui **9 linhas de dados** e **642 bytes**, mas
não é carregado. Ele documenta duplicata, variações de status, quantidade zero
ou negativa, preço negativo/malformado e timestamp malformado sem contaminar a
consulta demonstrativa.

## Formato

- Formato: **CSV com cabeçalho e delimitador vírgula**.
- Arquivos carregados: **1**.
- Tamanho carregado: **895 bytes**.

CSV foi mantido porque Parquet não é exigido na AV1 e o volume demonstrativo é
inferior a 1 KiB. Ainda não foi feita comparação medida com Parquet; portanto,
nenhuma economia é alegada.

## Particionamento

A Parte 1 não usa partições. O arquivo possui somente **895 bytes** e quatro
datas; criar partições para essa demonstração aumentaria a quantidade de
objetos sem ganho mensurável relevante. A decisão deve ser revista com dados em
escala real.

## Infraestrutura e nomenclatura

- Infraestrutura integralmente declarada em Terraform.
- Módulo: `parte-1/modules/data_lake`.
- Estado remoto: S3 `eda262-g09-tfstate` com lock DynamoDB
  `eda262-g09-terraform-locks`.
- Workspace: obrigatório e diferente de `default`.
- Bucket trusted: `eda262-g09-lake-trusted`.
- Bucket de resultados: `eda262-g09-athena-results`.
- Workgroup: `eda262-g09-athena`.
- Banco Glue: `eda262_g09_pedidos_ecommerce_catalog`; underscores são usados
  para compatibilidade com identificadores do Athena.
- Tabela: `trusted`.
- Tags obrigatórias: `turma=eda262`, `grupo=g09`,
  `projeto=engenharia-de-dados`.
- Região: validação bloqueia qualquer valor diferente de `us-east-1`.

## Resultado esperado da consulta local

A consulta agrupa por data e status. Estes valores foram calculados localmente
a partir do CSV para conferência funcional; ainda não são evidência de execução
no Athena:

| Data | Status | Valor bruto (R$) |
|---|---|---:|
| 2026-09-28 | cancelled | 118,50 |
| 2026-09-28 | paid | 159,80 |
| 2026-09-28 | shipped | 249,90 |
| 2026-09-29 | delivered | 899,00 |
| 2026-09-29 | paid | 100,00 |
| 2026-09-29 | shipped | 240,00 |
| 2026-09-30 | delivered | 99,95 |
| 2026-09-30 | paid | 301,00 |
| 2026-09-30 | pending | 59,90 |
| 2026-10-01 | cancelled | 999,90 |
| 2026-10-01 | paid | 137,70 |
| 2026-10-01 | shipped | 349,00 |

Pedidos cancelados continuam visíveis em sua própria categoria; a consulta não
os trata como receita realizada nem os oculta.

## Custo da consulta no Athena — pendente

Não existe deploy nem execução Athena autorizada até o momento. Após executar a
consulta em `us-east-1`, registrar:

- Query execution ID: **PENDENTE**
- Data/hora: **PENDENTE**
- Tempo de execução: **PENDENTE**
- Dados processados em bytes: **PENDENTE**
- Preço oficial aplicado, moeda, região, data e fonte: **PENDENTE**
- Fórmula reproduzível: **PENDENTE**
- Custo calculado: **PENDENTE — não inventado**

## Destroy limpo — pendente

Os buckets da stack usam `force_destroy = true`; ainda assim, a comprovação
precisa de uma execução real:

- Workspace usado: **PENDENTE**
- Resultado do destroy: **PENDENTE**
- Checagem pós-destroy de S3, Glue e Athena: **PENDENTE**
- Recursos órfãos: **PENDENTE**
- Evidência em `evidencias/`: **PENDENTE**
