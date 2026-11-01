# Evaluation

Serviço Go de avaliação de flags. Porta padrão: `8004`. Consulta Flags/Targeting autenticado, usa Redis como cache e publica eventos no SQS.

| Endpoint | Uso |
| --- | --- |
| `GET /health` | Saúde HTTP |
| `GET /evaluate?user_id=<id>&flag_name=<flag>` | Retorna a decisão e publica evento |

Configuração: `REDIS_URL`, `FLAG_SERVICE_URL`, `TARGETING_SERVICE_URL`, `SERVICE_API_KEY`, `AWS_REGION`, `AWS_SQS_URL` e `PORT`. `AWS_ENDPOINT_URL` é exclusivo da simulação local; não configure no EKS. Credenciais AWS vêm de Pod Identity no EKS.

## Controles de segurança

`internal_http.go` limita host/porta dos serviços de destino e valida o nome da flag; o cliente HTTP bloqueia redirects para impedir encaminhamento da chave a outros destinos. As exceções pontuais `#nosec G704` dependem desses controles e são cobertas por `internal_http_test.go`. Ao alterar endpoints ou validação, revise as exceções e os testes antes de publicar.

## Executar e validar

Para infraestrutura e credenciais de produção, siga [deploy EKS](../../../deploy/README.md). Para simulação, use o [Compose](../../../docker-compose.yaml) e [desenvolvimento local](../../../docs/OPERACAO.md#desenvolvimento-local). Não grave credenciais reais nos exemplos.

Dentro desta pasta, usando a versão Go declarada em `go.mod`, execute:

```powershell
go build ./...
go test -race ./...
go vet ./...
```
