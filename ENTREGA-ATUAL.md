# Preparação da entrega - 25/11/2026

Repositório: https://github.com/RenatoSantanaDEV/eda262-projeto-g09
Branch de avaliação: `main`. Tag da entrega: `av2-entrega`.

O código do pipeline continua sendo a versão validada em 21/11. Em 25/11,
os 85 testes Python passaram novamente, o verificador AWS passou em 30/30,
a matriz de acesso em 17/17 e o teste funcional de ingestão em 6/6, com
limpeza completa. O Terraform terminou sem diferenças. A nova consulta
retornou os mesmos 150 grupos e R$ 526.021.301,72, lendo 10.060 bytes em
1.149 ms, sem reutilizar resultados. Evidências em
`evidencias/av2/brutas/revisao-25-11-2026/validation.json`.

A conta compartilhada deixou de reconhecer o executor como administrador
do Lake Formation. Esse acesso foi restaurado preservando os demais
administradores e configurações; em seguida, foram reconciliados os sete
grants de localização previstos no Terraform. Nenhum dado foi reprocessado
nem recurso removido nesta revisão.

Os slides receberam ajustes de diagramação e passaram a explicitar módulo,
backend S3/DynamoDB e workspace. O PDF foi renderizado e conferido; as
métricas históricas de 19/11 e 21/11 continuam identificadas pelas datas.
O ZIP e o manifesto foram atualizados para esta edição.

**Ainda não entregue no Classroom.** Na consulta de 25/11, a atividade de
submissão da Parte 2 não estava publicada. O guia prevê 30/11/2026, na aula,
e pede link do repositório mais PDF. Não há horário de upload específico
confirmado para a AV2. Consulte `CHECKLIST-AV2.md` para os itens restantes.

## Arquivos para entrega

- `apresentacao/apresentacao-parte-2-g09.pdf`: 8 páginas de apresentação e
  4 de apoio, Arial incorporada e gráficos derivados da consulta final.
- `apresentacao/roteiro-5min.md`: cerca de 600 palavras de fala, divisão
  sugerida entre os integrantes e respostas de apoio.
- Código, Terraform, consultas, documentação, testes e evidências neste
  repositório. A versão ZIP contém a mesma árvore, sem credenciais, estado,
  planos binários, dependências locais ou dados temporários.

## Validação completa de 21/11 preservada

| Verificação | Resultado |
|---|---|
| Testes Python de regressão | 85 aprovados |
| Testes reais Spark 3.3.0 / Python 3.10 / Java 8 | 10 aprovados |
| Sintaxe Python e 20 scripts Bash | aprovada |
| Terraform fmt e validate | aprovados |
| Plano da atualização final | 0 criar, 2 alterar, 0 destruir |
| Plano após atualização | No changes |
| Verificador com acesso à AWS | 30 PASSA, 0 FALHA |
| Matriz de acesso | 17/17: 6 chamadas reais e 11 simulações |
| Função de ingestão | 6/6 chamadas reais e limpeza do objeto de teste |
| Duas execuções FULL | métricas e hashes de conteúdo idênticos |
| Trusted | 174.878 linhas e chaves únicas, 30 partições |
| Refined | 150 grupos; valor bruto sintético R$ 526.021.301,72 |
| Backfill de 15/09/2026 | 5.821 linhas; 60 duplicatas; 316 rejeitados; 5 grupos |
| Isolamento do backfill | 29 partições preservadas em cada camada |
| Consulta Athena final | 10.060 bytes; 1.561 ms totais; sem reuso |

O pipeline final tem SHA-256
`68a7e9d629a3b6d08a9e5e73ea47a6feeee0af5cd27a60acb406a4dc3eee89c2`.
Os relatórios identificam `JOB_RUN_ID` e esse hash. A comparação da
idempotência também exige igualdade dos hashes das linhas completas de
trusted, refined e quarentena, independentemente da ordem dos arquivos.

## Correções concluídas

- Transformações separadas em funções, com testes Spark de nulos, datas,
  decimal, desempates, conteúdo e sobrescrita seletiva.
- Quarentena vazia substitui o snapshot anterior.
- FULL substitui todas as partições; BACKFILL só escreve datas solicitadas.
  Datas sem linhas válidas falham antes da escrita. Rejeitados sem data são
  contados separadamente no relatório (1.661 no experimento completo).
- Relatórios em chaves por execução, com identificação validada pelo wrapper.
- Polling do Glue limitado; `EXPIRED` e erro de API reprovam.
- Falha de sanitização/gravação reprova a matriz; hashes e IDs são preservados.
- Grants de compatibilidade ampla detectados. O grant desse tipo no database
  do grupo foi removido; os demais grupos e administradores foram preservados.
- A exceção `ignore_changes` nos grants de database foi investigada com plano
  e API reais. O provider propunha recriação apesar de a API mostrar somente
  DESCRIBE. A exceção permanece documentada e a checagem exata é obrigatória.

## Evidências e limites

O índice consolidado está em
`evidencias/av2/brutas/fechamento-21-11-2026/validacao-final.json`.
Os arquivos dessa pasta apontam para as capturas originais com timestamp.
Os timestamps AWS em 22/11 UTC correspondem à noite de 21/11 em Recife.

A primeira tentativa da integração nova falhou porque o identificador do run
é argumento reservado do Glue; isso foi corrigido antes do processamento.
Uma execução adicional concluiu, mas sua coleta local foi interrompida durante
atualização do wrapper. Ela não foi usada como prova de idempotência: a prova
final usa duas outras execuções completas, distintas e com relatórios.

O ciclo real de destroy/recriação de 59 recursos permanece comprovado pelos
arquivos históricos de 19/11. Não repetimos destroy nesta revisão, pois a
mudança não alterou o conjunto de recursos. Não foi realizado ensaio em uma
segunda conta dedicada; o procedimento e seus pré-requisitos estão documentados.
As camadas não têm transação atômica entre buckets. O experimento não mede
carga de produção. Custos históricos apresentados não são a fatura total.

## Antes de clicar em entregar no Classroom

1. Aguardar a atividade AV2, conferir eventual prazo atualizado e anexar o
   PDF final e o link do repositório acessível ao professor.
2. Confirmar os integrantes na planilha exigida pela disciplina.
3. Ensaiar as oito páginas em cinco minutos, mais dois para perguntas;
   assegurar presença e capacidade de defesa de todos os integrantes.
4. Combinar com o avaliador o teste em conta limpa: os nomes S3 são globais
   e exigem liberação coordenada na conta de origem. O roteiro está em
   `parte-2/conta-dedicada/README.md`; o ensaio em segunda conta permanece
   não realizado.

A submissão no Classroom fica a cargo do representante; não foi acionada.
