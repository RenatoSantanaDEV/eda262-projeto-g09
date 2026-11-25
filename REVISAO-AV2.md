# Revisão final de 21/11/2026

Consulte ENTREGA-ATUAL.md para o resultado consolidado da versão final.
A revisão abaixo é um registro histórico de 18-19/11/2026: expressões como
"código atual", hashes, contagens de testes e pendências nessa seção se
referem à versão daquela data, não substituem a validação de 21/11.

Correções implementadas nesta rodada: falha do sanitizador propagada pela
matriz; hashes/IDs preservados; quarentena vazia regravada; polling limitado;
relatórios por run; comparação de conteúdo na idempotência; transformação
separada em funções e testes Spark; detecção e remoção de compatibilidade LF.
A exceção `ignore_changes` foi investigada com plano real e resposta da API;
permanece documentada, com verificação externa de grants obrigatória.

---

# Revisão técnica da AV2 — Grupo 09

Revisão iniciada em 18/11/2026 e fechada em 19/11/2026 sobre a entrega de
pedidos de e-commerce. Este documento separa verificações locais, ciclo AWS
final, execução histórica e limitações remanescentes.

## Resultado executivo

O projeto possui as três camadas exigidas, transformação Glue, catálogo,
Athena, Lake Formation, dados sintéticos volumosos, idempotência, backfill,
scripts operacionais e documentação. A revisão encontrou falhas de prova,
casos-limite e duas incompatibilidades observadas somente na execução real.

O Terraform revisado foi formatado e validado. Um ciclo autorizado removeu 59
recursos, aprovou 12 checks pós-destroy, recriou 59 recursos com a policy
runtime mínima e obteve `No changes`. Duas execuções FULL, idempotência,
backfill, consulta e seis chamadas S3 reais da função de ingestão foram
aprovadas com o código atual. O inventário final confirmou 59 recursos, 11 data
sources, 12/12 tags, tamanhos esperados, SHA igual em quatro pontos e nenhuma
associação `AWSGlueServiceRole`. A matriz pós-recriação terminou **17/17** e o
verificador final terminou **26 PASSA, 0 FALHA**, além de **5 testes unitários
OK**.

## Achados e correções

