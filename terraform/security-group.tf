//wireguard sg and its ingress and egress rules
resource "aws_security_group" "sg-wireguard" {
  name        = "wireguard-sg"
  description = "Security group for WireGuard VPN"
  vpc_id      = aws_vpc.main.id
}

resource "aws_vpc_security_group_ingress_rule" "sg-wireguard-ingress" {
  description       = "WireGuard VPN handshake (UDP 51820) from the evaluator IP only - the single public entry point"
  from_port         = 51820
  to_port           = 51820
  ip_protocol       = "udp"
  cidr_ipv4         = var.evaluator_cidr
  security_group_id = aws_security_group.sg-wireguard.id
}

resource "aws_vpc_security_group_egress_rule" "sg-wireguard-egress" {
  description       = "Allow all egress so the gateway can route VPN traffic to private VMs and the internet"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  security_group_id = aws_security_group.sg-wireguard.id
}

//App sg and its ingress and egress rules
resource "aws_security_group" "sg-juiceshop" {
  name        = "juiceshop-sg"
  description = "Security group for Juice Shop"
  vpc_id      = aws_vpc.main.id
}

resource "aws_vpc_security_group_ingress_rule" "sg-juiceshop-ingress-https" {
  description                  = "WAF HTTPS (443) reachable only from VPN users via the WireGuard SG - Juice Shop itself is never exposed"
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.sg-wireguard.id
  security_group_id            = aws_security_group.sg-juiceshop.id
}

resource "aws_vpc_security_group_ingress_rule" "sg-juiceshop-ingress-ssh" {
  description                  = "SSH (22) to the app VM only from VPN users via the WireGuard SG - never from the internet"
  from_port                    = 22
  to_port                      = 22
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.sg-wireguard.id
  security_group_id            = aws_security_group.sg-juiceshop.id
}

resource "aws_vpc_security_group_egress_rule" "sg-juiceshop-egress" {
  description       = "Allow all egress for image pulls, OS updates, and forwarding logs to Wazuh"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  security_group_id = aws_security_group.sg-juiceshop.id
}

// wazuh sg and its ingress and egress rules
resource "aws_security_group" "sg-wazuh" {
  name        = "wazuh-sg"
  description = "Security group for Wazuh"
  vpc_id      = aws_vpc.main.id
}
resource "aws_vpc_security_group_ingress_rule" "sg-wazuh-ingress-https" {
  description                  = "Wazuh dashboard HTTPS (443) only from VPN users via the WireGuard SG"
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.sg-wireguard.id
  security_group_id            = aws_security_group.sg-wazuh.id
}
resource "aws_vpc_security_group_ingress_rule" "sg-wazuh-ingress-ssh" {
  description                  = "SSH (22) to the Wazuh VM only from VPN users via the WireGuard SG"
  from_port                    = 22
  to_port                      = 22
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.sg-wireguard.id
  security_group_id            = aws_security_group.sg-wazuh.id
}
resource "aws_vpc_security_group_ingress_rule" "sg-wazuh-agent-enrollment" {
  description                  = "Wazuh agent enrollment (1515) only from the app VM via the Juice Shop SG"
  from_port                    = 1515
  to_port                      = 1515
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.sg-juiceshop.id
  security_group_id            = aws_security_group.sg-wazuh.id
}

resource "aws_vpc_security_group_ingress_rule" "sg-wazuh-agent-forwarding" {
  description                  = "Wazuh agent log forwarding (1514) only from the app VM via the Juice Shop SG"
  from_port                    = 1514
  to_port                      = 1514
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.sg-juiceshop.id
  security_group_id            = aws_security_group.sg-wazuh.id
}

resource "aws_vpc_security_group_ingress_rule" "sg-wazuh-app-verifier" {
  description                  = "Wazuh indexer API (9200) only from the app VM so the verifier can query for the test marker"
  from_port                    = 9200
  to_port                      = 9200
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.sg-juiceshop.id
  security_group_id            = aws_security_group.sg-wazuh.id
}

resource "aws_vpc_security_group_egress_rule" "sg-wazuh-egress" {
  description       = "Allow all egress for updates and certificate/package downloads"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  security_group_id = aws_security_group.sg-wazuh.id
}
