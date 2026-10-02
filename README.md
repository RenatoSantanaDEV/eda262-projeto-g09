# EDA 2026.2 — Projeto g09 — Parte 1

Data Lake simples para pedidos de e-commerce, provisionado integralmente em
Terraform na AWS. A pergunta de negócio é:

> Qual foi o valor bruto de vendas por dia e por status dos pedidos?

O projeto usa obrigatoriamente **N. Virginia (`us-east-1`)**, conforme a regra
da disciplina. A configuração rejeita qualquer outra região.

## Arquitetura

- S3 `eda262-g09-lake-trusted`: dados CSV da camada `trusted`;
- AWS Glue Data Catalog: banco e tabela externa `trusted`, sem Crawler;
- S3 `eda262-g09-athena-results`: resultados de consultas;
- Athena workgroup `eda262-g09-athena`: execução controlada e medição, com
  limite de 10 MiB lidos por consulta;
- S3 + DynamoDB: backend remoto e lock do estado Terraform;
- workspace Terraform obrigatório, diferente de `default`; a entrega usa `av1`.

Todos os recursos que aceitam tags recebem:

- `turma = eda262`
- `grupo = g09`
- `projeto = engenharia-de-dados`

## Grão e schema

Uma linha representa um pedido consolidado com um único tipo de item. Nesse
modelo simplificado, `order_id` é a chave natural e `quantity * unit_price`
representa o valor bruto do pedido.

O schema é declarado em `parte-1/scenario.auto.tfvars`:

| Coluna | Tipo | Significado |
|---|---|---|
| `order_id` | `string` | chave natural sintética do pedido |
| `customer_id` | `string` | identificador sintético, sem PII |
| `order_timestamp` | `timestamp` | data e hora do pedido |
| `status` | `string` | status normalizado |
| `quantity` | `int` | unidades do item no pedido |
| `unit_price` | `decimal(10,2)` | preço unitário em reais |
| `city` | `string` | cidade, sem endereço detalhado |
| `state` | `string` | UF |

O arquivo `dados/pedidos.csv` contém somente dados sintéticos e coerentes. O
arquivo `dados/exemplos-sujeira.csv` documenta anomalias, mas não é carregado e
não pode quebrar a consulta principal.

## Segurança de credenciais

As credenciais fornecidas pelo professor são sensíveis. **Nunca copie os
arquivos de acesso para este projeto, Git, GitHub, Drive ou outro armazenamento
em nuvem.** Configure-as somente pelo mecanismo local aprovado para a aula.

O `.gitignore` bloqueia nomes e extensões comuns de credenciais, além de estado,
planos, cache de `init`, `backend.hcl` e `terraform.tfvars` locais. O script de
verificação procura padrões de access key, secret key, token de sessão e chave
privada, confere que nenhum arquivo operacional está versionado e que as
evidências não trazem o ID completo da conta. Nenhuma credencial está incluída
neste repositório.

## Versionamento da entrega

- Nome do repositório: `eda262-projeto-g09`
- Branch avaliada: `main`
- Tag da AV1: `av1-entrega`

O ZIP de entrega não contém a pasta `.git`; branch e tag ficam disponíveis no
repositório local e devem ser preservadas no repositório remoto escolhido pelo
grupo.

## Estrutura

```text
.
├── .gitignore
├── DECISOES.md
├── README.md
├── consultas/
│   └── pergunta-negocio.sql
├── dados/
│   ├── README.md
│   ├── exemplos-sujeira.csv        # anomalias documentadas; não é carregado
│   └── pedidos.csv                 # único arquivo enviado a trusted/
├── evidencias/
│   ├── README.md
│   ├── destroy-aws.md
│   └── execucao-aws.md
├── parte-1/
│   ├── .terraform.lock.hcl
│   ├── backend.hcl.example
│   ├── bootstrap/                  # cria backend S3 + DynamoDB
│   │   ├── .terraform.lock.hcl
│   │   ├── locals.tf
│   │   ├── main.tf
│   │   ├── outputs.tf
│   │   ├── terraform.tfvars.example
│   │   ├── variables.tf
│   │   └── versions.tf
│   ├── locals.tf
│   ├── main.tf
│   ├── modules/
│   │   └── data_lake/              # módulo da stack
│   │       ├── main.tf
│   │       ├── outputs.tf
│   │       └── variables.tf
│   ├── outputs.tf
│   ├── scenario.auto.tfvars
│   ├── terraform.tfvars.example
│   ├── variables.tf
│   └── versions.tf
└── verificacao/
    └── verifica.sh
```