| Achado | Risco | Correção aplicada | Validação |
|---|---|---|---|
| README saía de `parte-2/` antes de chamar `./scripts` | comandos inválidos | diretórios e comandos corrigidos | stack, carga, jobs e verificadores executados; backend preexistente e separado |
| `DECISOES.md` ainda descrevia a AV1 | arquivo oficial ambíguo | AV2 tornou-se canônica; AV1 preservada em `DECISOES-AV1.md` | aprovado |
| deduplicação empatava em `updated_at` e `arrival_date` | resultado não determinístico | SHA-256 do conteúdo normalizado é o desempate final | aprovado com o SHA atual |
| evidências não vinculavam o código executado | prova podia pertencer a outra revisão | SHA-256 no objeto S3, argumento do job, relatório Glue e manifesto local | aprovado: SHA `8f7e09...` |
| idempotência aceitava métricas ausentes dos dois lados | falso positivo | colunas obrigatórias, valores positivos, igualdade chave/linha e comparação estrita | aprovado em `idempotency-20261119T030334Z.json` |
| segunda execução Glue encontrou `ConcurrentRunsExceededException` mesmo após `SUCCEEDED` | teste interrompido por liberação tardia do slot | retry limitado a esse erro, com timeout de 180 s; outros erros falham imediatamente | aprovado na reexecução de idempotência |
| pós-destroy tratava qualquer erro como ausência | `AccessDenied` podia ocultar órfão | apenas códigos de inexistência são aceitos; outros erros falham | aprovado: 12 PASSA, 0 FALHA |
| verificador declarava grants válidos pela presença no Terraform | falso positivo | declaração local e grants efetivos agora são resultados separados | `--aws` final aprovado |
| `list-permissions --principal` sem recurso falhou na API | `InvalidInputException` | listagem global única e filtro por ARN do principal no `jq` | aprovado no verificador final 26/0 |
| resposta real usa `DataLocation` e separa SELECT em `TableWithColumns` de DESCRIBE em `Table` | grants válidos eram rejeitados | filtros aceitam o schema real e exigem wildcard de colunas, SELECT e DESCRIBE | aprovado no verificador final 26/0 |
| a primeira página retornou `NextToken` | grants de páginas seguintes eram ignorados | paginação explícita, limite de 100 páginas e detecção de token repetido | aprovado no verificador final 26/0 |
| configurações globais do Lake Formation estavam no estado da stack | apply/destroy podia alterar administradores e recursos de outros grupos | `removed` com `destroy=false`; baseline remoto preservado e admin preexistente vira pré-requisito | aprovado: apply 0/0/0 e hash global idêntico |
| `sync --delete` não estava coberto pela política de ingestão | carga assumida não poderia remover objeto antigo | `s3:DeleteObject` restrito a `raw/orders/*` | aprovado: simulação e 6/6 chamadas reais |
| UF aceitava qualquer combinação de duas letras | dados inválidos poderiam entrar na trusted | lista explícita das 27 UFs | pipeline revisado aprovado |
| acesso por camada não tinha prova funcional | grants declarados sem teste de uso | script assume analyst, consulta refined, nega raw/trusted e simula ingestion | aprovado: 17/17 verificações |
| execução antiga era apresentada como atual | números corretos para código anterior, mas não para a revisão | README, decisões e resumo marcam a execução como histórica | ciclo atual recapturado e fechado |
| valor bruto podia ser interpretado como receita | cancelados estão incluídos | documentação explicita que é dado sintético e não receita reconhecida | documentado |
| falha de consulta podia reutilizar resultado Athena antigo | falso positivo de idempotência | caminho exato retornado por `run_query.sh`, estado `SUCCEEDED` obrigatório e falha explícita fora de `set -e` | harness local bloqueou arquivo antigo com rc 1 |
| logs Terraform eram sobrescritos e plano/apply não estavam ligados | perda de proveniência | nomes UTC imutáveis, `-no-color`, SHA-256 do plano e manifesto consumido pelo apply/destroy | aprovado no destroy/recreate 59/59 |
| README da raiz continuava centrado na AV1 | entrada principal ambígua | AV2 promovida; AV1 preservada em `README-AV1.md` | aprovado |
| exemplo Athena usava 1 GiB | proteção 100 vezes maior que o default | exemplo corrigido para 10 MiB | aprovado no plano `20261119T025835Z` |
| `AWSGlueServiceRole` era ampla | menor privilégio anulado | substituída por policy inline de logs e métricas; S3/catálogo permanecem restritos | aprovado: três jobs Glue pós-recriação |

## Ajustes após a revisão independente de 19/11

Aplicados depois do ciclo AWS medido. Nenhum deles foi executado na AWS; a
validação abaixo é local.

