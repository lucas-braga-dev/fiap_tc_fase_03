# Operação DevSecOps

Execute no PowerShell local, na raiz do repositório, usando sua identidade administrativa AWS. O usuário IAM do GitHub é exclusivo para publicação no ECR. Para a primeira instalação, use os guias de [infraestrutura](01-PROVISIONAMENTO.md) e [deploy](02-DEPLOY.md).

## Verificar o ambiente

```powershell
aws sts get-caller-identity
$clusterName = terraform -chdir=infrasctructure/eks output -raw cluster_name
$awsRegion = terraform -chdir=infrasctructure/eks output -raw aws_region
aws eks update-kubeconfig --region $awsRegion --name $clusterName
kubectl config current-context
kubectl get nodes --request-timeout=15s
kubectl get applications -n argocd
kubectl get deployments,pods,services -n togglemaster
kubectl rollout status daemonset/eks-pod-identity-agent -n kube-system
```

Espere nós `Ready`, Application `Synced/Healthy` e cinco Deployments disponíveis. Em caso de falha, veja [diagnóstico](SOLUCAO-DE-PROBLEMAS.md). Para testar APIs, reabra os port-forwards da etapa 6 do deploy e leia a chave existente. Não repita o bootstrap dos bancos.

## Publicar e reverter versões

Abra PR e acompanhe os testes, lint, SAST, SCA e scan das imagens dos cinco serviços. Uma falha de segurança bloqueia a publicação; corrija o pacote ou o código e publique outro commit. Não remova o gate CRITICAL.

Após merge em `main`, o CI publica imagens com tag SHA e o job `gitops` atualiza os cinco `newTag` em `gitops-manifests/aws/kustomization.yaml`. O ArgoCD reconcilia a alteração. Confira as imagens implantadas:

```powershell
kubectl get deployments -n togglemaster -o "custom-columns=SERVICO:.metadata.name,IMAGEM:.spec.template.spec.containers[*].image"
kubectl rollout status deployment/evaluation-service -n togglemaster
```

Para reverter, faça um commit de reversão do código, abra PR e publique pelo pipeline. Não edite Deployments com `kubectl set image`: o self-heal reconciliará com o Git. Em uma reversão urgente de tags no GitOps, confirme antes que as imagens anteriores existem e foram aprovadas; uma publicação posterior pode atualizar essas tags de novo.

## Atualizar infraestrutura

```powershell
terraform -chdir=infrasctructure/eks fmt -check -recursive
terraform -chdir=infrasctructure/eks validate
terraform -chdir=infrasctructure/eks plan -out=eks.tfplan
terraform -chdir=infrasctructure/eks apply eks.tfplan
```

Revise o plano antes do apply. Mantenha a conta, o backend e a chave de estado. Se endpoints mudarem, gere outputs UTF-8 e execute `scripts/configure-eks.py` conforme o deploy; publique o diff dos manifestos pelo Git. Se o IP de administração mudar, ajuste `admin_cidrs` e aplique antes de usar kubectl.

## Credenciais e bancos

| Credencial | Gestão |
| --- | --- |
| Senhas master RDS | Gerenciadas pelo RDS no Secrets Manager |
| Usuários dos bancos | Criados no bootstrap; alterações posteriores exigem migração coordenada do banco e Secret |
| `MASTER_KEY` | Preservada em `togglemaster-secrets`; não expor em Git ou logs |
| `SERVICE_API_KEY` | Emitida por `scripts/issue-eks-service-key.py`; preserva a master e reinicia Evaluation |
| Access key do CI | Criada no IAM fora do Terraform e mantida nos GitHub Secrets |
| Credenciais AWS dos Pods | Temporárias, obtidas por Pod Identity |

Para rotacionar a access key do CI, crie a segunda chave do mesmo usuário, atualize os dois GitHub Secrets, valide uma publicação e depois exclua a antiga. Para emitir nova chave de serviço, siga a etapa 5 do deploy e coordene a troca com outros clientes. Não use o bootstrap como rotação de senhas.

Mudanças de schema devem ser versionadas e aplicadas como migrações compatíveis com o rollout. O bootstrap é uma inicialização, não um sistema de migrações.

## Logs e custos

```powershell
kubectl get events -n togglemaster --sort-by=.metadata.creationTimestamp
kubectl logs -n togglemaster deployment/evaluation-service --tail=100
kubectl logs -n togglemaster deployment/analytics-service --tail=100
```

