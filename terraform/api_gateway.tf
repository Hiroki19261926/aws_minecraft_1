# api_gateway.tf

resource "aws_apigatewayv2_api" "discord_bot" {
  name          = "minecraft_discord_bot_api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.discord_bot.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id           = aws_apigatewayv2_api.discord_bot.id
  integration_type = "AWS_PROXY"

  connection_type        = "INTERNET"
  description            = "Lambda Integration"
  integration_method     = "POST"
  integration_uri        = aws_lambda_function.discord_bot.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "default_route" {
  api_id    = aws_apigatewayv2_api.discord_bot.id
  route_key = "POST /"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_lambda_permission" "allow_apigateway" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.discord_bot.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.discord_bot.execution_arn}/*/*"
}
