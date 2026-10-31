# Deploy na EC2

Tenha disponíveis: EC2 com Docker/Compose, clone em `~/fiap-tc-fase-03`, bancos e usuários criados, senhas e outputs do Terraform.

## 1. Configurar Docker Hub e GitHub — navegador

No Docker Hub, crie os repositórios no mesmo namespace:

```text
togglemaster-auth-service
togglemaster-flag-service
togglemaster-targeting-service
togglemaster-evaluation-service
togglemaster-analytics-service
```

No GitHub, em **Settings → Secrets and variables → Actions**, configure:

| Tipo | Nome | Valor |
| --- | --- | --- |
| Variable | `DOCKERHUB_NAMESPACE` | Usuário ou organização Docker Hub |
| Secret | `DOCKERHUB_USERNAME` | Usuário Docker Hub |
| Secret | `DOCKERHUB_TOKEN` | Token com permissão de publicação |
| Secret | `EC2_HOST` | Output `ec2_public_ip` |
| Secret | `EC2_USER` | `ubuntu` ou `ec2-user` |
| Secret | `EC2_SSH_KEY` | Conteúdo completo da chave privada `.pem` |
| Secret | `EC2_SSH_PASSPHRASE` | Senha da chave, se houver |
| Secret | `EC2_HOST_FINGERPRINT` | Fingerprint SHA256 do servidor SSH |

Obtenha o fingerprint dentro de uma sessão SSH confiável na EC2:

```bash
sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub -E sha256
```

Copie somente `SHA256:...` para o secret. Permita SSH do runner do GitHub à EC2.

No GitHub, crie **Settings → Environments → production**. Mantenha as credenciais Docker Hub nos secrets do repositório.

Para imagens privadas, autentique o Docker **na EC2** com um token de leitura:

```bash
docker login --username <USUARIO_DOCKERHUB>
```

## 2. Preencher o `.env` — EC2

Na raiz do clone, crie o arquivo somente se ainda não existir:

```bash
cd ~/fiap-tc-fase-03
test -f .env || cp deploy/.env.ec2.example .env
chmod 600 .env
nano .env
```

Preencha os valores de [`.env.ec2.example`](.env.ec2.example):

| Variável | Preencher com |
| --- | --- |
| `DOCKERHUB_NAMESPACE` | Mesmo namespace configurado no GitHub |
| `IMAGE_TAG` | SHA completo do commit que será implantado |
| `AUTH_DATABASE_URL` | `postgres://auth_user:SENHA@HOST:5432/auth_db?sslmode=require` |
| `FLAGS_DATABASE_URL` | `postgres://flags_user:SENHA@HOST:5432/flags_db?sslmode=require` |
| `TARGETING_DATABASE_URL` | `postgres://targeting_user:SENHA@HOST:5432/targeting_db?sslmode=require` |
| `MASTER_KEY` | Segredo novo; gere com `openssl rand -hex 32` |
| `SERVICE_API_KEY` | No primeiro deploy: `PENDENTE_PRIMEIRO_DEPLOY`; substitua na etapa 4 |
| `AWS_REGION` | Output `aws_region` |
| `AWS_SQS_URL` | Output `sqs_queue_url` |
| `AWS_DYNAMODB_TABLE` | Output `dynamodb_table_name` |

- Em `HOST`, use o endpoint RDS sem a porta; mantenha `:5432` uma única vez na URL.
- Codifique caracteres especiais nas credenciais da URL: `@` → `%40`, `#` → `%23`, `$` → `%24`.
- Deixe `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` e `AWS_SESSION_TOKEN` vazios.
- Não defina `AWS_ENDPOINT_URL` no deploy.
- Não use a `MASTER_KEY` como `SERVICE_API_KEY`.

## 3. Executar o primeiro deploy — GitHub

1. Publique os arquivos na branch `main`.
2. Abra **Actions → Build and deploy EC2**.
3. Acompanhe a execução do push ou escolha **Run workflow → main**.
4. Aguarde os jobs `build` e `deploy` terminarem.
5. Na EC2, atualize `IMAGE_TAG` no `.env` com o SHA salvo em `deployed-image-tag`.

O pipeline fornece namespace e tag durante a execução. Para comandos manuais, mantenha esses valores atualizados no `.env`.

