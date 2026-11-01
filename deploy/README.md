# Deploy EKS com GitOps

Tenha o EKS provisionado, contexto kubectl correto, nós Ready e `tmp/eks-outputs.json` atualizado. Execute na raiz do projeto.

## 1. Configurar os manifestos

```bash
python scripts/configure-eks.py tmp/eks-outputs.json
kubectl kustomize gitops-manifests/aws > tmp/aws-rendered.yaml
```

Confira os arquivos alterados em `gitops-manifests/aws` e `gitops-manifests/argocd/application.yaml`. Não versione o arquivo de outputs.

Evaluation e Analytics usam as associações EKS Pod Identity criadas pelo Terraform. O script configura endpoints, imagens e origem Git; a identidade dos Pods é configurada no EKS, sem annotations de role nos manifestos.

Se já usava IRSA, remova de sua cópia local o bloco `components: / - identity` do Kustomization e os patches que adicionam `eks.amazonaws.com/role-arn`. Após sincronizar os novos manifestos, remova a annotation antiga das duas ServiceAccounts se ainda existir e reinicie os Pods para receber as variáveis do Pod Identity:

```bash
kubectl annotate serviceaccount evaluation-service analytics-service -n togglemaster eks.amazonaws.com/role-arn-
kubectl rollout restart deployment/evaluation-service deployment/analytics-service -n togglemaster
```

Essa limpeza só é necessária para workloads já implantados com a configuração anterior. Não injete access keys AWS nos Secrets dos Pods.

## 2. Inicializar bancos e Secrets

Confira o contexto antes de executar:

```bash
kubectl config current-context
kubectl apply -f gitops-manifests/aws/namespace.yaml
python scripts/bootstrap-eks-databases.py tmp/eks-outputs.json
```

O script usa Secrets Manager, aplica schemas/grants dentro do cluster e remove o Secret master temporário após sucesso. Não execute novamente se o Secret de aplicação já existir.

Se falhar:

```bash
kubectl logs -n togglemaster job/togglemaster-db-bootstrap
kubectl get jobs,pods -n togglemaster
```

Corrija a causa e repita o script antes de iniciar o deploy. Não publique Secrets no Git.

## 3. Configurar GitHub Actions

Em **Settings → Secrets and variables → Actions**, defina:

| Tipo | Nome | Valor |
| --- | --- | --- |
| Variable | `AWS_REGION` | Output `aws_region` |
| Variable | `AWS_ACCOUNT_ID` | Output `aws_account_id` |
| Secret | `AWS_ACCESS_KEY_ID` | Access key do usuário exclusivo de publicação |
| Secret | `AWS_SECRET_ACCESS_KEY` | Secret access key desse usuário |

Após o apply, execute `terraform -chdir=infrasctructure/eks output -raw github_ecr_user_name`. No console **IAM → Users → usuário retornado → Security credentials → Create access key**, crie uma chave para o GitHub Actions e copie os dois valores diretamente para os Secrets acima. O usuário tem apenas as permissões necessárias para autenticação ECR, leitura e envio de imagens aos cinco repositórios do projeto.

Não use as credenciais do usuário que provisiona a infraestrutura. O Terraform não cria access keys, não exibe segredos em outputs e não armazena essas chaves no estado. Não salve os valores em arquivos versionados, logs ou manifestos. O workflow usa as chaves diretamente, sem `role-to-assume`, `AWS_SESSION_TOKEN` ou permissão `id-token: write`. Remova a antiga variável `AWS_ECR_ROLE_ARN`, se existir.

Na rotação, crie a segunda chave do mesmo usuário, atualize os dois Secrets, confirme uma publicação e depois desative/exclua a antiga. Antes de destruir a infraestrutura, exclua as access keys desse usuário no IAM; elas foram criadas fora do Terraform e impedem a exclusão do usuário enquanto existirem.

Permita escrita de Contents pelo GitHub Actions. Se houver proteção da branch, autorize o mecanismo de automação a atualizar os manifestos.

## 4. Instalar ArgoCD

O ArgoCD será instalado **dentro do cluster EKS `togglemaster-fase3`, no namespace `argocd`**. Execute os comandos abaixo **no terminal da sua máquina local, na raiz deste repositório**. O Helm deve estar instalado nessa máquina; ele enviará os recursos ao cluster configurado no seu kubeconfig.

No PowerShell, selecione o cluster usando os outputs do Terraform e confira os nós antes de instalar:

