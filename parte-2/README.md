# Operação da versão final - 21/11/2026

O procedimento abaixo mantém o backend existente e o escopo do grupo.
O fechamento verificável está em `../ENTREGA-ATUAL.md`. As execuções de
18-19/11 mencionadas no histórico são anteriores às correções finais.

## Testes locais reproduzíveis

Use Python 3.10 e Java 8. Em um ambiente virtual, instale
`pip install -r tests/requirements-spark.txt` e execute
`./scripts/run_local_tests.sh` a partir de `parte-2/`.
O script executa os testes unitários e os testes Spark reais separadamente,
sem pular silenciosamente os testes Spark quando a dependência está ausente.

## Depois do apply

Execute `./scripts/harden_catalog.sh` para listar grants de compatibilidade
no banco do grupo. Execute `./scripts/harden_catalog.sh --apply` para remover
somente esses grants e depois `./verificacao/verifica.sh --aws`.
Esse passo não altera administradores nem configurações globais da conta.
A matriz funcional é `./scripts/verify_access_matrix.sh`; o teste da função
de ingestão é `./scripts/verify_ingestion_access.sh`.

## Relatórios, idempotência e falhas

`./scripts/run_pipeline.sh FULL all` grava a evidência local vinculada ao
run e lê `reports/runs/<JOB_RUN_ID>.json`. A chave antiga por modo deixou de
ser consumida; os objetos históricos não são tratados como evidência atual.
`./scripts/test_idempotency.sh` executa dois FULL e exige igualdade das
métricas e das assinaturas de conteúdo das três saídas.
`./scripts/run_backfill.sh 2026-09-15` refaz somente essa data.
Datas sem nenhuma linha válida reprovam antes de alterar os destinos.
O relatório informa também rejeitados sem `order_date`; no BACKFILL esses
registros não são atribuídos artificialmente a um dia específico.

A quarentena por modo é um snapshot substituído mesmo vazio. FULL substitui
o conjunto completo de partições, enquanto BACKFILL sobrescreve apenas as
selecionadas. Não há transação entre as três gravações: consultar somente
após o job terminar com sucesso. A raw permanece disponível para repetir.

`GLUE_WAIT_TIMEOUT_SECONDS` (padrão 2400) e `GLUE_POLL_SECONDS` (20) controlam
a espera local. Ao exceder o limite, a rotina falha e informa o run; isso não
cancela o processamento remoto automaticamente.

## Procedimento de infraestrutura e histórico

# AV2 — Data Lake de pedidos de e-commerce — g09

Pipeline em três camadas para responder:

> Qual foi o valor bruto de vendas por dia e status dos pedidos?

Todo recurso é criado por Terraform em **N. Virginia (`us-east-1`)**. Nenhuma
credencial é armazenada no projeto.

O provider aplica, sempre que o serviço aceita tags:

- `turma = eda262`
- `grupo = g09`
- `projeto = engenharia-de-dados`
- `entrega = av2`

## Arquitetura

```text
gerador determinístico
        │ NDJSON + sujeira + reentregas
        ▼
S3 eda262-g09-lake-raw  ── Glue 4.0/Spark ──►  S3 trusted (Parquet)
       │ quarentena                                  │ chave composta
       │                                             │ order_date
       └──────────────── Glue report                 ▼
                                            S3 refined (Parquet)
                                                   │ dia/status
                                                   ▼
                                           Glue Catalog + Athena
```

Lake Formation registra os três buckets e separa acesso por papel. O principal
de execução deve ser administrador preexistente do Lake Formation. O Terraform
concede somente os grants do projeto necessários para criar/remover suas
tabelas; esses grants são separados dos acessos operacionais abaixo:

| Papel | Raw | Trusted | Refined |
|---|---|---|---|
| `eda262-g09-av2-ingestion` | carga | — | — |
| `eda262-g09-av2-glue-pipeline` | leitura/quarentena | leitura/escrita | leitura/escrita |
| `eda262-g09-av2-analyst` | — | — | consulta |

