# Analytics

Consumidor Python/Flask que lê avaliações do SQS, grava itens no DynamoDB e exclui a mensagem após persistência. Porta padrão: `8005`; `GET /health` verifica a saúde HTTP, não o processamento fim a fim.

Configuração: `AWS_REGION`, `AWS_SQS_URL`, `AWS_DYNAMODB_TABLE` e `PORT`. `AWS_ENDPOINT_URL` é exclusivo do LocalStack. Credenciais AWS vêm de Pod Identity no EKS.

Eventos contêm `user_id`, `flag_name`, `result` e `timestamp`; o consumidor gera `event_id`. Para diagnosticar persistência, correlacione o evento da avaliação com os logs e o item na tabela; a fila pode estar vazia porque a mensagem já foi processada.

## Executar e validar

Para infraestrutura e credenciais de produção, siga [deploy EKS](../../../deploy/README.md). Para simulação, use o [Compose](../../../docker-compose.yaml) e [desenvolvimento local](../../../docs/OPERACAO.md#desenvolvimento-local). Não grave credenciais reais nos exemplos.

Dentro desta pasta, usando Python 3.11, execute:

```powershell
python -m pip install -r requirements.txt
python -m unittest discover -s . -p 'test_*.py'
```