```powershell
$clusterName = terraform -chdir=infrasctructure/eks output -raw cluster_name
$awsRegion = terraform -chdir=infrasctructure/eks output -raw aws_region
aws eks update-kubeconfig --region $awsRegion --name $clusterName
kubectl config current-context
kubectl get nodes
helm version
```

O contexto deve terminar em `cluster/togglemaster-fase3` (ou no nome retornado pelo Terraform, se você mudou o ambiente), e os nós devem estar `Ready`. Se `helm` não for encontrado, instale o [Helm](https://helm.sh/docs/intro/install/) na máquina local antes de continuar.

Execute no mesmo terminal; estes comandos funcionam em PowerShell e Bash:

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm upgrade --install argocd argo/argo-cd --namespace argocd --create-namespace --wait --timeout 10m
kubectl get pods -n argocd
```

Para repositório privado, configure acesso de leitura em **ArgoCD → Settings → Repositories** antes de aplicar a Application.

Publique os manifestos configurados e acompanhe o workflow **DevSecOps and GitOps** em `main`. Após o job `gitops` atualizar as cinco tags:

```bash
git pull --ff-only
kubectl apply -f gitops-manifests/argocd/application.yaml
kubectl get applications -n argocd
kubectl get pods -n togglemaster -w
```

O pipeline não acessa a EC2 nem aplica Deployments diretamente no cluster.

Para abrir a interface, execute na máquina local e mantenha esse terminal aberto:

```bash
kubectl port-forward -n argocd service/argocd-server 8443:443
```

Abra `https://localhost:8443`. Obtenha a senha inicial do usuário `admin`:

No PowerShell, em outro terminal local:

```powershell
$passwordBase64 = kubectl -n argocd get secret argocd-initial-admin-secret -o "jsonpath={.data.password}"
[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($passwordBase64))
```

Ou, no Bash:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 --decode
```

## 5. Emitir a chave de serviço

Mantenha o port-forward em outro terminal:

```bash
kubectl port-forward -n togglemaster service/auth-service 18001:8001
```

Na raiz do projeto:

```bash
python scripts/issue-eks-service-key.py
```

O script preserva a `MASTER_KEY`, atualiza `SERVICE_API_KEY` e reinicia Evaluation.

## 6. Testar

```bash
kubectl get deployments,pods,services -n togglemaster
kubectl rollout status deployment/evaluation-service -n togglemaster
kubectl port-forward -n togglemaster service/evaluation-service 18004:8004
```

Em outro terminal:

```bash
curl --fail "http://localhost:18004/health"
```

Abra port-forwards de Flags (`18002:8002`) e Targeting (`18003:8003`). Obtenha a chave de API do Secret e crie uma flag/regra:

```bash
API_KEY="$(kubectl get secret togglemaster-secrets -n togglemaster -o jsonpath='{.data.SERVICE_API_KEY}' | base64 --decode)"
curl --fail-with-body -X POST http://localhost:18002/flags -H "Authorization: Bearer $API_KEY" -H 'Content-Type: application/json' -d '{"name":"teste-deploy","is_enabled":true}'
curl --fail-with-body -X POST http://localhost:18003/rules -H "Authorization: Bearer $API_KEY" -H 'Content-Type: application/json' -d '{"flag_name":"teste-deploy","is_enabled":true,"rules":{"type":"PERCENTAGE","value":100}}'
curl --fail "http://localhost:18004/evaluate?user_id=teste&flag_name=teste-deploy"
unset API_KEY
```

Confirme `result: true` e o evento na tabela DynamoDB indicada pelo Terraform. Se flag/regra já existirem, repita apenas a avaliação.

Se houver falha de credenciais AWS nos serviços, confira o DaemonSet `eks-pod-identity-agent` em `kube-system`, as duas associações com `aws eks list-pod-identity-associations --region <REGIAO> --cluster-name <CLUSTER>` e os logs de Evaluation/Analytics. As associações precisam corresponder ao namespace e às ServiceAccounts dos manifestos. Pods antigos precisam ser recriados após configurar a identidade. Os SDKs atuais do projeto suportam Pod Identity pela cadeia padrão de credenciais.

## Rotina

- Publique código por PR. Em `main`, o CI publica imagens aprovadas no ECR e atualiza as cinco tags.
- Confira a Application `togglemaster` como `Synced/Healthy` no ArgoCD.
- Para reverter, reverta o código e publique uma nova versão.
- Se um scan detectar CRITICAL, corrija a dependência/imagem; não remova o bloqueio.
- Consulte falhas com `kubectl logs -n togglemaster deployment/<servico> --tail=100`.
