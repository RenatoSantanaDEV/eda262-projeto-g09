# Decisões técnicas - versão de fechamento

A seção a seguir registra as decisões novas de 21/11/2026. As medições e
limitações citadas mais abaixo pertencem ao histórico de 18-19/11; o estado
atual verificável está em ENTREGA-ATUAL.md.

## Decisões da revisão final

1. **Separação entre transformação e execução.** Normalizar, validar,
   deduplicar e agregar são funções testáveis sem inicializar Glue/S3. Dez
   testes Spark cobrem decimal, nulos, datas inválidas, desempates,
   particionamento, backfill, limpeza de quarentena e conteúdo.
2. **Relatório por execução.** Cada run grava uma chave própria com seu
   `JOB_RUN_ID` e SHA do código. O identificador reservado é lido da resposta
   de `getResolvedOptions`, sem registrá-lo novamente na lista de argumentos.
   A primeira tentativa real detectou esse conflito de integração; ela falhou
   antes de processar os dados e foi corrigida, com log preservado.
3. **Prova de idempotência mais forte.** Além das quatro métricas, calculamos
   SHA-256 sobre os hashes ordenados das linhas completas. A multiplicidade
   faz parte da assinatura. O custo é uma ordenação distribuída e a leitura
   sequencial dos hashes pelo driver; adequado ao experimento de 175 mil
   itens, sem afirmar escalabilidade ilimitada.
4. **Snapshots consistentes com o relatório.** Quarentena vazia também é
   gravada, eliminando rejeições antigas. FULL usa overwrite estático;
   BACKFILL usa overwrite dinâmico. Nenhuma data solicitada pode ficar sem
   linha válida e ser silenciosamente ignorada. Sem dados válidos, o job
   falha e preserva os destinos. As camadas são escritas sequencialmente:
   não há transação atômica entre buckets, e leitores devem aguardar sucesso.
5. **Grants conferidos pela API.** O plano sem `ignore_changes` tentou
   recriar dois grants com `ALL`, enquanto `list-permissions` mostrou apenas
   `DESCRIBE`, sem grant option. Essa diferença do provider justifica manter
   a exceção. A comparação exata dos três papéis e dos grants de
   compatibilidade é obrigatória após implantação e passou na AWS. Não
   alteramos o singleton global da conta compartilhada.
6. **Compatibilidade restrita ao projeto.** `scripts/harden_catalog.sh`
   lista o que removeria por padrão; `--apply` remove apenas grants
   `IAM_ALLOWED_PRINCIPALS` do database `eda262_g09_av2` e suas tabelas.
   O script recusa outro database e preserva administradores/outros grupos.
   Deve ser executado após um apply em uma conta nova, antes da verificação.
7. **Limites operacionais explícitos.** Polling limitado a 2.400 s por padrão,
   incluindo falha terminal `EXPIRED` e erro de API. Timeout local não cancela
   automaticamente o job: o operador deve verificar o run informado.
   Falha do sanitizador ou da gravação de evidência reprova o teste.

## Registro histórico preservado

# Decisões de Engenharia — AV2 — Grupo 09

Renato Santana (representante), João Augusto Pimentel, Raphael Barros e Lara
Pessoa.

Pergunta de negócio: **qual foi o valor bruto de vendas por dia e status dos
pedidos?**

Os números locais são reproduzíveis com seed `20261118`. A validação AWS final
foi feita em **19/11/2026**, na conta acadêmica do grupo, em `us-east-1`, após
destroy e recriação da stack. As saídas sanitizadas estão em
`evidencias/av2/brutas/`; nenhum número remoto foi reconstruído de memória.

## Estado atual

O ciclo final removeu 59 recursos da stack, aprovou 12 checks pós-destroy,
recriou os mesmos 59 recursos com a policy runtime mínima do Glue e obteve
`No changes` na reconciliação. O backend e as configurações globais do Lake
Formation permaneceram inalterados.

O pipeline revisado possui SHA-256
`8f7e09c80b1fa6e7eaec2065dae5817631516467bc908c615c04ac2b42f1a165` e MD5
`335728a0a8759c911fc0bbcefee77964`. O arquivo
`evidencias/av2/brutas/code-sha256.txt` registra os hashes locais dos artefatos
autorais; os relatórios Glue revisados repetem o SHA-256 do pipeline.

