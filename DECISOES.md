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
- Workspace: obrigatório e diferente de `default`; a entrega usa `av1`.
- Bucket trusted: `eda262-g09-lake-trusted`.
- Bucket de resultados: `eda262-g09-athena-results`.
- Workgroup: `eda262-g09-athena`, com limite de 10.485.760 bytes (10 MiB) lidos
  por consulta.
- Banco Glue: `eda262_g09_pedidos_ecommerce_catalog`; underscores são usados
  para compatibilidade com identificadores do Athena.
- Tabela: `trusted`.
- Tags obrigatórias: `turma=eda262`, `grupo=g09`,
  `projeto=engenharia-de-dados`.
- Região: validação bloqueia qualquer valor diferente de `us-east-1`.
- Arquivo de dados: referenciado por caminho relativo a `parte-1`
  (`path.root`), para que plano e estado não dependam da máquina.

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

O preço sob demanda publicado pela AWS é **US$ 5 por TB verificado**. A
estimativa registrada aplica um piso de **10 MB por consulta** e, por isso, é um
teto conservador para os 895 bytes informados pelo Athena:

`US$ 5 × 10 MB ÷ 1 TB ≈ US$ 0,00005`

Sem o piso, o mesmo cálculo daria
`US$ 5 × 895 bytes ÷ 1 TB ≈ US$ 0,0000000045`. Em releitura da página de preços
em 02/10/2026, o trecho que cita o mínimo de 10 MB descreve consultas a fontes
de dados federadas; a regra para dados no S3 precisa ser confirmada antes de
tratar o piso como faturamento certo. Nas duas leituras o custo desta consulta
fica abaixo de US$ 0,0001.

Fonte consultada em 01/10/2026 e relida em 02/10/2026:
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

O roteiro para remover o backend, ainda não executado, está no `README.md`,
etapa 7.

## Mudanças após a execução de 01/10/2026

As evidências descrevem a stack como ela foi aplicada em 01/10/2026. Depois
disso o código recebeu três ajustes, **ainda não reaplicados na AWS**:

| Ajuste | Antes | Agora | Efeito sobre o que foi evidenciado |
|---|---|---|---|
| Caminho do CSV | caminho absoluto da máquina (`abspath`) | relativo a `parte-1` (`path.root`) | nenhum recurso novo; mesmo arquivo de 895 bytes, mesma chave `trusted/pedidos.csv` |
| Limite de bytes por consulta | sem limite (`null`) | 10.485.760 bytes | atributo do workgroup já existente; a stack continua com 14 recursos |
| Validação de variáveis | cutoff mínimo de 10.000.000 | cutoff mínimo de 10.485.760; `source` precisa ser relativo | só rejeita entradas inválidas antes do plano |

Nomes de recursos, schema, dados e consulta não mudaram. A contagem de 14
recursos, o Query execution ID, os 895 bytes, os 608 ms e o custo estimado
continuam sendo os da execução real; uma nova execução exige novas medições.

## Limitações e trade-offs

Os números da AV1 valem para o conjunto de demonstração e não devem ser
extrapolados. Cada item registra a decisão, o número que a sustenta e o que ela
deixa de cobrir.

### Dataset sintético e pequeno

- Decisão: 12 pedidos sintéticos, suficientes para validar catálogo, consulta e
  custo sem expor dados reais.
- Número: 895 bytes, 608 ms de tempo total e 414 ms de engine.
- Limitação: com esse volume, tempo e custo refletem o custo fixo de uma
  consulta, não o comportamento em escala. Nenhuma conclusão de desempenho é
  alegada.

### Grão de pedido com um único tipo de item

- Decisão: uma linha por pedido, com `order_id` como chave.
- Número: 12 linhas, 12 valores distintos de `order_id`.
- Limitação: `quantity * unit_price` só equivale ao valor do pedido porque cada
  pedido tem um item. Pedidos com vários itens exigiriam o grão pedido-item,
  chave composta e soma por pedido antes de agregar por dia.

### Cancelados incluídos no valor bruto

- Decisão: a consulta mantém todos os status, cada um em sua categoria.
- Número: 2 dos 12 pedidos estão `cancelled` e somam R$ 1.118,40 de
  R$ 3.714,65, ou 30,1% do valor bruto. Sem eles o total seria R$ 2.596,25.
- Limitação: valor bruto não é receita realizada. Quem consome o resultado
  precisa filtrar por status para chegar à receita.

### Fuso horário

- Decisão: `order_timestamp` é gravado e lido sem fuso; o dia é a data literal
  do arquivo.
- Número: os horários vão de 08:20 a 18:45, então um deslocamento de até 5
  horas para frente ou 8 horas para trás não mudaria nenhum pedido de dia.
