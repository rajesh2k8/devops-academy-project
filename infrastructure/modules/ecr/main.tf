variable "repositories" { type = list(string) }

resource "aws_ecr_repository" "this" {
  for_each = toset(var.repositories)
  name     = each.key
  force_delete = true
  image_scanning_configuration { scan_on_push = true }
  encryption_configuration { encryption_type = "AES256" }
  tags = { Name = each.key }
}

output "repository_urls" {
  value = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}
