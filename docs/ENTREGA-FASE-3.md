# Relatório de entrega — Tech Challenge Fase 3

Preencha os campos e inclua o print da estimativa antes de exportar para **PDF ou TXT**, conforme o [enunciado](<POSTECH - Tech Challenge - Fase 3.pdf>), páginas 5–6. Este Markdown é a fonte do relatório, não substitui o arquivo final exigido.

## Participantes e links

| Campo | Preencher |
| --- | --- |
| Participantes | Nomes completos de todos os integrantes |
| Código-fonte | URL do repositório e revisão entregue |
| Documentação | URL acessível do README/documentação publicada |
| Vídeo | URL do vídeo de até 20 minutos |
| Pipeline bloqueado | URL da execução e commit com a alteração que falhou no gate de segurança |
| Pipeline corrigido | URL da execução aprovada e commit da correção |
| GitOps | URL do commit do bot e evidência da revisão sincronizada pelo ArgoCD |

## Solução

ToggleMaster com cinco microsserviços: Auth, Flags, Targeting, Evaluation e Analytics. Terraform provisiona rede, EKS/Node Groups, três RDS PostgreSQL, ElastiCache Redis, SQS, DynamoDB, cinco ECR e IAM, com estado remoto S3. O CI valida os cinco serviços, executa testes, lint, SAST, SCA e scan das imagens. Após aprovação, publica no ECR com SHA e atualiza os manifestos GitOps. O ArgoCD reconcilia o EKS automaticamente.

## Desafios e decisões

| Desafio | Decisão e consequência |
| --- | --- |
| Restrição de providers OIDC pela SCP da conta | EKS Pod Identity para workloads; usuário IAM exclusivo e restrito para publicação ECR. A access key do CI exige rotação. |
| Limites do plano gratuito | Tipo x86_64 elegível confirmado na região e backup RDS de um dia; consumo continua sujeito aos créditos e custos AWS. |
| Acesso ao endpoint EKS | CIDR restrito ao IP público de administração, atualizado via Terraform quando necessário. |
| Credenciais dos bancos | Senha master gerenciada pelo RDS/Secrets Manager e bootstrap sem senhas no Git; credenciais da aplicação em Secret Kubernetes. |
| CVEs na base dos três containers Python | Migração Bookworm → Trixie e atualização Debian, mantendo o gate CRITICAL ativo. Anexar diffs e execuções bloqueada/aprovada. |
| Rastreabilidade da implantação | Tags SHA no ECR e atualização em Git antes do sync automático pelo ArgoCD. |

Complete com os resultados observados e eventuais limitações da entrega. Não declare resultados sem evidências. A [operação](OPERACAO.md) documenta rotação, rollback e encerramento; o [roteiro](ROTEIRO-APRESENTACAO.md) organiza a demonstração.

## Estimativa de custos AWS

Insira o print da estimativa com região, quantidades e hipóteses de uso. Considere EKS, nós EC2, três RDS, Redis, NAT, armazenamento, logs e tráfego. Informe a data e o valor estimado; diferencie estimativa, créditos e gasto real. Em TXT, acompanhe o arquivo com a imagem da estimativa; em PDF, inclua-a no próprio relatório. Não use dados de contas ou arquiteturas anteriores.

## Checklist final

- [ ] Nomes, revisão do código, documentação e vídeo preenchidos e acessíveis ao avaliador.
- [ ] Vídeo com duração de até 20 minutos, conforme o roteiro.
- [ ] Terraform plan/apply ou resultado final na AWS, incluindo rede, EKS e bancos.
- [ ] Backend remoto S3 demonstrado.
- [ ] Alteração que falha no gate de segurança, correção e execução aprovada identificadas.
- [ ] Cinco imagens publicadas com SHA e tags atualizadas pelo CI no GitOps.
- [ ] ArgoCD detectando a nova revisão e sincronizando automaticamente os cinco serviços.
- [ ] Avaliação e evento DynamoDB correlacionados como evidência funcional.
- [ ] Print da estimativa de custos inserido e hipóteses descritas.
- [ ] Relatório exportado em PDF/TXT, sem chaves, senhas ou conteúdo de estados/Secrets.