Após a recriação, duas execuções FULL, idempotência, backfill, consulta Athena e
seis chamadas reais da função de ingestão foram aprovadas. Os resultados atuais
aparecem primeiro nas seções abaixo; as medições de 18/11 e da rodada
incremental anterior permanecem identificadas como históricas. O dataset e
todos os identificadores de clientes são sintéticos. O valor bruto inclui
`cancelled` em uma categoria separada e não é receita reconhecida.

## 1. Grão e chaves

### Raw

Um evento recebido de um item de pedido. Reentregas são preservadas. A partição
`arrival_date` representa o dia de chegada, não o dia do pedido.

### Trusted

Uma linha por item vigente do pedido. A chave composta é
`(order_id, order_item_id)`; o evento de maior `updated_at` vence,
`arrival_date` é o segundo critério e o SHA-256 do conteúdo normalizado é o
desempate final. Essa chave permite que um pedido possua vários itens sem
somá-los como pedidos independentes.

### Refined

Uma linha por `(order_date, status)`, com:

- pedidos distintos;
- itens;
- unidades;
- valor bruto `SUM(quantity * unit_price)`.

### Números locais

- pedidos base: **120.000**;
- itens base: **185.938**;
- eventos raw, incluindo reentregas: **187.854**;
- reentregas plantadas: **1.916**;
- eventos válidos antes da deduplicação: **176.680**;
- duplicatas válidas removíveis: **1.802**;
- linhas trusted esperadas: **174.878**;
- grupos refined esperados: **150** (30 dias × 5 status).

Aceitamos perder o histórico de versões na trusted: ele permanece íntegro na
raw, enquanto a trusted expõe apenas o estado mais recente de cada item.

## 2. Limpeza real

O pipeline não apenas converte formato. Ele:

1. remove espaços e normaliza status para minúsculas e UF para maiúsculas;
2. converte preço com vírgula para decimal;
3. tipa timestamps, quantidade e preço;
4. rejeita chave/cliente/cidade vazios, timestamp inválido, status fora da
   lista, quantidade não positiva, preço não positivo e UF inválida;
5. grava rejeitados em `raw/quality/rejected/`;
6. deduplica pela chave composta.

Medição do gerador:

- eventos normalizáveis plantados: **10.861**;
- eventos inválidos/rejeitáveis: **11.174**;
- valor bruto esperado após limpeza e deduplicação: **R$ 526.021.301,72**.

Medições reais das execuções FULL pós-recriação:

- `raw_rows_read`: **187.854**;
- `rejected_rows_selected`: **11.174**;
- `valid_rows_before_dedup_selected`: **176.680**;
- `duplicates_removed_selected`: **1.802**;
- `trusted_rows_after_run`: **174.878**;
- `trusted_distinct_keys_after_run`: **174.878**;
- partições trusted: **30**;
- grupos refined: **150**.

Esses valores coincidem com as contagens e os totais do resumo local do
gerador; não foi feita comparação registro a registro. Evidências:
`generation-summary.json`, `pipeline-full-20261119T030340Z-report.json` e
`pipeline-full-20261119T030719Z-report.json`.

## 3. Idempotência

A carga local gera os mesmos objetos e usa `aws s3 sync`, portanto não cria
chaves novas a cada execução. No Glue, bookmarks ficam desabilitados de forma
intencional: o job relê a fonte, deduplica deterministicamente e usa overwrite
dinâmico por `order_date`. Reexecutar troca as mesmas partições em vez de
acrescentar arquivos lógicos.

O teste `scripts/test_idempotency.sh` compara antes/depois:

- linhas trusted;
- chaves distintas;
- partições;
- valor bruto.

Resultado pós-recriação em 19/11: **PASSOU**. Antes e depois das duas
reexecuções havia
**174.878 linhas**, **174.878 chaves distintas**, **30 partições** e valor
bruto de **R$ 526.021.301,72**. Evidência:
`idempotency-20261119T030334Z.json`, com `passed: true`. A evidência
`idempotency-20261119T023658Z.json` permanece somente como histórico da rodada
anterior.

## 4. Particionamento e backfill

- Raw: `arrival_date`, porque chegada e evento podem divergir.
- Trusted: `order_date`, alinhada aos filtros e ao backfill.
- Refined: `order_date`, alinhada à pergunta diária.

