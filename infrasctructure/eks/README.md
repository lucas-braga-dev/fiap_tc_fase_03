# Infraestrutura EKS — Fase 3

Use sua conta pessoal AWS. Execute no **PowerShell da máquina local**. Comece na raiz do repositório. Não execute estes comandos dentro de um Pod ou por SSH nos nós.

## 1. Preparar

1. Instale AWS CLI, Terraform >= 1.10, kubectl, Helm e Python.
2. Configure as credenciais AWS da identidade que provisionará o cluster e confira `aws sts get-caller-identity`. Essa identidade é diferente do usuário restrito que o pipeline usará para publicar imagens.
3. Crie um bucket S3 para o estado, se ainda não existir.
4. Configure:

```powershell
cd infrasctructure/eks
if (-not (Test-Path backend.hcl)) { Copy-Item backend.hcl.example backend.hcl }
if (-not (Test-Path terraform.tfvars)) { Copy-Item terraform.tfvars.example terraform.tfvars }
```

Edite:

| Arquivo | Preencher |
| --- | --- |
| `backend.hcl` | Bucket, região e chave `fase3/eks/terraform.tfstate` |
| `terraform.tfvars` | Região, ambiente e seu IP público em `admin_cidrs` |

Para descobrir seu IPv4 público no PowerShell, execute `Invoke-RestMethod https://checkip.amazonaws.com`. Preencha `admin_cidrs` com o endereço retornado seguido de `/32`. O endereço `203.0.113.10/32` do exemplo não serve para provisionar o EKS.

Os Pods usam EKS Pod Identity: o Terraform instala `eks-pod-identity-agent` e associa roles distintas às ServiceAccounts `evaluation-service` e `analytics-service` no namespace `togglemaster`. A confiança de cada role limita cluster, namespace e ServiceAccount; as policies permitem somente as operações necessárias em SQS e DynamoDB. Os nós já recebem `eks-auth:AssumeRoleForPodIdentity` por `AmazonEKSWorkerNodePolicy` e acessam as APIs AWS pelo NAT da rede.

O GitHub Actions usa um usuário IAM exclusivo, criado pelo Terraform com permissão de publicação nos cinco ECR. A access key é criada separadamente após o apply, conforme [deploy/README.md](../../deploy/README.md), para não armazenar o segredo no estado Terraform.

O launch template exige IMDSv2 com hop limit 1 para limitar o acesso dos Pods à role do nó. O agente Pod Identity usa a rede do host e continua acessando essa role; Evaluation e Analytics recebem suas próprias credenciais temporárias pelo agente.

