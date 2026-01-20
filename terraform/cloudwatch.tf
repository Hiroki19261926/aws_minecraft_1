# cloudwatch.tf

resource "aws_cloudwatch_event_rule" "monitor_schedule" {
  name                = "minecraft_monitor_schedule"
  description         = "Trigger Monitor Lambda every 5 minutes"
  schedule_expression = "rate(5 minutes)"
}

resource "aws_cloudwatch_event_target" "monitor_target" {
  rule      = aws_cloudwatch_event_rule.monitor_schedule.name
  target_id = "MonitorLambda"
  arn       = aws_lambda_function.monitor.arn
}

resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.monitor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.monitor_schedule.arn
}