O conjunto possui **33 partições raw de chegada** e **30 dias de evento**. O
backfill padrão reconstrói `2026-09-15`, que possui **6.197 eventos raw**; **216**
deles chegaram mais de dois dias depois. O modo `BACKFILL` lê a raw, seleciona
o dia do evento, deduplica e sobrescreve somente essa partição na trusted e na
refined.

Resultado pós-recriação em 19/11 do backfill de `2026-09-15`:

- partições escritas: **1**;
- eventos válidos antes da deduplicação: **5.881**;
- duplicatas removidas na partição: **60**;
- linhas rejeitadas na partição: **316**;
- linhas trusted da partição: **5.821**;
- grupos refined da partição: **5**;
- total global depois: **174.878 linhas e 174.878 chaves distintas**;
- grupos refined depois: **150**.

O job terminou em **107 s**, com **214 DPU-s**. Evidência:
`pipeline-backfill-20261119T031009Z-report.json`. O snapshot anterior à
reescrita foi capturado em `backfill-recreated-before-objects.json`. A
reconciliação `backfill-recreated-isolation.json` confirmou que os 29 objetos
não selecionados permaneceram idênticos por chave, ETag, tamanho e
`LastModified` em cada camada trusted e refined. Isso prova isolamento de
objetos/partições, não comparação registro a registro.

Aceitamos o custo de reler a raw para assegurar que chegadas tardias sejam
incorporadas sem depender de uma lista de arquivos manual.

## 5. Formato

- Raw: NDJSON, apropriado para eventos imutáveis e inspeção do original.
- Trusted/refined: Parquet com schema explícito, compressão padrão do Spark e
  leitura colunar no Athena.

Tamanhos medidos no S3 após o job:

- raw NDJSON: **46.543.442 bytes**, 33 objetos;
- trusted Parquet: **5.584.100 bytes**, 30 objetos — redução de **88,0%**
  contra a raw;
- refined Parquet: **50.858 bytes**, 30 objetos — redução de **99,89%**
  contra a raw.

O dataset volumoso é gerado localmente e não exige versionar um CSV gigante.
Os tamanhos atuais e os hashes do ciclo pós-recriação estão em
`inventory-recreated-final.json`.

## 6. Lake Formation e menor privilégio

Há três registros de localização, um por bucket de camada:

- ingestão: `DATA_LOCATION_ACCESS` apenas na raw;
- pipeline Glue: localização nas três camadas e `SELECT/DESCRIBE` das tabelas;
- analista: `SELECT/DESCRIBE` apenas na tabela refined; o IAM limita o S3 à
  refined e ao bucket de resultados.

IAM e Lake Formation são usados juntos; conceder somente um deles não basta. O
Terraform histórico cadastrou o executor como administrador do Lake Formation
e criou os grants declarados. O verificador antigo, porém, só conferia a
presença dos recursos no código. O verificador atual pagina a listagem global
de `list-permissions` e filtra somente os três ARNs do g09. A captura derivada
`lakeformation-g09-review.json` confirmou o formato real da API; a validação
paginada pós-recriação foi aprovada no fechamento de **26 PASSA, 0 FALHA**, que
também executou **5 testes unitários**. Evidência:
`final-verification-20261119T115835Z.txt`.

A revisão independente de 19/11 mostrou que aqueles filtros exigiam a presença
dos grants, mas aceitavam extras: `ALL` e grant options nos databases e
`SELECT` com `TableWildcard` para o analyst. Decisão: o modo `--aws` passou a
comparar o conjunto exato de permissões por principal e recurso:

| Papel | Conjunto aceito |
|---|---|
| ingestion | `DATA_LOCATION_ACCESS` somente na raw |
| pipeline | três localizações, `DESCRIBE` no database, `SELECT` e `DESCRIBE` nas três tabelas |
| analyst | `DESCRIBE` no database, `SELECT` e `DESCRIBE` somente na refined |

