# Evidência de execução AWS

## Contexto

- Data: 01/10/2026.
- Conta: `3255…8777`.
- Região: `us-east-1`.
- Workspace Terraform: `av1`.
- Terraform: `1.16.4`.
- Provider AWS: `5.100.0`.

Nenhuma credencial é registrada neste arquivo.

## Backend remoto

O bootstrap criou cinco recursos:

- S3 `eda262-g09-tfstate`, com versionamento habilitado e criptografia AES-256;
- bloqueio público do bucket;
- configuração de criptografia;
- configuração de versionamento;
- DynamoDB `eda262-g09-terraform-locks`, ativo e em modo `PAY_PER_REQUEST`.

Resultado do Terraform: `5 added, 0 changed, 0 destroyed`.

## Stack da Parte 1

O plano aprovado continha `14 to add, 0 to change, 0 to destroy`. O `apply`
terminou com `14 added, 0 changed, 0 destroyed`.

Verificação remota após o `apply`:

- S3 trusted: `eda262-g09-lake-trusted`;
- objeto: `trusted/pedidos.csv`, 895 bytes, AES-256;
- S3 de resultados: `eda262-g09-athena-results`;
- Glue database: `eda262_g09_pedidos_ecommerce_catalog`;
- Glue table: `trusted`, com oito colunas declaradas e cabeçalho ignorado;
- Athena workgroup: `eda262-g09-athena`, habilitado, configuração obrigatória e saída criptografada em S3.

## Consulta real no Athena

- Query execution ID: `5c11fe2f-ba30-457e-aa26-0055b3970cb1`.
- Estado: `SUCCEEDED`.
- Submissão: `2026-10-01T23:43:29.413000-03:00`.
- Conclusão: `2026-10-01T23:43:30.021000-03:00`.
- Tempo total: 608 ms.
- Tempo de engine: 414 ms.
- Dados processados: 895 bytes.
- Resultado anterior reutilizado: não.
- Saída: `s3://eda262-g09-athena-results/results/5c11fe2f-ba30-457e-aa26-0055b3970cb1.csv`.

Resultado:

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

## Custo estimado

O Athena informou 895 bytes lidos. A AWS publica preço sob demanda de US$ 5
por TB, com mínimo faturável de 10 MB por consulta. Portanto, o custo estimado
para esta execução é aproximadamente **US$ 0,00005**.

Fonte: <https://aws.amazon.com/pt/athena/pricing/>.
