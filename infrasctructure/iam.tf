resource "aws_iam_role" "api_server" {
  name = "togglemaster-ec2-${var.environment}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "application_events" {
  name = "togglemaster-events-${var.environment}"
  role = aws_iam_role.api_server.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage"
        ]
        Resource = aws_sqs_queue.evaluation_events.arn
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem"]
        Resource = aws_dynamodb_table.analytics.arn
      }
    ]
  })
}

resource "aws_iam_instance_profile" "api_server" {
  name = "togglemaster-ec2-${var.environment}"
  role = aws_iam_role.api_server.name
}