São rejeitados permissões extras, `ALL`, qualquer grant option (inclusive
`DESCRIBE` sobre um `DESCRIBE` permitido), `TableWildcard`, colunas restritas
ou excluídas, grants em outros recursos e recursos sem `CatalogId` ou de outro
catálogo. O tipo de recurso faz parte da regra: `DESCRIBE` só vale em `Table`;
`SELECT` vale em `Table` ou em `TableWithColumns` com `ColumnWildcard` igual a
`{}` na tabela exata, que é como a API devolve um `SELECT` de tabela inteira.
Assim, trocar `SELECT` para `Table` e `DESCRIBE` para `TableWithColumns`
reprova. A paginação
com limite de 100 páginas e detecção de token repetido foi preservada. Número:
**30 testes locais** cobrem a captura real sanitizada, a representação
combinada, os dois casos reproduzidos na revisão, a troca de tipo de recurso,
`CatalogId` ausente, grant option isolado, `TableWildcard` isolado do pipeline
e outros desvios, além de paginação com `aws` simulado. A nova comparação **ainda não foi executada na
AWS**; o 26/0 acima continua sendo a medição da versão anterior.

Os grants de database mantêm `ignore_changes` em `permissions` e
`permissions_with_grant_option`. Remover essa proteção sem um plano real contra
o estado poderia gerar atualização ou recriação de grants, e nenhuma mudança de
privilégio real foi autorizada nesta correção. A divergência que o
`ignore_changes` esconderia do Terraform passa a ser detectada pelo verificador
exato. O grant `ALL` do executor no database continua fora da verificação de
papéis: ele pertence ao administrador que cria e remove as tabelas.

A conta acadêmica é compartilhada e contém recursos de outros grupos. Por isso,
o singleton global `aws_lakeformation_data_lake_settings` não pode permanecer
sob ownership desta stack. A revisão usa `removed` com `destroy = false`: após
backup e apply, o Terraform esquece somente o endereço no estado e não envia
alteração ao Lake Formation. A lista remota de administradores é preservada
exatamente como está, pois o baseline anterior é desconhecido. O principal de
execução já ser administrador do Lake Formation passa a ser pré-requisito.

A migração foi aplicada com **0 adicionar, 0 alterar e 0 destruir**. O hash
global antes/depois permaneceu idêntico, conforme
`lf-global-preserved-review.json`. Após a recriação, a matriz funcional
confirmou **17/17** checks em `access-matrix-20261119T115835Z.json`: 6 chamadas
reais do analyst e 11 simulações IAM da ingestion. O analyst consultou refined,
não consultou raw/trusted e não leu seus objetos. A evidência anterior
`access-matrix-20261119T023530Z.json` permanece apenas como histórico.

Após a recriação, um teste separado assumiu a função de ingestão e aprovou
**6/6 chamadas reais**: `Put`, `Get`, `List` e `Delete` em um objeto sintético
exclusivo da raw, com `Get` negado em objetos reais trusted/refined. O cleanup,
executado pelo principal original, removeu as duas versões/marcadores somente
dessa chave e confirmou zero resíduo. Evidência:
`ingestion-access-real-20261119T031029Z.json`. Esse teste reduz a limitação da
simulação IAM, mas não transforma a carga volumosa em uma execução pela função.
Somados sem misturar seus métodos, são **12 acessos reais** (6 analyst + 6
ingestion) e **11 avaliações simuladas**.

IAM controla a leitura e escrita dos objetos; `DATA_LOCATION_ACCESS` governa o
uso das localizações pelo catálogo, não escrita S3. A policy gerenciada
`AWSGlueServiceRole` foi substituída por policy inline: escrita de logs somente
em `/aws-glue/*`, descrição de logs e `cloudwatch:PutMetricData` limitada ao
namespace `Glue`. As permissões S3, catálogo e Lake Formation continuam nos
statements restritos do projeto, preservando 59 recursos gerenciados.

O executor suportado nesta entrega é um usuário IAM preexistente como
administrador do Lake Formation. ARNs de sessão SSO/STS não são convertidos
automaticamente; o operador deve interromper antes do plano quando o preflight
retornar `arn:aws:sts` ou o usuário não estiver em `DataLakeAdmins`.

## 7. Custo

### Geração e armazenamento

O dataset tem **46.543.442 bytes** na raw. No ciclo pós-recriação, os dois FULL
e o BACKFILL somaram **752 DPU-s**. Com a tarifa de exemplo de **US$ 0,44 por
DPU-h**, a estimativa é `752 / 3.600 × 0,44 = US$ 0,0919111`. A captura final
acumulada contém 11 runs e soma **2.556 DPU-s**, ou **US$ 0,3124**; inclui as
oito execuções preservadas da rodada anterior. Isso não é uma fatura e exclui
S3, CloudWatch, Athena e outras chamadas. Fontes:
`glue-cost-estimate-final.json`, `glue-cost-estimate-review.json` e
<https://aws.amazon.com/glue/pricing/>.

