# -------------Provider with user access -----------------------

provider "alicloud" {
  access_key = var.access_key
  secret_key = var.secret_key
  region = "me-central-1"
}

# ----------------create VPC ------------------

# Create a Virtual Private Cloud (VPC) with the specified CIDR block.
resource "alicloud_vpc" "vpc" {
  vpc_name   = "flare"
  cidr_block = "172.16.0.0/16"
}


# ----------------create Zone ------------------

data "alicloud_zones" "zones_ds" {
  available_resource_creation = "VSwitch"
}

# ----------------create VSwitches ------------------

# Create a public VSwitch in the specified zone within the VPC.
resource "alicloud_vswitch" "public" {
  vpc_id     = alicloud_vpc.vpc.id
  cidr_block = "172.16.1.0/24"  # Valid within the VPC CIDR range
  zone_id    = data.alicloud_zones.zones_ds.zones.0.id
}


# Create a private VSwitch in the same zone within the VPC.
resource "alicloud_vswitch" "private" {
  vpc_id     = alicloud_vpc.vpc.id
  cidr_block = "172.16.2.0/24"  # Valid within the VPC CIDR range
  zone_id    = data.alicloud_zones.zones_ds.zones.0.id
}
# ----------------create Internet Gateway (EIP) ------------------

# Create an Elastic IP (EIP) for internet access with bandwidth and payment details.
resource "alicloud_eip" "eip_nat" {
  bandwidth            = "5"
  internet_charge_type = "PayByTraffic"
}
# ----------------create NAT Gateway ------------------

# Create a NAT Gateway for internet access to private instances via VSwitch.
resource "alicloud_nat_gateway" "nat" {
  vpc_id      = alicloud_vpc.vpc.id
  nat_gateway_name = "nat1"
  payment_type     = "PayAsYouGo"
  vswitch_id       = alicloud_vswitch.public.id
  nat_type         = "Enhanced"
}

# ----------------create EIP for NAT and Associate with NAT Gateway ------------------

# Create another EIP for the NAT Gateway with specific bandwidth and payment method.
resource "alicloud_eip_address" "ipnat" {
  description               = "NAT"
  address_name              = "NAT"
  netmode                   = "public"
  bandwidth                 = "100"
  payment_type              = "PayAsYouGo"
  internet_charge_type      = "PayByTraffic"
}

# Associate the EIP created above with the NAT Gateway.
resource "alicloud_eip_association" "example" {
  allocation_id = alicloud_eip_address.ipnat.id
  instance_id   = alicloud_nat_gateway.nat.id
}

# ----------------create SNAT Entry ------------------

# Create an SNAT rule to allow private instances to communicate with the internet using the NAT Gateway.
resource "alicloud_snat_entry" "snat" {
  snat_table_id     = alicloud_nat_gateway.nat.snat_table_ids
  source_vswitch_id = alicloud_vswitch.private.id
  snat_ip           = alicloud_eip_address.ipnat.ip_address
}



# ----------------create Route Tables ------------------

# Create a route table for the private VSwitch.
resource "alicloud_route_table" "privateroute" {
  description      = "test-description"
  vpc_id           = alicloud_vpc.vpc.id
  # route_table_name = var.name
  associate_type   = "VSwitch"
}


# Add a default route entry in the private route table to route traffic via the NAT Gateway.
resource "alicloud_route_entry" "private_route" {
  route_table_id        = alicloud_route_table.privateroute.id
  destination_cidrblock = "0.0.0.0/0"
  nexthop_type          = "NatGateway"
  nexthop_id            = alicloud_nat_gateway.nat.id
}



# ----------------associate Route Tables ------------------




# Attach the route table to the private VSwitch for managing traffic routing.
resource "alicloud_route_table_attachment" "foo" {
  vswitch_id     = alicloud_vswitch.private.id
  route_table_id = alicloud_route_table.privateroute.id
}

#-------------------------------------