O IAM fornece a permissão física no S3; Lake Formation fornece a permissão de
localização e catálogo. A conta que aplica o Terraform precisa ser administradora
do Lake Formation para conceder essas permissões.

## Dados e grão

- Raw: NDJSON particionado por `arrival_date`, preservando o texto original.
- Trusted: uma linha Parquet por item do pedido, chave
  `(order_id, order_item_id)`, particionada por `order_date`.
- Refined: uma linha Parquet por `(order_date, status)`, particionada por
  `order_date`.

O gerador não contém PII. Identificadores são sintéticos e as únicas dimensões
geográficas são cidade e UF. Com os parâmetros oficiais, ele produz
**120.000 pedidos**, **185.938 itens**, **187.854 eventos raw**, 33 partições de
chegada e **46.543.442 bytes**. Esses números são locais e reproduzíveis; não
são alegações de execução AWS.

A raw inclui:

- 1.916 reentregas da mesma chave;
- status com caixa/espaço e preço com vírgula, que são normalizados;
- status desconhecido, quantidade zero, preço negativo, timestamp inválido e
  identificador ausente, que são rejeitados e enviados para quarentena;
- eventos de 15/09 que chegam cinco dias depois, ou seis quando também são
  reentregues, usados no backfill.

## Inventário lógico da stack

- 5 buckets S3: raw, trusted, refined, artefatos e resultados Athena;
- 1 database e 3 tabelas Glue;
- 1 job Glue;
- 1 workgroup Athena;
- 3 papéis IAM;
- 3 registros de localização no Lake Formation.

Recursos auxiliares de segurança (criptografia, bloqueio público, políticas e
permissões) também são gerenciados pelo Terraform.

Todos os recursos ficam no módulo `modules/data_lake`. A raiz mantém backend,
provider, tags padrão, variáveis, outputs com os mesmos nomes, o bloco
`removed` do singleton global do Lake Formation e `moved.tf`, que leva os 36
endereços de recurso da raiz para `module.data_lake` (59 instâncias, inclusive
as de `for_each`). O caminho do script Glue continua `glue/pipeline_orders.py`
e é passado pela raiz para que o valor `./glue/pipeline_orders.py` registrado
no estado não mude. No ciclo final de
19/11/2026, o plano e o apply registraram **59 recursos gerenciados** e **11
data sources**. O backend é separado. O singleton global de configurações do
Lake Formation foi retirado do estado com `destroy = false`, sem alterar a
conta compartilhada. A execução histórica de 18/11 continha 60 recursos porque
ainda incluía esse singleton.

## Ciclo final em 19/11/2026

O código com SHA-256
`8f7e09c80b1fa6e7eaec2065dae5817631516467bc908c615c04ac2b42f1a165`
foi destruído, recriado e reexecutado em `us-east-1`:

- destroy: **59 removidos**; pós-destroy **12 PASSA, 0 FALHA**, estado vazio,
  nenhuma localização LF do g09, backend ativo e hash global inalterado;
- recriação pareada: **59 adicionados, 0 alterados, 0 destruídos**;
- duas execuções FULL: `SUCCEEDED`, **141 s/282 DPU-s** e **128 s/256 DPU-s**;
- idempotência: **174.878 linhas**, **174.878 chaves**, **30 partições** e
  **R$ 526.021.301,72** antes/depois;
- backfill de `2026-09-15`: `SUCCEEDED`, **107 s/214 DPU-s**, **1 partição**,
  **5.821 linhas**, **60 duplicatas**, **316 rejeitados** e **5 grupos**;
- isolamento do backfill: os **29 objetos não selecionados** permaneceram
  idênticos por chave, ETag, tamanho e `LastModified` em cada camada trusted e
  refined;
- função de ingestão assumida: **6/6 chamadas reais aprovadas**, com escrita,
  leitura, listagem e exclusão na raw, negação de leitura em trusted/refined e
  limpeza de duas versões/marcadores sem resíduo;