Estado (`*.tfstate`), planos (`*.tfplan`), cache `.terraform/`, `backend.hcl` e
`terraform.tfvars` são criados localmente pelos passos abaixo e nunca são
versionados nem empacotados.

## Pré-requisitos

- Terraform 1.5 ou superior (a execução evidenciada usou 1.16.4 com o provider
  AWS 5.100.0);
- AWS CLI configurada localmente, sem credenciais no repositório;
- `jq`, usado somente pelas checagens AWS do verificador;
- acesso autorizado à conta do grupo g09 em `us-east-1`.

Uma execução real foi realizada em 01/10/2026 na conta acadêmica do grupo, em
`us-east-1`. O resultado da consulta e as medições estão em
`evidencias/execucao-aws.md`. A stack foi destruída e a ausência de órfãos está
registrada em `evidencias/destroy-aws.md`. O backend remoto foi mantido para
preservar o estado. As credenciais não fazem parte do projeto.

Depois dessa execução o código recebeu ajustes que ainda não foram reaplicados
na AWS: caminho do CSV relativo a `parte-1` e limite de bytes por consulta no
workgroup. Eles não mudam os 14 recursos nem o objeto enviado; o detalhe está em
`DECISOES.md`, seção "Mudanças após a execução de 01/10/2026".

Cada etapa abaixo indica o diretório de partida. Os comandos `cd` assumem a
raiz do projeto.

## 1. Criar o backend remoto

A partir da raiz do projeto. O backend precisa existir antes da stack
principal. Ele também é criado por Terraform, mas mantém um pequeno estado local
de bootstrap (`parte-1/bootstrap/terraform.tfstate`, não versionado).

```bash
cd parte-1/bootstrap
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan -out=bootstrap.tfplan
# Revise o plano antes de executar (esperado: 5 to add):
terraform apply bootstrap.tfplan
```

O nome S3 é global. Se `eda262-g09-tfstate` já pertencer a outra conta, escolha
outro nome iniciado por `eda262-g09-` e use o mesmo valor em
`parte-1/backend.hcl`.

### Quando o backend já existe

Na conta do grupo g09 o backend foi criado em 01/10/2026 e mantido depois do
destroy da stack (ver `evidencias/destroy-aws.md`). Enquanto ele existir:

- **em outra máquina ou em um clone limpo, pule esta etapa** e siga para a
  etapa 2. A stack principal só precisa do nome do bucket e da tabela em
  `backend.hcl`; repetir o `apply` do bootstrap sem o estado local falharia
  porque o bucket e a tabela já existem;
- na máquina que guarda o estado local do bootstrap, não há nada a reaplicar:
  `terraform plan` nessa pasta não deve propor mudanças.

Se o estado local do bootstrap for perdido e o backend precisar voltar a ser
gerenciado por Terraform (por exemplo, para removê-lo na etapa 7), importe os
cinco recursos antes de qualquer `apply`. Procedimento de referência, ainda não
executado pelo grupo:

```bash
cd parte-1/bootstrap
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform import aws_s3_bucket.terraform_state eda262-g09-tfstate
terraform import aws_s3_bucket_versioning.terraform_state eda262-g09-tfstate
terraform import aws_s3_bucket_server_side_encryption_configuration.terraform_state eda262-g09-tfstate
terraform import aws_s3_bucket_public_access_block.terraform_state eda262-g09-tfstate
terraform import aws_dynamodb_table.terraform_locks eda262-g09-terraform-locks
terraform plan
# Revise: o plano não pode recriar nem destruir nenhum dos cinco recursos.
```

## 2. Inicializar a stack e o workspace

A partir da raiz do projeto:

```bash
cd parte-1
cp backend.hcl.example backend.hcl
# Ajuste apenas o nome do bucket caso tenha mudado no bootstrap.
terraform init -backend-config=backend.hcl
terraform workspace select -or-create av1
terraform fmt -check -recursive
terraform validate
terraform plan -out=av1.tfplan
# Esperado em uma conta sem a stack: Plan: 14 to add, 0 to change, 0 to destroy.
```

