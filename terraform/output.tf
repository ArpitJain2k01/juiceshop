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
