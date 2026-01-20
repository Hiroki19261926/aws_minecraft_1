# iam.tf

# --------------------------------------------------------------------------------
# EC2 Instance Role
# --------------------------------------------------------------------------------

resource "aws_iam_role" "ec2_role" {
  name = "minecraft_ec2_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# SSM Agent用のポリシーアタッチ (Session Manager等用)
resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "minecraft_ec2_profile"
  role = aws_iam_role.ec2_role.name
}


# --------------------------------------------------------------------------------
# Lambda Role (Shared for Bot and Monitor)
# --------------------------------------------------------------------------------

resource "aws_iam_role" "lambda_role" {
  name = "minecraft_lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# 基本的なLambda実行権限 (Logs)
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# VPCアクセス権限 (Monitor Lambda用)
resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# カスタムポリシー: EC2操作、SSM Parameter Store操作
resource "aws_iam_policy" "lambda_custom_policy" {
  name        = "minecraft_lambda_custom_policy"
  description = "Allow Lambda to manage EC2 and SSM Parameters"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:StartInstances",
          "ec2:StopInstances",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus"
        ]
        Resource = "*" # 特定のインスタンスに絞るのがベストだが、サイクル回避のため一旦*
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:PutParameter"
        ]
        Resource = "arn:aws:ssm:*:*:parameter/minecraft/player_zero_count"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_custom" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_custom_policy.arn
}