`terraform workspace select -or-create av1` cria o workspace na primeira vez e
apenas o seleciona nas seguintes, então o bloco pode ser repetido.
`scenario.auto.tfvars` é carregado automaticamente. O workspace `default` é
bloqueado pela configuração.

Para apenas validar o código, sem backend e sem credenciais, a partir da raiz:

```bash
cd parte-1
terraform init -backend=false
terraform validate
```

## 3. Aplicar

Em `parte-1`, somente após revisar o plano:

```bash
terraform apply av1.tfplan
terraform output
```

## 4. Consultar no Athena e medir custo

Com a stack aplicada, na raiz do projeto. O workgroup já define o local de saída
e a consulta qualifica o banco, então não é preciso informar mais nada:

```bash
QUERY_ID="$(aws athena start-query-execution \
  --region us-east-1 \
  --work-group eda262-g09-athena \
  --query-string file://consultas/pergunta-negocio.sql \
  --query QueryExecutionId --output text)"
echo "Query execution ID: $QUERY_ID"
```

Estado e métricas (repita enquanto `estado` for `QUEUED` ou `RUNNING`):

```bash
aws athena get-query-execution \
  --region us-east-1 \
  --query-execution-id "$QUERY_ID" \
  --query 'QueryExecution.{estado: Status.State, submissao: Status.SubmissionDateTime, conclusao: Status.CompletionDateTime, tempo_total_ms: Statistics.TotalExecutionTimeInMillis, tempo_engine_ms: Statistics.EngineExecutionTimeInMillis, bytes_lidos: Statistics.DataScannedInBytes, reuso: Statistics.ResultReuseInformation.ReusedPreviousResult, saida: ResultConfiguration.OutputLocation}' \
  --output json
```

Resultado da consulta (CSV gravado pelo Athena no bucket de resultados):

```bash
SAIDA="$(aws athena get-query-execution \
  --region us-east-1 \
  --query-execution-id "$QUERY_ID" \
  --query QueryExecution.ResultConfiguration.OutputLocation --output text)"
aws s3 cp "$SAIDA" - --region us-east-1
```

Custo estimado a partir dos bytes lidos, a US$ 5 por TB:

```bash
BYTES="$(aws athena get-query-execution \
  --region us-east-1 \
  --query-execution-id "$QUERY_ID" \
  --query QueryExecution.Statistics.DataScannedInBytes --output text)"
awk -v b="$BYTES" 'BEGIN {
  piso = 10 * 1000 * 1000
  printf "bytes lidos: %d\n", b
  printf "custo sem piso: US$ %.10f\n", 5 * b / 1e12
  printf "custo com piso de 10 MB: US$ %.5f\n", 5 * (b > piso ? b : piso) / 1e12
}'
```

Também é possível colar o conteúdo de `consultas/pergunta-negocio.sql` no editor
do Athena, com o workgroup `eda262-g09-athena` selecionado.

A execução comprovada, seu Query execution ID, tempo, bytes processados e
cálculo do custo estão em `DECISOES.md` e `evidencias/execucao-aws.md`. Em uma
nova execução, atualize essas medições em vez de reutilizá-las como se fossem
atuais. Os comandos desta etapa são o roteiro para repetir a medição pela AWS
CLI; eles não foram reexecutados depois do destroy.

## 5. Verificar

Na raiz do projeto:

```bash
./verificacao/verifica.sh
```

O modo padrão é o de entrega: local, somente leitura e sem AWS. Ele confere
estrutura, requisitos, dados, consistência com as evidências e segurança, e
termina com código 0 em um clone limpo ou no ZIP extraído. O que depende do
ambiente (Terraform instalado, cache de `init`, `backend.hcl`, AWS) aparece como
`PULADO`, não como falha. Se o Terraform estiver instalado, `fmt` roda sempre e
`validate` roda onde já houver `init`.

Depois do `init` da etapa 2, exija também o ambiente operacional:

```bash
RUN_OPERATIONAL_CHECKS=1 ./verificacao/verifica.sh
```

Esse modo falha se o Terraform não estiver disponível, se faltar `init`,
`validate`, `backend.hcl` preenchido ou se o workspace não for `av1`.

Com a stack implantada, acrescente as checagens AWS, exclusivamente de leitura:

```bash
RUN_OPERATIONAL_CHECKS=1 RUN_AWS_CHECKS=1 ./verificacao/verifica.sh
```

