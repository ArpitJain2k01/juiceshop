resource "aws_instance" "wireguard" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.wg_instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.sg-wireguard.id]
  iam_instance_profile   = aws_iam_instance_profile.app.name # reuse SSM-capable profile (or make a wg one)
  key_name               = aws_key_pair.lab.key_name

  # WG gateway must forward packets to the private subnet → disable src/dst check
  source_dest_check = false

  user_data = templatefile("${path.module}/templates/wg-userdata.sh.tftpl", {
    wg_client_public_key = var.wg_client_public_key
    wg_server_port       = var.wg_server_port
    server_vpn_ip        = cidrhost(var.wg_vpn_cidr, 1) # 10.8.0.1/24 for the server
    client_vpn_ip        = cidrhost(var.wg_vpn_cidr, 2) # 10.8.0.2/32 for your laptop
  })

  root_block_device {
    volume_size = var.wg_root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }
  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }
  tags = { Name = "${var.project}-wireguard" }
}

resource "aws_eip" "wireguard" {
  domain   = "vpc"
  instance = aws_instance.wireguard.id
  tags     = { Name = "${var.project}-wg-eip" }
}