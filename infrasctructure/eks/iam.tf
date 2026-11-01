resource "aws_iam_role" "cluster" {
  count = 1
  name  = "${local.name}-cluster"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "eks.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}
resource "aws_iam_role_policy_attachment" "cluster" {
  count      = 1
  role       = aws_iam_role.cluster[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}
resource "aws_iam_role" "nodes" {
  count = 1
  name  = "${local.name}-nodes"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}
resource "aws_iam_role_policy_attachment" "nodes" {
  for_each   = toset(["AmazonEKSWorkerNodePolicy", "AmazonEKS_CNI_Policy", "AmazonEC2ContainerRegistryReadOnly"])
  role       = aws_iam_role.nodes[0].name
  policy_arn = "arn:aws:iam::aws:policy/${each.key}"
}
resource "aws_iam_role" "workload" {
  for_each = toset(["evaluation-service", "analytics-service"])
  name     = "${local.name}-${each.key}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Condition = {
        StringEquals = {
          "aws:RequestTag/eks-cluster-arn"            = aws_eks_cluster.main.arn
          "aws:RequestTag/kubernetes-namespace"       = "togglemaster"
          "aws:RequestTag/kubernetes-service-account" = each.key
        }
      }
    }]
  })
}
resource "aws_iam_role_policy" "workload" {
  for_each = aws_iam_role.workload
  role     = each.value.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([{
      Effect   = "Allow"
      Action   = each.key == "evaluation-service" ? ["sqs:SendMessage"] : ["sqs:ReceiveMessage", "sqs:DeleteMessage"]
      Resource = aws_sqs_queue.events.arn
      }], each.key == "analytics-service" ? [{
      Effect = "Allow", Action = ["dynamodb:PutItem"], Resource = aws_dynamodb_table.analytics.arn
    }] : [])
  })
}
resource "aws_iam_user" "publisher" {
  name = "${local.name}-github-ecr"
}
resource "aws_iam_user_policy" "publisher" {
  name = "publish-togglemaster-images"
  user = aws_iam_user.publisher.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*" },
      {
        Effect   = "Allow"
        Action   = ["ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload", "ecr:PutImage"]
        Resource = [for repo in aws_ecr_repository.service : repo.arn]
      }
    ]
  })
}

resource "aws_eks_addon" "pod_identity" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "eks-pod-identity-agent"
  depends_on   = [aws_eks_node_group.main]
}
resource "aws_eks_pod_identity_association" "workload" {
  for_each        = aws_iam_role.workload
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "togglemaster"
  service_account = each.key
  role_arn        = each.value.arn
  depends_on      = [aws_eks_addon.pod_identity, aws_iam_role_policy.workload]
}
