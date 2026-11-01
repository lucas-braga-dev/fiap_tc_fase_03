import importlib.util
import json
import os
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

from botocore.exceptions import ClientError


class AnalyticsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sqs = MagicMock()
        cls.dynamo = MagicMock()
        session = MagicMock()
        session.client.side_effect = lambda name, **kwargs: {"sqs": cls.sqs, "dynamodb": cls.dynamo}[name]
        with patch.dict(os.environ, {"AWS_REGION": "us-east-2", "AWS_SQS_URL": "https://example.com/queue", "AWS_DYNAMODB_TABLE": "test"}), patch("boto3.Session", return_value=session), patch("threading.Thread"):
            spec = importlib.util.spec_from_file_location("analytics_test_app", Path(__file__).with_name("app.py"))
            cls.module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(cls.module)

    def setUp(self):
        self.sqs.reset_mock()
        self.dynamo.reset_mock()
        self.dynamo.put_item.side_effect = None
        self.message = {"MessageId": "one", "ReceiptHandle": "receipt", "Body": json.dumps({
            "user_id": "user", "flag_name": "checkout", "result": True, "timestamp": "2026-10-31T00:00:00Z"
        })}

    def test_acknowledges_only_after_persisting_event(self):
        self.module.process_message(self.message)
        self.dynamo.put_item.assert_called_once()
        self.sqs.delete_message.assert_called_once()
        item = self.dynamo.put_item.call_args.kwargs["Item"]
        self.assertEqual(item["flag_name"], {"S": "checkout"})
        self.assertEqual(item["result"], {"BOOL": True})

    def test_does_not_acknowledge_failed_write(self):
        self.dynamo.put_item.side_effect = ClientError({"Error": {"Code": "AccessDeniedException", "Message": "denied"}}, "PutItem")
        self.module.process_message(self.message)
        self.sqs.delete_message.assert_not_called()

    def test_does_not_acknowledge_invalid_json(self):
        self.message["Body"] = "invalid"
        self.module.process_message(self.message)
        self.dynamo.put_item.assert_not_called()
        self.sqs.delete_message.assert_not_called()


if __name__ == "__main__":
    unittest.main()
