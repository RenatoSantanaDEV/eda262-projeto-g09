# Revalidação de 25/11/2026

`validation.json` resume as checagens reais desta data. Logs e respostas AWS
estão sanitizados; planos binários, estados e credenciais ficam fora do repo.

- `verification.txt`: 85 testes unitários, fmt/validate e 30 PASSA / 0 FALHA.
- `no-drift.txt`: plano Terraform sem diferenças.
- `admin-restoration.json`: restauração do executor como administrador LF,
  com preservação dos administradores existentes e demais configurações.
- `permissions-restored.txt`: reconciliação dos sete grants de localização
  previstos no código. Não houve exclusão de recursos nem reprocessamento.
- `access-matrix.json`: 6 chamadas reais do analista + 11 simulações IAM.
- `ingestion-access.json`: 6 checagens reais e limpeza completa do objeto
  sintético exclusivo utilizado pelo teste.
- `athena-execution.json`, `athena-results.json`, `athena-metrics.json`:
  consulta `4ee64559-c768-42ca-9711-c408a116ef8d`, 150 grupos, R$526.021.301,72
  de valor bruto sintético, 10.060 bytes lidos e 1.149 ms, sem reuso.
- `pdf-validation.json`: 12 páginas, Arial incorporada, sem texto fora da
  página; a inspeção visual conferiu as páginas alteradas.

Meta menor que 1 MiB atendida. A estimativa usa US$5/TB e mínimo de 10 MB:
aproximadamente **US$0,00005 por consulta**, antes de S3, catálogo e impostos.
É uma estimativa, não a fatura. [Fonte oficial consultada em 25/11](https://aws.amazon.com/athena/pricing/).

O código do pipeline permanece idêntico ao validado em 21/11:
`68a7e9d629a3b6d08a9e5e73ea47a6feeee0af5cd27a60acb406a4dc3eee89c2`.
Testes Spark, duas execuções FULL e backfill completos constam do fechamento
de 21/11; o ciclo destroy/recriação de 59 recursos permanece datado de 19/11.
Esses procedimentos não foram repetidos em 25/11. A segunda conta dedicada
não foi ensaiada, e a atividade AV2 ainda não estava disponível no Classroom.
