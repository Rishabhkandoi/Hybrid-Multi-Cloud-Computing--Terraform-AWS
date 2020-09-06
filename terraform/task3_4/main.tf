provider "aws" {
  version = "~> 2.0"
  region = "ap-south-1"
}

resource "aws_vpc" "myvpc" {
  cidr_block       = "10.0.0.0/16"
  enable_dns_hostnames=true

  tags = {
    Name = "myvpc"
 }
}

resource "aws_subnet" "myvpc_private" {
  depends_on = [
    aws_vpc.myvpc
  ]

  vpc_id = aws_vpc.myvpc.id

  cidr_block = "10.0.2.0/24"
  availability_zone = "ap-south-1b"
  map_public_ip_on_launch = false

  tags = {
      Name = "my_private_subnet"
  }
}

resource "aws_subnet" "myvpc_public" {
  depends_on =[
    aws_subnet.myvpc_private
  ]

  vpc_id = aws_vpc.myvpc.id

  cidr_block = "10.0.1.0/24"
  availability_zone = "ap-south-1b"
  map_public_ip_on_launch = true

  tags = {
      Name = "my_public_subnet"
  }
}

resource "aws_internet_gateway" "myvpc_gateway" {
  depends_on = [
    aws_subnet.myvpc_private
  ]

  vpc_id = aws_vpc.myvpc.id

  tags = {
    Name = "myvpc_gateway"
  }
}

resource "aws_route_table" "myvpc_routetable" {
  depends_on = [
    aws_internet_gateway.myvpc_gateway
  ]

  vpc_id = aws_vpc.myvpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.myvpc_gateway.id
  }

  tags = {
    Name = "my_routing_table"
  }
}

resource "aws_route_table_association" "myvpc_routetable_association" {
  subnet_id      = aws_subnet.myvpc_public.id
  route_table_id = aws_route_table.myvpc_routetable.id
}

resource "aws_key_pair" "myvpc_access_key" {
  key_name = "myvpc-terraform-key"
  public_key = file("/home/rishabhkumarkandoi/.ssh/terraform.pub")
}

resource "aws_security_group" "myvpc_wordpress_sg" {
  depends_on =[
    aws_vpc.myvpc
  ]

  name = "public_security_group"
  description = "Wordpress Security Group"
  vpc_id = aws_vpc.myvpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }
  tags ={
    Name ="public_security_group"
  }
}

resource "aws_instance" "myvpc_wordpress" {
  depends_on = [
    aws_subnet.myvpc_public,
    aws_security_group.myvpc_wordpress_sg,
    aws_key_pair.myvpc_access_key
  ]
  ami =  "ami-049cbce295a54b26b"
  instance_type = "t2.micro"
  key_name = aws_key_pair.myvpc_access_key.key_name
  vpc_security_group_ids = [aws_security_group.myvpc_wordpress_sg.id]
  subnet_id = aws_subnet.myvpc_public.id

  tags = {
    Name = "wordpress"
  }
}

resource "aws_security_group" "myvpc_mysql_sg" {
  depends_on = [
    aws_vpc.myvpc
  ]

  name = "private_security_group"
  description = "MySQL Security Group"
  vpc_id = aws_vpc.myvpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }
  tags ={
    Name ="private_security_group"
  }
}

resource "aws_instance" "mysql" {
  depends_on = [
    aws_subnet.myvpc_private,
    aws_security_group.myvpc_mysql_sg,
    aws_key_pair.myvpc_access_key
  ]
  ami = "ami-08706cb5f68222d09"
  instance_type = "t2.micro"
  key_name = aws_key_pair.myvpc_access_key.key_name
  vpc_security_group_ids = [aws_security_group.myvpc_mysql_sg.id]
  subnet_id = aws_subnet.myvpc_private.id
  tags = {
    Name = "MySQL"
  }
}

resource "aws_eip" "myvpc_eip" {
  vpc = true
  public_ipv4_pool = "amazon"
}

resource "aws_nat_gateway" "myvpc_nat_gateway" {
  depends_on = [
    aws_eip.myvpc_eip,
    aws_subnet.myvpc_public
  ]

  allocation_id = aws_eip.myvpc_eip.id
  subnet_id     = aws_subnet.myvpc_public.id

  tags = {
    Name = "myvpc_nat_gateway"
  }
}

resource "aws_route_table" "myvpc_routetable_private" {
  depends_on = [
    aws_nat_gateway.myvpc_nat_gateway
  ]

  vpc_id = aws_vpc.myvpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.myvpc_nat_gateway.id
  }

  tags = {
    Name = "private_subnet_route_table"
  }
}

resource "aws_route_table_association" "myvpc_routetable_association_private" {
  depends_on = [
    aws_route_table.myvpc_routetable_private
  ]

  subnet_id      = aws_subnet.myvpc_private.id
  route_table_id = aws_route_table.myvpc_routetable_private.id
}

resource "aws_security_group" "only_ssh_bastion" {
  depends_on = [
    aws_subnet.myvpc_public
  ]

  name        = "only_ssh_bastion"
  description = "Allow ssh bastion inbound traffic"
  vpc_id      =  aws_vpc.myvpc.id

  ingress {
    description = "Only ssh_basiton in public subnet"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks =  ["::/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks =  ["::/0"]
  }

  tags = {
    Name = "only_ssh_bastion"
  }
}

resource "aws_security_group" "only_sql_web" {
  depends_on = [
    aws_subnet.myvpc_public
  ]

  name        = "only_sql_web"
  description = "Allow only sql web inbound traffic"
  vpc_id      =  aws_vpc.myvpc.id

  ingress {
    description = "Only web sql from public subnet"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [
      aws_security_group.myvpc_wordpress_sg.id
    ]
  }

  ingress {
    description = "Only web ping sql from public subnet"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    security_groups = [
      aws_security_group.myvpc_wordpress_sg.id
    ]
    ipv6_cidr_blocks=["::/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "only_sql_web"
  }
}

resource "aws_security_group" "only_ssh_sql_bastion" {
  depends_on = [
    aws_subnet.myvpc_public
  ]

  name        = "only_ssh_sql_bastion"
  description = "Allow ssh bastion inbound traffic"
  vpc_id      =  aws_vpc.myvpc.id

  ingress {
    description = "Only ssh_sql_bastion in public subnet"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    security_groups = [
      aws_security_group.only_ssh_bastion.id
    ]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks =  ["::/0"]
  }

  tags = {
    Name = "only_ssh_sql_bastion"
  }
}

resource "aws_instance" "bastion_host" {
  depends_on = [
    aws_security_group.only_ssh_bastion
  ]

  ami                    = "ami-0447a12f28fddb066"
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.myvpc_public.id
  key_name               = aws_key_pair.myvpc_access_key.key_name
  vpc_security_group_ids = [
    aws_security_group.only_ssh_bastion.id
  ]

  tags = {
    Name = "bastion_host"
  }
}

resource "aws_instance" "myvpc_mysql_2" {
  depends_on = [
    aws_security_group.only_sql_web,
    aws_security_group.only_ssh_sql_bastion
  ]

  ami                    = "ami-08706cb5f68222d09"
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.myvpc_private.id
  key_name               = aws_key_pair.myvpc_access_key.key_name
  vpc_security_group_ids = [
    aws_security_group.only_sql_web.id,
    aws_security_group.only_ssh_sql_bastion.id
  ]

  tags = {
    Name = "mysql_2"
  }
}
