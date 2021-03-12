#----- data sources
data "ibm_is_ssh_key" "ssh_key" {
  name = var.ssh_key_name
}

data "ibm_is_image" "ubuntu" {
  name = var.image_name
}

data "external" "ifconfig_me" {
  program = ["bash", "-c", <<-EOS
    echo '{"ip": "'$(curl ifconfig.me)'"}'
  EOS
  ]
}

data "ibm_resource_group" "group" {
  name = var.resource_group_name
}

locals {
  # myip = data.external.ifconfig_me.result.ip # ratched down to just your workstation if needed
  myip    = "0.0.0.0/0"

  vpc_cidr = "10.0.0.0/14"

  zones = {
    0 : { zone : "${var.region}-1", cidr : cidrsubnet(local.vpc_cidr, 2, 0) },
    # 1 : { zone : "${var.region}-2", cidr : cidrsubnet(local.vpc_cidr, 2, 1) },
  }

  proxy_zone_index = 0 # zone for proxy
  proxy_zone = ibm_is_vpc_address_prefix.prefixes[local.proxy_zone_index].zone
  proxy_cidr = cidrsubnet(ibm_is_vpc_address_prefix.prefixes[local.proxy_zone_index].cidr, 8, 1)

  jump_zone_index  = 0 # zone for jump
  jump_zone = ibm_is_vpc_address_prefix.prefixes[local.jump_zone_index].zone
  jump_cidr = cidrsubnet(ibm_is_vpc_address_prefix.prefixes[local.jump_zone_index].cidr, 8, 2)
}

#----- vpc, address prefix 
resource "ibm_is_vpc" "vpc" {
  name           = var.basename
  resource_group = data.ibm_resource_group.group.id
  address_prefix_management = "manual"
}

resource "ibm_is_vpc_address_prefix" "prefixes" {
  for_each = local.zones
  name     = "${var.basename}-${each.value.zone}"
  zone     = each.value.zone
  vpc      = ibm_is_vpc.vpc.id
  cidr     = each.value.cidr
}

# Routing and subnets.  The host zone is controlled by the routes
resource "ibm_is_vpc_routing_table" "vpc" {
  name = var.basename
  vpc  = ibm_is_vpc.vpc.id
}

#----- security groups and instances
resource "ibm_is_security_group" "sg1" {
  name           = "${var.basename}-sg1"
  vpc            = ibm_is_vpc.vpc.id
  resource_group = data.ibm_resource_group.group.id
}

# allow outbound anywhere, the jump server really only needs to get to the hosts
resource "ibm_is_security_group_rule" "outbound_all" {
  group     = ibm_is_security_group.sg1.id
  direction = "outbound"
  remote    = "0.0.0.0/0"
}

# allow inbound from each other
resource "ibm_is_security_group_rule" "inbound_all" {
  group     = ibm_is_security_group.sg1.id
  direction = "inbound"
  remote     = ibm_is_security_group.sg1.id
}

# allow ssh access to the jump server from your desktop
resource "ibm_is_security_group" "sg_ssl" {
  name           = "${var.basename}-ssl"
  vpc            = ibm_is_vpc.vpc.id
  resource_group = data.ibm_resource_group.group.id
}
resource "ibm_is_security_group_rule" "ingress_ssh_all" {
  group     = ibm_is_security_group.sg_ssl.id
  direction = "inbound"
  remote    = local.myip
  tcp {
    port_min = 22
    port_max = 22
  }
}

#----- squid proxy
resource "ibm_is_public_gateway" "proxy" {
  name           = "${var.basename}-proxy"
  vpc            = ibm_is_vpc.vpc.id
  zone           = local.proxy_zone
}

resource "ibm_is_subnet" "proxy" {
  name            = "${var.basename}-proxy"
  vpc             = ibm_is_vpc.vpc.id
  zone           = local.proxy_zone
  ipv4_cidr_block = local.proxy_cidr
  resource_group  = data.ibm_resource_group.group.id
  public_gateway = ibm_is_public_gateway.proxy.id
}

resource "ibm_is_instance" "proxy" {
  name           = "${var.basename}-proxy"
  vpc            = ibm_is_vpc.vpc.id
  zone           = ibm_is_subnet.proxy.zone
  keys           = [data.ibm_is_ssh_key.ssh_key.id]
  image          = data.ibm_is_image.ubuntu.id
  profile        = var.profile
  resource_group = data.ibm_resource_group.group.id
  primary_network_interface {
    subnet            = ibm_is_subnet.proxy.id
    security_groups   = [ibm_is_security_group.sg1.id]
    allow_ip_spoofing = true #---- spoofing is required, squid impersonates the host
  }
  # hosts can be in all zones
  user_data = replace(file("proxy_user_data.sh"), "__ipv4_cidr_block__", local.vpc_cidr)
}

output "ip_proxy" {
  value = ibm_is_instance.proxy.primary_network_interface[0].primary_ipv4_address
}

output "sshproxy" {
  value = "ssh -J root@${ibm_is_floating_ip.jump.address} root@${ibm_is_instance.proxy.primary_network_interface[0].primary_ipv4_address}"
}

