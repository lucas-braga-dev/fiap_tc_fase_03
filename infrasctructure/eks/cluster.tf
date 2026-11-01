resource "aws_eks_cluster" "main" {
  name     = local.name
  role_arn = local.cluster_role
  version  = var.kubernetes_version
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }
  vpc_config {
    subnet_ids              = module.network.private_subnets
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = var.admin_cidrs
  }
  enabled_cluster_log_types = ["api", "audit", "authenticator"]
  depends_on                = [aws_iam_role_policy_attachment.cluster]
}
resource "aws_launch_template" "nodes" {
  name_prefix = "${local.name}-"
  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }
}
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${local.name}-workers"
  node_role_arn   = local.node_role
  subnet_ids      = module.network.private_subnets
  instance_types  = var.node_instance_types
  capacity_type   = "ON_DEMAND"
  scaling_config {
    desired_size = 2
    min_size     = 2
    max_size     = 4
  }
  launch_template {
    id      = aws_launch_template.nodes.id
    version = aws_launch_template.nodes.latest_version
  }
  update_config { max_unavailable = 1 }
  depends_on = [aws_iam_role_policy_attachment.nodes]
}
