# Roteiro de cinco minutos - Grupo 09

Apresentar páginas 1 a 8. Páginas 9 a 12 ficam para perguntas. A divisão é
uma proposta: confirmar com o grupo e ensaiar com cronômetro.

| Página | Tempo | Integrante | Tema |
|---|---|---|---|
| 1 | 0:00-0:25 | Renato | Pergunta e cenário |
| 2 | 0:25-1:05 | Renato | Arquitetura |
| 3 | 1:05-1:45 | João | Qualidade |
| 4 | 1:45-2:30 | João | Reexecução e backfill |
| 5 | 2:30-3:05 | Raphael | Resultado de negócio |
| 6 | 3:05-3:45 | Raphael | Segurança |
| 7 | 3:45-4:25 | Lara | Decisões e custos |
| 8 | 4:25-5:00 | Lara | Evidências e limites |

## 1. Pergunta

Somos o grupo 09. Construímos um data lake para responder qual foi o valor
bruto dos pedidos por dia e status. O cenário tem dados sintéticos de trinta
dias. Partimos de quase 188 mil eventos e chegamos a cerca de 175 mil itens
únicos. O valor bruto inclui cancelados separados por status; não é receita.

## 2. Arquitetura

O Terraform provisiona um módulo, com estado remoto em S3, lock no DynamoDB
e workspace av2.
A raw preserva os eventos originais em NDJSON, organizados pela data de
chegada. O Glue, usando PySpark, normaliza, valida, deduplica e agrega.
A trusted guarda o item vigente de cada pedido em Parquet, particionado pela
data do pedido. A refined responde à pergunta, com uma linha por dia e
status. O Catálogo tem schema e projeção de partições definidos no Terraform,
sem crawler. O Athena consulta a camada final com SQL e filtro de data.

## 3. Qualidade

O gerador insere erros conhecidos para testar o tratamento. Padronizamos
espaços, status, UF e preços com vírgula. Rejeitamos chaves vazias, datas
inválidas, estados ou status desconhecidos e valores não positivos.
Foram 11.174 rejeitados e 1.802 duplicatas válidas removidas. Na chave pedido
mais item, vence a maior atualização, depois a chegada mais recente e,
finalmente, um hash determinístico. Sobram 174.878 linhas e chaves únicas.

## 4. Reexecução e backfill

Rodamos o FULL duas vezes. Além de conferir linhas, chaves, partições e valor
bruto, a revisão final compara o hash do conteúdo de trusted, refined e
quarentena. Os resultados precisam ser iguais mesmo que os arquivos mudem.
No backfill de 15 de setembro, 5.881 eventos válidos, menos sessenta
repetições, geram 5.821 itens. Só esse dia é reescrito; os objetos dos outros
29 dias são comparados antes e depois. Datas sem linhas válidas falham antes
da escrita. Atrasos podem chegar a seis dias, incluindo reentregas.

## 5. Resultado

Temos 150 grupos: trinta dias vezes cinco status. O total bruto sintético é
R$ 526.021.301,72. O gráfico separa os status e começa no zero. A regularidade
diária vem do gerador, não de vendas reais. O SQL lê a refined, já agregada,
reduzindo o volume examinado. Contagem de pedidos dentro de cada grupo não é
contagem de clientes únicos; cancelados não devem ser tratados como receita.

## 6. Segurança

A função de ingestão acessa a raw; a de processamento transforma as camadas;
o analista consulta a refined. IAM controla objetos, e Lake Formation
controla o catálogo e as localizações. O S3 tem criptografia, acesso público
bloqueado e exigência de conexão segura. A revisão removeu um grant amplo de
compatibilidade do banco. A verificação final passou nos trinta checks.
A matriz combina seis chamadas reais do analista com onze simulações IAM;
outras seis chamadas reais testam a ingestão. Os métodos ficam separados.

## 7. Decisões

A chave composta impede confundir pedidos com itens. Particionar pela data
do evento permite refazer um dia, ao custo de reler a raw. A redução de
volume vem de limpeza, deduplicação e Parquet; na refined, também da
agregação. Catálogo explícito dispensa crawler, mas mudanças de schema exigem
revisão. O apoio mostra tempos e estimativas do ciclo histórico de 19 de
novembro. São estimativas com exclusões, não a fatura total nem o custo de
todas as validações posteriores.

## 8. Fechamento

O histórico inclui remoção e recriação de 59 recursos, preservando o backend.
A versão final passou em 85 testes unitários e dez testes Spark, além das
verificações na AWS. Os relatórios identificam cada execução e o hash do
código. A apresentação traz as evidências para perguntas. O experimento é
acadêmico: não há transação atômica entre buckets nem prova de desempenho em
produção. A implantação em outra conta tem procedimento documentado, mas não
foi ensaiada em uma segunda conta real.

## Respostas de apoio

- **Quarentena registra o motivo?** Não há coluna textual de motivo. É um
  snapshot por modo, regravado mesmo vazio. Rejeitados sem data são contados
  no relatório; não são atribuídos a uma data fictícia no backfill.
- **Por que ignorar mudanças em alguns grants no Terraform?** O plano do
  provider difere da resposta direta da API. A exceção foi preservada e
  compensada por comparação exata obrigatória dos grants na AWS.
- **Como reproduzir?** README da parte 2: backend e administrador LF,
  workspace av2, plano/apply, restrição de compatibilidade, carga, FULL,
  idempotência, backfill, Athena e verificadores.
- **Conta limpa?** Houve recriação da stack na conta compartilhada. Backend
  e administrador são pré-requisitos. Buckets têm nomes globais, portanto a
  segunda conta exige coordenar a liberação desses nomes.
- **Limite do teste?** Os hashes comprovam igualdade do conteúdo nas execuções
  comparadas. Isso não equivale a provar todos os cenários possíveis.
