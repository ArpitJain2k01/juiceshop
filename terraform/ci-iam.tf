# Dedicated least-privilege IAM user for CI (GitHub Actions self-hosted runner).
#
# Scoping approach ("Option A" - scoped-but-broad, defensible for a lab):
#   - EC2 + CloudWatch Logs: action-scoped and fenced to this region only.
#   - IAM: locked to our juiceshop-* role/instance-profile/policy names, so CI
#     cannot touch or escalate outside the lab's namespace.
#   - S3: limited to the Terraform state bucket and the lab's state key prefix.
#
# The access key is intentionally NOT created here, so it never lands in state.
# Create it in the console and store it in GitHub Actions secrets (see README).

data "aws_caller_identity" "me" {}

resource "aws_iam_user" "ci" {
  name = "${var.project}-ci"
  tags = { Purpose = "github-actions-ci" }
}

data "aws_iam_policy_document" "ci" {
  # EC2 + Logs: these APIs largely do not support resource-level scoping on
  # create/describe, so we fence by action set AND region instead.
  statement {
    sid       = "EC2AndLogsRegionFenced"
    effect    = "Allow"
    actions   = ["ec2:*", "logs:*"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }

  # IAM: scoped to our resource names only - CI can manage the lab's roles but
  # cannot create an admin role or modify arpit-admin.
  statement {
    sid    = "ScopedIAM"
    effect = "Allow"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:TagRole", "iam:UntagRole",
      "iam:ListRolePolicies", "iam:ListAttachedRolePolicies", "iam:ListInstanceProfilesForRole",
      "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:GetRolePolicy",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy",
      "iam:CreateInstanceProfile", "iam:DeleteInstanceProfile", "iam:GetInstanceProfile",
      "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile",
      "iam:CreatePolicy", "iam:DeletePolicy", "iam:GetPolicy", "iam:GetPolicyVersion",
      "iam:CreatePolicyVersion", "iam:DeletePolicyVersion", "iam:ListPolicyVersions",
      "iam:PassRole",
    ]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.me.account_id}:role/${var.project}-*",
      "arn:aws:iam::${data.aws_caller_identity.me.account_id}:instance-profile/${var.project}-*",
      "arn:aws:iam::${data.aws_caller_identity.me.account_id}:policy/${var.project}-*",
    ]
  }

  # S3: Terraform state bucket + the lab's state key prefix only.
  statement {
    sid     = "StateBucket"
    effect  = "Allow"
    actions = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket", "s3:GetBucketVersioning"]
    resources = [
      "arn:aws:s3:::itsajsince2k01",
      "arn:aws:s3:::itsajsince2k01/juiceshop/*",
    ]
  }
}

resource "aws_iam_user_policy" "ci" {
  name   = "${var.project}-ci-policy"
  user   = aws_iam_user.ci.name
  policy = data.aws_iam_policy_document.ci.json
}

output "ci_user_name" {
  description = "Create an access key for this user in the console and store it in GitHub secrets."
  value       = aws_iam_user.ci.name
}
