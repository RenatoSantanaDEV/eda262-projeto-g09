# AV2 - conferência de entrega em 25/11/2026

Fonte: [Guia do Projeto no Classroom](https://classroom.google.com/u/5/c/ODcwNzE4ODE1ODMw/m/ODcwODM0MjYyOTc3/details), versão 1.1, seções 4 a 10. O mural de 23/11 confirma apresentação na semana seguinte. A lista de atividades de 25/11 ainda não mostra uma atividade de envio da Parte 2.

## Materiais preparados

- Repositório: https://github.com/RenatoSantanaDEV/eda262-projeto-g09
- Branch: `main`; tag: `av2-entrega`.
- PDF para anexar: `apresentacao/apresentacao-parte-2-g09.pdf`.
- Roteiro: `apresentacao/roteiro-5min.md`.
- Documentação: `README.md`, `parte-2/README.md` e `DECISOES.md`.
- Evidências mais recentes: `evidencias/av2/brutas/revisao-25-11-2026/`.
- Evidências completas de processamento: `evidencias/av2/brutas/fechamento-21-11-2026/`.

## Requisitos e comprovação

| Requisito | Situação e prova |
|---|---|
| Infraestrutura em Terraform, módulo, backend e workspace | Implementados; fmt/validate aprovados, plano sem diferenças em 25/11 |
| Raw / trusted / refined e Parquet particionado | Três camadas, 30 partições trusted/refined; schema em Terraform |
| Eventos em volume e limpeza real | 187.854 eventos raw; 174.878 itens únicos; 1.802 duplicatas removidas; 11.174 rejeitados em quarentena |
| Idempotência | Duas execuções FULL distintas com igualdade de métricas e hashes de linhas completas em 21/11 |
| Backfill de uma partição | 15/09/2026: 5.821 itens; 29 partições restantes preservadas em cada camada |
| Permissões por camada via Lake Formation | Verificador 30/30, matriz 17/17 (6 chamadas reais + 11 simulações), ingestão funcional 6/6 em 25/11 |
| Pergunta de negócio e custo medido | Consulta real em 25/11: 150 grupos, 10.060 bytes, 1.149 ms; meta menor que 1 MiB atendida; estimativa de custo documentada |
| Decisões com números | Grão, chaves, particionamento, formato e custo em DECISOES.md |
| Apply e destroy comprovados | Logs reais e inventário do ciclo de 19/11: 59 recursos removidos e recriados; backend preservado |
| Logs e JSON versionados | Saídas sanitizadas de Terraform, verificador, Glue e Athena incluídas |
| PDF | 8 slides principais + 4 de apoio, Arial incorporada, revisado visualmente em 25/11 |
| Código sem comentários explicativos | Python, Terraform, Bash e SQL conferidos; shebangs e metadados do catálogo preservados |

## O que depende da entrega/apresentação

1. **Classroom:** anexar o link do repositório e o PDF quando a atividade for publicada. Conferir o prazo então. O guia aponta **30/11/2026, na aula**; nenhum horário específico de upload da AV2 foi confirmado.
2. **Apresentação:** ensaiar os oito slides principais em **5 minutos**, com **2 minutos** adicionais para perguntas. Todos precisam comparecer e conseguir defender uma decisão individualmente.
3. **Integrantes:** o representante deve confirmar a planilha exigida. Ela não foi alterada nesta preparação.
4. **Conta limpa:** há procedimento e pré-checagem, mas não foi realizado ensaio numa segunda conta. O ciclo de destroy/recriação foi real na conta compartilhada. Os nomes S3 fixos são globais: combinar a liberação dos buckets de origem antes de testar em outra conta, conforme `parte-2/conta-dedicada/README.md`. Não excluir a demonstração sem essa coordenação.

A extensão Firehose é opcional e não integra os 10 pontos obrigatórios. A submissão oficial não foi acionada.
