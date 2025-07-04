terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# Use existing ECS task execution role
data "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"
}

# Use existing ECR repository
data "aws_ecr_repository" "python_app_repo" {
  name = "python-app-repo"
}

# Use existing default VPC and subnets
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Use existing security group
data "aws_security_group" "ecs_sg" {
  filter {
    name   = "group-name"
    values = ["ecs-security-group"]
  }
  vpc_id = data.aws_vpc.default.id
}

# ECS Cluster
resource "aws_ecs_cluster" "python_app_cluster" {
  name = "python-app-cluster"
}

# IAM policy attachment to existing role
resource "aws_iam_role_policy_attachment" "ecs_task_policy_attach" {
  role       = data.aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECS Task Definition
resource "aws_ecs_task_definition" "python_task" {
  family                   = "python-app-task"
  requires_compatibilities = ["FARGATE"]
  network_mode            = "awsvpc"
  cpu                     = "256"
  memory                  = "512"
  execution_role_arn      = data.aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "python-app"
      image     = "${data.aws_ecr_repository.python_app_repo.repository_url}:latest"
      essential = true
      portMappings = [
        {
          containerPort = 80
          protocol      = "tcp"
        }
      ]
    }
  ])
}

# ECS Service
resource "aws_ecs_service" "python_app_service" {
  name            = "python-app-service-0"
  cluster         = aws_ecs_cluster.python_app_cluster.id
  task_definition = aws_ecs_task_definition.python_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [data.aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }

  depends_on = [aws_iam_role_policy_attachment.ecs_task_policy_attach]
lifecycle {
  create_before_destroy = true
  ignore_changes        = [desired_count]
}
}
