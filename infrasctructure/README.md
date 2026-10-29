# Como criar a infraestrutura e configurar os serviços AWS

abra a pasta 'infrasctructure' no terminal e rode os seguintes comandos:

``` cmd
# inicializa o projeto, já aplicado
terraform init -reconfigure

# cria os recursos na aws
terraform apply
```

depois de tudo criado, pegue o IP público retornado no terminal e se conecte à instância ec2:

ssh -i "caminho/do/arquivo/pem" ec2-user@<ip-da-instância>

após conectado, configurar a VM:

# 1. Atualiza os pacotes do sistema
sudo yum update -y

# 2. Instala o motor do Docker e o cliente PostgreSQL
sudo yum install -y docker 
sudo yum install -y postgresql17-server

# 3. Inicia o serviço do Docker e o configura para ligar junto com a máquina
sudo systemctl start docker
sudo systemctl enable docker

# 4. Instala o Docker Compose baixando o binário oficial
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# 5. Adiciona o ec2-user ao grupo do Docker para não precisar usar 'sudo'
sudo usermod -aG docker ec2-user

ao finalizar, encerre e abra uma nova conexão SSH na EC2.
configure o banco com:

# baixa alguma coisa
curl -o global-bundle.pem https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem

# faz a conexão
export RDSHOST="terraform-20261029211403455500000003.chs4wkeuil9w.us-east-2.rds.amazonaws.com" 
psql "host=$RDSHOST port=5432 dbname=togglemasterdb user=master sslmode=verify-full sslrootcert=./global-bundle.pem"

