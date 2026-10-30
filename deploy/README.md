# CI/CD para EC2

O workflow `.github/workflows/deploy.yml` usa Docker Hub e a EC2 existente. Não executa Terraform nem inicializa o RDS durante deploys.

## Fluxo

1. Pull request para `main`: verifica sintaxe Python, executa testes Go e constrói as cinco imagens, sem publicar ou acessar a EC2.
2. Push em `main` (ou execução manual nessa branch): repete o CI e publica `NAMESPACE/togglemaster-SERVICO:SHA_DO_COMMIT` no Docker Hub.
3. Após todos os builds passarem, o job de deploy envia o Compose pelo SSH, executa `pull` e `up -d`, aguarda a inicialização e consulta `/health` dos cinco serviços.
4. O commit implantado com sucesso fica em `~/togglemaster/deployed-image-tag`. Execuções da mesma branch são serializadas.

O Compose da EC2 usa RDS e serviços AWS reais, com Redis local persistido. Ele não usa o Compose local nem inicia PostgreSQL ou LocalStack. As imagens são `linux/amd64`, compatíveis com a EC2 `t3.micro` atual.

## Configuração no GitHub

Crie a variável de repositório em **Settings → Secrets and variables → Actions → Variables**:

| Variável | Valor |
| --- | --- |
| `DOCKERHUB_NAMESPACE` | Usuário ou organização no Docker Hub que receberá as cinco imagens. |

Cadastre os secrets do repositório:

| Secret | Conteúdo |
| --- | --- |
| `DOCKERHUB_USERNAME` | Usuário autorizado a publicar no namespace. |
| `DOCKERHUB_TOKEN` | Token Docker Hub com permissão de publicação. |
| `EC2_HOST` | IP público ou DNS da EC2. Atualize se o endereço mudar. |
| `EC2_USER` | Usuário SSH da AMI (`ubuntu` ou `ec2-user`). |
| `EC2_SSH_KEY` | Conteúdo completo da chave privada `.pem`, incluindo cabeçalho e rodapé. |
| `EC2_SSH_PASSPHRASE` | Senha da chave, somente se ela for protegida. |
| `EC2_HOST_FINGERPRINT` | Fingerprint SHA256 da chave pública do servidor SSH, obtido por acesso confiável à EC2. |

Crie o environment `production`. Regras de aprovação nesse environment, se configuradas, pausam o CD; sem elas, o deploy segue automaticamente. Os secrets do Docker Hub precisam estar disponíveis no repositório, pois o build não usa esse environment.

## Preparação única da EC2

- Conclua o provisionamento e a inicialização do RDS descritos em `../infrasctructure/README.md`.
- Tenha Docker, Compose v2 com suporte a `up --wait`, `curl` e `base64` disponíveis. O usuário SSH precisa executar Docker sem interação com `sudo`.
- Permita o acesso SSH do runner do GitHub à instância e confirme o fingerprint do servidor. O workflow não altera Security Groups.
- Crie `~/togglemaster` e coloque uma cópia preenchida de `.env.ec2.example` em `~/togglemaster/.env`, acessível apenas ao usuário de deploy (`chmod 600`).
- Crie os cinco repositórios `togglemaster-auth-service`, `togglemaster-flag-service`, `togglemaster-targeting-service`, `togglemaster-evaluation-service` e `togglemaster-analytics-service` no namespace escolhido.
- Para imagens privadas, autentique o Docker da EC2 uma vez com um token separado de leitura (`docker login --username USUARIO --password-stdin`). O login do CI não autentica a EC2.
- Disponibilize SQS e DynamoDB, suas configurações e permissões. Prefira uma IAM Role associada à EC2; o Terraform atual ainda não a cria. Credenciais temporárias no `.env` precisam ser renovadas quando expirarem.
- Use usuários de banco com acesso às tabelas. O exemplo usa TLS com `sslmode=require`; para validar também identidade e cadeia de confiança, configure o certificado dentro dos contêineres e `sslmode=verify-full`.

O `SERVICE_API_KEY` deve ser uma chave válida emitida pelo Auth, não a `MASTER_KEY`. No primeiro deploy, pode ser necessário iniciar o Auth, emitir a chave e atualizar o `.env` antes de consumir as APIs de avaliação.

As portas 8001 a 8005 ficam acessíveis somente em `127.0.0.1` na EC2. Para acesso externo, configure um proxy na instância e o roteamento HTTP/TLS. O pipeline não instala esse proxy.

## Validação e recuperação

O primeiro push em `main` após configurar os requisitos dispara o fluxo; também é possível usar **Actions → Build and deploy EC2 → Run workflow**, selecionando `main`.

O deploy não executa `compose down` nem apaga volumes. Uma falha de download impede a etapa de atualização; uma falha durante a inicialização pode deixar serviços parcialmente atualizados. Não há rollback automático ou garantia de indisponibilidade zero nesta base. Para recuperar, escolha um commit conhecido e execute novamente o workflow desse commit na branch `main` (por exemplo, revertendo a mudança com um novo commit).

Os checks de saúde verificam disponibilidade HTTP; não substituem testes funcionais de autenticação, avaliação e processamento de eventos. Esta base inclui testes Go e validação de sintaxe Python, sem uma política de bloqueio por vulnerabilidades de imagens.

Referências: [build e publicação de imagens](https://github.com/docker/build-push-action) e [SSH com verificação de fingerprint](https://github.com/appleboy/ssh-action).
