output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_id" {
  value = aws_subnet.public.id
}
output "private_subnet_id" {
  value = aws_subnet.private.id
}
output "nat_gateway_id" {
  value = aws_nat_gateway.nat.id
}
output "internet_gateway_id" {
  value = aws_internet_gateway.igw.id
}
output "security_group_wireguard_id" {
  value = aws_security_group.sg-wireguard.id
}
output "security_group_juiceshop_id" {
  value = aws_security_group.sg-juiceshop.id
}
output "security_group_wazuh_id" {
  value = aws_security_group.sg-wazuh.id
}
output "ssh_keypair_name" {
  value = aws_key_pair.lab.key_name
}
output "app_instance_profile" {
  value = aws_iam_instance_profile.app.name
}
output "wazuh_instance_profile" {
  value = aws_iam_instance_profile.wazuh.name
}
output "app_private_ip" {
  value = aws_instance.app.private_ip
}
output "wireguard_public_ip" {
  value = aws_eip.wireguard.public_ip
}
output "wireguard_private_ip" {
  value = aws_instance.wireguard.private_ip
}
output "wazuh_private_ip" {
  value = aws_instance.wazuh.private_ip
}
output "wazuh_dashboard_url" {
  value = "https://${aws_instance.wazuh.private_ip}:443  (via VPN only)"
}