Para um container reiniciando, consulte `kubectl logs -n togglemaster NOME_DO_POD --previous` e `kubectl describe pod NOME_DO_POD -n togglemaster`, substituindo o nome. Health HTTP não substitui o fluxo SQS → Analytics → DynamoDB.

Monitore consumo e créditos em Billing/Cost Explorer. Elegibilidade Free Tier não garante custo zero. EKS, nós, NAT, RDS, Redis, armazenamento, logs e tráfego devem entrar na estimativa de custos. Consulte o consumo antes e depois de encerrar o ambiente para identificar recursos remanescentes.

## Desenvolvimento local

O Compose é uma alternativa de desenvolvimento, separada do EKS. Use Docker com containers Linux e um `.env` local com valores fictícios; não use as chaves reais do CI ou credenciais dos bancos AWS.

Na raiz do projeto:

```powershell
if (-not (Test-Path .env)) { Copy-Item .env.example .env }
docker compose up -d --build
docker compose ps
```

Na primeira execução, crie os recursos simulados no LocalStack. Os comandos abaixo usam a região e os nomes do `.env.example`; adapte se os alterou:

```powershell
docker compose exec localstack awslocal sqs create-queue --queue-name togglemaster-events --region us-east-1
docker compose exec localstack awslocal dynamodb create-table --table-name ToggleMasterAnalytics --attribute-definitions AttributeName=event_id,AttributeType=S --key-schema AttributeName=event_id,KeyType=HASH --billing-mode PAY_PER_REQUEST --region us-east-1
```

Se a tabela já existir, consulte-a em vez de recriar. Como o Compose não configura persistência do LocalStack, confira esses recursos novamente ao recriar seu container.

Para emitir uma chave local, leia a master do `.env`, chame Auth e atualize somente a chave de serviço, sem imprimir seu valor:

```powershell
$masterKey = ((Get-Content .env | Where-Object { $_ -match '^MASTER_KEY=' }) -replace '^MASTER_KEY=', '').Trim('"')
$issued = Invoke-RestMethod -Method Post -Uri 'http://localhost:8001/admin/keys' -Headers @{ Authorization = "Bearer $masterKey" } -ContentType 'application/json' -Body (@{ name = 'evaluation-local' } | ConvertTo-Json)
(Get-Content .env) -replace '^SERVICE_API_KEY=.*', "SERVICE_API_KEY=$($issued.key)" | Set-Content -Encoding utf8 .env
Remove-Variable masterKey, issued
docker compose up -d evaluation-service
```

Os serviços ficam em localhost nas portas 8001–8005. Use os exemplos HTTP da etapa 6 do deploy adaptando as portas 18002–18004 para 8002–8004 e lendo a chave do `.env` local, sem usar kubectl. Para parar preservando os volumes PostgreSQL/Redis, execute `docker compose down`; não adicione `--volumes` se precisar dos dados.

## Encerrar o ambiente

Execute quando terminar de usar o ambiente e puder remover os recursos e seus dados. Exporte os dados que precisar: os RDS usam `skip_final_snapshot = true`.

1. Desative a sincronização automática da Application antes de limpar aplicações; se remover a Application, confira seus finalizers e o efeito sobre os recursos.
2. Remova eventuais Services LoadBalancer/Ingress e espere os balanceadores serem excluídos.
3. Consulte `terraform -chdir=infrasctructure/eks output -raw github_ecr_user_name` e exclua as access keys desse usuário no IAM. Elas foram criadas fora do Terraform e impedem a exclusão do usuário enquanto existirem. Remova os Secrets AWS do GitHub quando deixar de usar o pipeline.
4. Desinstale ArgoCD e revise o plano de destruição:

```powershell
kubectl config current-context
helm uninstall argocd -n argocd
terraform -chdir=infrasctructure/eks init -backend-config=backend.hcl
terraform -chdir=infrasctructure/eks plan -destroy -out=destroy.tfplan
terraform -chdir=infrasctructure/eks apply destroy.tfplan
```

Se o ECR impedir exclusão de repositórios com imagens, exporte o que precisar e exclua as imagens após revisar; gere outro plano de destruição. Não ative exclusão forçada sem avaliar a perda de artefatos.

Confira no console se restaram EKS, EC2 dos nós, RDS, ElastiCache, NAT Gateways, IPs elásticos, volumes e balanceadores. O bucket S3 do estado foi criado separadamente e não é removido pelo stack; preserve seu histórico até concluir a auditoria. Recursos de stacks antigos exigem a configuração e o backend de sua própria revisão no Git; não aplique EKS sobre um estado legado.
