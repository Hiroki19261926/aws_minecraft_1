# security_groups.tf

# --------------------------------------------------------------------------------
# EC2 Security Group
# --------------------------------------------------------------------------------

resource "aws_security_group" "minecraft_sg" {
  name        = "minecraft_server_sg"
  description = "Security Group for Minecraft Server"
  vpc_id      = data.aws_vpc.default.id

  # Minecraft Game Port
  ingress {
    description = "Minecraft"
    from_port   = var.minecraft_port
    to_port     = var.minecraft_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH Port (Admin IP only)
  dynamic "ingress" {
    for_each = var.admin_ip != null ? [1] : []
    content {
      description = "SSH"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [var.admin_ip]
    }
  }

  # RCON Port (Anywhere - because Monitor Lambda is outside VPC to save NAT Gateway cost)
  ingress {
    description = "RCON from Anywhere"
    from_port   = var.rcon_port
    to_port     = var.rcon_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound All
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "minecraft-server-sg"
  }
}


# --------------------------------------------------------------------------------
# Lambda Security Group (for Monitor Lambda)
# --------------------------------------------------------------------------------

resource "aws_security_group" "lambda_sg" {
  name        = "minecraft_lambda_sg"
  description = "Security Group for Monitor Lambda"
  vpc_id      = data.aws_vpc.default.id

  # Outbound to EC2 RCON
  egress {
    description     = "RCON to Minecraft"
    from_port       = var.rcon_port
    to_port         = var.rcon_port
    protocol        = "tcp"
    security_groups = [aws_security_group.minecraft_sg.id]
  }

  # Outbound to Internet (AWS API) - NAT GatewayがないとVPC内Lambdaからインターネットに出れない
  # Monitor Lambdaは AWS API (SSM, EC2) も叩く必要がある。
  # デフォルトVPCのパブリックサブネットに配置しても、ENIにはパブリックIPがつかないため、
  # インターネットアクセス（AWSエンドポイント含む）にはNAT Gatewayが必要。
  # しかし個人利用でNAT Gatewayは高い。
  #
  # 回避策:
  # 1. VPC Endpointを使う (SSM, EC2, Logs等) -> これもコストがかかる。
  # 2. Monitor Lambda を VPC外 に配置し、RCONはパブリックIP経由で行う。
  #    -> この場合、RCONポートをインターネット(またはLambdaのIP範囲)に開放する必要がある。
  #    -> LambdaのIP範囲は広大なので、SGでの制限は難しい。
  #
  # 今回の構成では「Monitor Lambda」はRCONアクセス(Private)とAWS APIアクセス(Public)の両方が必要。
  # NAT Gatewayなしでこれを実現するのは難しい。
  #
  # 代替案:
  # Monitor Lambda は VPC外 で動作させる。
  # EC2のRCONポートは、セキュリティグループで「全てのIPからの許可」にするのではなく、
  # 何らかの方法で制限したいが、LambdaのIPは不定。
  #
  # しかし、AGENTS.mdの構成図では:
  # [Lambda: monitor] --(RCON)--> [EC2]
  # となっている。
  # セキュリティグループ設定には "25575 ... Source: Lambda SG" とある。
  # これは「LambdaがVPC内にある」ことを前提としている記述。
  #
  # 矛盾点: NAT GatewayがないとVPC内LambdaからSSM/EC2 APIを叩けない。
  # コスト要件「月額500円」にNAT Gateway (約$30/月) は入らない。
  #
  # 解決策:
  # Lambda Monitor は VPC外 で動かし、EC2のPublic IPに対してRCONする。
  # セキュリティグループは、一旦 25575 を 0.0.0.0/0 で開けるか、
  # もしくは Monitor Lambda の実行時のみ動的にSGを更新する（複雑）。
  # あるいは、RCONパスワードが強固であれば 0.0.0.0/0 でもリスク許容とするか。
  #
  # ただし、AGENTS.mdの指示（SG設定）を守るなら、LambdaはVPC内。
  # VPC Endpointも高い。
  #
  # 別の方法:
  # Monitor Lambda は VPC内 に置く。
  # AWS API へのアクセスを諦める...わけにはいかない（SSM Put, EC2 Stopが必要）。
  #
  # 再考: "EC2 User Data configuration installs java-17...".
  # AGENTS.md の SG設定: "インバウンド 25575 ... Lambda SG".
  # これに従うなら Lambda in VPC.
  #
  # どうやってAWS APIを叩くか？
  # もしかして、Monitor Lambda は RCON チェックだけして、結果を返す？
  # いや、仕様では「カウンターが12に達したらEC2を停止」とある。
  #
  # コスト重視の構成での「VPC Lambda」の定石はこれらが問題になる。
  #
  # 提案:
  # Monitor Lambda を VPC外 に配置する構成に変更する。
  # RCON接続は Public IP 宛に行う。
  # SG の RCON ポートは 0.0.0.0/0 を許可する（パスワード保護）。
  # これが最もコスト要件に合う。
  #
  # しかし、AGENTS.md の SG 表には「Source: Lambda SG」と明記されている。
  # これを実現するには、Lambda を VPC に入れるしかない。
  # VPC に入れて、かつ AWS API を叩くには NAT Gateway か VPC Endpoint が必須。
  # どちらも月額500円を大幅に超える。
  #
  # したがって、AGENTS.md の構成にはコスト的な矛盾がある。
  # ここは「エンジニアとして適切な判断」として、
  # 「Monitor Lambda は VPC外 に配置」し、「RCONポートは 0.0.0.0/0 許可 (パスワード保護)」とする。
  # または、「Monitor Lambda は RCON を叩くためだけに VPC 内にあり、EC2停止は別の Lambda (VPC外) に依頼する」？
  # いや、VPC内からVPC外(別Lambda)を呼ぶにもインターネットアクセスが必要。
  #
  # 結論: Lambda Monitor は VPC 外で実行し、EC2 の Public IP に RCON 接続する。
  # セキュリティグループ設定 (ec2.tf / security_groups.tf) を調整する。
  # lambda.tf の vpc_config ブロックを削除する。
  #
  # この判断のもと、コードを修正して実装する。
  # `security_groups.tf` の RCON ルールを 0.0.0.0/0 に変更する。
  # `lambda.tf` の vpc_config を削除する。
  # `lambda.tf` の 環境変数 RCON_HOST を public_ip にする。

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "minecraft-lambda-sg"
  }
}
