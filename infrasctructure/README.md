# Infraestrutura AWS

Este diretório provisiona VPC, subnets, regras de acesso, EC2, RDS PostgreSQL, bucket S3, fila SQS com DLQ e tabela DynamoDB. Uma IAM Role permite à EC2 acessar a fila e a tabela. O estado do Terraform fica em um bucket S3 separado, que precisa existir antes da inicialização.

## 1. Preparar os pré-requisitos

Antes de executar o Terraform, tenha:

- Terraform instalado, compatível com o backend S3 e a opção `use_lockfile` de `main.tf`.
- AWS CLI configurada com credenciais válidas e permissões para provisionar os recursos e acessar o estado remoto, incluindo SQS, DynamoDB, criação de roles e instance profiles e `iam:PassRole`. Se as credenciais forem temporárias, inclua o token de sessão.
- Um **EC2 Key Pair** criado ou importado na região de implantação. O nome esperado em `compute.tf` é `fiap-tc-fase-03-devops`. Guarde a chave privada correspondente para acessar a EC2; ela não é criada pelo Terraform.
- O bucket de estado `tc-fase-03-tfstate-bucket`, na região `us-east-2`, já disponível, com permissões para o estado e seu arquivo de lock. Caso use outro bucket, ajuste o backend em `main.tf`. O bucket de `storage.tf` é para a aplicação e não substitui esse pré-requisito.
- Uma senha definida para a variável obrigatória `db_password`, fornecida na execução ou por `TF_VAR_db_password`, sem versioná-la.

Confira a identidade usada antes de seguir:

```bash
aws sts get-caller-identity
```

**Para avançar:** credenciais válidas, acesso ao bucket de estado, nome do Key Pair confirmado e chave privada disponível.

## 2. Conferir e provisionar os recursos

Revise os valores antes de aplicar:

| Arquivo | O que conferir |
| --- | --- |
| `main.tf` | Bucket, chave e região do estado remoto. |
| `variables.tf` | Região (`us-east-2`), ambiente (`dev`) e AMI válida nessa região. |
| `compute.tf` | Nome do Key Pair e tipo da instância. |
| `storage.tf` | Nome globalmente único para o bucket da aplicação. |
| `network.tf` | Acesso SSH, HTTP e acesso da EC2 ao RDS na porta 5432. |

A AMI determina o usuário SSH e o gerenciador de pacotes. A descrição em `variables.tf` indica Ubuntu; confirme o sistema da AMI escolhida antes de preparar a instância.

Na pasta `infrasctructure`, execute:

```bash
terraform init
terraform validate
terraform plan
terraform apply
terraform output
```

Use `terraform init -reconfigure` quando precisar reconfigurar o backend de um diretório já inicializado.

**Para avançar:** aplicação concluída e valores de `ec2_public_ip`, `rds_endpoint` e `s3_bucket_name` disponíveis. Guarde também a senha definida para o usuário `master` do RDS.

## 3. Acessar e preparar a EC2

Use a chave privada do Key Pair, com as permissões locais de arquivo exigidas pelo SSH, e o IP retornado pelo Terraform:

```bash
ssh -i "caminho/da/chave.pem" <usuario-da-ami>@<ec2_public_ip>
```

Use `ubuntu` para uma AMI Ubuntu ou `ec2-user` para Amazon Linux, conforme a imagem selecionada.

Na EC2, é preciso:

- Atualizar os pacotes usando o gerenciador da distribuição (`sudo yum update -y`).
- Instalar Git, Docker, Docker Compose e o cliente PostgreSQL (`sudo yum install git docker postgresql17-server -y`). O servidor PostgreSQL ficará no RDS.
- Iniciar o Docker e habilitá-lo na inicialização (`sudo systemctl start docker` e `sudo systemctl enable docker`).
- Se for executar Docker sem `sudo`, adicionar o usuário ao grupo `docker` (`sudo usermod -aG docker $USER`) e abrir uma nova sessão SSH.
- Disponibilizar uma cópia completa deste repositório, incluindo `infrasctructure` e `apps-togglemaster` (publicar no GitHub ou outro "servidor de arquivos").

