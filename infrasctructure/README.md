# Infraestrutura AWS

Este diretório provisiona VPC, subnets, regras de acesso, uma EC2, um RDS PostgreSQL e um bucket S3 para a aplicação. O estado do Terraform fica em um bucket S3 separado, que precisa existir antes da inicialização.

## 1. Preparar os pré-requisitos

Antes de executar o Terraform, tenha:

- Terraform instalado, compatível com o backend S3 e a opção `use_lockfile` de `main.tf`.
- AWS CLI configurada com credenciais válidas e permissões para provisionar os recursos e acessar o estado remoto. Se as credenciais forem temporárias, inclua o token de sessão.
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

- Atualizar os pacotes usando o gerenciador da distribuição.
- Instalar Docker, Docker Compose e o cliente PostgreSQL (`psql`). O servidor PostgreSQL ficará no RDS.
- Iniciar o Docker e habilitá-lo na inicialização.
- Se for executar Docker sem `sudo`, adicionar o usuário ao grupo `docker` e abrir uma nova sessão SSH.
- Disponibilizar uma cópia completa deste repositório, incluindo `infrasctructure` e `apps-togglemaster`.

**Para avançar:** conexão SSH funcionando, comandos `docker`, `docker compose` e `psql` disponíveis e repositório presente na EC2.

## 4. Inicializar os bancos no RDS

Execute esta etapa na EC2: a regra de rede do RDS permite conexões na porta 5432 a partir do Security Group da instância.

Na raiz do repositório, baixe o certificado de confiança do RDS e informe o host retornado pelo Terraform. O output `rds_endpoint` inclui a porta; em `RDSHOST`, use somente o nome do host, sem `:5432`.

```bash
curl -o global-bundle.pem https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
export RDSHOST="<host-do-rds>"

psql "host=$RDSHOST port=5432 dbname=togglemasterdb user=master sslmode=verify-full sslrootcert=./global-bundle.pem" \
  -X -f infrasctructure/init.sql
```

Informe a senha do RDS quando solicitada. O banco inicial `togglemasterdb` é criado pelo Terraform; o script cria os bancos usados pelos serviços:

| Serviço | Banco | Tabela |
| --- | --- | --- |
| Auth | `auth_db` | `api_keys` |
| Flags | `flags_db` | `flags` |
| Targeting | `targeting_db` | `targeting_rules` |

O script carrega os arquivos SQL dos serviços por caminhos relativos ao próprio arquivo. Mantenha a estrutura do repositório na EC2; copiar apenas `init.sql` não basta.

A execução pode ser repetida: bancos e tabelas existentes são preservados, e funções e triggers são recriados. O script não migra estruturas antigas. Não use `--single-transaction`; se ocorrer um erro, a execução para e as etapas anteriores podem já ter sido aplicadas.

**Para avançar:** script concluído sem erros e as três tabelas disponíveis nos respectivos bancos. Para conferir, conecte-se a cada banco pelo `psql` e execute `\dt public.*`.

## 5. Preparar a configuração da aplicação

Antes do deploy, é preciso:

- Definir as `DATABASE_URL` de Auth, Flags e Targeting com o host do RDS, o banco correspondente, credenciais válidas e configuração SSL.
- Disponibilizar usuários e permissões de acesso às tabelas. O script não cria os usuários `auth_user` e `config_user` usados no ambiente Docker local; as tabelas são criadas pelo usuário que executa o script.
- Configurar as demais dependências dos serviços: Redis, SQS, DynamoDB, chaves da aplicação e credenciais ou permissões AWS. Os arquivos Terraform deste diretório não provisionam Redis, SQS ou DynamoDB, nem associam uma IAM Role à EC2.
- Conferir os caminhos e as configurações do mecanismo de deploy escolhido. O `docker-compose.yaml` da raiz ainda referencia caminhos antigos dos serviços e bancos locais; precisa ser adaptado para o RDS antes de ser usado nesse cenário.
- Definir como as APIs serão expostas. O Security Group atual libera HTTP na porta 80, mas não configura proxy nem libera diretamente as portas 8001 a 8005 dos serviços.

**Para avançar:** dependências disponíveis, variáveis configuradas e acesso HTTP definido. Provisionar a infraestrutura e inicializar o banco não inicia os serviços da aplicação.
