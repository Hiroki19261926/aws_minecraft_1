output "ec2_instance_id" {
  description = "MinecraftサーバーのインスタンスID"
  value       = aws_instance.minecraft.id
}

output "api_gateway_url" {
  description = "Discord Webhook用エンドポイントURL"
  value       = aws_apigatewayv2_api.discord_bot.api_endpoint
}

output "minecraft_server_ip" {
  description = "MinecraftサーバーのパブリックIP"
  value       = aws_instance.minecraft.public_ip
}