Depois do destroy essas checagens AWS falham, como esperado: os recursos não
existem mais.

Fora de um repositório Git (ZIP extraído), a presença de estado, planos, cache
`.terraform/`, `backend.hcl` ou `terraform.tfvars` é tratada como pacote
contaminado e faz o modo padrão falhar.

## 6. Destroy limpo da stack

Os buckets e o workgroup da stack acadêmica usam `force_destroy = true`,
permitindo remover os objetos de demonstração e o histórico de consultas junto
com os recursos. Em `parte-1`, confirme conta, região e workspace antes de
destruir:

```bash
terraform workspace show
terraform plan -destroy -out=destroy.tfplan
# Revise o plano antes de executar (esperado: 14 to destroy):
terraform apply destroy.tfplan
terraform state list
# Esperado: nenhuma saída.
```

Depois, confirme por leitura que nada ficou órfão:

```bash
aws s3api head-bucket --bucket eda262-g09-lake-trusted --region us-east-1
aws s3api head-bucket --bucket eda262-g09-athena-results --region us-east-1
aws glue get-database --name eda262_g09_pedidos_ecommerce_catalog --region us-east-1
aws glue get-table --database-name eda262_g09_pedidos_ecommerce_catalog --name trusted --region us-east-1
aws athena get-work-group --work-group eda262-g09-athena --region us-east-1
# Esperado: os cinco comandos terminam com erro de recurso inexistente
# (404 nos buckets, EntityNotFoundException no Glue).
```

Na execução de 01/10/2026 o destroy precisou de duas etapas, porque o workgroup
ainda não tinha `force_destroy` (ver `evidencias/destroy-aws.md`). O código atual
já traz a correção; o destroy em etapa única ainda não foi reexecutado.

## 7. Remover o backend remoto (opcional, não executado)

O `destroy` da etapa 6 não remove o backend. Ele foi mantido de propósito em
01/10/2026 e continua na conta: S3 `eda262-g09-tfstate` e DynamoDB
`eda262-g09-terraform-locks`. O bucket tem `prevent_destroy = true`, versionamento
e não tem `force_destroy`, então um `terraform destroy` direto no bootstrap é
recusado.

Remova o backend somente quando o estado não for mais necessário e com
autorização do professor. A operação é irreversível e apaga todo o histórico de
estado. Roteiro, ainda não executado:

1. Em `parte-1`, confirme que a stack está vazia:
   `terraform workspace select av1 && terraform state list` (sem saída).
2. Em `parte-1/bootstrap`, com o estado local do bootstrap presente (ou
   reimportado como na etapa 1), altere **apenas localmente** o recurso
   `aws_s3_bucket.terraform_state` em `main.tf`: troque `prevent_destroy = true`
   por `false` e acrescente `force_destroy = true`.
3. Registre a mudança no estado e destrua:

   ```bash
   terraform apply
   # Revise: 0 to add, 1 to change, 0 to destroy.
   terraform plan -destroy -out=bootstrap-destroy.tfplan
   # Revise: 0 to add, 0 to change, 5 to destroy.
   terraform apply bootstrap-destroy.tfplan
   ```

4. Confirme a ausência:

   ```bash
   aws s3api head-bucket --bucket eda262-g09-tfstate --region us-east-1
   aws dynamodb describe-table --table-name eda262-g09-terraform-locks --region us-east-1
   # Esperado: 404 no bucket e ResourceNotFoundException na tabela.
   ```

5. Descarte a alteração local, sem versioná-la:
   `git restore parte-1/bootstrap/main.tf`.

## Evidências

| Arquivo | O que registra |
|---|---|
| `evidencias/execucao-aws.md` | bootstrap (5 recursos), apply da stack (14 recursos), verificação remota e consulta real no Athena: Query execution ID, 608 ms, 895 bytes e custo estimado |
| `evidencias/destroy-aws.md` | destroy em duas etapas (9 + 5 recursos), ausência dos cinco alvos e backend preservado |
| `evidencias/README.md` | o que está e o que não está versionado, e como acrescentar saídas brutas sanitizadas |

Os dois registros são resumos textuais da execução de 01/10/2026. Saídas brutas
dessa execução não foram versionadas; a convenção para incluí-las em uma próxima
execução está em `evidencias/README.md`.
