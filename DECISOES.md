# Decisões de Engenharia — AV1 — g09

As medições locais abaixo são reproduzíveis sobre os arquivos versionados. A
stack também foi executada na conta acadêmica do grupo em `us-east-1`, e os
resultados reais estão registrados sem credenciais em `evidencias/`.

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

## Resultado verificado no Athena

A consulta agrupa por data e status. Os valores calculados localmente foram
confirmados por uma execução real no Athena em 01/10/2026:

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

## Custo medido da consulta no Athena

- Query execution ID: `5c11fe2f-ba30-457e-aa26-0055b3970cb1`.
- Data/hora de submissão: **01/10/2026 23:43:29 -03:00**.
- Estado: **SUCCEEDED**.
- Tempo total: **608 ms**.
- Tempo de engine: **414 ms**.
- Dados processados informados pelo Athena: **895 bytes**.
- Reuso de resultado anterior: **não**.
- Saída: `s3://eda262-g09-athena-results/results/5c11fe2f-ba30-457e-aa26-0055b3970cb1.csv`.

O preço sob demanda publicado pela AWS é **US$ 5 por TB verificado**, com
arredondamento e mínimo faturável de **10 MB por consulta**. Assim, embora o
Athena tenha informado somente 895 bytes processados, a estimativa conservadora
é:

`US$ 5 × 10 MB ÷ 1 TB ≈ US$ 0,00005`

Fonte consultada em 01/10/2026:
<https://aws.amazon.com/pt/athena/pricing/>.

## Destroy limpo

- Workspace: `av1`.
- Plano original: `0 to add, 0 to change, 14 to destroy`.
- Resultado final: estado da stack com **0 recursos**.
- S3 `eda262-g09-lake-trusted`: ausente após o destroy.
- S3 `eda262-g09-athena-results`: ausente após o destroy.
- Glue database e tabela trusted: ausentes após o destroy.
- Athena workgroup: ausente após o destroy.
- Recursos órfãos da stack: **0**.

A primeira tentativa revelou que o workgroup não podia ser removido enquanto
mantinha histórico de consulta. O módulo foi corrigido com
`force_destroy = true`, validado e reaplicado somente ao workgroup antes da
conclusão do destroy. O backend remoto foi deliberadamente mantido: S3
`eda262-g09-tfstate` e DynamoDB `eda262-g09-terraform-locks` continuam ativos
para preservar o estado e o mecanismo de lock do projeto.
