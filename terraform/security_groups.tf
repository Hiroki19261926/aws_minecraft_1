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

  # RCON Port
  # SECURITY WARNING: This port is open to the world (0.0.0.0/0) to allow
  # the Monitor Lambda (running outside VPC to save costs) to connect.
  # A strong RCON password is REQUIRED to prevent unauthorized access.
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

  # Outbound to Internet (AWS API)
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
