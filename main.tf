terraform {  
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "5.49.0"      
    }
  }
}
                                       
provider "aws" {
    region = var.availability_zone

}  

# Crear VPC Frontend
resource "aws_vpc" "main" {
  cidr_block = "10.1.0.0/16"
  tags = {
    Name = "main_vpc"
  }
}

resource "aws_flow_log" "mainflow_logs" {
  iam_role_arn    = aws_iam_role.rol_cw.arn
  log_destination = aws_cloudwatch_log_group.grupo_logs_cloudwatch.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.main.id
}

resource "aws_cloudwatch_log_group" "grupo_logs_cloudwatch" {
  name = "grupo_logs_cloudwatch"
  retention_in_days = 7
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "rol_cw" {
  name               = "rol_cw"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

data "aws_iam_policy_document" "documento_politica_cw" {
  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "politica_cw" {
  name   = "politica_cw"
  role   = aws_iam_role.rol_cw.id
  policy = data.aws_iam_policy_document.documento_politica_cw.json
}

# Crear red principal
resource "aws_subnet" "main_sn" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.1.1.0/24"
  availability_zone = "eu-west-1a"
  tags = {
    Name = "frontend-subnet"
  }
}

# Crear subred para backend y servidor
resource "aws_subnet" "backend" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.1.2.0/24"
  availability_zone = "eu-west-1b"
  tags = {
    Name = "backend-subnet"
  }
}

# Crear subred para la BD de
resource "aws_subnet" "backup" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.1.3.0/24"
  availability_zone = "eu-west-1a"
  tags = {
    Name = "backup-subnet"
  }
}

# Crear Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "main-igw"
  }
}

resource "aws_security_group" "allow_tls" {
  name = "allow_tls"
  vpc_id = aws_vpc.main.id
}

resource "aws_vpc_security_group_ingress_rule" "allow_tls_ipv4" {
  security_group_id = aws_security_group.allow_tls.id

  cidr_ipv4         = aws_vpc.main.cidr_block
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.allow_tls.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# Creamos la subred para la BD principal
resource "aws_db_subnet_group" "subred_mainDB" {
  name = "subred_maindb"
  subnet_ids = [aws_subnet.main_sn.id, aws_subnet.backend.id]

  tags = {
    Name = "My DB Subnet Group"
  }
}

resource "aws_db_instance" "mainDB" {
  allocated_storage = 10
  storage_type = "gp2"
  engine = "mysql"
  engine_version = "5.7"
  instance_class = "db.t3.micro"
  identifier = "main"
  username = "main"
  password = "main1234"
  enabled_cloudwatch_logs_exports = ["audit","error", "general"]
  iam_database_authentication_enabled = true


  vpc_security_group_ids = [aws_security_group.allow_tls.id]
  db_subnet_group_name = aws_db_subnet_group.subred_mainDB.name
  
  backup_retention_period = 14
  backup_window = "02:00-04:00"
  maintenance_window = "mon:04:30-mon:05:00"

  skip_final_snapshot = true
  final_snapshot_identifier = "snap"
}

data "aws_ami" "amazon-linux-2" {
 most_recent = true


 filter {
   name   = "owner-alias"
   values = ["amazon"]
 }


 filter {
   name   = "name"
   values = ["amzn2-ami-hvm*"]
 }
}

resource "aws_instance" "frontend_ec2" {
  ami = data.aws_ami.amazon-linux-2.id 
  instance_type = "t2.micro"               # Tipo de instancia
  vpc_security_group_ids = [aws_security_group.allow_tls.id]
  subnet_id = aws_subnet.main_sn.id
  monitoring = true  
 
  metadata_options {
    http_tokens = "required"
  }

  tags = {
    Name = "frontend_ec2"  # Etiqueta de nombre para la instancia
  }
}

resource "aws_instance" "backend_ec2" {
  ami = data.aws_ami.amazon-linux-2.id 
  instance_type = "t2.micro"               
  vpc_security_group_ids = [aws_security_group.allow_tls.id]
  subnet_id = aws_subnet.backend.id
  monitoring = true
  
  metadata_options {
    http_tokens = "required"
  }
 
  tags = {
    Name = "backend_ec2" 
  }
}