/*-----
resource "ibm_is_floating_ip" "proxy" {
  name           = "${var.basename}-proxy"
  target         = ibm_is_instance.proxy.primary_network_interface[0].id
  resource_group = data.ibm_resource_group.group.id
}
-----*/

#----
resource "ibm_is_subnet" "jump" {
  name           = "${var.basename}-jump"
  vpc             = ibm_is_vpc.vpc.id
  zone           = local.jump_zone
  ipv4_cidr_block = local.jump_cidr
  resource_group  = data.ibm_resource_group.group.id
}

resource "ibm_is_instance" "jump" {
  name           = "${var.basename}-jump"
  vpc            = ibm_is_vpc.vpc.id
  zone           = ibm_is_subnet.jump.zone
  keys           = [data.ibm_is_ssh_key.ssh_key.id]
  image          = data.ibm_is_image.ubuntu.id
  profile        = var.profile
  resource_group = data.ibm_resource_group.group.id
  primary_network_interface {
    subnet            = ibm_is_subnet.jump.id
    security_groups   = [ibm_is_security_group.sg1.id, ibm_is_security_group.sg_ssl.id]
    allow_ip_spoofing = true #---- spoofing is required, squid impersonates the host
  }
}

resource "ibm_is_floating_ip" "jump" {
  name           = "${var.basename}-jump"
  target         = ibm_is_instance.jump.primary_network_interface[0].id
  resource_group = data.ibm_resource_group.group.id
}

output "ip_jump" {
  value = ibm_is_instance.jump.primary_network_interface[0].primary_ipv4_address
}
output "fip_jump" {
  value = ibm_is_floating_ip.jump.address
}
output "sshjump" {
  value = "ssh root@${ibm_is_floating_ip.jump.address}"
}
output "ip_workstation" {
  value = local.myip
}

#----- subnets for hosts
resource "ibm_is_subnet" "hosts" {
  for_each        = ibm_is_vpc_address_prefix.prefixes # address prefixes is the correct dependency
  name            = "${each.value.name}-host"
  vpc             = ibm_is_vpc.vpc.id
  zone            = each.value.zone
  ipv4_cidr_block = cidrsubnet(each.value.cidr, 8, each.key)
  resource_group  = data.ibm_resource_group.group.id
  routing_table   = ibm_is_vpc_routing_table.vpc.routing_table
}

#----- routes

# address for cloud service endpoints for dns server, timeserver, resources, ... defaults are good
# https://cloud.ibm.com/docs/vpc-on-classic?topic=vpc-on-classic-service-endpoints-available-for-ibm-cloud-vpc
resource "ibm_is_vpc_routing_table_route" "ibm_cloud_service_endpoints_161" {
  for_each = ibm_is_subnet.hosts
  vpc           = ibm_is_vpc.vpc.id
  routing_table = ibm_is_vpc_routing_table.vpc.routing_table
  zone          = each.value.zone
  destination   = "161.26.0.0/16"
  action        = "delegate"
  next_hop      = "0.0.0.0"
}

resource "ibm_is_vpc_routing_table_route" "ibm_cloud_service_endpoints_166" {
  for_each = ibm_is_subnet.hosts
  vpc           = ibm_is_vpc.vpc.id
  routing_table = ibm_is_vpc_routing_table.vpc.routing_table
  zone          = each.value.zone
  destination   = "166.8.0.0/14"
  action        = "delegate"
  next_hop      = "0.0.0.0"
}

# address explicitly for the proxy - send to proxy
resource "ibm_is_vpc_routing_table_route" "host_within_vpc" {
  for_each = ibm_is_subnet.hosts
  vpc           = ibm_is_vpc.vpc.id
  routing_table = ibm_is_vpc_routing_table.vpc.routing_table
  zone          = each.value.zone
  destination   = local.vpc_cidr
  action        = "delegate"
  next_hop      = "0.0.0.0"
}

# all other addresses, go to the proxy
resource "ibm_is_vpc_routing_table_route" "host_to_proxy_all" {
  for_each = ibm_is_subnet.hosts
  vpc           = ibm_is_vpc.vpc.id
  routing_table = ibm_is_vpc_routing_table.vpc.routing_table
  zone          = each.value.zone
  destination   = "0.0.0.0/0"
  action        = "deliver"
  next_hop      = ibm_is_instance.proxy.primary_network_interface[0].primary_ipv4_address
}

resource "ibm_is_instance" "host" {
  for_each = ibm_is_subnet.hosts
  name           = each.value.name
  vpc            = ibm_is_vpc.vpc.id
  zone          = each.value.zone
  keys           = [data.ibm_is_ssh_key.ssh_key.id]
  image          = data.ibm_is_image.ubuntu.id
  profile        = var.profile
  resource_group = data.ibm_resource_group.group.id
  primary_network_interface {
    subnet          = each.value.id
    security_groups   = [ibm_is_security_group.sg1.id]
  }
}


output "host" {
  value = [
    #for index, instance in ibm_is_instance.host: index => {
    for index, instance in ibm_is_instance.host: {
      ip_host = instance.primary_network_interface[0].primary_ipv4_address,
      sshhost = "ssh -J root@${ibm_is_floating_ip.jump.address} root@${instance.primary_network_interface[0].primary_ipv4_address}",
    }
  ]
}

output basename {
  value = var.basename
}
