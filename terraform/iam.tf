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
# Discord Bot Lambda Role
# --------------------------------------------------------------------------------

resource "aws_iam_role" "discord_bot_role" {
  name = "minecraft_discord_bot_role"

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
resource "aws_iam_role_policy_attachment" "discord_bot_basic" {
  role       = aws_iam_role.discord_bot_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Discord Bot用ポリシー: EC2 Start/Stop/Describe
resource "aws_iam_policy" "discord_bot_policy" {
  name        = "minecraft_discord_bot_policy"
  description = "Allow Discord Bot Lambda to start/stop EC2"

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
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "discord_bot_custom" {
  role       = aws_iam_role.discord_bot_role.name
  policy_arn = aws_iam_policy.discord_bot_policy.arn
}


# --------------------------------------------------------------------------------
# Monitor Lambda Role
# --------------------------------------------------------------------------------

resource "aws_iam_role" "monitor_role" {
  name = "minecraft_monitor_role"

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
resource "aws_iam_role_policy_attachment" "monitor_basic" {
  role       = aws_iam_role.monitor_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Monitor用ポリシー: EC2 Stop/Describe, SSM Get/Put (Startは含まない)
resource "aws_iam_policy" "monitor_policy" {
  name        = "minecraft_monitor_policy"
  description = "Allow Monitor Lambda to stop EC2 and manage SSM Parameters"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:StopInstances",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus"
        ]
        Resource = "*"
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

resource "aws_iam_role_policy_attachment" "monitor_custom" {
  role       = aws_iam_role.monitor_role.name
  policy_arn = aws_iam_policy.monitor_policy.arn
}
