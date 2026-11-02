# Deploy EKS com GitOps

Execute no **PowerShell da sua máquina local, na raiz do projeto**. Todos os comandos deste guia usam esse terminal, exceto o exemplo explicitamente marcado como Bash. No CMD, abra uma sessão com `powershell` antes de continuar e confirme a pasta com `Get-Location`.

Tenha o EKS provisionado, contexto kubectl correto, nós `Ready` e agente Pod Identity disponível. Se ainda não conectou ou gerou os outputs, siga [a etapa 3 do guia EKS](PROVISIONAMENTO.md#3-conectar-ao-cluster). Timeout de conexão deve ser resolvido antes de continuar.

Execute as etapas em ordem. Em uma retomada, confira o que já está concluído: o bootstrap da etapa 2 só deve rodar uma vez; a emissão da chave da etapa 5 só precisa ser repetida para gerar uma nova chave. Não refaça bancos e Secrets para corrigir imagens ou acesso ao cluster.

## 1. Configurar os manifestos

Gere novamente os outputs após alterações da infraestrutura e configure os arquivos:

```powershell
New-Item -ItemType Directory -Force tmp | Out-Null
terraform -chdir=infrasctructure/eks output -json | Set-Content -Encoding utf8 tmp/eks-outputs.json
python scripts/configure-eks.py tmp/eks-outputs.json
kubectl kustomize gitops-manifests/aws > tmp/aws-rendered.yaml
```

Confira os arquivos alterados em `gitops-manifests/aws` e `gitops-manifests/argocd/application.yaml`. Não versione o arquivo de outputs.

`kubectl kustomize` apenas renderiza os manifestos para inspeção; não implanta os serviços. O arquivo renderizado contém o ConfigMap e os Deployments, mas o Secret da aplicação é criado separadamente pelo bootstrap. Na primeira configuração, as tags podem estar como `bootstrap`: são provisórias e precisam ser substituídas pelo job `gitops` antes da primeira sincronização.

Evaluation e Analytics usam as associações EKS Pod Identity criadas pelo Terraform. O script configura endpoints, imagens e origem Git; a identidade dos Pods é configurada no EKS, sem annotations de role nos manifestos.

## 2. Inicializar bancos e Secrets

Confira o contexto antes de executar:

```powershell
kubectl config current-context
kubectl get nodes
kubectl get secret togglemaster-secrets -n togglemaster --ignore-not-found
```

O contexto deve ser o EKS esperado. Se o namespace ainda não existir, a consulta do Secret pode retornar `NotFound`; crie o namespace abaixo. **Se o Secret `togglemaster-secrets` já aparecer, não execute o bootstrap novamente.** Se ele não existe e esta é a primeira inicialização:

```powershell
kubectl apply -f gitops-manifests/aws/namespace.yaml
python scripts/bootstrap-eks-databases.py tmp/eks-outputs.json
```

O script usa Secrets Manager, aplica schemas/grants dentro do cluster e remove o Secret master temporário após sucesso. Não execute novamente se o Secret de aplicação já existir.

Se falhar:

```powershell
kubectl logs -n togglemaster job/togglemaster-db-bootstrap
kubectl get jobs,pods -n togglemaster
```

Corrija a causa e repita o script antes de iniciar o deploy. Não publique Secrets no Git.

O sucesso termina com `Three databases initialized; application Secret created; temporary master Secret removed.` Confira apenas a existência, sem exibir o conteúdo: `kubectl get secret togglemaster-secrets -n togglemaster`. A chave de serviço ainda é provisória; será emitida após Auth ficar disponível.

## 3. Configurar GitHub Actions

Em **Settings → Secrets and variables → Actions**, defina:

Essas configurações ficam **no repositório do GitHub**, não no ArgoCD nem nos Secrets Kubernetes. Obtenha os valores não secretos e o nome do usuário IAM assim:

```powershell
terraform -chdir=infrasctructure/eks output -raw aws_region
terraform -chdir=infrasctructure/eks output -raw aws_account_id
terraform -chdir=infrasctructure/eks output -raw github_ecr_user_name
```

| Tipo | Nome | Valor |
| --- | --- | --- |
| Variable | `AWS_REGION` | Output `aws_region` |
| Variable | `AWS_ACCOUNT_ID` | Output `aws_account_id` |
| Secret | `AWS_ACCESS_KEY_ID` | Access key do usuário exclusivo de publicação |
| Secret | `AWS_SECRET_ACCESS_KEY` | Secret access key desse usuário |

Após o apply, execute `terraform -chdir=infrasctructure/eks output -raw github_ecr_user_name`. No console **IAM → Users → usuário retornado → Security credentials → Create access key**, crie uma chave para o GitHub Actions e copie os dois valores diretamente para os Secrets acima. O usuário tem apenas as permissões necessárias para autenticação ECR, leitura e envio de imagens aos cinco repositórios do projeto.

Na criação da access key, selecione o caso de uso de aplicação fora da AWS e conclua as confirmações do console. A tela final exibe **Access key ID** e **Secret access key**; a segunda só é exibida nessa criação. Na aba **Secrets** do GitHub, use **New repository secret** para cadastrar um valor por vez. Na aba **Variables**, use **New repository variable** para região e ID da conta. Nunca cole as chaves em conversas ou commits.

Não use as credenciais do usuário que provisiona a infraestrutura. O Terraform não cria access keys, não exibe segredos em outputs e não armazena essas chaves no estado. Não salve os valores em arquivos versionados, logs ou manifestos. O workflow usa as chaves diretamente, sem `role-to-assume`, `AWS_SESSION_TOKEN` ou permissão `id-token: write`.

Na rotação, crie a segunda chave do mesmo usuário, atualize os dois Secrets, confirme uma publicação e depois desative/exclua a antiga. Antes de destruir a infraestrutura, exclua as access keys desse usuário no IAM; elas foram criadas fora do Terraform e impedem a exclusão do usuário enquanto existirem.

Permita escrita de Contents pelo GitHub Actions. Se houver proteção da branch, autorize o mecanismo de automação a atualizar os manifestos.

Confira em **Settings → Actions → General → Workflow permissions** se a política permite escrita. O job `gitops` declara `contents: write`, mas a proteção da branch pode exigir configuração adicional. O resultado esperado é o bot conseguir atualizar `gitops-manifests/aws/kustomization.yaml` na branch `main`.

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

```powershell
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm upgrade --install argocd argo/argo-cd --namespace argocd --create-namespace --wait --timeout 10m
kubectl get pods -n argocd
```

O Helm instala os componentes no EKS; após concluir, os Pods do namespace `argocd` devem ficar prontos. A interface fica acessível por port-forward conforme abaixo. Para repositório privado, configure acesso de leitura em **ArgoCD → Settings → Repositories** antes de aplicar a Application.

### Publicar imagens antes de sincronizar a aplicação

Revise `git status` e `git diff`, faça commit das alterações de código e dos manifestos configurados e publique em `main` pelo fluxo de PR do projeto. Não inclua credenciais, planos, estados ou arquivos de `tmp`. Se tudo já está publicado e as configurações do GitHub foram corrigidas depois, use **Actions → DevSecOps and GitOps → Run workflow → main**.

Uma execução de PR valida o código, mas não publica imagens. Espere os jobs **container-scan**, **publish** e **gitops** terminarem com sucesso em `main`. O pipeline publica as imagens com a tag SHA do commit e depois atualiza as cinco tags no Kustomization. O commit do bot usa `[skip ci]`, portanto pode não iniciar outra execução; confira o arquivo e o job `gitops` da execução original.

Somente após essa atualização, execute na raiz do projeto:

```powershell
git pull --ff-only
Select-String -Path gitops-manifests/aws/kustomization.yaml -Pattern 'newName:|newTag:'
```

Os cinco `newName` devem apontar para sua conta/região e todos os `newTag` devem conter o SHA publicado, sem `bootstrap`. Se `git pull` reclamar de mudanças locais, revise-as antes de continuar; não descarte automaticamente configurações locais. Agora registre a Application:

```powershell
kubectl apply -f gitops-manifests/argocd/application.yaml
kubectl get applications -n argocd
kubectl get deployments -n togglemaster -o "custom-columns=SERVICO:.metadata.name,IMAGEM:.spec.template.spec.containers[*].image"
kubectl get pods -n togglemaster
```

O ArgoCD aplica os manifestos; o CI publica as imagens e atualiza as tags no Git.

Confira a Application `togglemaster` como `Synced/Healthy`. Na interface, use **Refresh → Sync** se ainda não sincronizou. Espere os cinco Deployments terem réplicas disponíveis e os Pods ficarem `Running`, com containers `1/1` prontos. `kubectl get pods -n togglemaster -w` acompanha as mudanças continuamente; use **Ctrl+C** para voltar ao prompt. Se aparecer `ImagePullBackOff`, veja [o diagnóstico de imagens](SOLUCAO-DE-PROBLEMAS.md#errimagepull-ou-imagepullbackoff).

Para abrir a interface, execute na máquina local e mantenha esse terminal aberto:

```powershell
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

Faça esta etapa depois que Auth estiver pronto. Todos os terminais abaixo são PowerShell locais, na raiz do projeto e no mesmo contexto EKS. O usuário de publicação do GitHub não tem as permissões administrativas para executar esses scripts; use sua identidade local de administração.

**Terminal A:** abra o acesso ao Auth e mantenha o comando executando:

```powershell
kubectl port-forward -n togglemaster service/auth-service 18001:8001
```

**Terminal B:** emita a chave:

```powershell
python scripts/issue-eks-service-key.py
```

O script preserva a `MASTER_KEY`, atualiza `SERVICE_API_KEY` e reinicia Evaluation.

O resultado esperado termina com `SERVICE_API_KEY issued and Evaluation updated; MASTER_KEY preserved.` O script já espera o rollout de Evaluation. Feche o port-forward do Terminal A com **Ctrl+C** ao terminar. Não repita a emissão apenas para consultar a chave existente; a etapa seguinte lê o Secret atual.

## 6. Testar

### Conferir serviços e abrir as portas locais

Na raiz do projeto, confira o rollout:

```powershell
kubectl get deployments,pods,services -n togglemaster
kubectl rollout status deployment/evaluation-service -n togglemaster
```

Abra **três terminais PowerShell locais**, um para cada comando abaixo, e deixe todos executando. Os port-forwards encerram quando o terminal fecha ou você pressiona Ctrl+C.

Terminal Evaluation:

```powershell
kubectl port-forward -n togglemaster service/evaluation-service 18004:8004
```

Terminal Flags:

```powershell
kubectl port-forward -n togglemaster service/flag-service 18002:8002
```

Terminal Targeting:

```powershell
kubectl port-forward -n togglemaster service/targeting-service 18003:8003
```

### Criar flag, regra e avaliar no PowerShell

Em um **quarto terminal PowerShell**, na raiz do projeto:

```powershell
Invoke-RestMethod -Uri 'http://localhost:18004/health'

$keyBase64 = kubectl get secret togglemaster-secrets -n togglemaster -o "jsonpath={.data.SERVICE_API_KEY}"
$apiKey = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($keyBase64))
if ($apiKey -eq 'PENDENTE_PRIMEIRO_DEPLOY') { throw 'Emita a chave de servico seguindo a etapa 5 antes de continuar.' }
$headers = @{ Authorization = "Bearer $apiKey" }

$flagBody = @{ name = 'teste-deploy'; is_enabled = $true } | ConvertTo-Json
Invoke-RestMethod -Method Post -Uri 'http://localhost:18002/flags' -Headers $headers -ContentType 'application/json' -Body $flagBody

$ruleBody = @{ flag_name = 'teste-deploy'; is_enabled = $true; rules = @{ type = 'PERCENTAGE'; value = 100 } } | ConvertTo-Json -Depth 4
Invoke-RestMethod -Method Post -Uri 'http://localhost:18003/rules' -Headers $headers -ContentType 'application/json' -Body $ruleBody

Invoke-RestMethod -Uri 'http://localhost:18004/evaluate?user_id=teste&flag_name=teste-deploy'
Remove-Variable apiKey, keyBase64, headers
```

Execute cada chamada e confira a resposta antes de avançar; se uma falhar, corrija a causa antes da próxima. O health deve retornar `status: ok`, e a avaliação deve retornar `result: true`. Se a flag/regra já foi criada com sucesso, não repita os POSTs: execute apenas a avaliação. Os exemplos usam `Invoke-RestMethod` para evitar diferenças de alias de `curl` e escape de JSON no Windows. Se preferir curl para uma consulta simples, use `curl.exe --fail http://localhost:18004/health`.

Não use `API_KEY="$(...)"`, `base64 --decode` ou `unset` no CMD/PowerShell: são formas Bash. Não exiba a chave de serviço no terminal para copiar nem a inclua nas evidências.

### Confirmar o evento no DynamoDB

O health sozinho não confirma o fluxo de eventos. Depois da avaliação, confira o processamento assíncrono:

```powershell
kubectl logs -n togglemaster deployment/analytics-service --tail=50
terraform -chdir=infrasctructure/eks output -raw dynamodb_table_name
```

Nos logs, procure o evento da flag `teste-deploy` salvo no DynamoDB. No console AWS, na mesma conta/região, abra **DynamoDB → Tables → nome retornado pelo output → Explore table items** e confira um item com `user_id = teste`, `flag_name = teste-deploy` e `result = true`. Aguarde o consumidor SQS processar antes de concluir que o item não existe. Salve a evidência do evento, sem incluir Secrets.

Se houver falha de credenciais AWS nos serviços, confira o DaemonSet `eks-pod-identity-agent` em `kube-system`, as duas associações com `aws eks list-pod-identity-associations --region <REGIAO> --cluster-name <CLUSTER>` e os logs de Evaluation/Analytics. As associações precisam corresponder ao namespace e às ServiceAccounts dos manifestos. Pods antigos precisam ser recriados após configurar a identidade. Os SDKs atuais do projeto suportam Pod Identity pela cadeia padrão de credenciais.

## Rotina

- Publique código por PR. Em `main`, o CI publica imagens aprovadas no ECR e atualiza as cinco tags.
- Confira a Application `togglemaster` como `Synced/Healthy` no ArgoCD.
- Para reverter, reverta o código e publique uma nova versão.
- Se um scan detectar CRITICAL, corrija a dependência/imagem; não remova o bloqueio.
- Consulte falhas com `kubectl logs -n togglemaster deployment/<servico> --tail=100`.
- Consulte [problemas e correções](SOLUCAO-DE-PROBLEMAS.md) para timeout, imagem `bootstrap`, falha de scan, autenticação e comandos Windows.
