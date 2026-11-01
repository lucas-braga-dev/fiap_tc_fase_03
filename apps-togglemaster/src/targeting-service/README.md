# Targeting

Serviço Python/Flask de regras de segmentação por flag. Porta padrão: `8003`; PostgreSQL com schema em `db/init.sql`.

| Endpoint | Uso |
| --- | --- |
| `GET /health` | Saúde HTTP |
| `POST /rules` | Cria regra com `flag_name`, `is_enabled` e `rules` |
| `GET /rules/<flag_name>` | Consulta regra |
| `PUT /rules/<flag_name>` | Atualiza regra |
| `DELETE /rules/<flag_name>` | Exclui regra |

Exceto health, os endpoints exigem chave validada pelo Auth no header Authorization. A regra percentual usa `rules: { "type": "PERCENTAGE", "value": 100 }`. Configuração: `DATABASE_URL`, `AUTH_SERVICE_URL` e `PORT`.

## Executar e validar

Para infraestrutura e credenciais de produção, siga [deploy EKS](../../../deploy/README.md). Para simulação, use o [Compose](../../../docker-compose.yaml) e [desenvolvimento local](../../../docs/OPERACAO.md#desenvolvimento-local). Não grave credenciais reais nos exemplos.

Dentro desta pasta, usando Python 3.11, execute:

```powershell
python -m pip install -r requirements.txt
python -m unittest discover -s . -p 'test_*.py'
```
