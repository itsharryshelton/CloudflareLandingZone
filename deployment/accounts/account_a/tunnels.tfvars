# Account: account_a - Cloudflare Tunnel. Consumed by the tunnels layer only.
#
#   terraform -chdir=layers/tunnels plan \
#     -var-file=../../accounts/account_a/account.tfvars \
#     -var-file=../../accounts/account_a/zones.tfvars \
#     -var-file=../../accounts/account_a/tunnels.tfvars
#
# THE CONNECTOR TOKEN IS NOT IN THIS FILE, IN STATE, OR IN ANY OUTPUT ON PURPOSE.
#
# Public hostnames here are reachable from the internet unless an Access
# application in zerotrust.tfvars covers them. 
# Grafana example below is paired with the "Grafana" application in zerotrust.tfvars

cloudflare_tunnels = {
  london_dc = {
    name = "lon-dc-01"

    # In evaluation order: the first match wins, so the path-specific rule sits
    ingress = [
      {
        hostname = "grafana.example.com"
        zone_key = "primary"
        path     = "^/api/"
        service  = "http://grafana-api.internal:3000"
      },
      {
        hostname = "grafana.example.com"
        zone_key = "primary"
        service  = "http://grafana.internal:3000"

        # Make cloudflared check the Access token itself, so a request that
        # reached the tunnel without passing Access is refused at the origin.
        # The AUD tag is the zerotrust layer's access_applications output:
        #
        #   origin_request = {
        #     access = {
        #       team_name = "account-a"
        #       aud_tags  = ["<Grafana application AUD tag>"]
        #     }
        #   }
      },
      {
        hostname = "metrics.example.com"
        zone_key = "primary"
        service  = "https://prometheus.internal:9090"

        # A privately signed origin
        origin_request = {
          ca_pool            = "/etc/cloudflared/internal-ca.pem"
          origin_server_name = "prometheus.internal"
        }
      },
    ]
  }

  # Private network only: no public hostnames, just the routes below. WARP
  # clients reach the Manchester DC ranges through it.
  manchester_dc = {
    name = "man-dc-01"
  }
}

# Both data centres number their server VLAN 172.16.10.0/24. Manchester's copy
# goes in a virtual network of its own so the two routes do not collide.
tunnel_virtual_networks = {
  manchester = {
    name    = "man-dc"
    comment = "Manchester DC - overlaps London's server range"
  }
}

tunnel_routes = {
  london_servers = {
    network    = "172.16.10.0/24"
    tunnel_key = "london_dc"
    comment    = "London DC server VLAN"
  }

  manchester_servers = {
    network             = "172.16.10.0/24"
    tunnel_key          = "manchester_dc"
    virtual_network_key = "manchester"
    comment             = "Manchester DC server VLAN"
  }

  manchester_management = {
    network             = "172.16.20.0/24"
    tunnel_key          = "manchester_dc"
    virtual_network_key = "manchester"
    comment             = "Manchester DC out-of-band management"
  }
}