- consulta de negócio: `SUCCEEDED`, **10.060 bytes**, **1.115 ms** total,
  **977 ms** de engine e sem reuso;
- reconciliação Terraform pós-recriação: `No changes`;
- inventário: **59 recursos**, **11 data sources**, **12/12 tags**, tamanhos S3
  de **46.543.442/5.584.100/50.858 bytes**, SHA-256 igual em quatro pontos,
  hash global LF preservado e nenhuma associação `AWSGlueServiceRole`;
- matriz de acesso: **17/17**, com 6 chamadas reais do analyst e 11 simulações
  IAM da ingestion;
- verificador final: **26 PASSA, 0 FALHA** e **5 testes unitários OK**.

Origens: `terraform-destroy-review-executed.txt`,
`post-destroy-review-executed.txt`, `post-destroy-scope-preservation.json`,
`terraform-plan-apply-20261119T025835Z-at-20261119T030118Z.json`,
`pipeline-full-20261119T030340Z.json`,
`pipeline-full-20261119T030719Z.json`,
`idempotency-20261119T030334Z.json`,
`pipeline-backfill-20261119T031009Z-report.json`,
`backfill-recreated-isolation.json`, `inventory-recreated-final.json`,
`ingestion-access-real-20261119T031029Z.json`, arquivos
`athena-20261119T032256Z-*`, `terraform-recreated-no-drift.txt`,
`access-matrix-20261119T115835Z.json` e
`final-verification-20261119T115835Z.txt`.

Somando a matriz e o teste separado da função de ingestão, a assinatura final
possui **12 chamadas reais** (6 analyst + 6 ingestion) e **11 simulações IAM**.
As evidências permanecem separadas para distinguir acesso funcional de
avaliação de política.

## Execução histórica medida em 18/11/2026

Os números abaixo pertencem à revisão anterior do código. O dataset é
integralmente sintético, e o valor bruto inclui pedidos cancelados na categoria
`cancelled`; portanto, não representa receita reconhecida.

- raw: **187.854 eventos / 46.543.442 bytes / 33 partições**;
- limpeza: **11.174 rejeitados** e **1.802 duplicatas removidas**;
- trusted: **174.878 linhas e chaves distintas / 5.584.100 bytes**;
- refined: **150 grupos / 50.858 bytes**;
- idempotência: antes/depois **174.878 linhas**, **30 partições** e
  **R$ 526.021.301,72**;
- backfill de `2026-09-15`: **1 partição**, 5.821 linhas e 5 grupos refined;
- consulta final: `SUCCEEDED`, **10.060 bytes**, 1.001 ms, sem reuso;
- verificador antigo: **22 PASSA, 0 FALHA**; esse resultado não incluía a
  validação efetiva dos grants do Lake Formation nem as checagens endurecidas
  nesta revisão;
- plano após apply: **No changes**.
- plano de destroy revisado naquela rodada: **0 criar, 0 alterar, 60 remover**.

As provas correspondentes continuam preservadas em `evidencias/av2/brutas/`
como histórico e não substituem as evidências do ciclo final de 19/11.

## Pré-requisitos

- Terraform >= 1.7;
- Python >= 3.9;
- AWS CLI v2 configurada localmente;
- usuário IAM com permissão administrativa para S3, Glue, Athena e IAM e já
  cadastrado como administrador do Lake Formation; sessões SSO/STS não fazem
  parte do contrato desta entrega;
- região `us-east-1`.

As credenciais devem ficar apenas no mecanismo local aprovado pela disciplina.
Não copie arquivos de acesso para o repositório.

## 1. Backend remoto

O estado da AV2 fica no backend criado por `parte-1/bootstrap`, o mesmo
registrado nas evidências: bucket `eda262-g09-tfstate`, tabela
`eda262-g09-terraform-locks`, chave `parte-2/terraform.tfstate` e prefixo
`workspaces`. `backend.hcl.example` usa exatamente esses valores. Na conta
compartilhada, não recrie o backend. Em conta limpa, crie-o a partir da raiz:

