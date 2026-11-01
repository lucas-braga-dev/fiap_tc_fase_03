# Roteiro de apresentação — ToggleMaster Fase 3

**Duração planejada: 19 minutos, com 1 minuto de margem.** Fonte: [enunciado oficial](<POSTECH - Tech Challenge - Fase 3.pdf>), requisitos técnicos nas páginas 3–5 e entregáveis nas páginas 5–6. O vídeo deve evidenciar IaC, falha/correção de segurança e entrega GitOps automática. O relatório final deve ser PDF ou TXT.

## Preparação da gravação

1. Preencha participantes e links no [relatório de entrega](ENTREGA-FASE-3.md). Prepare o print da estimativa de custos AWS e confira acesso do avaliador ao repositório, documentação e vídeo.
2. Confirme EKS acessível, nós prontos, cinco serviços disponíveis, Application `Synced/Healthy` e evento funcional no DynamoDB. Use [operação](OPERACAO.md) e a etapa 6 do [deploy](../deploy/README.md).
3. Abra abas: repositório e workflow, execução de segurança bloqueada, execução corrigida, commit do bot com as tags, console AWS, ArgoCD e item DynamoDB. Mostre identificadores de commit/execução para correlacionar as evidências.
4. Deixe preparados os port-forwards e os terminais de consulta. Esconda abas com Secrets, senhas, access keys e `.env`; não exiba o estado Terraform ou o conteúdo de Secrets Kubernetes.
5. Prepare a demonstração de segurança **antes** da gravação. Use uma alteração real no microsserviço ou em sua construção, apresente o diff, a falha no gate e o commit de correção aprovado. A ocorrência SQLite/zlib e o diff Bookworm → Trixie são evidências reais disponíveis no histórico. Se precisar reproduzir, use branch temporária/PR e não faça merge de uma versão vulnerável.
6. Para mostrar o sync automático, capture o ArgoCD no momento em que o job `gitops` publicar as novas tags. O build pode levar vários minutos: inicie-o antes da gravação ou grave esse trecho separadamente, mostrando claramente a mesma sequência de commits e execução. Não apresente um Sync manual como evidência de sincronização automática.

Os comandos abaixo são PowerShell local, na raiz do repositório. Se houver mais de um apresentador, uma divisão possível é infraestrutura/segurança até 10:00 e GitOps/validação/entrega depois disso. Todos devem estar identificados no relatório.

## 00:00–01:15 — Problema e solução

**Tela:** README e fluxo de entrega.

**Fala sugerida:**

> “O ToggleMaster tem cinco microsserviços: Auth gerencia chaves; Flags gerencia feature flags; Targeting define regras; Evaluation calcula a decisão e publica eventos; Analytics consome e persiste os resultados. Nesta fase automatizamos a infraestrutura e a entrega. O objetivo é reduzir configuração manual, impedir publicação de imagens críticas e manter o estado desejado das aplicações no Git.”

Explique o fluxo em uma frase: PR/push → testes/lint/SAST/SCA → build/scan → ECR com SHA → atualização das tags no Git → ArgoCD → EKS. Diferencie CI, que valida/publica, de CD, feito pelo ArgoCD.

## 01:15–04:30 — Infraestrutura como código

**Telas:** `infrasctructure/eks/main.tf`, módulo `modules/network/main.tf`, `cluster.tf`, `data.tf` e recursos correspondentes no console AWS.

**Fala sugerida:**

> “O Terraform provisiona a VPC, subnets públicas e privadas, Internet Gateway, rotas e NAT; o EKS e seus Node Groups; três RDS PostgreSQL, um ElastiCache Redis, SQS com fila de mensagens não processadas, DynamoDB e cinco repositórios ECR. O estado usa backend remoto S3 e locking configurado no exemplo de backend.”

Mostre no código e no console, sem percorrer todos os atributos:

| Requisito | Evidência |
| --- | --- |
| Rede | VPC, subnets públicas/privadas e tabelas de rotas do módulo |
| EKS | Cluster, Node Group e nós `Ready` |
| Bancos/cache | Três instâncias PostgreSQL e replication group Redis |
| Eventos | Fila SQS e tabela DynamoDB de Analytics |
| Imagens | Cinco repositórios ECR |
| Estado remoto | `backend "s3" {}` e exemplo `backend.hcl.example`; bucket no console, sem abrir o conteúdo do estado |

