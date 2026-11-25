# Evidências da AV2

Nenhuma evidência AWS é pré-preenchida. Os scripts geram saídas reais e passam
logs/JSON pelo sanitizador antes de gravá-los em `brutas/`.

## Evidências mínimas esperadas

- `terraform-plan-<UTC>.txt`, `terraform-apply-plan-<UTC>-at-<UTC>.txt` e o
  JSON de pareamento com SHA-256;
- `code-sha256.txt` e o mesmo `code_sha256` nos relatórios do Glue;
- `generation-summary.json` e `raw-load.txt`;
- ao menos dois runs `pipeline-full-*.json` e seus `*-report.json`;
- `idempotency-*.json` com `passed: true`;
- `access-matrix-*.json` com permissões efetivas e simulação IAM aprovadas;
- `ingestion-access-real-*.json` com seis chamadas funcionais e cleanup sem
  resíduo;
- `pipeline-backfill-*.json` e `*-report.json`;
- reconciliação de isolamento do backfill e inventário final de objetos,
  tamanhos, tags e hashes;
- `athena-*-execution.json`, `*-results.json` e `*-metrics.json`;
- `final-verification-*.txt` com os checks locais/remotos e testes unitários;
- `terraform-destroy-plan-<UTC>.txt`, apply de destroy pareado e
  `post-destroy-<UTC>.txt` sem órfãos.

## Revisão antes de versionar

1. confirme que o arquivo veio do comando real e não foi editado para parecer
   um sucesso;
2. procure account ID, access key, secret, token, e-mail, nomes de perfil e
   caminhos pessoais;
3. mantenha Query IDs, métricas, contagens, estados e timestamps;
4. não versione arquivos de `.runtime/`, `.generated/`, `.terraform/`, estado,
   plano, `backend.hcl` ou `terraform.tfvars`;
5. compare as contagens entre relatório Glue, Athena e `DECISOES.md`.

`resumo/` pode receber uma síntese feita a partir das saídas brutas, desde que
cada número aponte para o arquivo de origem.

As evidências AWS de 18/11/2026 são históricas e antecedem a revisão atual do
pipeline, IAM e verificadores. Preserve esses arquivos sem reescrevê-los, mas
não os apresente como prova do código atual. O ciclo completo pós-recriação de
19/11 está identificado pelos timestamps e nomes usados no resumo final.

`lakeformation-permissions-review.json` é uma captura global incompleta da
primeira página e contém metadados de outros grupos; por isso fica ignorada e
não deve ser versionada. `lakeformation-g09-review.json` é a derivação
sanitizada somente dos principals g09 encontrados nessa página. Ela prova o
formato real da API, mas não substitui a execução paginada do verificador,
registrada no fechamento final de 26 PASSA e 0 FALHA. Ela também é lida, sem
alteração, como caso válido pelos testes `parte-2/tests/test_lf_grants.py`; o
plano `terraform-plan-20261119T025835Z.txt` é lido por
`parte-2/tests/test_terraform_layout.py` para conferir os blocos `moved`.