```bash
cd parte-1/bootstrap
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform fmt -check -recursive
terraform validate
mkdir -p .runtime
terraform plan -out=.runtime/bootstrap.tfplan
terraform apply .runtime/bootstrap.tfplan
```

Se o nome global do bucket já existir, escolha outro iniciado por
`eda262-g09-` em `state_bucket_name` e replique o mesmo nome em
`parte-2/backend.hcl`. O backend tem ciclo de vida separado da stack avaliada.
`parte-2/bootstrap` cria um par alternativo (`eda262-g09-av2-tfstate` e
`eda262-g09-av2-terraform-locks`) que não foi usado pela entrega; só o adote
ajustando `backend.hcl` de forma correspondente.

## 2. Stack AV2

Antes do plano, confirme localmente que o principal de execução já aparece em
`DataLakeAdmins`. Não versione essa saída:

```bash
aws sts get-caller-identity --query Arn --output text
aws lakeformation get-data-lake-settings \
  --query DataLakeSettings.DataLakeAdmins \
  --output json
```

A stack não cria, substitui nem remove administradores globais do Lake
Formation. Em conta nova ou dedicada, essa inicialização é um pré-requisito
administrativo externo ao projeto. Interrompa antes do plano se o primeiro
comando retornar `arn:aws:sts` ou se o usuário IAM não aparecer em
`DataLakeAdmins`; esta entrega não converte sessões assumidas em principal IAM.

```bash
cd ../../parte-2
cp backend.hcl.example backend.hcl
terraform init -backend-config=backend.hcl
terraform workspace select -or-create av2
terraform fmt -check -recursive
terraform validate
./scripts/capture_terraform.sh plan
./scripts/capture_terraform.sh apply
./scripts/harden_catalog.sh
./scripts/harden_catalog.sh --apply
./verificacao/verifica.sh --aws
```

A migração para `module.data_lake` já foi aplicada sem mudanças de recursos.
Na revisão de 21/11, o plano de atualização alterou somente o objeto do script
e o job Glue: 0 criações, 2 alterações, 0 destruições. Depois do apply, o plano
voltou a `No changes`. Em uma conta sem estado, os blocos `moved` não têm
efeito e o plano esperado permanece 59 criações. A reprodução em uma segunda
conta dedicada não foi executada; siga o procedimento específico e confira
o plano antes de aplicar.

Para uma conta dedicada, use o procedimento opt-in de
[conta-dedicada/README.md](conta-dedicada/README.md), que confirma a conta
alvo, bloqueia a conta compartilhada e faz pré-checagens somente leitura.

O workspace `default` é bloqueado. `capture_terraform.sh` grava logs imutáveis
com timestamp e `-no-color`; um manifesto local registra o SHA-256 e garante
que o apply consuma exatamente o plano revisado. Plano binário, estado,
backend e tfvars locais ficam ignorados.

## 3. Gerar e carregar a raw

```bash
./scripts/load_raw.sh
```

O script recria `parte-2/.generated/` com seed fixa e sincroniza as mesmas
chaves S3. Reexecutá-lo não cria objetos com nomes novos. Ele registra resumo
JSON e listagem S3 sanitizados.

Para gerar apenas localmente:

```bash
python3 scripts/generate_raw.py \
  --output .generated \
  --start-date 2026-09-01 \
  --days 30 \
  --orders-per-day 4000 \
  --seed 20261118
```

## 4. Executar, provar idempotência e fazer backfill

```bash
./scripts/run_pipeline.sh FULL all
./scripts/test_idempotency.sh
./scripts/run_backfill.sh 2026-09-15
./scripts/verify_access_matrix.sh
./scripts/verify_ingestion_access.sh
```

O pipeline normaliza, valida, coloca rejeitados em quarentena, deduplica pela
chave composta e sobrescreve dinamicamente somente as partições processadas.
`test_idempotency.sh` executa o pipeline duas vezes e compara linhas, chaves,
partições e valor bruto antes/depois. O backfill reconstrói 15/09 a partir da
raw inteira para o dia de evento solicitado.

