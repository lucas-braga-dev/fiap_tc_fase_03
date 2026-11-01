# Checklist de entrega — Fase 3

## Participantes

- Nome:
- Nome:

## Links

- Código:
- Documentação:
- Vídeo de até 20 minutos:

## Evidências a produzir

- [ ] Terraform plan/apply e recursos AWS.
- [ ] EKS e Node Groups.
- [ ] Três instâncias RDS, ElastiCache, SQS, DynamoDB e cinco ECR.
- [ ] Backend remoto S3.
- [ ] CI dos cinco serviços em PR/main: testes, lint, SAST, SCA e scan de imagens.
- [ ] Pipeline bloqueando uma falha de segurança e passando após correção.
- [ ] CI atualizando as cinco tags na pasta GitOps.
- [ ] ArgoCD mostrando os cinco microsserviços e sincronizando uma alteração.
- [ ] Avaliação retornando resultado e evento persistido no DynamoDB.
- [ ] Print da estimativa de custos AWS.

## Demonstração de segurança

1. Crie uma branch temporária para demonstrar uma falha SAST ou dependência vulnerável.
2. Abra PR e mostre a falha no job de segurança.
3. Corrija na mesma branch e mostre os jobs aprovados.
4. Não faça merge da versão vulnerável nem desabilite os scanners.

## Desafios e decisões

- Migração da EC2/Compose para EKS/GitOps:
- Conta pessoal AWS com EKS Pod Identity e usuário IAM exclusivo de publicação no ECR:
- Separação de estados e preservação do ambiente anterior:
- Gestão de credenciais:
- Validação de destinos HTTP internos, bloqueio de redirects e testes contra SSRF:
- Estimativa de custos e encerramento dos recursos:

Exporte este documento preenchido para PDF ou TXT. Não entregue o checklist vazio.