## 4. Emitir a chave de serviço — EC2, uma vez

Na raiz do clone, crie a chave pelo Auth local:

```bash
read -rsp 'MASTER_KEY definida no .env: ' MASTER_KEY; echo
curl --fail-with-body -X POST http://127.0.0.1:8001/admin/keys \
  -H "Authorization: Bearer $MASTER_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"name":"evaluation-service"}'
unset MASTER_KEY
```

Copie o campo `key` retornado para `SERVICE_API_KEY` no `.env`. Guarde a chave; ela aparece uma vez.

```bash
nano .env
docker compose --env-file .env -f compose.ec2.yaml up -d --no-deps evaluation-service
```

## 5. Testar — EC2

Verifique os cinco serviços pelo proxy:

```bash
for service in auth flags targeting evaluation analytics; do
  curl --fail --show-error "http://localhost/$service/health"
done
```

Informe a chave emitida na etapa 4:

```bash
read -rsp 'Chave de API: ' API_KEY; echo
curl --fail-with-body http://localhost/auth/validate \
  -H "Authorization: Bearer $API_KEY"

curl --fail-with-body -X POST http://localhost/flags/flags \
  -H "Authorization: Bearer $API_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"name":"teste-deploy","description":"Teste de deploy","is_enabled":true}'

curl --fail-with-body -X POST http://localhost/targeting/rules \
  -H "Authorization: Bearer $API_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"flag_name":"teste-deploy","is_enabled":true,"rules":{"type":"PERCENTAGE","value":100}}'

curl --fail-with-body 'http://localhost/evaluation/evaluate?user_id=teste&flag_name=teste-deploy'
unset API_KEY
```

Confirme `result: true`. No console AWS, abra **DynamoDB → Tables → valor de `AWS_DYNAMODB_TABLE` → Explore table items** e confira o evento de `teste-deploy`.

Repita apenas a avaliação se a flag e a regra já existirem.

Na máquina local, teste o acesso externo:

```bash
curl --fail http://<IP_EC2>/auth/health
curl --fail 'http://<IP_EC2>/evaluation/evaluate?user_id=teste&flag_name=teste-deploy'
```

## Rotina

**Publicar código:** faça push em `main` e acompanhe o workflow.

**Aplicar alterações do `.env`:** na EC2, atualize `IMAGE_TAG` com `cat deployed-image-tag`, edite `.env` e execute:

```bash
cd ~/fiap-tc-fase-03
docker compose --env-file .env -f compose.ec2.yaml config --quiet
docker compose --env-file .env -f compose.ec2.yaml up -d --wait
```

**Consultar estado e logs:**

```bash
docker compose --env-file .env -f compose.ec2.yaml ps
docker compose --env-file .env -f compose.ec2.yaml logs --tail=100 evaluation-service analytics-service proxy
cat deployed-image-tag
```

**Alterar o proxy:** edite [nginx.conf](nginx.conf) e publique em `main`.

**Recuperar uma versão:** reverta o commit no GitHub e acompanhe o novo deploy.

**Investigar falhas de eventos:** confira os logs de Evaluation/Analytics e a fila indicada pelo output `sqs_dlq_url` no console SQS.

## Falha de conexão SSH

Para `dial tcp ...:22: i/o timeout`, confira nesta ordem:

1. AWS → EC2 → instância: confirme `Running` e status checks aprovados.
2. Copie o **Public IPv4 address** atual para o secret `EC2_HOST` no GitHub. Use somente o IP ou DNS, sem `http://`, usuário ou `:22`.
3. Confira o Security Group associado à instância: permita TCP 22 a partir do runner do GitHub. Não use apenas o IP do seu computador para o deploy.
4. Confira a tabela de rotas da subnet da EC2: `0.0.0.0/0` deve apontar para o Internet Gateway.
5. Se houver Network ACL personalizada, permita entrada TCP 22 e saída para as portas efêmeras do cliente (`1024–65535`).
6. Teste SSH da máquina local e confira o firewall e o serviço SSH na EC2.
7. No GitHub, escolha **Re-run failed jobs**.

Após parar/iniciar ou substituir a EC2, confira novamente `EC2_HOST`. Se trocar a instância, atualize também o fingerprint e a chave SSH, se necessário.