**Para avançar:** conexão SSH funcionando, comandos `docker`, `docker compose` e `psql` disponíveis e repositório presente na EC2.

## 4. Inicializar os bancos no RDS

Execute esta etapa na EC2: a regra de rede do RDS permite conexões na porta 5432 a partir do Security Group da instância.

Na raiz do repositório, com os comandos abaixo, baixe o certificado de confiança do RDS e informe o host retornado pelo Terraform. O output `rds_endpoint` inclui a porta; em `RDSHOST`, use somente o nome do host, sem `:5432`.

```bash
curl -o global-bundle.pem https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
export RDSHOST="<host-do-rds>"

psql "host=$RDSHOST port=5432 dbname=togglemasterdb user=master sslmode=verify-full sslrootcert=./global-bundle.pem" \
  -X -f infrasctructure/00-init.sql
```

Informe a senha do RDS quando solicitada. O banco inicial `togglemasterdb` é criado pelo Terraform; o script cria os bancos usados pelos serviços:

| Serviço | Banco | Tabela |
| --- | --- | --- |
| Auth | `auth_db` | `api_keys` |
| Flags | `flags_db` | `flags` |
| Targeting | `targeting_db` | `targeting_rules` |

O script carrega os arquivos SQL dos serviços por caminhos relativos ao próprio arquivo. Mantenha a estrutura do repositório na EC2; copiar apenas `00-init.sql` não basta.

A execução pode ser repetida: bancos e tabelas existentes são preservados, e funções e triggers são recriados. O script não migra estruturas antigas. Não use `--single-transaction`; se ocorrer um erro, a execução para e as etapas anteriores podem já ter sido aplicadas.

**Para avançar:** script concluído sem erros e as três tabelas disponíveis nos respectivos bancos. Para conferir, conecte-se a cada banco pelo `psql` (com `psql -h <SEU_ENDPOINT_DO_RDS> -U <SEU_USUARIO_DO_BANCO> -d auth_db`) e execute `\dt public.*`.

## 5. Preparar a configuracao da aplicacao

Na EC2, na raiz do clone, execute o script de usuarios como `master`, depois de `00-init.sql`:

```bash
psql "host=$RDSHOST port=5432 dbname=togglemasterdb user=master sslmode=verify-full sslrootcert=./global-bundle.pem" -X -v ON_ERROR_STOP=1 -f infrasctructure/01-users.sql
```

O script solicita senhas para `auth_user`, `flags_user` e `targeting_user` e concede acesso a cada tabela e sua sequencia. Execute a criacao dos usuarios uma vez.

Copie `deploy/.env.ec2.example` para `.env` na raiz do clone, se ainda nao existir, e execute `chmod 600 .env`. Preencha:

- `AUTH_DATABASE_URL`, `FLAGS_DATABASE_URL` e `TARGETING_DATABASE_URL`: host RDS, usuarios acima, senhas e respectivos bancos. Preserve `sslmode=require`; caracteres especiais nas credenciais precisam de percent-encoding.
- `MASTER_KEY` e `SERVICE_API_KEY`, conforme `deploy/README.md`.
- `DOCKERHUB_NAMESPACE` e `IMAGE_TAG` para deploy manual. O pipeline fornece esses valores durante seu deploy.
- Outputs AWS da etapa 6, antes de iniciar todos os servicos.

O `docker-compose.yaml` da raiz e para desenvolvimento local, com PostgreSQL e LocalStack. Na EC2, use `deploy/compose.ec2.yaml`, com RDS e AWS reais, Redis e proxy Nginx.

Depois de concluir a etapa 6, execute na raiz do clone:

