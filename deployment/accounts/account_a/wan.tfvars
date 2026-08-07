# Account: account_a - Cloudflare WAN (formerly Magic WAN). Consumed by the wan layer only.
#
#   terraform -chdir=layers/wan plan \
#     -var-file=../../accounts/account_a/account.tfvars \
#     -var-file=../../accounts/account_a/wan.tfvars
##
# THE PRE-SHARED KEYS ARE NOT IN THIS FILE AND MUST NEVER BE. 
#   TF_VAR_wan_ipsec_tunnel_psks={"london_primary":"<psk>","london_secondary":"<psk>"}
#
# Cloudflare WAN is not enabled here. It is an Enterprise entitlement Cloudflare
#
# Addresses below use the documentation ranges: 192.0.2.0/24 stands in for the
# anycast addresses Cloudflare allocates to the account, and 203.0.113.0/24 for
# the customer's own public addresses. Replace both.

wan_ipsec_tunnels = {
  london_primary = {
    name                = "lon-ipsec-01"
    description         = "London HQ, primary circuit"
    cloudflare_endpoint = "192.0.2.10"
    customer_endpoint   = "203.0.113.10"
    interface_address   = "10.252.0.0/31"
  }

  london_secondary = {
    name                = "lon-ipsec-02"
    description         = "London HQ, secondary circuit"
    cloudflare_endpoint = "192.0.2.10"
    customer_endpoint   = "203.0.113.11"
    interface_address   = "10.252.0.2/31"
  }
}

wan_gre_tunnels = {
  manchester_primary = {
    name                = "man-gre-01"
    description         = "Manchester DC, primary circuit"
    cloudflare_endpoint = "192.0.2.10"
    customer_endpoint   = "203.0.113.20"
    interface_address   = "10.252.1.0/31"
  }

  manchester_secondary = {
    name                = "man-gre-02"
    description         = "Manchester DC, secondary circuit"
    cloudflare_endpoint = "192.0.2.10"
    customer_endpoint   = "203.0.113.21"
    interface_address   = "10.252.1.2/31"

    health_check_type   = "request"
    health_check_target = "10.20.0.1"
  }

  # Dynamic routing instead of static routes, for a site whose internal
  # addressing changes often enough that a pull request per prefix is friction:
  #
  #   bgp_customer_asn   = 65010
  #   bgp_extra_prefixes = ["10.30.0.0/16"]
  #
  # The session key, if the device wants one, comes from the apply environment as
  # TF_VAR_wan_bgp_md5_keys and not from this file. Cloudflare is explicit that MD5 is not a security control.
}

wan_static_routes = {
  # Two routes per prefix, down two different tunnels. That is what makes the
  # site survive one circuit failing, and the plan refuses a prefix with only
  # one route unless allow_single_tunnel_prefixes is set.
  #
  # The next hop is not written here. tunnel_key resolves it from the tunnel's
  # /31: the address in interface_address is Cloudflare's own end, and a route
  # pointing at that is a blackhole the dashboard shows as configured.
  london_lan_primary = {
    prefix      = "10.10.0.0/16"
    tunnel_key  = "london_primary"
    priority    = 100
    description = "London HQ LAN, preferred path"
  }

  london_lan_secondary = {
    prefix      = "10.10.0.0/16"
    tunnel_key  = "london_secondary"
    priority    = 200
    description = "London HQ LAN, standby path"
  }

  # Same priority on both, so Manchester load-shares across the pair rather than holding one idle.
  manchester_lan_primary = {
    prefix      = "10.20.0.0/16"
    tunnel_key  = "manchester_primary"
    description = "Manchester DC LAN"
  }

  manchester_lan_secondary = {
    prefix      = "10.20.0.0/16"
    tunnel_key  = "manchester_secondary"
    description = "Manchester DC LAN"
  }
}
