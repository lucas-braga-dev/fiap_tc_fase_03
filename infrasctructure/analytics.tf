resource "aws_dynamodb_table" "analytics" {
  name         = "ToggleMasterAnalytics-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "event_id"

  attribute {
    name = "event_id"
    type = "S"
  }

  tags = { Environment = var.environment }
}
