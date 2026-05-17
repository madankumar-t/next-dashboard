####################################################################
# EventBridge rule – scheduled inventory refresh
####################################################################
resource "aws_cloudwatch_event_rule" "refresh_schedule" {
  name                = "${local.name_prefix}-refresh-schedule"
  description         = "Triggers the inventory refresh Lambda on a schedule"
  schedule_expression = var.refresh_schedule_expression
  state               = "ENABLED"
}

resource "aws_cloudwatch_event_target" "refresh_lambda" {
  rule      = aws_cloudwatch_event_rule.refresh_schedule.name
  target_id = "RefreshLambdaTarget"
  arn       = aws_lambda_function.refresh.arn
}
