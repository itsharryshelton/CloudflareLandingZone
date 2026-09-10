# Account: account_b - Cloudflare Tunnel. Consumed by the tunnels layer only.
#
#   terraform -chdir=layers/tunnels plan \
#     -var-file=../../accounts/account_b/account.tfvars \
#     -var-file=../../accounts/account_b/zones.tfvars \
#     -var-file=../../accounts/account_b/tunnels.tfvars
#
# See accounts/account_a/tunnels.tfvars for the fuller worked example.
#
# A single office tunnel publishing the wiki, which the "Internal Wiki" Access
# application in zerotrust.tfvars protects, plus a route to the office LAN.

cloudflare_tunnels = {
  office = {
    name = "office-01"

    ingress = [
      {
        hostname = "wiki.example.net"
        zone_key = "primary"
        service  = "http://wiki.internal:8080"
      },
    ]
  }
}

tunnel_routes = {
  office_lan = {
    network    = "10.60.0.0/16"
    tunnel_key = "office"
    comment    = "Office LAN"
  }
}
