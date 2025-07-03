provider "aws" {
  region = var.region
}

# ECR Repository
resource "aws_ecr_repository" "python_app_repo" {
  name = "python-app-repo"
}

# Get default VPC and subnet
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Security Group for ECS Task
resource "aws_security_group" "ecs_sg" {
  name        = "ecs-security-group"
  description = "Allow HTTP on port 5000"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ECS Cluster
resource "aws_ecs_cluster" "python_app_cluster" {
  name = "python-app-cluster"
}

resource "data.aws_iam_role_policy_attachment" "ecs_task_policy_attach" {
  role       = data.aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
data "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}


# ECS Task Definition
resource "aws_ecs_task_definition" "python_task" {
  family                   = "python-app-task"
  requires_compatibilities = ["FARGATE"]
  network_mode            = "awsvpc"
  cpu                     = "256"
  memory                  = "512"
  execution_role_arn      = data.aws_iam_role.ecs_task_execution_role.arn
  container_definitions   = jsonencode([
    {
      name      = "python-app"
      image     = "${aws_ecr_repository.python_app_repo.repository_url}:latest"
      essential = true
      portMappings = [
        {
          containerPort = 5000
          protocol      = "tcp"
        }
      ]
    }
  ])
}

# ECS Service
resource "aws_ecs_service" "python_app_service" {
  name            = "python-app-service"
  cluster         = aws_ecs_cluster.python_app_cluster.id
  task_definition = aws_ecs_task_definition.python_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = data.aws_subnets.default.ids
    security_groups = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }

  depends_on = [aws_iam_role_policy_attachment.ecs_task_policy_attach]
}