Essa configuração não cria providers IAM OIDC. Ela evita a dependência das ações `iam:*Provider*` bloqueadas na experiência simplificada da AWS; outras restrições da conta ainda podem impedir recursos. Referências: [EKS Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html) e [políticas gerenciadas para projetos](https://docs.aws.amazon.com/accounts/latest/reference/scps-and-rcps-for-projects.html).

Na experiência básica/simplificada, a AWS gerencia as SCPs da organização. Ser dono do projeto não garante acesso à conta de gerenciamento ou à edição dessas políticas. `AccessDenied` com `explicit deny in a service control policy` não é corrigido adicionando `AdministratorAccess`. O fluxo deste repositório foi adaptado para dispensar providers OIDC; não é necessário ativar os recursos avançados apenas para seguir esse fluxo. Veja [as restrições e a solução adotada](../../docs/SOLUCAO-DE-PROBLEMAS.md#bloqueio-de-provider-oidc-por-scp).

Não versione `backend.hcl` nem `terraform.tfvars`.

### Restrições do plano gratuito: EC2 e RDS

O default dos nós é `m7i-flex.large` (x86_64, compatível com as imagens `linux/amd64` do pipeline), listado pela AWS como elegível para o novo Free Tier. Confirme na região da conta antes do apply:

```powershell
aws ec2 describe-instance-types --region us-east-2 --filters "Name=free-tier-eligible,Values=true" --query "InstanceTypes[].InstanceType" --output table
```

Use a região do seu `terraform.tfvars`. Se necessário, escolha outro tipo x86_64 elegível com capacidade para os serviços e ArgoCD. Não use `t4g` com as imagens atuais, pois essa família exige ARM64. `t3.medium` não é elegível nesse plano; `t3.micro` e `t3.small` oferecem menos memória e capacidade de Pods. A elegibilidade não significa custo zero: o consumo continua sujeito aos créditos, cotas e limites do plano. Consulte [Free Tier EC2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-free-tier-usage.html).

O backup RDS usa `rds_backup_retention_days = 1`. O valor é configurável; períodos maiores podem ser rejeitados pelo plano gratuito. Os três RDS e demais serviços continuam sujeitos aos limites próprios da conta.

No seu `terraform.tfvars`, confira explicitamente estes valores (a configuração local prevalece sobre os defaults do código):

```hcl
node_instance_types       = ["m7i-flex.large"]
rds_backup_retention_days = 1
```

Se a tabela de elegibilidade aparecer vazia, repita sem `--query`, com `--output json`. No CMD, aspas simples não delimitam argumentos como no Bash; use sempre as aspas duplas mostradas acima. Confirme a elegibilidade na conta e região de destino antes do provisionamento.

Se o Node Group terminou em `CREATE_FAILED`, gere um novo plano após corrigir `node_instance_types`. A mudança do tipo deve provocar substituição do Node Group. Se o plano não mostrar substituição, force somente esse recurso:

```powershell
terraform plan -replace=aws_eks_node_group.main -out=eks.tfplan
terraform apply eks.tfplan
```

Revise a substituição antes de aplicar. Mantenha o estado e os demais recursos; não é necessário destruir toda a infraestrutura. Se seu `terraform.tfvars` já define `node_instance_types` ou `rds_backup_retention_days`, ajuste esses valores: eles prevalecem sobre os defaults novos.

## 2. Validar e provisionar

Execute **dentro de `infrasctructure/eks`**, após preencher os dois arquivos. Se um comando falhar, pare e corrija a causa antes do próximo.

```powershell
aws sts get-caller-identity
terraform init -backend-config=backend.hcl
terraform fmt -check -recursive
terraform validate
terraform plan -out=eks.tfplan
terraform apply eks.tfplan
terraform output
```

Revise o plan e a estimativa de custos antes do apply. Preserve o backend e revise substituições e exclusões antes de aplicar.

## 3. Conectar ao cluster

Volte para a raiz do projeto com `Set-Location ../..`, se ainda estiver em `infrasctructure/eks`.

```powershell
New-Item -ItemType Directory -Force tmp | Out-Null
$clusterName = terraform -chdir=infrasctructure/eks output -raw cluster_name
$awsRegion = terraform -chdir=infrasctructure/eks output -raw aws_region
aws eks update-kubeconfig --region $awsRegion --name $clusterName
kubectl config current-context
kubectl get nodes --request-timeout=15s
kubectl rollout status daemonset/eks-pod-identity-agent -n kube-system
aws eks list-pod-identity-associations --region $awsRegion --cluster-name $clusterName
terraform -chdir=infrasctructure/eks output -json | Set-Content -Encoding utf8 tmp/eks-outputs.json
```

Use a identidade AWS que criou o cluster. Se seu IP mudar, atualize `admin_cidrs` e aplique o Terraform.

Antes de avançar, confirme os dois nós `Ready`, o agente disponível e duas associações Pod Identity no namespace `togglemaster`. `i/o timeout` ao executar kubectl indica falha de conexão; compare seu IP público com os CIDRs permitidos seguindo [o diagnóstico de acesso](../../docs/SOLUCAO-DE-PROBLEMAS.md#kubectl-com-io-timeout). Não precisa recriar o cluster para corrigir o IP permitido.

Os outputs incluem endpoints, ARNs dos segredos RDS e roles. As senhas master são gerenciadas pelo RDS no Secrets Manager.

O uso de `Set-Content -Encoding utf8` evita gerar JSON UTF-16 no Windows PowerShell 5.1. Os scripts aceitam UTF-8 com ou sem BOM. Não versione `tmp/eks-outputs.json`. Com as verificações acima aprovadas, siga [o deploy](../../deploy/README.md).

## Atualizar

Na raiz do projeto:

```powershell
terraform -chdir=infrasctructure/eks plan -out=eks.tfplan
terraform -chdir=infrasctructure/eks apply eks.tfplan
```

Mantenha a mesma configuração de backend e conta AWS. Atualize os manifestos se os endpoints mudarem.