# Create Security Group
resource "alicloud_security_group" "SG_node1" {
  name        = "SG_node1"
  description = "SG node1 Allwo"
  vpc_id      = alicloud_vpc.vpc.id
}


resource "alicloud_security_group" "SG_node2" {
  name        = "SG_node2"
  description = "SG node2 Allwo"
  vpc_id      = alicloud_vpc.vpc.id
}




# # Add Security Group Rules
resource "alicloud_security_group_rule" "ssh" {
  security_group_id = alicloud_security_group.SG_node1.id
  ip_protocol       = "tcp"
  port_range        = "22/22"
  cidr_ip           = "0.0.0.0/0"
  policy            = "accept"
  priority          = 1
  type              = "ingress"  
}



# # Add Security Group Rules
resource "alicloud_security_group_rule" "http" {
  security_group_id = alicloud_security_group.SG_node1.id
  ip_protocol       = "tcp"
  port_range        = "80/80"  
  cidr_ip           = "0.0.0.0/0"  
  policy            = "accept"
  priority          = 1
  type              = "ingress"  
}




# resource "alicloud_security_group_rule" "allow_all_sshRDS" {
#   type              = "ingress"
#   ip_protocol       = "tcp"
#   policy            = "accept"
#   port_range        = "22/22"
#   priority          = 1
#   security_group_id = alicloud_security_group.SG_node2.id
#   source_security_group_id = alicloud_security_group.SG_node1.id
# }

# resource "alicloud_security_group_rule" "allow_all_redis" {
#   type              = "ingress"
#   ip_protocol       = "tcp"
#   policy            = "accept"
#   port_range        = "6379/6379"
#   priority          = 1
#   security_group_id = alicloud_security_group.SG_node2.id
#   source_security_group_id = alicloud_security_group.SG_node1.id
# }

# -----------------------------------------

resource "alicloud_ecs_key_pair" "publickey" {
  key_pair_name = "publickey"
  key_file = "key2.pem"
}


resource "alicloud_instance" "node1" {
  # cn-beijing
  availability_zone = data.alicloud_zones.zones_ds.zones.0.id
  security_groups   = [alicloud_security_group.SG_node1.id]

  # series III
  instance_type              = "ecs.g6.large"
  system_disk_category       = "cloud_essd"
  system_disk_name           = "sara"
  system_disk_size           = 40
  system_disk_description    = "system_disk_description"
  image_id                   = "ubuntu_22_04_x64_20G_alibase_20240926.vhd"
  instance_name              = "node1"
  vswitch_id                 = alicloud_vswitch.public.id
  internet_max_bandwidth_out = 100
  internet_charge_type       = "PayByTraffic"
  instance_charge_type      = "PostPaid"
  key_name                   = alicloud_ecs_key_pair.publickey.key_pair_name
  user_data                 = base64encode(file("dock.sh"))
}


# Create a new private instance for VPC
resource "alicloud_instance" "node2" {
  # cn-beijing
  availability_zone = data.alicloud_zones.zones_ds.zones.0.id
  security_groups   = [alicloud_security_group.SG_node2.id]

  # series III
  instance_type              = "ecs.g6.large"
  system_disk_category       = "cloud_essd"
  system_disk_name           = "sara"
  system_disk_size           = 40
  system_disk_description    = "system_disk_description"
  image_id                   = "ubuntu_22_04_x64_20G_alibase_20240926.vhd"
  instance_name              = "node2"
  vswitch_id                 = alicloud_vswitch.private.id
  internet_max_bandwidth_out = 0
  internet_charge_type       = "PayByTraffic"
  instance_charge_type       = "PostPaid"
  key_name                   = alicloud_ecs_key_pair.publickey.key_pair_name
  user_data = base64encode(file("dock.sh"))
}


output "node1_ip" {
  value = alicloud_instance.node1.public_ip
  
}
output "node2_ip" {
  value = alicloud_instance.node2.private_ip
  
}

