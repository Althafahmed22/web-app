output "ecr_repo_url" {
  value = data.aws_ecr_repository.python_app_repo.repository_url
}