No terminal:

```powershell
terraform -chdir=infrasctructure/eks validate
terraform -chdir=infrasctructure/eks plan
kubectl get nodes
```

Revise o plano antes de mostrá-lo. Em um ambiente já reconciliado, `No changes` é esperado. O PDF permite mostrar plan/apply **ou o resultado final na AWS**: use os recursos existentes e uma execução anterior do apply se não houver mudança a aplicar. Não recrie a infraestrutura apenas para o vídeo.

## 04:30–06:00 — IAM e credenciais

**Telas:** `iam.tf`, ServiceAccounts dos manifestos e referência dos Deployments ao Secret, sem abrir seus valores.

**Fala sugerida:**

> “Usamos conta pessoal. As aplicações recebem credenciais AWS temporárias por EKS Pod Identity: Evaluation só envia ao SQS; Analytics consome a fila e grava no DynamoDB. Cada role é associada à sua ServiceAccount e limitada ao cluster e namespace. O CI usa outro usuário IAM, limitado aos repositórios ECR. As access keys ficam em GitHub Secrets; senhas master do RDS são gerenciadas pelo Secrets Manager. O bootstrap inicializa os bancos e entrega às aplicações um Secret Kubernetes, sem gravar senhas no Git.”

Explique a restrição que motivou a escolha: a experiência simplificada bloqueava providers OIDC por SCP. Pod Identity remove essa dependência. A access key do CI exige rotação, documentada em operação. Não prometa ausência de credenciais persistentes nem apresente Kubernetes Secret em Base64 como criptografia.

## 06:00–10:00 — Pipeline DevSecOps e bloqueio de segurança

**Telas:** `.github/workflows/deploy.yml`, jobs das cinco entradas da matriz, diff vulnerável/corrigido e logs das duas execuções.

Mostre a configuração para PR e push em `main`, e os estágios:

1. Build/testes unitários de Go e Python.
2. `go vet` e Ruff como análise estática/lint.
3. gosec/Bandit para SAST e Trivy filesystem para SCA.
4. Build e Trivy na imagem; CRITICAL retorna erro, impedindo `publish`.
5. Somente após aprovação, publicação das imagens já escaneadas no ECR com SHA.

**Fala sugerida:**

> “Aqui está a alteração que resultou no bloqueio. Nos três containers Python, o scan detectou CVEs críticas nas bibliotecas SQLite e zlib da base Debian Bookworm. O relatório identifica pacote, CVE e versão; o job terminou com erro e a publicação não prosseguiu. Corrigimos os Dockerfiles para Trixie com atualização de pacotes e nova construção. Nesta segunda execução, os scans passaram e a publicação foi liberada. O gate não foi desativado e `ignore-unfixed` continua falso.”

