data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name    = "name"
    values  = [ "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" ]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_instance" "api_server" {
  ami                       = data.aws_ami.ubuntu.id
  instance_type             = "t2.micro"
  subnet_id                 = aws_subnet.public_1.id
  vpc_security_group_ids    = [ aws_security_group.api_sg.id ]

  tags = {
    Name = "api-server-${var.environment}"
  }
}