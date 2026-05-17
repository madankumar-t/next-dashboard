output "inventory_read_role_arn" {
  description = "ARN of the InventoryReadRole created in this member account"
  value       = aws_iam_role.inventory_read.arn
}

output "inventory_read_role_name" {
  description = "Name of the InventoryReadRole created in this member account"
  value       = aws_iam_role.inventory_read.name
}
