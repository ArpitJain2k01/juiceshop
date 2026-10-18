resource "aws_instance" "wazuh" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.wazuh_instance_type
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.sg-wazuh.id]
  iam_instance_profile   = aws_iam_instance_profile.wazuh.name
  key_name               = aws_key_pair.lab.key_name
  availability_zone      = "${var.region}a"

  user_data = templatefile("${path.module}/templates/wazuh-userdata.sh.tftpl", {
    data_device = "/dev/sdf"
  })

  root_block_device {
    volume_size = var.wazuh_root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }
  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }
  tags = { Name = "${var.project}-wazuh" }
}

// EBS volume for Wazuh data
resource "aws_ebs_volume" "wazuh_data" {
  availability_zone = aws_instance.wazuh.availability_zone
  size              = var.wazuh_data_volume_size
  type              = "gp3"
  encrypted         = true

  tags = { Name = "${var.project}-wazuh-data" }

  # Protect persisted data: don't let a routine replace nuke it
  lifecycle {
    prevent_destroy = false # set true for real prod; false here so `make destroy` works
  }
}
resource "aws_volume_attachment" "wazuh_data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.wazuh_data.id
  instance_id = aws_instance.wazuh.id

  # So replacing the instance doesn't try to force-detach badly
  stop_instance_before_detaching = true
}