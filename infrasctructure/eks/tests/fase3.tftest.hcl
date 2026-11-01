mock_provider "aws" {
  mock_resource "aws_launch_template" {
    defaults = { id = "lt-0123456789abcdef0", latest_version = 1 }
  }
  mock_resource "aws_ecr_repository" {
    defaults = { arn = "arn:aws:ecr:us-east-2:123456789012:repository/test" }
  }
  mock_data "aws_availability_zones" {
    defaults = { names = ["us-east-2a", "us-east-2b"] }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/test" }
  }
  mock_resource "aws_eks_cluster" {
    defaults = { arn = "arn:aws:eks:us-east-2:123456789012:cluster/test" }
  }
  mock_resource "aws_sqs_queue" {
    defaults = { arn = "arn:aws:sqs:us-east-2:123456789012:test" }
  }
  mock_resource "aws_db_instance" {
    defaults = {
      master_user_secret = [{ secret_arn = "arn:aws:secretsmanager:us-east-2:123456789012:secret:test", kms_key_id = "test", secret_status = "active" }]
    }
  }
}

variables {
  admin_cidrs = ["203.0.113.10/32"]
}

run "personal_account_mock_apply" {
  command = apply
  assert {
    condition = (
      aws_eks_node_group.main.instance_types == tolist(["m7i-flex.large"]) &&
      alltrue([for db in aws_db_instance.service : db.backup_retention_period == 1])
    )
    error_message = "Os defaults devem usar instancia x86 elegivel e retencao RDS de um dia."
  }
  assert {
    condition     = length(aws_db_instance.service) == 3 && length(aws_ecr_repository.service) == 5
    error_message = "A Fase 3 exige tres instancias RDS e cinco repositorios ECR."
  }
  assert {
    condition     = length(aws_iam_role.workload) == 2 && aws_iam_user.publisher.name == "togglemaster-fase3-github-ecr"
    error_message = "A conta pessoal precisa de roles de workload e publicacao restritas."
  }
  assert {
    condition = alltrue([for service, association in aws_eks_pod_identity_association.workload :
      association.namespace == "togglemaster" && association.service_account == service &&
      association.role_arn == aws_iam_role.workload[service].arn
    ]) && length(aws_eks_pod_identity_association.workload) == 2 && aws_eks_addon.pod_identity.addon_name == "eks-pod-identity-agent"
    error_message = "Evaluation e Analytics precisam de associacoes Pod Identity e do agente."
  }
  assert {
    condition = alltrue([for service, role in aws_iam_role.workload :
      jsondecode(role.assume_role_policy).Statement[0].Principal.Service == "pods.eks.amazonaws.com" &&
      contains(jsondecode(role.assume_role_policy).Statement[0].Action, "sts:TagSession") &&
      jsondecode(role.assume_role_policy).Statement[0].Condition.StringEquals["aws:RequestTag/kubernetes-service-account"] == service &&
      jsondecode(role.assume_role_policy).Statement[0].Condition.StringEquals["aws:RequestTag/kubernetes-namespace"] == "togglemaster"
    ])
    error_message = "A confianca Pod Identity deve restringir a ServiceAccount e o namespace."
  }
  assert {
    condition = (
      jsondecode(aws_iam_user_policy.publisher.policy).Statement[0].Action == ["ecr:GetAuthorizationToken"] &&
      length(jsondecode(aws_iam_user_policy.publisher.policy).Statement[1].Resource) == 5 &&
      !contains(jsondecode(aws_iam_user_policy.publisher.policy).Statement[1].Action, "ecr:DeleteRepository") &&
      alltrue([for arn in jsondecode(aws_iam_user_policy.publisher.policy).Statement[1].Resource : arn != "*"])
    )
    error_message = "O publisher deve publicar somente nos cinco ECR, sem exclusao de repositorios."
  }
}
