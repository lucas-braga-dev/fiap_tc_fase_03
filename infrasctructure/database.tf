resource "aws_db_subnet_group" "db_subnets" {
  name       = "main-db-subnet-group"
  
  subnet_ids = [
    aws_subnet.private_1.id, 
    aws_subnet.private_2.id
  ]
}

resource "aws_db_instance" "postgres" {
  allocated_storage         = 20
  max_allocated_storage     = 50
  engine                    = "postgres"
  engine_version            = "15"
  instance_class            = "db.t3.micro"
  db_name                   = "togglemasterdb"
  username                  = "master"
  password                  = var.db_password
  db_subnet_group_name      = aws_db_subnet_group.db_subnets.name
  vpc_security_group_ids    = [ aws_security_group.db_secgp.id ]
  skip_final_snapshot       = true
}