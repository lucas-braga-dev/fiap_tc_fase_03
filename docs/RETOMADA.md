# Retomar o projeto

## Estado desta alteração

- Código do cenário EKS, CI DevSecOps, ECR e GitOps preparado.
- Cenário EC2 anterior preservado.
- Nenhum `terraform apply` do EKS executado pelo assistente.
- Configuração real da conta, provisionamento, scans no GitHub, ArgoCD e testes no EKS ainda precisam ser executados.
- Não considere os requisitos encerrados apenas pela validação local do código.

## Validações locais concluídas

- Terraform validate nos cenários EC2 e EKS.
- Apply Terraform simulado com provider AWS mockado para validar associações Pod Identity, confiança das roles e escopo do usuário ECR, sem criar recursos reais.
- Renderização Kubernetes local e AWS, sem patches de role nas ServiceAccounts.
- Testes unitários Go/Python e dos scripts de configuração.
- Go vet, Ruff e SAST com gosec/Bandit no nível de bloqueio configurado.
- Trivy: nenhuma vulnerabilidade CRITICAL nas dependências declaradas dos cinco serviços.
- Teste negativo Trivy: uma dependência vulnerável em pasta temporária retornou código 1.

Ainda execute o scan das imagens no CI e os testes reais no EKS. Revise as exceções pontuais G704 documentadas no Evaluation junto dos testes de destino permitido e bloqueio de redirects.

O scan do commit `1b1175cc4c68abc77173841e822bbd41b738a1da` identificou duas vulnerabilidades CRITICAL iguais nos três containers Python baseados em Debian Bookworm: `libsqlite3-0` (CVE-2025-7458) e `zlib1g` (CVE-2023-45853). As dependências Python não apresentaram achados nesse scan. Os Dockerfiles foram migrados para `python:3.11-slim-trixie`, mantendo Python 3.11 e atualizando os pacotes Debian nos dois estágios. O CI busca imagens base atuais, reconstrói os estágios Python sem cache e verifica imports e `pip check` antes do Trivy. A aprovação das novas imagens precisa ser confirmada em uma nova execução do pipeline; o bloqueio CRITICAL continua ativo, inclusive para vulnerabilidades sem correção.

Referência da correção SQLite no Trixie: [Debian Security Tracker](https://security-tracker.debian.org/tracker/CVE-2025-7458).

## Amanhã

A autenticação foi adaptada para EKS Pod Identity e usuário IAM exclusivo do GitHub Actions, sem providers IAM OIDC. A access key deve ser criada no IAM e cadastrada nos GitHub Secrets após o apply. Os testes locais não confirmam que todas as operações sejam permitidas pelas políticas da conta AWS.

1. Confira `git status` e revise as alterações.
2. Configure e provisione o cenário EKS seguindo `infrasctructure/eks/README.md`.
3. Siga `deploy/README.md`.
4. Preencha `docs/ENTREGA-FASE-3.md`.
5. Faça commit das configurações sem incluir credenciais ou estados.

## Remover o cenário EC2 atual

Na raiz do projeto, com credenciais da mesma conta e backend original:

```bash
terraform -chdir=infrasctructure init
terraform -chdir=infrasctructure plan -destroy -out=destroy.tfplan
terraform -chdir=infrasctructure apply destroy.tfplan
```

## Remover o EKS, se tiver sido provisionado

Antes de remover o cluster, remova eventuais Services LoadBalancer/Ingress criados manualmente e aguarde a exclusão dos balanceadores.

Exclua também as access keys do usuário indicado pelo output `github_ecr_user_name`; elas são gerenciadas fora do Terraform e impedem a exclusão desse usuário enquanto existirem.

```bash
helm uninstall argocd -n argocd
terraform -chdir=infrasctructure/eks init -backend-config=backend.hcl
terraform -chdir=infrasctructure/eks plan -destroy -out=destroy.tfplan
terraform -chdir=infrasctructure/eks apply destroy.tfplan
```

Revise cada plano. Remova ou exporte os dados necessários antes: os RDS deste cenário usam `skip_final_snapshot = true`.

Se o destroy do ECR falhar por repositórios com imagens, remova as imagens após confirmar que não precisará delas e repita o destroy.

Confira no console AWS se restaram EKS, EC2, RDS, ElastiCache, NAT Gateways, IPs elásticos, volumes e balanceadores. O bucket de estado foi criado separadamente e não é removido por esses stacks.
