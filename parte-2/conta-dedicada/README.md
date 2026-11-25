# Implantação opt-in em conta dedicada

Procedimento separado para reproduzir a stack AV2 em uma conta AWS **dedicada**
ao avaliador ou ao grupo. Ele não faz parte do fluxo regular da conta
compartilhada, não é executado automaticamente e **não foi executado em outra
conta** durante esta revisão. Os scripts foram testados apenas localmente, com
um `aws` simulado.

## O que está garantido pelos scripts

- a conta alvo precisa ser declarada duas vezes, em `CONTA_DEDICADA_ID` e
  `CONFIRMA_CONTA_DEDICADA`; sem isso nada é chamado na AWS;
- a conta compartilhada da disciplina é recusada como alvo e também quando as
  credenciais carregadas pertencem a ela;
- as credenciais precisam pertencer exatamente à conta confirmada e a um
  usuário IAM, porque a stack usa o ARN do executor como principal do Lake
  Formation; sessões STS/SSO continuam fora do contrato;
- `preflight.sh` só faz leituras e termina com código 0 (pronto), 3
  (pré-requisitos pendentes) ou 1 (conflito ou verificação inconclusiva). Ele
  falha fechado: acesso negado nunca é tratado como ausência, e qualquer
  resposta inesperada reprova. Checagens:
  - os cinco buckets da stack e o bucket do backend com
    `head-bucket --expected-bucket-owner <ID>`; 404 é ausência, 403 significa
    outra conta ou acesso negado;
  - versionamento `Enabled` do bucket do backend (`get-bucket-versioning`,
    também com o dono esperado);
  - tabela de lock `ACTIVE`, com chave `LockID` do tipo `S` e `HASH`;
  - administrador do Lake Formation;
  - registros do Lake Formation dos três buckets de camada, com paginação de
    `list-resources` (limite de 100 páginas e detecção de token repetido);
  - conflitos de database `eda262_g09_av2`, job
    `eda262-g09-av2-orders-pipeline`, workgroup `eda262-g09-av2` e dos três
    papéis IAM;
- `registrar_admin_lf.sh` é uma simulação por padrão. Só altera a conta com
  `--aplicar` e `CONFIRMA_ALTERACAO_LF=adicionar-admin-<ID>`, acrescenta apenas
  o usuário atual a `DataLakeAdmins`, preserva os demais campos lidos da API e
  relê as configurações para confirmar o resultado.

A configuração global do Lake Formation continua fora da stack regular: o
bloco `removed` com `destroy = false` permanece na raiz de `parte-2` e nenhum
recurso `aws_lakeformation_data_lake_settings` foi reintroduzido.

## Nomes S3 globais

Os buckets da stack seguem o padrão acadêmico fixo (`eda262-g09-lake-raw`,
`eda262-g09-lake-trusted`, `eda262-g09-lake-refined`,
`eda262-g09-artifacts-av2` e `eda262-g09-athena-results-av2`). Nomes de bucket
são globais na AWS: enquanto a stack existir na conta compartilhada, a mesma
stack **não pode** ser criada em outra conta. O preflight identifica esse caso
como `ocupado globalmente`.

Não troque o padrão de nomes. Combine com o avaliador uma janela e libere os
nomes executando o destroy controlado na conta de origem
(`capture_terraform.sh destroy-plan` + `destroy_and_verify.sh`). Após um
destroy, a AWS pode levar algum tempo até liberar o nome; repita o preflight
até que os cinco buckets apareçam como disponíveis.

O bucket do backend tem nome configurável dentro do prefixo `eda262-g09-`. Se
`eda262-g09-tfstate` estiver ocupado por outra conta, escolha outro nome com o
mesmo prefixo e use-o de forma idêntica no bootstrap, em `BACKEND_BUCKET` e no
`backend.hcl`.

## Passo a passo

Todos os comandos partem da raiz do repositório. Configure as credenciais da
conta dedicada fora do repositório e confirme o ID com o avaliador antes de
começar.

### 1. Pré-checagem somente leitura

```bash
export CONTA_DEDICADA_ID=<12 dígitos confirmados>
export CONFIRMA_CONTA_DEDICADA=<os mesmos 12 dígitos>
export BACKEND_BUCKET=eda262-g09-tfstate
export LOCK_TABLE=eda262-g09-terraform-locks
./parte-2/conta-dedicada/preflight.sh
```

Interrompa em qualquer `FALHA`. `ALERTA` indica backend ou administrador do
Lake Formation ainda ausentes.

### 2. Backend separado

Reutilize o bootstrap separado de `parte-1/bootstrap`, que tem estado local,
`prevent_destroy` no bucket e o mesmo par de nomes usado pela entrega na conta
compartilhada (`eda262-g09-tfstate` e `eda262-g09-terraform-locks`, os valores
de `parte-2/backend.hcl.example`):

```bash
cd parte-1/bootstrap
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan -out=.runtime-bootstrap.tfplan
terraform apply .runtime-bootstrap.tfplan
cd ../..
```

Ajuste `state_bucket_name` em `terraform.tfvars` se o nome padrão estiver
ocupado. O `terraform.tfvars`, o plano e o estado local do bootstrap não devem
ser versionados.

### 3. Administrador do Lake Formation

Escolha uma das alternativas:

- **administrador preexistente**: um administrador da conta dedicada cadastra o
  usuário IAM executor em `DataLakeAdmins` pelo console ou pela política da
  própria conta; ou
- **registro opt-in**: simule e só depois aplique.

```bash
./parte-2/conta-dedicada/registrar_admin_lf.sh
CONFIRMA_ALTERACAO_LF=adicionar-admin-$CONTA_DEDICADA_ID \
  ./parte-2/conta-dedicada/registrar_admin_lf.sh --aplicar
```

O registro não remove administradores nem altera permissões padrão. Para
desfazê-lo, remova o usuário de `DataLakeAdmins` no console da conta dedicada
depois do destroy da stack.

### 4. Repetir a pré-checagem

```bash
./parte-2/conta-dedicada/preflight.sh
```

Prossiga somente com código 0: `0 ALERTA, 0 FALHA`.

### 5. Stack AV2

```bash
cd parte-2
cp backend.hcl.example backend.hcl
terraform init -backend-config=backend.hcl
terraform workspace select -or-create av2
terraform fmt -check -recursive
terraform validate
./scripts/capture_terraform.sh plan
```

Em conta nova, o plano esperado é **59 a adicionar, 0 a alterar e 0 a
destruir**. Os blocos `moved` não têm efeito quando o estado começa vazio.
Revise o log gerado e então:

```bash
./scripts/capture_terraform.sh apply
```

### 6. Dados, pipeline e verificação

Siga as seções 3 a 6 de `parte-2/README.md`: `load_raw.sh`,
`test_idempotency.sh`, `run_backfill.sh 2026-09-15`, `run_query.sh`,
`verify_access_matrix.sh`, `verify_ingestion_access.sh` e
`verificacao/verifica.sh --aws`.

### 7. Destroy

```bash
cd ..
./parte-2/scripts/capture_terraform.sh destroy-plan
CONFIRM_DESTROY=eda262-g09-av2 ./parte-2/scripts/destroy_and_verify.sh
```

O backend permanece, por ter ciclo de vida próprio e `prevent_destroy`.

## Limites

- Nenhum passo deste procedimento foi executado em conta real nesta revisão.
- O comportamento de `put-data-lake-settings` foi verificado apenas contra o
  formato documentado e um simulador local; a releitura pós-aplicação é a
  proteção prevista para uma divergência real.
- O procedimento não substitui o aceite do avaliador sobre os pré-requisitos de
  conta limpa.