- Limitação: o arquivo não declara o fuso de origem. Com pedidos próximos da
  meia-noite, o fuso teria de ser fixado antes de agrupar por dia.

### CSV em vez de Parquet, sem particionamento

- Decisão: um único CSV, sem partições.
- Número: a consulta usa 4 das 8 colunas, que somam 386 dos 724 bytes de valores
  do arquivo (53%). Particionar por data geraria 4 objetos com 197 a 212 bytes
  de dados cada, e a pergunta lê todos os dias.
- Limitação: não há comparação medida com Parquet nem com tabela particionada;
  nenhuma economia é alegada. A decisão deve ser refeita com medição quando o
  volume ultrapassar o que uma leitura completa justifica.

### SerDe

- Decisão: `LazySimpleSerDe` com delimitador vírgula e cabeçalho ignorado.
- Número: as 13 linhas do arquivo têm exatamente 7 vírgulas e nenhuma aspa.
- Limitação: esse SerDe não trata aspas nem vírgula dentro de campo, e pelo
  comportamento padrão do Hive um valor que não converte para o tipo declarado é
  lido como nulo, sem erro (não exercitado na AV1). Por isso
  `exemplos-sujeira.csv` fica fora de `trusted/`. O `OpenCSVSerde` trataria
  aspas, mas só reconhece `timestamp` em formato numérico UNIX, o que obrigaria
  a mudar o arquivo ou o schema.

### Criptografia

- Decisão: SSE-S3 (AES-256) no bucket do lake, no bucket de resultados, no
  objeto enviado e no bucket de estado; resultados do Athena com `SSE_S3`.
- Limitação: sem chave KMS própria não há controle de acesso nem auditoria por
  chave, e não há política de bucket exigindo TLS. É aceitável para dado
  sintético sem PII e deve ser revisto com dados reais.

### Versionamento

- Decisão: versionamento ligado no bucket do lake e no bucket de estado;
  desligado no bucket de resultados.
- Número: o apply envia 1 objeto ao lake, que fica com 1 versão.
- Limitação: versões antigas ocupam espaço e só saem com `force_destroy` ou
  limpeza explícita. No bucket de estado isso torna a remoção do backend um
  procedimento à parte (`README.md`, etapa 7). Resultados do Athena não têm
  histórico porque podem ser recalculados.

### `force_destroy`

- Decisão: `force_destroy = true` nos dois buckets da stack e no workgroup.
- Número: sem ele no workgroup, o primeiro destroy removeu 9 dos 14 recursos e
  parou; com ele, os 5 restantes saíram.
- Limitação: a opção apaga dados e histórico sem confirmação adicional. Serve a
  uma stack acadêmica descartável; em produção ficaria desligada. O destroy em
  etapa única com o código atual ainda não foi reexecutado.

### Limite de bytes por consulta

- Decisão: `athena_bytes_scanned_cutoff = 10485760` (10 MiB). O provider AWS
  5.100.0 recusa valores menores; a API do Athena aceita a partir de 10.000.000.
- Número: o limite é cerca de 11,7 mil vezes os 895 bytes medidos.
- Limitação: o limite foi acrescentado depois da execução de 01/10/2026, quando
  o workgroup não tinha limite, e ainda não foi aplicado na AWS. Ele cancela uma
  consulta que passe do teto, mas não limita o gasto acumulado de várias
  consultas.

### Expiração dos resultados

- Decisão: não há regra de ciclo de vida no bucket de resultados.
- Número: a regra seria um 15º recurso e invalidaria a evidência de 14.
- Limitação: enquanto a stack fica ativa, os resultados se acumulam. Na AV1 isso
  é contido pelo destroy, que remove o bucket com `force_destroy`.

### Backend com lock no DynamoDB

- Decisão: estado em S3 com lock em DynamoDB, como a disciplina exige.
- Número: 5 recursos no bootstrap; a execução real usou Terraform 1.16.4.
- Limitação: a documentação atual do backend S3 marca o lock por DynamoDB como
  obsoleto e indica o lock nativo do S3 (`use_lockfile`). Como `required_version`
  aceita qualquer 1.x a partir de 1.5, uma versão futura que remova
  `dynamodb_table` quebraria o `init`; a saída é fixar a versão testada ou
  migrar quando a disciplina permitir. O estado do próprio bootstrap é local e
  não versionado: se for perdido, o backend só volta a ser gerenciado por
  importação (`README.md`, etapa 1).

### Nomes fixos e workspace

- Decisão: nomes no padrão `eda262-g09-*`, sem o nome do workspace.
- Limitação: dois workspaces não podem coexistir na mesma conta, porque
  disputariam os mesmos nomes, e nomes de bucket são globais. A configuração só
  bloqueia o workspace `default`; `av1` é a convenção da entrega, conferida pelo
  verificador no modo operacional.
