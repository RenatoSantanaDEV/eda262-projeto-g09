# Evidência de destroy AWS

## Execução

- Data de verificação: `2026-10-01T23:52:21-03:00`.
- Região: `us-east-1`.
- Workspace: `av1`.
- Conta: `3255…8777`.
- Plano inicial: `0 to add, 0 to change, 14 to destroy`.
- Contagem final no estado do workspace: `0` recursos.

## Ajuste descoberto na execução

A primeira tentativa removeu nove recursos, mas o Athena recusou a exclusão do
workgroup porque ele continha o histórico da consulta. O recurso
`aws_athena_workgroup` foi corrigido com `force_destroy = true`. Após aplicar
somente essa atualização, o segundo plano removeu os cinco recursos restantes.

Resultado final do segundo apply: `0 added, 0 changed, 5 destroyed`.

## Checagem pós-destroy

Consultas de leitura à AWS confirmaram:

| Recurso da stack | Resultado |
|---|---|
| S3 `eda262-g09-lake-trusted` | ausente |
| S3 `eda262-g09-athena-results` | ausente |
| Glue database `eda262_g09_pedidos_ecommerce_catalog` | ausente |
| Glue table `trusted` | ausente |
| Athena workgroup `eda262-g09-athena` | ausente |

Recursos órfãos da stack: **0**.

## Backend deliberadamente mantido

O backend remoto não é tratado como órfão e foi preservado para manter o
histórico do estado:

- S3 `eda262-g09-tfstate`: presente;
- DynamoDB `eda262-g09-terraform-locks`: presente.

Nenhuma credencial foi registrada nesta evidência.
