# ec2.tf

# 最新のAmazon Linux 2023 (ARM64) のAMIを取得
data "aws_ami" "al2023_arm64" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-arm64"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }
}

# EC2インスタンス
resource "aws_instance" "minecraft" {
  ami           = data.aws_ami.al2023_arm64.id
  instance_type = var.instance_type
  key_name      = var.key_name

  subnet_id                   = data.aws_subnet.default.id
  vpc_security_group_ids      = [aws_security_group.minecraft_sg.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name

  root_block_device {
    volume_size = var.volume_size
    volume_type = "gp3"
    tags = {
      Name = "Minecraft-Server-Root"
    }
  }

  # User Data スクリプト
  user_data = templatefile("${path.module}/../scripts/user_data.sh", {
    rcon_password = var.rcon_password
  })

  # インスタンス停止保護 (誤操作防止のため有効化推奨だが、自動停止スクリプトがあるためfalseにするか、スクリプト側でForceStopするか)
  # 自動停止スクリプトは StopInstances を呼ぶので disable_api_stop は false (デフォルト) でOK
  disable_api_stop = false

  tags = {
    Name = "Minecraft-Server"
  }

  # 初期状態は停止にしておくことはできない（TerraformはDesire Stateを作るため、Apply直後は起動する）
  # コスト削減のため、User Data処理完了後に停止するなどの工夫も可能だが、
  # ここでは単純に作成＝起動とする。
}

# デフォルトVPCとサブネットの取得
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# とりあえず最初のサブネットを選択
data "aws_subnet" "default" {
  id = data.aws_subnets.default.ids[0]
}
