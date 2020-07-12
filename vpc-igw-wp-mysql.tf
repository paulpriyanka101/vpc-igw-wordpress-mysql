# Provide Credentials
 
provider "aws" {
  region = "ap-south-1"
  profile = "admin"
}

# Create VPC and Subnets:

resource "aws_vpc" "myvpc" {
  cidr_block = "10.0.0.0/16"
  instance_tenancy = "default"

  tags = {
    Name = "myvpc"
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_subnet" "public-sn" {
  vpc_id = aws_vpc.myvpc.id
  cidr_block = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "public-sn"
  }
}

resource "aws_subnet" "private-sn" {
  vpc_id = aws_vpc.myvpc.id
  cidr_block = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "private-sn"
  }
}

resource "aws_internet_gateway" "my-igw" {
  vpc_id = aws_vpc.myvpc.id

  tags = {
    Name = "my-igw"
  }
}

resource "aws_route_table" "public-rt" {
  vpc_id = aws_vpc.myvpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.my-igw.id
  }

  tags = {
    Name = "public-rt"
  } 
}

resource "aws_route_table_association" "pub-sn-assoc" {
  subnet_id = aws_subnet.public-sn.id
  route_table_id = aws_route_table.public-rt.id
}

# Create SG for Wordpress Server:

resource "aws_security_group" "wp-sg" {
  depends_on = [aws_vpc.myvpc]
  name = "wp-sg"
  description = "Security group for Wordpress Server"
  vpc_id = aws_vpc.myvpc.id

  ingress {
    description = "allow SSH"
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = [aws_vpc.myvpc.cidr_block]
  }

  ingress {
    description = "allow HTTP"
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "allow ICMP"
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "allow ICMP"
    from_port = 0
    to_port=0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "wp-sg"
  }
}

# Create SG for MySQL DB Server:

resource "aws_security_group" "mysql-sg" {
  depends_on = [aws_vpc.myvpc]
  name = "mysql-sg"
  description = "Security group for MYSQL DB Server"
  vpc_id = aws_vpc.myvpc.id

  ingress {
    description = "allow MYSQL"
    from_port = 3306
    to_port = 3306
    protocol = "tcp"
    security_groups = [aws_security_group.wp-sg.id]
  }

  egress {
    description = "allow ICMP"
    from_port = 0
    to_port=0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "mysql-sg"
  }
}

# create a key-pair:

resource "tls_private_key" "webappkey" {
  algorithm = "RSA"
  rsa_bits = 4096
}

resource "local_file" "private_key" {
  content = tls_private_key.webappkey.private_key_pem
  filename = "${path.module}/webappkey.pem"
  file_permission = 0400
}

resource "aws_key_pair" "webappkey" {
  key_name = "webappkey"
  public_key = tls_private_key.webappkey.public_key_openssh
}

variable "key" {
  type = string
}

# Create Wordpress EC2 Instance in Public Subnet:

resource "aws_instance" "wordpress-os" {
  ami = "ami-7e257211"   
  instance_type = "t2.micro"
  subnet_id = aws_subnet.public-sn.id
  associate_public_ip_address = true
  key_name = var.key
  vpc_security_group_ids = [ aws_security_group.wp-sg.id ]
  
  tags = {
    Name = "wordpress-os"
  }
}

# Create MYSQL DB instance in Private Subnet:

resource "aws_instance" "mysqldb-os" {
  ami = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  subnet_id = aws_subnet.private-sn.id
  key_name = var.key
  vpc_security_group_ids = [ aws_security_group.mysql-sg.id ]

  tags = {
    Name = "mysqldb-os"
  }
}

# Take output of Wordpress and MySQL DB instances:

output "wordpress-az" {
  value = aws_instance.wordpress-os.availability_zone
  }
output "wordpress-publicip" {
  value = aws_instance.wordpress-os.public_ip
  }
output "wordpress-instance-id" {
  value = aws_instance.wordpress-os.id
}
output "mysqldb-az" {
  value = aws_instance.mysqldb-os.availability_zone
  }
output "mysqldb-privateip" {
  value = aws_instance.mysqldb-os.private_ip
  }

# Creation of Provisioner to directly go to Wordpress in Webbrowser

resource "null_resource" "nulllocal1" {
  depends_on = [
    aws_instance.wordpress-os,
    aws_instance.mysqldb-os,
  ]
      provisioner "local-exec" {
        command = "open http://${aws_instance.wordpress-os.public_ip}"
      }
}