| Achado | Risco | Correção aplicada | Validação local |
|---|---|---|---|
| filtros LF aceitavam `ALL`, grant options e `SELECT` com `TableWildcard` | verificador aprovava excesso de privilégio | comparação exata por papel, recurso e tipo de recurso em `scripts/lf_grants.py`, com `CatalogId` obrigatório; paginação isolada em `scripts/verify_lf_grants.sh` | 30 testes: captura real, formato combinado, casos da revisão, troca `Table`/`TableWithColumns`, `CatalogId` ausente, grant option isolado, `TableWildcard` isolado, extras, ausências e paginação simulada |
| `ignore_changes` nos grants de database escondia divergência do Terraform | drift de privilégio silencioso | mantido para não provocar mudança real de privilégio sem plano; drift passa a ser detectado pelo verificador exato | decisão documentada em `DECISOES.md` |
| stack AV2 fora de módulo, ao contrário da AV1 | aderência ao requisito de stack empacotada | recursos em `modules/data_lake`; 36 blocos `moved`; outputs, caminho do Glue e `removed` global na raiz | 10 testes estáticos contra o plano de 59 criações, os 11 data sources e o backend real; plano real pendente |
| conta limpa dependia de backend e administrador LF externos | reprodução em conta do avaliador sem roteiro seguro | `conta-dedicada/` com confirmação dupla, bloqueio da conta compartilhada, preflight somente leitura e fail-closed (dono do bucket, versionamento, lock `LockID`, registros LF paginados, job, workgroup) e registro de administrador opt-in | 25 testes com `aws` simulado; nenhum teste em conta real |
| `backend.hcl.example` apontava para `eda262-g09-av2-tfstate`, diferente do backend registrado nas evidências | `init` em conta limpa ou nova cópia apontaria para outro estado | exemplo usa `eda262-g09-tfstate` e `eda262-g09-terraform-locks` de `parte-1/bootstrap`; READMEs ajustados | teste compara o exemplo com o bootstrap e as evidências |
| slide 2 dizia atrasos de até 5 dias | imprecisão: três eventos chegam em 6 dias | "até 6 dias, incluindo reentregas" no slide, nas notas e no roteiro | PPTX renderizado sem cortes |
| desempate omitia `arrival_date` | descrição incompleta | slide 4, notas e roteiro citam `updated_at`, `arrival_date` e SHA-256 | renderização conferida |
| roteiro permitia marcar publicação como concluída sem o envio | falso "MEDIDO" | só após `main`, tag `av2-entrega` e envio do link e do PDF | texto revisado |
| PDF incorporava Liberation Sans | diverge da exigência de Arial | PDF refeito em Arial incorporada, com oito páginas de exposição e quatro de apoio | fontes e renderização verificadas nesta edição |

Os testes de higiene também garantem que `.py`, `.sh`, `.tf` e `.sql` não têm
comentários explicativos nem docstrings, preservando os shebangs.

## Segurança e rastreabilidade

- região fixa em `us-east-1`;
- nenhum arquivo de credencial, estado, plano, backend operacional ou tfvars
  operacional deve ser versionado;
- credenciais temporárias da matriz ficam em diretório temporário com modo
  restrito, não são impressas e são removidas ao sair;
- logs e JSON passam pelo sanitizador antes de entrar em evidências;
- `code-sha256.txt` registra hashes dos artefatos autorais;
- pipeline atual: SHA-256
  `8f7e09c80b1fa6e7eaec2065dae5817631516467bc908c615c04ac2b42f1a165`.

## Validações concluídas

- `terraform fmt -check -recursive`: aprovado;
- `terraform validate`: aprovado no ambiente operacional usado para a
  atualização AWS;
- compilação Python: aprovada;
- 5 testes unitários Python: aprovados;
- sintaxe de todos os scripts Bash: aprovada;
- `git diff --check`: aprovado;
- varredura local de padrões de segredo: sem correspondências;
- teste simulado do pós-destroy: `AccessDenied` falha e respostas de ausência
  passam;
- atualização incremental histórica: 0 adicionar, 3 alterar, 0 destruir;
- matriz histórica antes do destroy: 17/17 verificações aprovadas;
- remoção do ownership global: 0 adicionar, 0 alterar, 0 destruir e hash remoto
  idêntico antes/depois;
- idempotência pós-recriação: 174.878 linhas/chaves, 30 partições e R$
  526.021.301,72 inalterados;
- backfill pós-recriação: uma partição, 5.821 linhas, 60 duplicatas, 316
  rejeitados, 5 grupos e 214 DPU-s;
- função de ingestão: 6/6 chamadas S3 reais e cleanup sem resíduo;
- consulta de negócio pós-recriação: 10.060 bytes, 1.115 ms total, 977 ms de
  engine, sem reuso;
- inventário final: 59 recursos, 11 data sources, 12/12 tags, hashes/bytes
  coerentes, hash global LF preservado e nenhuma associação
  `AWSGlueServiceRole`;
- backfill isolado: 29 objetos não selecionados intactos em cada camada trusted
  e refined;
- matriz pós-recriação: 17/17, com 6 chamadas reais do analyst e 11 simulações
  IAM da ingestion;
- assinatura total de acesso: 12 chamadas reais e 11 simulações, mantidas em
  evidências separadas;
