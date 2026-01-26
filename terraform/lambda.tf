# lambda.tf

# 共通のIAMロールなどを参照するために iam.tf が必要ですが、ここでアーカイブ作成とLambda定義を行います。

# --------------------------------------------------------------------------------
# Discord Bot Lambda
# --------------------------------------------------------------------------------

data "archive_file" "discord_bot_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/discord_bot"
  output_path = "${path.module}/discord_bot.zip"
  excludes    = ["__pycache__", "*.pyc"]
}

# 依存ライブラリはCI/CD (GitHub Actions) 側で `pip install -t ...` を実行して
# Lambdaディレクトリ内にインストールされる前提です。
# data "archive_file" はインストール後のディレクトリをzip化します。

resource "aws_lambda_function" "discord_bot" {
  filename         = data.archive_file.discord_bot_zip.output_path
  function_name    = "minecraft_discord_bot"
  role             = aws_iam_role.discord_bot_role.arn
  handler          = "index.handler"
  source_code_hash = data.archive_file.discord_bot_zip.output_base64sha256
  runtime          = "python3.12"
  timeout          = 10

  environment {
    variables = {
      INSTANCE_ID        = aws_instance.minecraft.id
      DISCORD_PUBLIC_KEY = var.discord_public_key
      # ADMIN_ID など必要なら
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.discord_bot_log
  ]
}

resource "aws_cloudwatch_log_group" "discord_bot_log" {
  name              = "/aws/lambda/minecraft_discord_bot"
  retention_in_days = 14
}


# --------------------------------------------------------------------------------
# Monitor Lambda
# --------------------------------------------------------------------------------

data "archive_file" "monitor_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/monitor"
  output_path = "${path.module}/monitor.zip"
  excludes    = ["__pycache__", "*.pyc"]
}

resource "aws_lambda_function" "monitor" {
  filename         = data.archive_file.monitor_zip.output_path
  function_name    = "minecraft_monitor"
  role             = aws_iam_role.monitor_role.arn
  handler          = "index.handler"
  source_code_hash = data.archive_file.monitor_zip.output_base64sha256
  runtime          = "python3.12"
  timeout          = 30

  # VPC Config removed to save cost (NAT Gateway required for internet/AWS API access if in VPC)
  # Monitor Lambda will connect to RCON via Public IP.

  environment {
    variables = {
      INSTANCE_ID = aws_instance.minecraft.id
      # RCON_HOST is dynamic (Public IP), will be fetched in Lambda using boto3 describe_instances
      RCON_PORT     = var.rcon_port
      RCON_PASSWORD = var.rcon_password
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.monitor_log
  ]
}

resource "aws_cloudwatch_log_group" "monitor_log" {
  name              = "/aws/lambda/minecraft_monitor"
  retention_in_days = 14
}
