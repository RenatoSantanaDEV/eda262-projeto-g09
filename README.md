# EDA 2026.2 — Projeto g09 — AV2

Data Lake em três camadas para responder:

> Qual foi o valor bruto de vendas por dia e status dos pedidos?

A AV2 é a entrega canônica deste repositório. O histórico da primeira entrega
está em [README-AV1.md](README-AV1.md) e
[DECISOES-AV1.md](DECISOES-AV1.md).

## Edição revisada da apresentação

Consulte [ENTREGA-ATUAL.md](ENTREGA-ATUAL.md) para o fechamento desta edição.
O [PDF atual](apresentacao/apresentacao-parte-2-g09.pdf) tem oito páginas de
exposição e quatro de apoio; roteiro e fonte editável estão na pasta
[apresentacao](apresentacao/README.md).

Revisão de 25/11: **85 testes Python**, **30/30 critérios AWS**, matriz de
acesso **17/17**, ingestão funcional **6/6** e plano Terraform **sem
diferenças**. A consulta confirmou 150 grupos, 10.060 bytes e 1.149 ms, sem
reuso. Consulte o [checklist da entrega](CHECKLIST-AV2.md) para prazo,
apresentação e limites do ensaio em conta limpa. A submissão no Classroom
continua pendente de publicação da atividade.

## Experimento histórico de 19/11/2026

A validação final executada em 19/11/2026, na região obrigatória `us-east-1`,
mediu após um ciclo real de destroy e recriação:

- pipeline com SHA-256
  `8f7e09c80b1fa6e7eaec2065dae5817631516467bc908c615c04ac2b42f1a165`;
- 174.878 linhas trusted e 174.878 chaves distintas;
- 30 partições e 150 grupos refined;
- idempotência aprovada, mantendo R$ 526.021.301,72;
- backfill de uma partição com 5.821 linhas, 60 duplicatas removidas, 316
  rejeitados e 5 grupos;
- duas execuções FULL aprovadas com 141 s/282 DPU-s e 128 s/256 DPU-s;
- teste real da função de ingestão 6/6: `Put`, `Get`, `List` e `Delete` na raw,
  negação de `Get` na trusted/refined e limpeza de duas versões/marcadores sem
  resíduo;
- matriz de acesso 17/17: 6 chamadas reais do analyst e 11 simulações IAM da
  ingestion;
- consulta de negócio com 10.060 bytes, 1.115 ms total, 977 ms de engine e sem
  reuso;
- destroy de 59 recursos concluído;
- pós-destroy com 12 PASSA e 0 FALHA, estado vazio, nenhuma localização LF do
  g09, hash global preservado e backend ativo;
- recriação pareada com 59 recursos adicionados, 0 alterados e 0 destruídos;
- reconciliação pós-recriação com `No changes`;
- inventário final com 59 recursos, 11 data sources, tags corretas nos 12
  recursos compatíveis e nenhuma associação `AWSGlueServiceRole`;
- tamanhos S3 de 46.543.442 bytes raw, 5.584.100 bytes trusted e 50.858 bytes
  refined;
- SHA-256 igual no arquivo local, S3, configuração Glue e metadata;
- backfill isolado: 29 objetos não selecionados intactos em cada uma das
  camadas trusted e refined;
- verificador final com **26 PASSA, 0 FALHA** e **5 testes unitários OK**,
  medido com a versão do verificador vigente naquele dia.

A assinatura de acesso final é: **12 chamadas reais** (6 analyst + 6
ingestion) e **11 simulações IAM**, mantidas em evidências separadas para não
confundir teste funcional com simulação de política.

O dataset é sintético. O valor bruto mantém `cancelled` em categoria separada
e não representa receita reconhecida.

## Versão de fechamento de 21/11/2026

As correções finais estão descritas em [ENTREGA-ATUAL.md](ENTREGA-ATUAL.md).
O pipeline foi refatorado em funções de normalização, validação, deduplicação
e agregação, exercitadas em Spark 3.3.0 com Python 3.10 e Java 8.

