# Auth

Serviço Go de emissão e validação de chaves de API. Porta padrão: `8001`; persistência PostgreSQL, schema em `db/init.sql`.

| Endpoint | Uso |
| --- | --- |
| `GET /health` | Saúde HTTP |
| `POST /admin/keys` | Emite chave; requer `Authorization: Bearer <MASTER_KEY>` e JSON com `name` |
| `GET /validate` | Valida a chave enviada no header Authorization |

Configuração: `DATABASE_URL`, `MASTER_KEY` e `PORT`. A master não deve ser usada como chave dos clientes. Para emitir a chave de Evaluation no EKS, use o script do guia de deploy.

## Executar e validar

Para infraestrutura e credenciais de produção, siga [deploy EKS](../../../deploy/README.md). Para simulação, use o [Compose](../../../docker-compose.yaml) e [desenvolvimento local](../../../docs/OPERACAO.md#desenvolvimento-local). Não grave credenciais reais nos exemplos.

Dentro desta pasta, usando a versão Go declarada em `go.mod`, execute:

```powershell
go build ./...
go test -race ./...
go vet ./...
```