```bash
docker compose --env-file .env -f deploy/compose.ec2.yaml config --quiet
docker compose --env-file .env -f deploy/compose.ec2.yaml pull
docker compose --env-file .env -f deploy/compose.ec2.yaml up -d --wait
docker compose --env-file .env -f deploy/compose.ec2.yaml exec -T proxy nginx -t
docker compose --env-file .env -f deploy/compose.ec2.yaml exec -T proxy nginx -s reload
curl --fail http://localhost/auth/health
```

O proxy publica a porta 80 e remove o prefixo ao encaminhar a requisicao:

| Prefixo externo | Destino interno |
| --- | --- |
| `/auth/` | `auth-service:8001/` |
| `/flags/` | `flag-service:8002/` |
| `/targeting/` | `targeting-service:8003/` |
| `/evaluation/` | `evaluation-service:8004/` |
| `/analytics/` | `analytics-service:8005/` |

Exemplos: `http://<ec2_public_ip>/flags/flags`, `/targeting/rules/<nome>` e `/evaluation/evaluate`. Health checks: `/<prefixo>/health`.

O Security Group ja libera a porta 80. Mantenha 8001-8005 restritas ao loopback da EC2; Redis nao publica porta e o RDS aceita 5432 apenas do Security Group da EC2. A porta 80 precisa estar livre na instancia. Para HTTPS, configure dominio, certificado e listener TLS no proxy (ou ALB), alem de liberar 443.

**Para avancar:** usuarios e variaveis configurados. Apos concluir a etapa 6 e iniciar o deploy, confirme o acesso HTTP pelo IP publico. Provisionar a infraestrutura nao inicia a aplicacao.

## 6. Configurar o fluxo de eventos

Depois de atualizar os arquivos Terraform, na pasta `infrasctructure`, execute
`terraform plan` e confira as alterações antes de `terraform apply`. Não é necessário
recriar manualmente a EC2 ou os recursos existentes. Se uma fila ou tabela com os
mesmos nomes já existir fora do estado, importe o recurso antes de aplicar.

O provisionamento inclui:

- Fila Standard `togglemaster-events-<ambiente>`, criptografada com chave gerenciada pelo SQS, retenção de quatro dias, long polling de 20 segundos e visibilidade de 120 segundos.
- DLQ `togglemaster-events-dlq-<ambiente>`, com retenção de 14 dias, para mensagens que falham após cinco recebimentos. Inspeção e reprocessamento são operações separadas.
- Tabela `ToggleMasterAnalytics-<ambiente>`, com cobrança por demanda e chave de partição textual `event_id`, conforme o Analytics.
- IAM Role na EC2 com `SendMessage`, `ReceiveMessage` e `DeleteMessage` somente na fila principal e `PutItem` somente na tabela. Como os serviços compartilham a EC2, compartilham também essa role.
- IMDSv2 obrigatório com hop limit 2 para permitir que os contêineres obtenham as credenciais da role.

Preencha o `.env` da EC2 com os outputs abaixo:

| Variável no `.env` | Comando na pasta `infrasctructure` |
| --- | --- |
| `AWS_REGION` | `terraform output -raw aws_region` |
| `AWS_SQS_URL` | `terraform output -raw sqs_queue_url` |
| `AWS_DYNAMODB_TABLE` | `terraform output -raw dynamodb_table_name` |

Deixe `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` e `AWS_SESSION_TOKEN` vazios
para usar a IAM Role. Remova credenciais antigas, pois valores preenchidos têm
precedência sobre a role. Não configure `AWS_ENDPOINT_URL` do LocalStack no deploy.
Recrie os contêineres após alterar o `.env` para aplicar os novos valores.

**Para avançar:** aplicação do Terraform concluída, outputs copiados para o `.env`
e role associada à EC2. Após o deploy, faça uma avaliação autenticada e confira
se o evento aparece no DynamoDB; o `/health` do Analytics não verifica esse fluxo.
Filas Standard podem entregar mensagens repetidas; o consumidor atual gera um novo
`event_id` por processamento e ainda não elimina duplicatas.

Referências: [SQS no Terraform](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue),
[DynamoDB no Terraform](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table)
e [opções de metadados da EC2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/configuring-instance-metadata-options.html).
