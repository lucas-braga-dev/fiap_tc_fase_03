# = = = = = = = = = = = = = = = =
# VPC e Subnets da aplicação
# = = = = = = = = = = = = = = = =
# 
# criar documentação sobre a rede aqui
#
# = = = = = = = = = = = = = = = =



# - - - - - - - - - - - - - - - -
# VPC principal da aplicação
# - - - - - - - - - - - - - - - -
resource "aws_vpc" "main" {
    cidr_block              = "10.0.0.0/16"
    enable_dns_hostnames    = true

    tags = {
        Name = "vpc-${var.environment}"
    }
} # fim VPC principal


# - - - - - - - - - - - - - - - -
# SUBNET pública para a -> EC2 <-
# - - - - - - - - - - - - - - - -
resource "aws_subnet" "public_1" {
    vpc_id                  = aws_vpc.main.id
    cidr_block              = "10.0.2.0/24"
    availability_zone       = "${var.aws_region}-a"
} # fim subnet EC2


# - - - - - - - - - - - - - - - -
# SUBNET pública para o -> RDS <-
# - - - - - - - - - - - - - - - -
resource "aws_subnet" "private_1" {
    vpc_id                  = aws_vpc.main.id
    cidr_block              = "10.0.1.0/24"
    map_public_ip_on_launch = true
    availability_zone       = "${var.aws_region}-b"
} # fim subnet RDS

# - - - - - - - - - - - - - 
# Security Group para o EC2
# - - - - - - - - - - - - - 
resource "aws_security_group" "api_secgp" {
    name = "api-security-group"
    vpc_id = aws_vpc.main.id

    ingress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = [ "0.0.0.0/0" ]
    }

    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = [ "0.0.0.0/0" ]
    }
}

# - - - - - - - - - - - - - 
# Security Group para o RDS
# - - - - - - - - - - - - - 
resource "aws_security_group" "db_secgp" {
    name = "db-security-group"
    vpc_id = aws_vpc.main.id

    ingress {
        from_port = 5432
        to_port = 5432
        protocol = "tcp"
        cidr_blocks = [ aws_security_group.api_secgp ]
    }
}

