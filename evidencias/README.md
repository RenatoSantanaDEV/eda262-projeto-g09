# Evidências

Esta pasta registra, sem credenciais ou dados sensíveis, a execução real feita
em 01/10/2026 na conta acadêmica do grupo g09, em `us-east-1`.

## O que está versionado

| Arquivo | Conteúdo |
|---|---|
| `execucao-aws.md` | bootstrap do backend (5 recursos), apply da stack (14 recursos), verificação remota após o apply e consulta real no Athena, com Query execution ID, tempo, bytes processados, resultado e custo estimado |
| `destroy-aws.md` | destroy em duas etapas (9 + 5 recursos), correção do `force_destroy` do workgroup, checagem de ausência dos cinco alvos e backend remoto preservado |

Os dois arquivos são resumos textuais, redigidos pelo grupo a partir das saídas
dos comandos. O ID da conta aparece mascarado (`3255…8777`).

## O que não está versionado

As saídas brutas dessa execução (log de `terraform apply` e `terraform destroy`,
JSON de `get-query-execution`, saída do `verifica.sh`, capturas de tela) **não
foram salvas no repositório**. Elas também não devem mais estar disponíveis na
AWS: o workgroup e o bucket de resultados foram destruídos com a stack, e com
eles o histórico e o arquivo de resultado da consulta.

Os planos binários (`*.tfplan`) e o estado local do bootstrap ficam somente na
máquina de quem executou. Eles nunca são versionados, porque podem conter dados
da conta.

Nada nesta pasta deve ser reconstruído de memória ou editado para parecer saída
de comando. Uma evidência bruta só entra aqui se vier de uma execução real.

## Como acrescentar saídas brutas sanitizadas

Convenção para uma próxima execução real:

| Pasta | Uso | Git |
|---|---|---|
| `evidencias/_local/` | capturas originais, ainda não revisadas | ignorada |
| `evidencias/brutas/` | as mesmas saídas depois de sanitizadas | versionada |

Arquivos `.txt`, `.json` e `.png` soltos diretamente em `evidencias/` continuam
ignorados, para que uma captura não revisada não seja versionada por engano.

1. Capture os originais em `evidencias/_local/`, a partir da raiz do projeto:

   ```bash
   mkdir -p evidencias/_local
   terraform -chdir=parte-1 apply -no-color av1.tfplan | tee evidencias/_local/apply.txt
   aws athena get-query-execution --region us-east-1 \
     --query-execution-id "$QUERY_ID" > evidencias/_local/query-execution.json
   terraform -chdir=parte-1 apply -no-color destroy.tfplan | tee evidencias/_local/destroy.txt
   ```

2. Sanitize cada arquivo ao copiá-lo para `evidencias/brutas/`, mascarando o ID
   da conta:

   ```bash
   mkdir -p evidencias/brutas
   CONTA="$(aws sts get-caller-identity --query Account --output text)"
   MASCARA="${CONTA:0:4}…${CONTA:8:4}"
   for arquivo in evidencias/_local/*.txt evidencias/_local/*.json; do
     sed "s/${CONTA}/${MASCARA}/g" "$arquivo" > "evidencias/brutas/$(basename "$arquivo")"
   done
   ```

3. Revise manualmente o que será versionado. Não pode haver:

   - access key, secret key, token de sessão ou URL pré-assinada;
   - ID completo da conta (12 dígitos), inclusive dentro de ARNs;
   - caminhos locais com nome de usuário ou dados pessoais.

   Capturas de tela exigem revisão visual: o verificador não lê imagens.

4. Rode `./verificacao/verifica.sh`. Ele falha se encontrar padrão de credencial
   no projeto ou ID de conta completo em `evidencias/`.

5. Só então `git add evidencias/brutas/` e atualize os resumos
   (`execucao-aws.md`, `destroy-aws.md`) e o `DECISOES.md` com os números da
   nova execução.

Estado (`*.tfstate`), planos (`*.tfplan`), `backend.hcl` e `terraform.tfvars`
continuam fora do Git em qualquer caso.
