# ssm.tf

resource "aws_ssm_parameter" "player_zero_count" {
  name        = "/minecraft/player_zero_count"
  description = "Count of consecutive checks with 0 players"
  type        = "String"
  value       = "0"
  overwrite   = false

  lifecycle {
    ignore_changes = [value]
  }
}