### Athena

O script `run_query.sh` captura:

- Query execution ID;
- bytes examinados;
- tempo total e de engine;
- reutilização de resultado;
- resultado JSON.

Meta declarada: a consulta da pergunta de negócio deve ler **menos de 1 MiB**
e custar no máximo **US$ 0,00005**. O workgroup impõe o menor teto aceito pela
API/provider: **10 MiB (10.485.760 bytes)**.

Medição revisada em 19/11/2026, `us-east-1`:

- Query execution ID: `73a2ef12-0fb8-477f-b293-6c70a5d0d404`;
- estado: `SUCCEEDED`;
- bytes processados: **10.060 bytes**;
- tempo total: **1.115 ms**; engine: **977 ms**;
- resultado reutilizado: **não**;
- preço oficial consultado: **US$ 5/TB**;
- custo proporcional: `10.060 / 1.000.000.000.000 × US$ 5` =
  **US$ 0,0000000503**;
- estimativa pelo mínimo de 10 MB: aproximadamente **US$ 0,00005**.

A meta de leitura foi atendida. Evidências: arquivos
`athena-20261119T032256Z-*`. A referência da AWS registra US$ 5/TB,
arredondamento ao MB e mínimo de 10 MB por consulta:
<https://docs.aws.amazon.com/whitepapers/latest/big-data-analytics-options/amazon-athena.html>.
O valor de US$ 0,00005 é uma estimativa, não custo faturado comprovado. O cutoff
de 10 MiB é uma proteção operacional e não uma garantia de orçamento.

## 8. Provisionamento e destroy

Inventário lógico esperado:

- 5 buckets;
- 1 database e 3 tabelas Glue;
- 1 job Glue;
- 1 workgroup Athena;
- 3 papéis IAM;
- 3 registros Lake Formation.

Políticas, grants, criptografia, bloqueios públicos e objetos de script são
recursos auxiliares. A execução histórica continha **60 recursos gerenciados**
e **11 data sources**, ou **71 entradas**. Após a migração segura do singleton
global, o inventário atual é **59 recursos gerenciados** e **11 data sources**,
ou **70 entradas**. O apply de forget terminou em **0/0/0** e preservou o hash
global. O inventário independente, as tags nos 12 recursos compatíveis e o
plano **No changes** foram confirmados em `inventory-code-review.json` e
`terraform-review-no-drift.txt`.

Esse fechamento incremental antecedeu a troca de `AWSGlueServiceRole` pela
policy runtime mínima. O ciclo real descrito a seguir é a prova atual dessa
configuração; os arquivos incrementais permanecem apenas como histórico.

Destroy limpo — **CONCLUÍDO EM 19/11/2026**:

- plano: **0 criar, 0 alterar, 59 remover**;
- resultado: **59 removidos**;
- pós-destroy: **12 PASSA, 0 FALHA**;
- estado: **0 recursos**;
- localizações Lake Formation do g09: **0**;
- hash global Lake Formation: **inalterado**;
- backend: bucket S3 `Enabled` e DynamoDB `ACTIVE`;
- recursos órfãos detectados: **0**.

Fontes: `terraform-destroy-review-executed.txt`,
`post-destroy-review-executed.txt` e
`post-destroy-scope-preservation.json`.

O plano de recriação `20261119T025835Z` foi validado com **59 criar, 0 alterar
e 0 destruir**, incluindo a policy runtime mínima. O apply pareado terminou às
`20261119T030118Z` com **59 adicionados, 0 alterados e 0 destruídos**.

Fontes: `terraform-plan-20261119T025835Z.txt`,
`terraform-apply-plan-20261119T025835Z-at-20261119T030118Z.txt` e
`terraform-plan-apply-20261119T025835Z-at-20261119T030118Z.json`.