- verificador final: 26 PASSA, 0 FALHA e 5 testes unitários OK;
- fechamento remoto anterior ao ajuste R12: 26 PASSA, 0 FALHA, 59 recursos
  gerenciados, 11 data sources, 12 recursos taggeáveis corretos, hashes e bytes
  coerentes, `No changes` e plano de destroy com 59 remoções;
- teste local R06: consulta forçada a falhar com evidência antiga válida saiu
  com código 1 e não criou JSON de idempotência.
- teste local R01: manifesto pareou plano/apply por SHA-256, consumiu o
  manifesto ativo e confirmou uso de `-no-color`.

`shellcheck` não estava disponível no ambiente local. A validação Terraform no
ambiente isolado da revisão não conseguiu iniciar o provider AWS para macOS,
mas passou posteriormente no ambiente operacional; o impedimento local não era
erro de HCL.

## Ciclo final após o ajuste R12

Concluído:

- destroy de 59 recursos;
- pós-destroy 12 PASSA, 0 FALHA;
- estado vazio e nenhuma localização LF g09;
- hash global LF inalterado;
- backend S3 habilitado e DynamoDB ativo;
- plano timestampado de recriação: 59 criar, 0 alterar, 0 destruir.

Recriação concluída:

- apply pareado `20261119T025835Z` → `20261119T030118Z`;
- 59 recursos adicionados, 0 alterados e 0 destruídos.

Também concluídos:

- duas execuções FULL: 141 s/282 DPU-s e 128 s/256 DPU-s;
- idempotência, backfill e consulta Athena pós-recriação;
- teste real da função de ingestão com cleanup de versões;
- reconciliação Terraform pós-recriação: `No changes`;
- inventário, tags, tamanhos, hashes e isolamento do backfill;
- matriz `access-matrix-20261119T115835Z.json` e verificador
  `final-verification-20261119T115835Z.txt`.

## Limitações

- O ciclo demonstra destroy/recriação da stack do g09, não que a conta
  acadêmica compartilhada estivesse vazia.
- O backend tem ciclo de vida separado e não faz parte do destroy da stack.
- O principal de implantação precisa ser administrador preexistente do Lake
  Formation e ser um usuário IAM; SSO/STS não é suportado nesta entrega. Esta
  stack não administra o singleton global da conta.
- A função de ingestão foi validada com um objeto sintético exclusivo; a carga
  volumosa foi executada pelas credenciais operacionais do grupo.
- O dataset é sintético, cobre 30 dias e não permite extrapolar desempenho,
  custo ou qualidade para produção.
- O valor bruto agrega todos os status, inclusive `cancelled`, em categorias
  separadas.
- Evidências AWS históricas permanecem preservadas e separadas das capturas
  pós-recriação que provam o código atual.

## Propostas de acompanhamento

R12 foi implementado com uma policy inline para logs `/aws-glue/*`, descrição
de logs e `cloudwatch:PutMetricData` condicionado ao namespace `Glue`. As três
execuções Glue pós-recriação confirmaram o funcionamento sem a policy
gerenciada.

Para R15, a entrega mantém escopo explícito: executor como usuário IAM
preexistente em `DataLakeAdmins`. Uma evolução futura poderia aceitar um ARN IAM
em variável e resolver sessões assumidas pelo issuer, mas isso não foi
implementado para não criar ou alterar administradores da conta compartilhada.

## Comandos de reprodução

```bash
cd parte-2
terraform fmt -check -recursive
terraform validate
./scripts/test_idempotency.sh
./scripts/run_backfill.sh 2026-09-15
./scripts/run_query.sh ../consultas/av2-valor-bruto.sql
./scripts/verify_access_matrix.sh
./scripts/verify_ingestion_access.sh
cd ..
./verificacao/verifica.sh --aws
```

O destroy não deve ser executado como parte desta revisão sem autorização
explícita.

## Fechamento da apresentação revisada

Consulte `ENTREGA-ATUAL.md`. O PDF e o roteiro foram reformulados; 73 testes
locais passaram. A formatação Terraform passou, mas validate não concluiu
por falha de inicialização do provider local. As validações AWS posteriores
à modularização continuam pendentes. O ZIP e o manifesto foram reconstruídos.
