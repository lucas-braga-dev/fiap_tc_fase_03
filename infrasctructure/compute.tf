# recurso criado direto de forma temporária
resource "aws_instance" "api_server" {
  ami           = var.ami_id
  instance_type = "t3.micro"
  subnet_id              = aws_subnet.public_1.id
  vpc_security_group_ids = [aws_security_group.api_secgp.id]
  associate_public_ip_address = true
  key_name = "fiap-tc-fase-03-devops"
  

  tags = {
    Name = "api-server-${var.environment}"
  }
}