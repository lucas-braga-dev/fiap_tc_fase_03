resource "aws_sqs_queue" "evaluation_events_dlq" {
  name                      = "togglemaster-events-dlq-${var.environment}"
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true

  tags = { Environment = var.environment }
}

resource "aws_sqs_queue" "evaluation_events" {
  # Standard: o produtor nao envia os campos exigidos por uma fila FIFO.
  name                       = "togglemaster-events-${var.environment}"
  visibility_timeout_seconds = 120
  message_retention_seconds  = 345600
  receive_wait_time_seconds  = 20
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.evaluation_events_dlq.arn
    maxReceiveCount     = 5
  })

  tags = { Environment = var.environment }
}

resource "aws_sqs_queue_redrive_allow_policy" "evaluation_events_dlq" {
  queue_url = aws_sqs_queue.evaluation_events_dlq.id
  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.evaluation_events.arn]
  })
}
