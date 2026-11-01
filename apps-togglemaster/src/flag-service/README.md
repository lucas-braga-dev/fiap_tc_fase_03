# Flags

Serviço Python/Flask de definições de feature flags. Porta padrão: `8002`; PostgreSQL com schema em `db/init.sql`.

| Endpoint | Uso |
| --- | --- |
| `GET /health` | Saúde HTTP |
| `POST /flags` | Cria flag com `name` e `is_enabled` |
| `GET /flags` | Lista flags |
| `GET /flags/<name>` | Consulta flag |
| `PUT /flags/<name>` | Atualiza flag |
| `DELETE /flags/<name>` | Exclui flag |

Exceto health, os endpoints exigem `Authorization: Bearer <SERVICE_API_KEY>`, validada pelo Auth. Configuração: `DATABASE_URL`, `AUTH_SERVICE_URL` e `PORT`.

## Executar e validar

Para infraestrutura e credenciais de produção, siga [deploy EKS](../../../deploy/README.md). Para simulação, use o [Compose](../../../docker-compose.yaml) e [desenvolvimento local](../../../docs/OPERACAO.md#desenvolvimento-local). Não grave credenciais reais nos exemplos.

Dentro desta pasta, usando Python 3.11, execute:

```powershell
python -m pip install -r requirements.txt
python -m unittest discover -s . -p 'test_*.py'
```
