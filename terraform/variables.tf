variable "aws_region" {
  description = "AWSリージョン"
  type        = string
  default     = "ap-northeast-1"
}

variable "instance_type" {
  description = "EC2インスタンスタイプ"
  type        = string
  default     = "t4g.medium"
}

variable "volume_size" {
  description = "EBSボリュームサイズ(GB)"
  type        = number
  default     = 30
}

variable "key_name" {
  description = "EC2キーペア名"
  type        = string
  default     = "minecraft-key"
}

variable "discord_app_id" {
  description = "Discord Application ID (Secret経由)"
  type        = string
  sensitive   = true
}

variable "discord_public_key" {
  description = "Discord Public Key (Secret経由)"
  type        = string
  sensitive   = true
}

variable "admin_ip" {
  description = "SSH接続を許可する管理者IPアドレス (CIDR形式)"
  type        = string
  default     = null
}

variable "rcon_password" {
  description = "RCON認証パスワード (Secret経由)"
  type        = string
  sensitive   = true
}

variable "minecraft_port" {
  description = "Minecraftポート"
  type        = number
  default     = 25565
}

variable "rcon_port" {
  description = "RCONポート"
  type        = number
  default     = 57000
}
