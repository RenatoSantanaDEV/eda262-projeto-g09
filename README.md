# EDA 2026.2 — Projeto g09 — Parte 1

Data Lake simples para pedidos de e-commerce, provisionado integralmente em
Terraform na AWS. A pergunta de negócio é:

> Qual foi o valor bruto de vendas por dia e por status dos pedidos?

O projeto usa obrigatoriamente **N. Virginia (`us-east-1`)**, conforme a regra
da disciplina. A configuração rejeita qualquer outra região.

## Arquitetura

- S3 `eda262-g09-lake-trusted`: dados CSV da camada `trusted`;
- AWS Glue Data Catalog: banco e tabela externa `trusted`, sem Crawler;
- S3 `eda262-g09-athena-results`: resultados de consultas;
- Athena workgroup `eda262-g09-athena`: execução controlada e medição;
- S3 + DynamoDB: backend remoto e lock do estado Terraform;
- workspace Terraform obrigatório, diferente de `default`.

Todos os recursos que aceitam tags recebem:

- `turma = eda262`
- `grupo = g09`
- `projeto = engenharia-de-dados`

## Grão e schema

Uma linha representa um pedido consolidado com um único tipo de item. Nesse
modelo simplificado, `order_id` é a chave natural e `quantity * unit_price`
representa o valor bruto do pedido.

O schema é declarado em `parte-1/scenario.auto.tfvars`:

| Coluna | Tipo | Significado |
|---|---|---|
| `order_id` | `string` | chave natural sintética do pedido |
| `customer_id` | `string` | identificador sintético, sem PII |
| `order_timestamp` | `timestamp` | data e hora do pedido |
| `status` | `string` | status normalizado |
| `quantity` | `int` | unidades do item no pedido |
| `unit_price` | `decimal(10,2)` | preço unitário em reais |
| `city` | `string` | cidade, sem endereço detalhado |
| `state` | `string` | UF |

O arquivo `dados/pedidos.csv` contém somente dados sintéticos e coerentes. O
arquivo `dados/exemplos-sujeira.csv` documenta anomalias, mas não é carregado e
não pode quebrar a consulta principal.

## Segurança de credenciais

As credenciais fornecidas pelo professor são sensíveis. **Nunca copie os
arquivos de acesso para este projeto, Git, GitHub, Drive ou outro armazenamento
em nuvem.** Configure-as somente pelo mecanismo local aprovado para a aula.

O `.gitignore` bloqueia nomes e extensões comuns de credenciais. O script de
verificação também procura padrões de access key e secret key antes da entrega.
Nenhuma credencial está incluída neste repositório.

## Versionamento da entrega

- Nome do repositório: `eda262-projeto-g09`
- Branch avaliada: `main`
- Tag da AV1: `av1-entrega`

O ZIP de entrega não contém a pasta `.git`; branch e tag ficam disponíveis no
repositório local e devem ser preservadas no repositório remoto escolhido pelo
grupo.

## Estrutura

```text
.
├── DECISOES.md
├── consultas/
│   └── pergunta-negocio.sql
├── dados/
│   ├── pedidos.csv
│   ├── exemplos-sujeira.csv
│   └── README.md
├── evidencias/
│   └── README.md
├── parte-1/
│   ├── bootstrap/              # cria backend S3 + DynamoDB
│   ├── modules/data_lake/      # módulo da stack
│   ├── backend.hcl.example
│   └── scenario.auto.tfvars
└── verificacao/
    └── verifica.sh
```

## Pré-requisitos

- Terraform 1.5 ou superior;
- AWS CLI configurada localmente, sem credenciais no repositório;
- acesso autorizado à conta do grupo g09 em `us-east-1`.

Uma execução real foi realizada em 01/10/2026 na conta acadêmica do grupo, em
`us-east-1`. O resultado da consulta e as medições estão em
`evidencias/execucao-aws.md`. A stack foi destruída e a ausência de órfãos está
registrada em `evidencias/destroy-aws.md`. O backend remoto foi mantido para
preservar o estado. As credenciais não fazem parte do projeto.

## 1. Criar o backend remoto

O backend precisa existir antes da stack principal. Ele também é criado por
Terraform, mas mantém um pequeno estado local de bootstrap.

```bash
cd parte-1/bootstrap
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan -out=bootstrap.tfplan
# Revise o plano antes de executar:
terraform apply bootstrap.tfplan
```

O nome S3 é global. Se `eda262-g09-tfstate` já pertencer a outra conta, escolha
outro nome iniciado por `eda262-g09-` e use o mesmo valor em
`parte-1/backend.hcl`.

## 2. Inicializar a stack e o workspace

```bash
cd ..
cp backend.hcl.example backend.hcl
# Ajuste apenas o nome do bucket caso tenha mudado no bootstrap.
terraform init -backend-config=backend.hcl
terraform workspace new av1
terraform workspace select av1
terraform fmt -check -recursive
terraform validate
terraform plan -out=av1.tfplan
```

`scenario.auto.tfvars` é carregado automaticamente. O workspace `default` é
bloqueado pela configuração.

## 3. Aplicar e consultar

Somente após revisar o plano:

```bash
terraform apply av1.tfplan
terraform output
```

Execute `consultas/pergunta-negocio.sql` no workgroup
`eda262-g09-athena`. A execução comprovada, seu Query execution ID, tempo,
bytes processados e cálculo do custo estão em `DECISOES.md` e
`evidencias/execucao-aws.md`. Em uma nova execução, atualize essas medições em
vez de reutilizá-las como se fossem atuais.

## 4. Verificar

Na raiz do projeto:

```bash
./verificacao/verifica.sh
```

O modo padrão é local e não destrutivo. Após um deploy autorizado, as checagens
AWS exclusivamente de leitura podem ser habilitadas explicitamente:

```bash
RUN_AWS_CHECKS=1 ./verificacao/verifica.sh
```

Em uma cópia limpa do repositório, a checagem de `backend.hcl` falha até a
configuração local do backend ser criada. As checagens AWS também falham por
padrão e só são habilitadas de forma consciente com `RUN_AWS_CHECKS=1`.

## 5. Destroy limpo

Os buckets da stack acadêmica usam `force_destroy = true`, permitindo remover
os objetos de demonstração junto com os recursos. Confirme conta, região e
workspace antes de destruir:

```bash
terraform workspace show
terraform plan -destroy -out=destroy.tfplan
# Revise o plano antes de executar:
terraform apply destroy.tfplan
```

Depois, execute verificações de leitura e salve a evidência de que buckets,
catálogo, tabela e workgroup não ficaram órfãos. O backend é removido
separadamente somente após decidir o destino do estado.
