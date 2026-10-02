# Evidências

Esta pasta registra, sem credenciais ou dados sensíveis:

- saída completa de `verificacao/verifica.sh`;
- resumo do `terraform apply`;
- consulta executada no Athena e seu Execution ID;
- bytes processados, tempo e custo calculado;
- saída do `terraform destroy`;
- verificações de leitura que demonstrem ausência de recursos órfãos.

`execucao-aws.md` contém a evidência textual da criação e da consulta real.
`destroy-aws.md` registra a destruição limpa e a checagem de ausência de
órfãos.