- Quarentena é sobrescrita mesmo quando não há rejeições: arquivos antigos
  não ficam aparentando erros da execução atual.
- Relatórios usam `reports/runs/<JOB_RUN_ID>.json`; o wrapper confere o run e
  não aceita um relatório de outra execução.
- Idempotência compara métricas e SHA-256 do conteúdo de trusted, refined e
  quarentena. O hash inclui todas as linhas, com multiplicidade e ordem
  canônica, sem depender da ordem dos arquivos Parquet.
- A espera do Glue tem limite e reconhece `EXPIRED`; erro de API falha.
- O sanitizador preserva hashes e IDs; falha ao salvar evidência reprova a
  matriz de acesso.
- O verificador rejeita grants de compatibilidade `IAM_ALLOWED_PRINCIPALS`
  nos recursos do grupo. A permissão ampla do database foi removida nesta
  validação. Grants de outros grupos e administradores globais são preservados.
- O FULL substitui o conjunto completo de partições; o BACKFILL substitui
  somente as datas selecionadas. Datas inválidas e dias sem linhas válidas
  falham antes de alterar os destinos. Rejeitados sem data são contabilizados
  separadamente, pois não podem ser atribuídos a um dia de evento.

Os resultados históricos acima permanecem preservados. Não representam o
hash da versão nova; consulte o fechamento e as evidências de 21/11.

## Arquitetura

```text
gerador determinístico
        │ NDJSON, reentregas e anomalias
        ▼
S3 raw ── AWS Glue 4.0 ──► S3 trusted/Parquet ──► S3 refined/Parquet
  │                              │                         │
  └── quarentena                 └── order_date            └── dia/status
                                                           │
                                                   Glue Catalog + Athena
```

- Raw: evento recebido por item, particionado por `arrival_date`.
- Trusted: uma linha por `(order_id, order_item_id)`, particionada por
  `order_date`.
- Refined: uma linha por `(order_date, status)`.
- Pergunta: `SUM(quantity * unit_price)` por dia e status.
- Região: somente `us-east-1`.
- Prefixo AWS: `eda262-g09-`.
- Tags: `turma=eda262`, `grupo=g09` e
  `projeto=engenharia-de-dados`.
- Terraform: a raiz `parte-2` configura backend e provider e chama o módulo
  `parte-2/modules/data_lake`, que contém todos os recursos da stack.

IAM controla o acesso físico ao S3; Lake Formation controla catálogo e Athena.
O principal que executa o Terraform deve ser um usuário IAM já cadastrado como
administrador do Lake Formation. A stack não assume ownership das configurações
globais da conta compartilhada.

## Documentos principais

- [parte-2/README.md](parte-2/README.md): roteiro operacional detalhado;
- [DECISOES.md](DECISOES.md): decisões, medições e limitações;
- [REVISAO-AV2.md](REVISAO-AV2.md): achados e correções da revisão;
- [resumo de 19/11](evidencias/av2/resumo/revisao-19-11-2026.md): resultados
  AWS revisados;
- [evidências](evidencias/av2/README.md): inventário e regras de sanitização;
- [verificador](verificacao/verifica.sh): checks locais, AWS e pós-destroy;
- [conta dedicada](parte-2/conta-dedicada/README.md): procedimento opt-in,
  com pré-checagem somente leitura;
- [apresentação AV2](apresentacao/apresentacao-parte-2-g09.pdf) e
  [roteiro de 5 minutos](apresentacao/roteiro-5min.md).

## Pré-requisitos

- Terraform 1.7 ou superior;
- Python 3.9 ou superior;
- AWS CLI v2 e `jq`;
- credenciais do grupo configuradas fora do repositório;
- principal IAM preexistente como administrador do Lake Formation;
- acesso autorizado à conta acadêmica em `us-east-1`.

Nunca versione credenciais, `backend.hcl`, `terraform.tfvars`, estado,
planos binários, `.terraform/`, `.runtime/` ou `.generated/`.