Mostre o diff do Dockerfile, não apenas o resumo vermelho/verde. Diferencie vulnerabilidades do SO daquelas dos pacotes Python. A [execução bloqueada conhecida](https://github.com/lucas-braga-dev/fiap_tc_fase_03/actions/runs/41265400644) está vinculada ao commit `1b1175cc4c68abc77173841e822bbd41b738a1da`; localize a execução aprovada correspondente e registre ambos os links no relatório. Se usar outra demonstração, substitua as referências pelas evidências reais.

## 10:00–14:00 — GitOps e sincronização automática

**Telas:** imagem no ECR com SHA, job `gitops`, commit do bot, `gitops-manifests/aws/kustomization.yaml`, Application YAML e interface ArgoCD.

**Fala sugerida:**

> “O CI publica imagens identificadas pelo commit e atualiza as tags nesta pasta de GitOps. O ArgoCD monitora `main` e esse caminho, com sincronização automática, prune e self-heal. O CI não executa o deploy da aplicação por kubectl: é o ArgoCD que reconcilia o Git com o cluster.”

Demonstre a sequência real:

1. Correlacione SHA publicado no ECR e `newTag` do commit do bot.
2. Mostre `source.path`, `targetRevision` e `syncPolicy.automated` da Application.
3. Mostre ArgoCD detectando a revisão nova, sincronizando e voltando a `Synced/Healthy`. Deixe visíveis os cinco microsserviços na árvore.
4. Confira as imagens e a conclusão do rollout no terminal:

```powershell
kubectl get applications -n argocd
kubectl get deployments -n togglemaster -o "custom-columns=SERVICO:.metadata.name,IMAGEM:.spec.template.spec.containers[*].image"
kubectl rollout status deployment/evaluation-service -n togglemaster
kubectl get pods -n togglemaster
```

As tags precisam ser SHA, não `bootstrap`. Mostre histórico de sync/revisão para comprovar a mudança, além do status final. Um Refresh pode antecipar a consulta do Git; não clique em Sync para substituir a demonstração automática exigida.

## 14:00–16:30 — Validação funcional

**Telas:** terminal HTTP, logs Analytics e item DynamoDB.

Deixe Flags/Targeting configurados antes da gravação conforme a etapa 6 do deploy. No terminal, com o port-forward Evaluation ativo:

```powershell
Invoke-RestMethod -Uri 'http://localhost:18004/health'
Invoke-RestMethod -Uri 'http://localhost:18004/evaluate?user_id=apresentacao&flag_name=teste-deploy'
kubectl logs -n togglemaster deployment/analytics-service --tail=30
```

**Fala sugerida:**

> “A flag de demonstração está habilitada com regra de 100%. A avaliação retorna true, publica o evento na fila e o Analytics o grava no DynamoDB. Este item tem o mesmo usuário e nome de flag, e mostra o resultado e timestamp.”

Atualize a visualização da tabela após o processamento assíncrono. Relacione chamada e evento por `user_id`, `flag_name` e horário. O acesso por port-forward é para demonstração; não afirme que há Ingress público, HPA ou KEDA na arquitetura entregue, pois os manifestos atuais não os configuram.

## 16:30–18:00 — Decisões e custos

**Telas:** tabela de decisões do relatório e print da estimativa AWS.

Explique brevemente as decisões com impacto operacional:

- Pod Identity e usuário de publicação ECR: compatibilidade com restrições da conta, menor privilégio e necessidade de rotação da access key.
- Nós x86_64 elegíveis e retenção RDS de um dia: limites do plano da conta; elegibilidade não significa custo zero.
- Atualização da base Python: corrigir pacotes do SO preservando o bloqueio do scan.
- Backend S3 e GitOps: estado da infraestrutura centralizado e versão das aplicações rastreável no Git.

No print, explicite região, quantidade de nós, três RDS, Redis, EKS, NAT, armazenamento e hipóteses de uso. Distinga **estimativa** de **gasto real**; não invente valores. Mostre o procedimento documentado de encerramento sem executá-lo no vídeo.

## 18:00–19:00 — Entregáveis

**Telas:** árvore final do repositório e relatório PDF/TXT.

**Fala sugerida:**

> “O repositório contém o Terraform, os cinco serviços e testes, o workflow DevSecOps e os manifestos GitOps. A documentação cobre provisionamento, implantação, operação e diagnóstico. O relatório identifica os participantes, os links de documentação e vídeo, as decisões e a estimativa de custos.”

Mostre os links preenchidos e confirme o formato final do relatório. Termine antes de 20:00; não deixe a publicação do vídeo ou a exportação do relatório como uma etapa presumida.

## Correspondência com o PDF

| Exigência | Página | Trecho do vídeo / artefato |
| --- | --- | --- |
| Rede, EKS/Node Groups, três RDS, Redis, DynamoDB, SQS e ECR | 3 | 01:15–04:30; Terraform e console |
| Backend remoto S3 | 3 | 01:15–04:30; backend e bucket |
| CI dos cinco serviços em PR/push, testes, lint, SAST/SCA, bloqueio e scan de imagens | 4 | 06:00–10:00; workflow e execuções |
| Alteração com falha de segurança, correção e sucesso | 5 | 06:00–10:00; diffs e logs vinculados |
| Imagens com commit hash, tags atualizadas e pasta GitOps | 4–5 | 10:00–14:00; ECR e commit do bot |
| ArgoCD no EKS e sync automático dos cinco serviços | 5 | 10:00–14:00; revisão/sync e árvore ArgoCD |
| Código Terraform, workflows e manifestos no repositório | 5 | 18:00–19:00; estrutura e links |
| Relatório PDF/TXT com participantes, documentação/vídeo, decisões e print de custos | 6 | 16:30–19:00; relatório final |
| Vídeo de até 20 minutos | 5 | Duração final do arquivo publicado |
