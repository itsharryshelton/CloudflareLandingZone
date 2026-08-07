# Account: account_b - Cloudflare WAN (formerly Magic WAN). Consumed by the wan layer only.
#
#   terraform -chdir=layers/wan plan \
#     -var-file=../../accounts/account_b/account.tfvars \
#     -var-file=../../accounts/account_b/wan.tfvars
#
# See accounts/account_a/wan.tfvars for the fuller worked example.
#
# The pre-shared keys are not in this file and must never be. They arrive from the
# apply environment, keyed the same way as wan_ipsec_tunnels:
#
#   TF_VAR_wan_ipsec_tunnel_psks={"bristol_primary":"<psk>","bristol_secondary":"<psk>"}

wan_ipsec_tunnels = {
  # A single site, dual circuit, dual stack. The /127 comes from the tunnel's
  # virtual_subnet6 space, and the IPv6 route below needs it
  bristol_primary = {
    name                = "bri-ipsec-01"
    description         = "Bristol office, primary circuit"
    cloudflare_endpoint = "192.0.2.30"
    customer_endpoint   = "203.0.113.30"
    interface_address   = "10.252.2.0/31"
    interface_address6  = "fd00:0:0:252::/127"
  }

  bristol_secondary = {
    name                = "bri-ipsec-02"
    description         = "Bristol office, secondary circuit"
    cloudflare_endpoint = "192.0.2.30"
    customer_endpoint   = "203.0.113.31"
    interface_address   = "10.252.2.2/31"
    interface_address6  = "fd00:0:0:252::2/127"
  }
}

wan_static_routes = {
  bristol_lan_primary = {
    prefix     = "10.40.0.0/16"
    tunnel_key = "bristol_primary"
    priority   = 100
  }

  bristol_lan_secondary = {
    prefix     = "10.40.0.0/16"
    tunnel_key = "bristol_secondary"
    priority   = 200
  }

  bristol_lan_v6_primary = {
    prefix     = "fd00:0:0:40::/64"
    tunnel_key = "bristol_primary"
    priority   = 100
  }

  bristol_lan_v6_secondary = {
    prefix     = "fd00:0:0:40::/64"
    tunnel_key = "bristol_secondary"
    priority   = 200
  }
}
