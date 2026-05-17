####################################################################
# Inventory data table
# pk  = "service#accountId#region"
# sk  = resourceId
####################################################################
resource "aws_dynamodb_table" "inventory" {
  name         = "${local.name_prefix}-inventory-data"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"
  range_key    = "sk"

  attribute {
    name = "pk"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"
}

####################################################################
# Metadata table – tracks last-refresh timestamps per service/account
# pk  = service
# sk  = accountId#region
####################################################################
resource "aws_dynamodb_table" "metadata" {
  name         = "${local.name_prefix}-inventory-metadata"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "service"
  range_key    = "accountRegion"

  attribute {
    name = "service"
    type = "S"
  }

  attribute {
    name = "accountRegion"
    type = "S"
  }

  attribute {
    name = "accountId"
    type = "S"
  }

  attribute {
    name = "region"
    type = "S"
  }

  global_secondary_index {
    name            = "accountId-index"
    hash_key        = "accountId"
    range_key       = "region"
    projection_type = "ALL"
  }
}
