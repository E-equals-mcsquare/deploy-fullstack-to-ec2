module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.19.0"

  name = "fullstack-ec2-tutorial-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = true

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}

module "frontend_server_sg" {
  source = "terraform-aws-modules/security-group/aws//modules/http-80"

  name        = "frontend-server"
  description = "Security group for web-server with HTTP ports open within VPC"
  vpc_id      = module.vpc.vpc_id

  ingress_cidr_blocks = ["10.10.0.0/16"]
}

module "backend_service_sg" {
  source = "terraform-aws-modules/security-group/aws"

  name        = "backend-service"
  description = "Security group for backend-service with custom ports open within VPC, and PostgreSQL publicly open"
  vpc_id      = module.vpc.vpc_id

  ingress_cidr_blocks = ["10.10.0.0/16"]
  ingress_rules       = ["https-443-tcp"]
  ingress_with_cidr_blocks = [
    {
      from_port   = 8080
      to_port     = 8090
      protocol    = "tcp"
      description = "Backend-service ports"
      cidr_blocks = "10.10.0.0/16"
    },
    {
      from_port   = 3000
      to_port     = 3000
      protocol    = "tcp"
      description = "Port 3000"
      cidr_blocks = "10.10.0.0/16"
    },
    {
      from_port   = 5000
      to_port     = 5000
      protocol    = "tcp"
      description = "Port 5000"
      cidr_blocks = "10.10.0.0/16"
    },
  ]
}

module "db_service_sg" {
  source = "terraform-aws-modules/security-group/aws"

  name        = "db-service"
  description = "Security group for database - allows traffic only from backend SG"
  vpc_id      = module.vpc.vpc_id

  ingress_with_source_security_group_id = [
    {
      from_port                = 5432
      to_port                  = 5432
      protocol                 = "tcp"
      description              = "Allow PostgreSQL from backend SG"
      source_security_group_id = module.backend_service_sg.security_group_id
    },
    {
      from_port                = 3306
      to_port                  = 3306
      protocol                 = "tcp"
      description              = "Allow MySQL from backend SG"
      source_security_group_id = module.backend_service_sg.security_group_id
    }
  ]
}

locals {
  instance_map = {
    az1 = 0
    az2 = 1
    az3 = 2
  }
}

module "frontend_ec2_instance" {
  source = "terraform-aws-modules/ec2-instance/aws"

  for_each = local.instance_map

  name = "frontend-instance-${each.key}"

  instance_type          = "t3.micro"
  monitoring             = true
  vpc_security_group_ids = [module.frontend_server_sg.security_group_id]
  subnet_id              = module.vpc.public_subnets[each.value]
  availability_zone      = module.vpc.azs[each.value]

  user_data = <<-EOF
              #!/bin/bash
              curl -fsSL https://rpm.nodesource.com/setup_18.x | bash -
              yum install -y nodejs
              node -v
              npm -v
              EOF

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}

module "backend_ec2_instance" {
  source = "terraform-aws-modules/ec2-instance/aws"

  for_each = local.instance_map

  name = "backend-instance-${each.key}"

  instance_type          = "t3.micro"
  monitoring             = true
  vpc_security_group_ids = [module.backend_service_sg.security_group_id]
  subnet_id              = module.vpc.private_subnets[each.value]
  availability_zone      = module.vpc.azs[each.value]

  user_data = <<-EOF
              #!/bin/bash
              curl -fsSL https://rpm.nodesource.com/setup_18.x | bash -
              yum install -y nodejs
              node -v
              npm -v
              EOF

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}

module "frontend_alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "8.6.0"

  name               = "fullstack-example-frontend-alb"
  load_balancer_type = "application"

  vpc_id  = module.vpc.vpc_id
  subnets = module.vpc.public_subnets

  security_groups = [module.frontend_server_sg.security_group_id]

  target_groups = [
    {
      name_prefix      = "tg"
      backend_protocol = "HTTP"
      backend_port     = 80
      target_type      = "instance"
      targets = flatten([
        for instance in values(module.frontend_ec2_instance) : [
          {
            target_id = instance.id
            port      = 80
          }
        ]
      ])
      health_check = {
        enabled              = true
        path                 = "/"
        port                 = "80"
        protocol             = "HTTP"
        matcher              = "200"
        healthy_http_codes   = "200"
        healthy_interval     = 30
        healthy_timeout      = 5
        healthy_threshold    = 2
        unhealthy_http_codes = "500,502,503,504"
        unhealthy_interval   = 30
        unhealthy_timeout    = 5
        unhealthy_threshold  = 2
        timeout              = 5
        interval             = 30
        timeout              = 5
        healthy_threshold    = 2
        unhealthy_threshold  = 2
      }
    }
  ]

  http_tcp_listeners = [
    {
      port               = 80
      protocol           = "HTTP"
      target_group_index = 0
    }
  ]

  tags = {
    Environment = "Development"
    Project     = "FullStack-Example"
  }
}
