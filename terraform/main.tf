provider "aws" {
  version = "~> 2.0"
  region = "ap-south-1"
}

resource "aws_key_pair" "deploy" {
  key_name   = "terraform-key"
  public_key = file("/home/rishabhkumarkandoi/.ssh/terraform.pub")
}

resource "aws_security_group" "sg" {

  name = "allow_http"

  ingress {
    from_port = 80
    protocol = "tcp"
    to_port = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 22
    protocol = "tcp"
    to_port = 22
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    protocol = "-1"
    to_port = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_http"
  }
}

resource "aws_instance" "first_terra_ins" {
  depends_on = [
    aws_security_group.sg,
    aws_key_pair.deploy,
  ]

  ami = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  key_name = aws_key_pair.deploy.key_name
  security_groups = [ aws_security_group.sg.name ]

  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = file("/home/rishabhkumarkandoi/.ssh/terraform")
    host     = aws_instance.first_terra_ins.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd git -y",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd",
    ]
  }

  tags = {
    Name = "first_terra_ins"
  }
}

resource "null_resource" "terra_ins_ip_save" {
  depends_on = [
    aws_instance.first_terra_ins,
  ]

  provisioner "local-exec" {
    command = "echo ${aws_instance.first_terra_ins.public_ip} > terra_first_ins_public_ip.txt"
  }
}

resource "aws_ebs_volume" "terra_vol" {
   depends_on = [
    aws_instance.first_terra_ins,
  ]
  availability_zone = aws_instance.first_terra_ins.availability_zone
  size              = 1

  tags = {
    Name = "terra_vol"
  }
}

resource "aws_volume_attachment" "terra_vol_att" {
  depends_on = [
    aws_instance.first_terra_ins,
    aws_ebs_volume.terra_vol
  ]
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.terra_vol.id
  instance_id = aws_instance.first_terra_ins.id
  force_detach = true
}

resource "aws_s3_bucket" "terra_s3_bucket" {
  bucket = "terra-ins-bucket"
  acl    = "public-read"

  tags = {
    Name = "Terra Bucket"
  }
}

resource "null_resource" "clone_git_to_local" {
  provisioner "local-exec" {
    command = "rm -rf /tmp/lw && git clone https://github.com/Rishabhkandoi/LW.git /tmp/lw/"
  }
}

resource "aws_s3_bucket_object" "terra_s3_bucket_file" {
  depends_on = [
    aws_s3_bucket.terra_s3_bucket,
    null_resource.clone_git_to_local,
  ]

  bucket = aws_s3_bucket.terra_s3_bucket.bucket
  key = "index_image.jpeg"
  source = "/tmp/lw/about.jpeg"
  acl = "public-read"
}

resource "aws_cloudfront_distribution" "terra_cdn" {
  depends_on = [
    aws_s3_bucket_object.terra_s3_bucket_file,
  ]

  origin {
    domain_name = aws_s3_bucket.terra_s3_bucket.bucket_regional_domain_name
    origin_id   = "terraBucketCdnOriginId"
  }

  enabled = true

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "terraBucketCdnOriginId"
    forwarded_values {
      query_string = true
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

resource "null_resource" "push_html_to_git" {
  depends_on = [
    aws_cloudfront_distribution.terra_cdn,
  ]

  provisioner "local-exec" {
     command = <<EOT
      echo '<html><h1>Hosted using Terraform</h1><body><img src="https://${aws_cloudfront_distribution.terra_cdn.domain_name}/index_image.jpeg" style="width:30%;height:70%;"></body></html>' > /tmp/lw/index.html &&
      cd /tmp/lw/ &&
      git add . &&
      git commit -m 'Added html page.' &&
      git push origin master
    EOT
  }
}

resource "null_resource" "mount_vol"  {

  depends_on = [
    aws_volume_attachment.terra_vol_att,
    null_resource.push_html_to_git,
  ]

  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = file("/home/rishabhkumarkandoi/.ssh/terraform")
    host     = aws_instance.first_terra_ins.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4  /dev/xvdh",
      "sudo mount  /dev/xvdh  /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/Rishabhkandoi/LW.git /var/www/html/"
    ]
  }
}