## Backend

O estado da AV2 usa o mesmo backend criado por `parte-1/bootstrap`: bucket S3
`eda262-g09-tfstate` e tabela DynamoDB `eda262-g09-terraform-locks`, com a
chave `parte-2/terraform.tfstate` sob o prefixo `workspaces`. Na conta
compartilhada ele já existe e não deve ser recriado. Em conta limpa, a partir
da raiz:

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

O backend tem ciclo de vida separado da stack avaliada. `parte-2/bootstrap`
cria um par alternativo (`eda262-g09-av2-tfstate`) que não foi usado pela
entrega; se for adotado, ajuste `backend.hcl` para esses nomes.

## Stack AV2

```bash
cd ../../parte-2
cp backend.hcl.example backend.hcl
terraform init -backend-config=backend.hcl
terraform workspace select -or-create av2
terraform fmt -check -recursive
terraform validate
./scripts/capture_terraform.sh plan
./scripts/capture_terraform.sh apply
```

Os scripts usam logs com timestamp, sem cor, e um manifesto com SHA-256 para
garantir que o apply consuma exatamente o plano revisado.

Em um diretório já inicializado antes da modularização, repita
`terraform init -backend-config=backend.hcl` para instalar o módulo local. Na
conta compartilhada, o primeiro plano após a modularização deve listar apenas
endereços movidos para `module.data_lake` e terminar sem criar, alterar ou
destruir recursos. Se aparecer qualquer outra ação, não aplique.

## Dados, pipeline e consulta

```bash
./scripts/load_raw.sh
./scripts/test_idempotency.sh
./scripts/run_backfill.sh 2026-09-15
./scripts/run_query.sh ../consultas/av2-valor-bruto.sql
./scripts/verify_access_matrix.sh
./scripts/verify_ingestion_access.sh
```

O teste de idempotência usa o caminho exato devolvido pela consulta recém-criada
e valida explicitamente o estado `SUCCEEDED`; evidência antiga não é aceita
como substituta.

## Verificação

Da raiz do repositório:

```bash
cd ..
./verificacao/verifica.sh
./verificacao/verifica.sh --aws
```

Para a AV1 preservada:

```bash
./verificacao/verifica.sh --av1
```

## Destroy e recriação

```bash
./parte-2/scripts/capture_terraform.sh destroy-plan
CONFIRM_DESTROY=eda262-g09-av2 ./parte-2/scripts/destroy_and_verify.sh
```

O destroy exige confirmação explícita, verifica o SHA-256 do plano pareado e
não remove o backend. Em 19/11, removeu 59 recursos; a auditoria confirmou S3
do backend habilitado, DynamoDB ativo, estado da stack vazio e configurações
globais do Lake Formation inalteradas. O plano de recriação timestampado em
`20261119T025835Z` previu 59 criações, 0 alterações e 0 destruições; seu apply
foi concluído às `20261119T030118Z` com **59 adicionados, 0 alterados e 0
destruídos**. A reconciliação seguinte retornou `No changes`.

## Limitações

- O ciclo prova destroy/recriação da stack do g09, não que a conta acadêmica
  compartilhada estivesse vazia; o backend é preexistente e separado.
- A conta é compartilhada; administração global do Lake Formation fica fora da
  stack.
- O teste real da função de ingestão usa somente um objeto sintético exclusivo;
  a carga volumosa continua sendo executada pelas credenciais operacionais do
  grupo.
- O contrato educacional usa 30 dias, datas de pedido imutáveis e quarentena
  como snapshot do modo executado.
- O projeto não promete corrigir mudanças retroativas de `order_timestamp`,
  remover automaticamente partições que desapareçam da raw nem registrar um
  motivo textual por rejeição.
- A modularização, o verificador exato de grants e o procedimento de conta
  dedicada foram testados apenas localmente; `terraform fmt`, `validate`,
  `plan` e a execução `--aws` ainda precisam ser repetidos no ambiente
  operacional.
