# Diagnóstico do ambiente

Use PowerShell na máquina local, na raiz do repositório. Preserve backend e estado Terraform. Para procedimentos recorrentes, consulte [operação](OPERACAO.md); para a implantação inicial, [deploy](../deploy/README.md).

## Comandos Windows

Se aparecer `'API_KEY' não é reconhecido`, confira o terminal: `API_KEY=...`, `base64 --decode` e `unset` são sintaxe Bash. Use o PowerShell e os exemplos de `Invoke-RestMethod` da etapa 6 do deploy. Não copie o prefixo do prompt.

Use aspas duplas nos argumentos `--query` e `-o "jsonpath=..."`. Se uma consulta AWS aparecer vazia, repita sem `--query` e com `--output json`. Grave outputs com `Set-Content -Encoding utf8` para evitar UTF-16 do redirecionamento no Windows PowerShell 5.1.

## Bloqueio de provider OIDC por SCP

`iam:CreateOpenIDConnectProvider` ou `iam:GetOpenIDConnectProvider` com `explicit deny in a service control policy` indica uma restrição da organização. Na experiência simplificada, a AWS pode gerenciar essas políticas; ser dono do projeto não concede acesso à edição. Adicionar uma policy IAM não supera a negação da SCP.

Este projeto dispensa providers OIDC: usa Pod Identity para os Pods e usuário IAM exclusivo para o CI. Confira se está usando os arquivos atuais. Se a SCP bloquear outros recursos, consulte a política aplicável; não remova recursos do estado para ocultar a falha.

## CIDR inválido

`203.0.113.10/32` é um endereço de documentação. Substitua `admin_cidrs` no `terraform.tfvars` pelo seu IP público real seguido de `/32`:

```powershell
Invoke-RestMethod https://checkip.amazonaws.com
```

Gere e revise um novo plano antes do apply. Não use o IP privado da máquina.

## Free Tier e apply parcial

Se o Node Group falhar por instância inelegível, consulte os tipos da região:

```powershell
aws ec2 describe-instance-types --region us-east-2 --filters "Name=free-tier-eligible,Values=true" --query "InstanceTypes[].InstanceType" --output table
```

O default é `m7i-flex.large`, x86_64. Confirme elegibilidade, capacidade e disponibilidade na região da conta. As imagens atuais são `linux/amd64`; `t4g` exige adaptar o build para ARM64. Elegibilidade não garante custo zero.

Se RDS rejeitar a retenção de backup no plano gratuito, confira `rds_backup_retention_days = 1`. Valores do `terraform.tfvars` prevalecem sobre os defaults.

Para retomar um apply parcial, mantenha conta/backend/estado e gere novo plano. Se o Node Group ficou em `CREATE_FAILED` e precisa ser recriado, revise a substituição somente dele:

```powershell
terraform -chdir=infrasctructure/eks plan -replace=aws_eks_node_group.main -out=eks.tfplan
terraform -chdir=infrasctructure/eks apply eks.tfplan
```

Não reutilize um plano gerado antes de mudar variáveis ou código. Não destrua toda a infraestrutura para corrigir esse recurso.

## kubectl com i/o timeout

Timeout TCP na porta 443 ocorre antes da autenticação. Compare seu IP atual com o endpoint público e os CIDRs:

```powershell
Invoke-RestMethod https://checkip.amazonaws.com
$clusterName = terraform -chdir=infrasctructure/eks output -raw cluster_name
$awsRegion = terraform -chdir=infrasctructure/eks output -raw aws_region
aws eks describe-cluster --region $awsRegion --name $clusterName --query "cluster.resourcesVpcConfig.{Publico:endpointPublicAccess,CIDRs:publicAccessCidrs}" --output json
```

Se o IP mudou, ajuste `admin_cidrs`, revise e aplique o Terraform. Não precisa recriar o cluster nem liberar `0.0.0.0/0`. Se os CIDRs estiverem corretos, verifique VPN, proxy e firewall:

```powershell
$endpoint = aws eks describe-cluster --region $awsRegion --name $clusterName --query "cluster.endpoint" --output text
Test-NetConnection -ComputerName ([Uri]$endpoint).Host -Port 443
```

`Unauthorized` ou `Forbidden` exige conferir a identidade (`aws sts get-caller-identity`), o contexto e o acesso EKS. O usuário limitado de publicação ECR não administra o cluster.

## Credenciais

| Local | Credencial e origem |
| --- | --- |
| GitHub Secrets | `AWS_ACCESS_KEY_ID` e `AWS_SECRET_ACCESS_KEY`, da access key do usuário `github_ecr_user_name` |
| GitHub Variables | `AWS_REGION` e `AWS_ACCOUNT_ID`, dos outputs Terraform |
| Kubernetes Secret | Bancos, `MASTER_KEY` e `SERVICE_API_KEY`, do bootstrap/emissão de chave |
| Evaluation/Analytics | Credenciais AWS temporárias por Pod Identity |

Uma Secret access key perdida deve ser substituída por nova chave e rotacionada; ela não pode ser recuperada pelo Terraform. Falhas de credenciais nos Pods exigem conferir o DaemonSet `eks-pod-identity-agent` e as associações no EKS, correspondendo a cluster, namespace e ServiceAccounts. Não injete as access keys do CI nos Pods nem repita o bootstrap para corrigir identidade AWS.

## ErrImagePull ou ImagePullBackOff

```powershell
kubectl get deployments -n togglemaster -o "custom-columns=SERVICO:.metadata.name,IMAGEM:.spec.template.spec.containers[*].image"
kubectl get events -n togglemaster --sort-by=.metadata.creationTimestamp
```

Para detalhes, consulte `kubectl describe pod NOME_DO_POD -n togglemaster`, substituindo o nome. `:bootstrap: not found` indica a tag provisória: espere `publish` e `gitops` passarem em `main`, confira os cinco `newTag` e sincronize o ArgoCD. Uma execução de PR não publica imagens.

`403` ou `no basic auth credentials` pode indicar permissão ECR da role dos nós; timeout pode indicar rede. As credenciais do GitHub servem para publicação, não para o pull feito pelos nós. Se `gitops` falhar, confira escrita de Contents e proteção da branch.

## Falha de scan

No relatório Trivy, identifique pacote, CVE, versão instalada e corrigida. Achados de sistema operacional exigem atualizar a imagem base/pacotes; editar `requirements.txt` não corrige uma biblioteca Debian.

Os containers Python usam Trixie com atualizações Debian; o CI atualiza a base e reconstrói esses estágios sem cache. Não desabilite o gate CRITICAL nem ignore CVEs apenas para publicar. Publique um commit com a correção: reexecutar um job antigo não incorpora um Dockerfile novo.

## Testes HTTP e eventos

`Connection refused` em localhost: confira o port-forward no terminal separado e se o Pod está pronto. Após restart, pode ser necessário reabrir o port-forward. A interface ArgoCD exige manter o forward `8443:443` ativo na máquina local.

`401/403` nas APIs: releia `SERVICE_API_KEY` do Secret e confirme emissão da chave. Não use a access key AWS ou `MASTER_KEY` para chamadas Flags/Targeting. `PENDENTE_PRIMEIRO_DEPLOY` exige a etapa 5 do deploy.

Health `ok` não prova persistência: execute avaliação e confira logs do Analytics e o item DynamoDB, conforme a etapa 6 do deploy. Não recrie flag/regra se já existem.