O contrato educacional usa 30 dias fixos e `order_timestamp` imutável. O FULL
não promete remover partições que desapareçam da raw, e o BACKFILL não promete
reconciliar uma chave cujo timestamp seja corrigido para outro dia. A
quarentena é um snapshot por modo, com valores normalizados e sem coluna de
motivo.

`verify_access_matrix.sh` assume temporariamente o papel de analista sem
imprimir credenciais, prova consulta e leitura da refined, nega raw/trusted e
simula a política IAM da ingestão. O JSON sanitizado fica em
`evidencias/av2/brutas/`.

`verify_ingestion_access.sh` assume a função de ingestão e faz seis
chamadas S3 reais com um objeto sintético exclusivo fora das partições de
dados. O cleanup removeu somente as duas versões/marcadores dessa chave e
confirmou zero resíduo. Evidência:
`ingestion-access-real-20261119T031029Z.json`.

## 5. Consulta e custo

```bash
./scripts/run_query.sh ../consultas/av2-valor-bruto.sql
```

São salvos o JSON da execução, o resultado e um resumo de bytes/tempo em
`evidencias/av2/brutas/`. Depois, registre em `DECISOES.md` o preço oficial
vigente, a data da consulta e a fórmula. O projeto não inventa custo AWS.

No ciclo pós-recriação, os dois FULL e o BACKFILL somaram **752 DPU-s**, ou
aproximadamente **US$ 0,0919111** pela tarifa de exemplo de US$ 0,44/DPU-h. A
captura final acumulada de 11 runs somou **2.556 DPU-s**, estimados em **US$
0,3124**; inclui também as oito execuções preservadas da rodada anterior. A
consulta Athena abaixo de 10 MB tem estimativa aproximada de US$ 0,00005 pelo
mínimo de 10 MB. Todos são estimativas, não faturas. Fontes:
`glue-cost-estimate-final.json`,
<https://aws.amazon.com/glue/pricing/> e
<https://docs.aws.amazon.com/whitepapers/latest/big-data-analytics-options/amazon-athena.html>.

## 6. Verificar

Da raiz do repositório:

```bash
cd ..
./verificacao/verifica.sh              # local; não acessa AWS
./verificacao/verifica.sh --aws        # leitura remota após o deploy
```

No modo `--aws`, `scripts/verify_lf_grants.sh` pagina `list-permissions` e
`scripts/lf_grants.py` compara, para cada papel, o conjunto exato esperado:

- ingestion: somente `DATA_LOCATION_ACCESS` na localização raw;
- pipeline: as três localizações, `DESCRIBE` no database e `SELECT`/`DESCRIBE`
  nas três tabelas;
- analyst: `DESCRIBE` no database e `SELECT`/`DESCRIBE` somente na refined.

Qualquer permissão extra, `ALL`, grant option, `TableWildcard`, colunas
restritas ou grant em outro recurso reprova o papel. `SELECT` retornado em
`TableWithColumns` com `ColumnWildcard` vazio na mesma tabela é tratado como a
representação normal da API.

O verificador anterior da AV1 foi preservado:

```bash
./verificacao/verifica.sh --av1
```

## 7. Destroy limpo

```bash
./parte-2/scripts/capture_terraform.sh destroy-plan
CONFIRM_DESTROY=eda262-g09-av2 ./parte-2/scripts/destroy_and_verify.sh
```

O script aplica apenas o plano já revisado e executa a checagem pós-destroy.
Buckets da stack e workgroup usam `force_destroy`; o backend é deliberadamente
separado e não é classificado como órfão da stack.

## Evidências reais exigidas

Antes da entrega, revise e versione apenas as saídas sanitizadas descritas em
`evidencias/av2/README.md`. Não use prints escritos manualmente como prova e não
versione `.terraform/`, `*.tfstate`, `*.tfplan`, `backend.hcl`,
`terraform.tfvars` ou credenciais.

