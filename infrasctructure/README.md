# AWS, EC2 e RDS

## 1. Preparar o Terraform — máquina local

1. Instale Terraform com suporte a `use_lockfile`, AWS CLI e Git.
2. Configure credenciais AWS com acesso ao Terraform, S3, EC2, RDS, SQS, DynamoDB e IAM, incluindo `iam:PassRole`.
3. Crie o bucket de estado `tc-fase-03-tfstate-bucket` em `us-east-2`, ou ajuste o backend em [main.tf](main.tf).
4. Crie ou importe o Key Pair `fiap-tc-fase-03-devops` na região escolhida. Guarde a chave privada.
5. Confira os arquivos:

| Arquivo | Ajustar |
| --- | --- |
| [main.tf](main.tf) | Bucket e região do estado |
| [variables.tf](variables.tf) | Região, ambiente e AMI; confirme o sistema operacional |
| [compute.tf](compute.tf) | Key Pair e tipo da EC2 |
| [storage.tf](storage.tf) | Nome único para o bucket da aplicação |
| [network.tf](network.tf) | SSH 22, HTTP 80 e RDS 5432 a partir da EC2 |

```bash
aws sts get-caller-identity
```

## 2. Provisionar — máquina local

Na pasta `infrasctructure`:

```bash
terraform init
terraform validate
terraform plan
terraform apply
terraform output
```

Informe a mesma senha de `db_password` no plan e no apply. Guarde-a como senha do usuário `master` do RDS.

Anote os outputs:

| Output | Usar em |
| --- | --- |
| `ec2_public_ip` | SSH, secret `EC2_HOST` e acesso HTTP |
| `rds_endpoint` | `RDSHOST` e URLs dos bancos |
| `aws_region` | `.env`: `AWS_REGION` |
| `sqs_queue_url` | `.env`: `AWS_SQS_URL` |
| `dynamodb_table_name` | `.env`: `AWS_DYNAMODB_TABLE` |

## 3. Preparar a EC2

Na máquina local, conecte por SSH. Use `ubuntu` para Ubuntu ou `ec2-user` para Amazon Linux:

```bash
ssh -i "caminho/chave.pem" <usuario>@<ec2_public_ip>
```

Na EC2, instale os pacotes conforme a AMI.

Ubuntu:

```bash
sudo apt-get update
sudo apt-get install -y git curl unzip openssl docker.io postgresql-client
```

Amazon Linux 2023:

```bash
sudo dnf install -y git curl unzip openssl docker postgresql17
```

Na EC2 x86_64, instale o plugin Compose:

```bash
sudo mkdir -p /usr/local/lib/docker/cli-plugins
sudo curl -fL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 -o /usr/local/lib/docker/cli-plugins/docker-compose
sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
exit
```

Reconecte por SSH e confira:

```bash
docker info
docker compose version
psql --version
curl --version
base64 --version
```

Clone o repositório na EC2. Para repositório privado, configure acesso de leitura ao GitHub antes:

```bash
git clone <URL_DO_REPOSITORIO>
cd <NOME_DO_REPOSITORIO>
```

## 4. Inicializar bancos e usuários — EC2

Na raiz do clone, informe o host do RDS **sem `:5432`**:

```bash
curl -fLo global-bundle.pem https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
export RDSHOST="<host-do-rds>"

psql "host=$RDSHOST port=5432 dbname=togglemasterdb user=master sslmode=verify-full sslrootcert=./global-bundle.pem" \
  -X -v ON_ERROR_STOP=1 -f fiap_tc_fase_03/infrasctructure/00-init.sql

psql "host=$RDSHOST port=5432 dbname=togglemasterdb user=master sslmode=verify-full sslrootcert=./global-bundle.pem" \
  -X -v ON_ERROR_STOP=1 -f infrasctructure/01-users.sql
```

Informe a senha `master` ao conectar. No segundo script, defina e guarde as três senhas solicitadas:

| Usuário | Banco | Tabela |
| --- | --- | --- |
| `auth_user` | `auth_db` | `api_keys` |
| `flags_user` | `flags_db` | `flags` |
| `targeting_user` | `targeting_db` | `targeting_rules` |

Execute `01-users.sql` uma vez. Não use `--single-transaction` nos scripts.

Confira o acesso de cada usuário; repita para os três bancos:

```bash
psql "host=$RDSHOST port=5432 dbname=auth_db user=auth_user sslmode=verify-full sslrootcert=./global-bundle.pem" \
  -X -c 'SELECT * FROM public.api_keys LIMIT 1;'
```

## Manutenção

Após alterar arquivos `.tf`, execute na máquina local:

```bash
cd infrasctructure
terraform validate
terraform plan
terraform apply
terraform output
```

- Use `terraform init -reconfigure` se mudar o backend.
- Importe recursos existentes antes de aplicar quando ainda não estiverem no estado.
- Reexecute `00-init.sql` apenas para inicialização; use uma migração para alterar tabelas existentes.
- Mantenha 8001–8005 fechadas no Security Group; deixe a porta 80 livre na EC2.
- Para HTTPS, configure domínio, certificado e listener TLS no proxy ou ALB; libere 443.