A reconciliação pós-recriação retornou `No changes` em
`terraform-recreated-no-drift.txt`. `inventory-recreated-final.json` confirmou
**59 recursos**, **11 data sources**, tags corretas nos **12 recursos
compatíveis**, tamanhos esperados, SHA-256 igual no arquivo local, objeto S3,
configuração Glue e metadata, hash global LF preservado e nenhuma associação
`AWSGlueServiceRole`.

O backend remoto possui ciclo de vida separado e não é removido pelo destroy da
stack.

### Modularização

A AV1 já empacotava a stack em `parte-1/modules/data_lake`. Para manter essa
organização no projeto incremental, a stack AV2 passou para
`parte-2/modules/data_lake`. A raiz conserva backend, provider, tags padrão,
variáveis, os 16 outputs com os mesmos nomes e o bloco `removed` do singleton
global. `moved.tf` declara **36 blocos**, um por recurso, que cobrem as **59
instâncias** do plano de recriação, inclusive as de `for_each`; os 11 data
sources passaram para o módulo sem alterar sua quantidade. O caminho do script
Glue é passado pela raiz para manter `./glue/pipeline_orders.py` no estado, e o
arquivo do pipeline permanece byte a byte igual (SHA-256 `8f7e09…`).

Resultado esperado na conta compartilhada: plano apenas com movimentações e
**0 adicionar, 0 alterar e 0 destruir**. Isso foi conferido estaticamente contra
`terraform-plan-20261119T025835Z.txt` por testes locais, mas o plano real ainda
não foi executado.

### Conta dedicada

O procedimento regular continua exigindo backend e administrador do Lake
Formation preexistentes. Para uma conta dedicada, `parte-2/conta-dedicada`
oferece um caminho opt-in: confirmação dupla do ID da conta, bloqueio da conta
compartilhada, exigência de usuário IAM, pré-checagem somente leitura e
fail-closed, reuso do bootstrap separado de `parte-1/bootstrap` e registro
opcional do administrador do Lake Formation com simulação por padrão. A
pré-checagem confirma o dono dos buckets com `--expected-bucket-owner`, exige
versionamento `Enabled` no backend e tabela de lock `ACTIVE` com `LockID`,
lista com paginação os registros do Lake Formation dos três buckets e procura
database, job, workgroup e papéis conflitantes; acesso negado nunca conta como
ausência.

O backend real da AV2 é o de `parte-1/bootstrap` (`eda262-g09-tfstate` e
`eda262-g09-terraform-locks`), e `parte-2/backend.hcl.example` foi corrigido
para esses nomes. `parte-2/bootstrap`, com `eda262-g09-av2-tfstate`, é uma
alternativa não usada pela entrega. A chave `parte-2/terraform.tfstate` do
exemplo não aparece nas evidências e deve ser conferida com o `backend.hcl`
local antes do próximo `init`. A configuração global do Lake
Formation não volta para a stack regular. Os buckets mantêm o padrão
acadêmico; como nomes S3 são globais, a stack não pode existir em duas contas ao
mesmo tempo, e a liberação precisa ser coordenada com o destroy na conta de
origem. Nenhum passo foi executado em outra conta.

## 9. Limitações da evidência atual

- O ciclo real prova destroy/recriação da stack do g09, mas não que toda a conta
  AWS compartilhada estivesse vazia; o backend remoto possui ciclo de vida
  separado.
- O administrador Lake Formation é um pré-requisito externo. A stack não deve
  assumir ownership nem modificar configurações globais de uma conta
  compartilhada.
- A publicação remota, o commit/tag final e o envio são etapas administrativas
  fora das evidências técnicas desta execução.
- A modularização, o verificador exato de grants e o procedimento de conta
  dedicada posteriores à medição foram validados apenas localmente. Falta um
  plano real sem mudanças, uma execução `--aws` e, se o avaliador exigir, um
  ensaio em conta dedicada.
- A função de ingestão foi provada com seis chamadas S3 reais sobre um objeto
  sintético exclusivo; a carga volumosa foi executada com as credenciais
  operacionais do grupo, não pela função assumida.
- Os dados são sintéticos e cobrem 30 dias. As medições não demonstram
  desempenho, custo ou qualidade com dados de produção.
- O contrato educacional assume `order_timestamp` imutável. O FULL não promete
  remover partições ausentes da raw; o BACKFILL não reconcilia uma chave movida
  para outro dia; a quarentena é snapshot por modo, sem texto de motivo.
