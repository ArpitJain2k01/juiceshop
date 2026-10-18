data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

//App VMs
resource "aws_instance" "app" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.app_instance_type
  key_name               = aws_key_pair.lab.key_name
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.sg-juiceshop.id]
  iam_instance_profile   = aws_iam_instance_profile.app.name

  user_data = templatefile("${path.module}/templates/app-userdata.sh.tftpl", {
    juiceshop_image = var.juiceshop_image
  })

  root_block_device {
    volume_size = var.app_root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }
  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }
  tags = {
    Name = "${var.project}-app"
  }
}