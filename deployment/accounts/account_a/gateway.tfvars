# Account: account_a - Cloudflare Gateway (Secure Web Gateway).
#
# A baseline meant to be dropped onto a new account and then edited.
#
# Three enforcement pipelines: dns, network and http each have their own precedence sequence
# Gateway stops at the first allow or block it matches within one.
#
# Precedence below 100 is reserved for the platform baseline in
# layers/gateway/locals.gateway.tf. The bands used below are:
#
#   dns      100-199   resolver-level blocks
#   network  100-199   L4 blocks, each allow immediately above the block it exempts
#   http     100-199   inspection decisions and SaaS tenant control
#            200-299   content and payload blocks
#            300-399   isolation
#            400+      acceptable use
#
# NAMES ARE RESOLVED AT PLAN TIME. Every category and application below is named
# rather than numbered, and the layer resolves it against this account's own
# Cloudflare catalogue. A name Cloudflare does not publish fails the plan and
# prints the list of valid names, so a rename on Cloudflare's side is a
# failed plan rather than a rule that quietly matches nothing. Expect to correct
# one or two of these on first apply.
#
# EDIT before this is a real baseline:
#   - gateway_dlp_profile_ids            the UUIDs from this account's DLP profiles
#   - allow_sanctioned_smtp_relay        the relay address
#   - allow_sanctioned_admin_endpoints   the bastion ranges
#   - restrict_microsoft_365_tenants     the tenant, then enable
#   - restrict_google_workspace_tenants  the domain, then enable
#   - allow_sanctioned_software_sources  the download mirrors this estate uses

# Platform baseline

gateway_baseline_policies = [
  "block_security_threats",
  "block_security_threats_http",
  "block_dlp_matches",
  "quarantine_risky_downloads",
]

# The core threat set, blocked at DNS and again at HTTP by the two baseline
# Overrides the platform default in layers/gateway/defaults.auto.tfvars.
gateway_security_categories = [
  "Command and Control & Botnet",
  "Malware",
  "Phishing",
  "Cryptomining",
  "Spyware",
  "Spam",
  "DGA Domains",
  "DNS Tunneling",
  "Anonymizer",
]

# Nothing is exempted from inspection by the baseline
# The account-level pair at HTTP 100/110 does it instead.
gateway_bypass_applications = []

# EDIT. DLP profiles are defined in the Zero Trust dashboard under DLP and
# referenced by UUID - Cloudflare exposes no way to resolve one by name. Until
# these are this account's real profiles, the baseline DLP rule matches whatever
# the placeholder happens to be, which is nothing.
gateway_dlp_profile_ids = [
  "33333333-3333-3333-3333-333333333333",
]

# Executables and archives are detonated in Cloudflare's sandbox before delivery.
# Kept short: quarantine makes the user wait for the scan. The sandbox accepts a
# fixed set of formats and "dll" and "scr" are not among them.
gateway_quarantine_file_types = ["exe", "zip", "rar"]

# Acceptable use rather than security, so there is no default that suits every
# organisation. Populate it and add "block_disallowed_content" to
# gateway_baseline_policies to switch the baseline content rule on. 
# Example Categories: "Adult Themes", "Gambling", "Violence", "Weapons" etc.
gateway_blocked_content_categories = []

# Account policies
gateway_policies = {

  # DNS Policies

  # DNS filtering is not a control a determined client has to cooperate with.
  # A browser or a piece of malware that speaks DNS-over-HTTPS to somebody else's
  # resolver never asks Gateway, so every policy in this builder is skipped.
  # This rule removes the resolvers by name; the network rules at 140 and 150
  # remove the ones reached by address.
  block_public_dns_resolvers = {
    name        = "Block third-party DNS resolvers"
    type        = "dns"
    action      = "block"
    precedence  = 100
    description = "DNS-over-HTTPS and DNS-over-TLS providers, which a client can use to route around every other rule in this builder"

    # `domains` matches the domain and every subdomain of it.
    match = {
      domains = [
        "dns.google",
        "cloudflare-dns.com",
        "one.one.one.one",
        "dns.quad9.net",
        "doh.opendns.com",
        "dns.nextdns.io",
        "dns.adguard-dns.com",
        "doh.cleanbrowsing.org",
        "doh.dns.sb",
        "dns.alidns.com",
      ]
    }

    settings = {
      block_reason       = "DNS resolution must go through your organisation's resolver."
      block_page_enabled = true
    }
  }

  # Newly registered and newly seen domains
  block_newly_registered_domains = {
    name        = "Block newly registered domains"
    type        = "dns"
    action      = "block"
    precedence  = 110
    description = "Domains registered or first seen in the last 30 days, before any reputation exists for them"

    match = {
      content_categories = ["New Domains", "Newly Seen Domains"]
    }

    settings = {
      block_reason       = "This domain was registered too recently to be trusted."
      block_page_enabled = true
    }
  }

  # Peer to Peer File Sharing Block Policy
  block_peer_to_peer = {
    name        = "Block peer-to-peer file sharing"
    type        = "dns"
    action      = "block"
    precedence  = 120
    description = "Peer-to-peer trackers and clients. Tor and the commercial VPN providers are already covered by the Anonymizer security category in the baseline"

    match = {
      content_categories = ["Peer-to-Peer"]
    }

    settings = {
      block_reason       = "Peer-to-peer file sharing is not permitted on this network."
      block_page_enabled = true
    }
  }

  # Aggressive Blocking of Known Bad Domains - Not designed for mass URL Deployment
  block_known_bad_domains = {
    name        = "Block known bad domains"
    type        = "dns"
    action      = "block"
    precedence  = 130
    description = "Domains this account has decided not to resolve, beyond what the security categories already cover"

    # Use `hosts` for one exact name rather than a domain and its subdomains.
    match = {
      domains = ["a-really-bad-website.net"]
    }

    settings = {
      block_reason       = "This domain is blocked by your organisation."
      block_page_enabled = true
    }
  }

  # =============================================================================
  # NETWORK (L4) - ports, protocols, addresses and the TLS SNI.
  # 
  # The allow/block pairs below are the shape to copy: Gateway stops at the first
  # allow or block that matches, so an exemption is a policy with a lower
  # precedence than the block it carves out of, not a negation inside the block.

  # EDIT: the relay address.
  allow_sanctioned_smtp_relay = {
    name        = "Allow the sanctioned SMTP relay"
    type        = "network"
    action      = "allow"
    precedence  = 100
    description = "Mail submission to the relay the organisation runs"

    match = {
      destination_ip_cidrs = ["203.0.113.25/32"]
      destination_ports    = [587]
      protocols            = ["tcp"]
    }
  }

  block_direct_smtp = {
    name        = "Block direct outbound SMTP"
    type        = "network"
    action      = "block"
    precedence  = 110
    description = "Outbound mail that does not go through the relay - the usual sign of a compromised host or an application nobody registered"

    match = {
      destination_ports = [25, 465, 587]
      protocols         = ["tcp"]
    }

    settings = {
      block_reason = "Outbound mail must go through the organisation's relay."
    }
  }

  # EDIT: the bastion ranges, before the block below it is applied to an estate
  # that administers anything over SSH or RDP. As shipped this allows a
  # documentation range, which permits nothing real - the effect is that 130
  # blocks all outbound administrative traffic.
  allow_sanctioned_admin_endpoints = {
    name        = "Allow sanctioned administrative endpoints"
    type        = "network"
    action      = "allow"
    precedence  = 120
    description = "SSH and RDP to the jump hosts the organisation operates, exempted from the block below"

    match = {
      destination_ip_cidrs = ["198.51.100.0/24"]
      destination_ports    = [22, 3389]
      protocols            = ["tcp"]
    }
  }

  # Reverse shells leave over 22, ransomware moves over 445, and Telnet carries
  # its credentials in clear text. None of the four has a legitimate destination
  # on the public internet that is not a jump host somebody registered above.
  block_insecure_admin_ports = {
    name        = "Block outbound administrative ports"
    type        = "network"
    action      = "block"
    precedence  = 130
    description = "SSH, Telnet, SMB and RDP bound for arbitrary internet hosts"

    match = {
      destination_ports = [22, 23, 445, 3389]
      protocols         = ["tcp"]
    }

    settings = {
      block_reason = "Administrative protocols may only be used towards the organisation's jump hosts."
    }
  }

  # DNS-over-TLS and DNS-over-QUIC both use 853, and neither has a use on an estate whose resolver is Cloudflare One.
  block_encrypted_dns_transports = {
    name        = "Block DNS-over-TLS and DNS-over-QUIC"
    type        = "network"
    action      = "block"
    precedence  = 140
    description = "Encrypted DNS to a resolver that is not Gateway, on the transport that does not need a hostname to work"

    match = {
      destination_ports = [853]
      protocols         = ["tcp", "udp"]
    }

    settings = {
      block_reason = "DNS resolution must go through your organisation's resolver."
    }
  }

  # The other half of the resolver problem: a client that dials 8.8.8.8 or
  # 1.1.1.1 directly never resolves a hostname, so the DNS rule at 100 never
  # sees it. Port 443 is here because that is the DoH port; port 53 because
  # plaintext DNS to a third party is the same bypass with less effort.
  #
  # Confirm that on a pilot device before a wide rollout.
  block_third_party_resolver_addresses = {
    name        = "Block third-party resolvers by address"
    type        = "network"
    action      = "block"
    precedence  = 150
    description = "The public resolver addresses, on both the DNS and the DNS-over-HTTPS port, for clients that skip resolution entirely"

    match = {
      destination_ip_cidrs = [
        "8.8.8.8/32",
        "8.8.4.4/32",
        "1.1.1.1/32",
        "1.0.0.1/32",
        "9.9.9.9/32",
        "149.112.112.112/32",
        "208.67.222.222/32",
        "208.67.220.220/32",
        "94.140.14.14/32",
        "94.140.15.15/32",
      ]
      destination_ports = [53, 443]
      protocols         = ["tcp", "udp"]
    }

    settings = {
      block_reason = "DNS resolution must go through your organisation's resolver."
    }
  }

  # Tor relays and the BitTorrent range. Ports are a weak signal on their own -
  # both protocols can be run anywhere, but this catches the common misconfigurations
  block_p2p_and_tor_ports = {
    name        = "Block peer-to-peer and Tor ports"
    type        = "network"
    action      = "block"
    precedence  = 160
    description = "The default BitTorrent range and the Tor relay and SOCKS ports"

    match = {
      destination_ports = [
        6881, 6882, 6883, 6884, 6885, 6886, 6887, 6888, 6889,
        9001, 9030, 9050, 9051,
      ]
      protocols = ["tcp", "udp"]
    }

    settings = {
      block_reason = "Peer-to-peer and anonymising tunnels are not permitted on this network."
    }
  }

  # =============================================================================
  # HTTP - The decrypted L7 request.

  # Inspection is decided before anything else, in the order these two are written:
  # The first policy that matches decides whether the connection is decrypted.
  inspect_saas_authentication_endpoints = {
    name        = "Inspect SaaS authentication endpoints"
    type        = "http"
    action      = "on"
    precedence  = 100
    description = "Sign-in endpoints stay decrypted so tenant restriction headers can be added to them, even though the rest of the application is bypassed below"

    match = {
      hosts = [
        "login.microsoftonline.com",
        "login.microsoft.com",
        "login.windows.net",
        "accounts.google.com",
      ]
    }
  }

  # Microsoft 365 outside the sign-in endpoints: certificate pinning and
  # client-side TLS behaviour break under inspection, so it is bypassed.
  bypass_trusted_applications = {
    name        = "Do not inspect trusted applications"
    type        = "http"
    action      = "off"
    precedence  = 110
    description = "TLS inspection bypass for applications that cannot tolerate it"

    match = {
      applications = ["Microsoft 365"]
    }
  }

  # EDIT the tenant, then set enabled = true. Shipped off because a wrong tenant
  # here is not a misconfiguration that goes unnoticed - it is every Microsoft
  # sign-in on the estate refused.
  #
  # Microsoft reads these headers to decide which tenants a sign-in may use, so
  # Gateway adding them is what stops a corporate device signing into a personal
  # or a supplier's Microsoft 365 account. Restrict-Access-To-Tenants lists the
  # permitted tenants; Restrict-Access-Context is the tenant ID whose policy
  # applies - yours.
  #
  # This is an allow, so it is terminal for these hosts: no HTTP policy below it
  # is reached for a Microsoft sign-in. That is intended here, and it is the
  # thing to check before adding hosts to it.
  restrict_microsoft_365_tenants = {
    name        = "Restrict Microsoft 365 to corporate tenants"
    type        = "http"
    action      = "allow"
    precedence  = 120
    description = "Tenant restriction headers injected into Microsoft sign-in, so a corporate device cannot sign into a personal or third-party tenant"
    enabled     = false

    match = {
      hosts = [
        "login.microsoftonline.com",
        "login.microsoft.com",
        "login.windows.net",
      ]
    }

    settings = {
      add_headers = {
        "Restrict-Access-To-Tenants" = ["contoso.onmicrosoft.com"]
        "Restrict-Access-Context"    = ["00000000-0000-0000-0000-000000000000"]
      }
    }
  }

  # EDIT the domain, then set enabled = true. Same warning as above: the wrong
  # value locks the estate out of Google rather than failing quietly.
  #
  # Google applies the restriction across its properties rather than only at the
  # sign-in page, which is why this matches the domain and every subdomain of it.
  # That breadth is also why it is worth being deliberate: an allow on
  # google.com means no HTTP policy below this one applies to Google at all,
  # including the download and upload blocks at 210 and 220.
  restrict_google_workspace_tenants = {
    name        = "Restrict Google Workspace to corporate domains"
    type        = "http"
    action      = "allow"
    precedence  = 130
    description = "X-GoogApps-Allowed-Domains injected into Google traffic, so a corporate device cannot sign into a personal Google account"
    enabled     = false

    match = {
      domains = ["google.com"]
    }

    settings = {
      add_headers = {
        "X-GoogApps-Allowed-Domains" = ["contoso.com"]
      }
    }
  }

  # EDIT: the mirrors this estate actually installs software from. Sits above the
  # download block so that a sanctioned source is still usable - and note that
  # this exempts those domains from everything below it, not only from the
  # download block. The baseline quarantine rule at HTTP precedence 40 still
  # applies, so an executable from these domains is still detonated first.
  allow_sanctioned_software_sources = {
    name        = "Allow downloads from sanctioned software sources"
    type        = "http"
    action      = "allow"
    precedence  = 200
    description = "The download mirrors and vendor sites the organisation installs software from, exempted from the executable block below"

    match = {
      domains = ["example.org"]
    }
  }

  # Execution payloads from arbitrary web sources. The scripting formats matter
  # as much as the installers here: a .ps1 or a .vbs is the first stage of most
  # of what arrives by browser.
  #
  # Cloudflare matches a fixed set of file types, so an extension it does not
  # recognise is rejected at apply rather than silently ignored.
  block_high_risk_downloads = {
    name        = "Block high-risk file downloads"
    type        = "http"
    action      = "block"
    precedence  = 210
    description = "Installers and scripting payloads downloaded from anywhere that is not a sanctioned source"

    match = {
      download_file_types = ["exe", "msi", "iso", "ps1", "vbs", "bat"]
    }

    settings = {
      block_reason = "Executable downloads are only permitted from the organisation's sanctioned software sources."
    }
  }

  # Corporate material pasted or uploaded into a tool nobody has assessed. The
  # block is on the upload rather than on the site, so reading and asking
  # questions still works and putting a document into it does not.
  #
  # If "Generative AI" does not resolve against this account's catalogue, the
  # plan prints the applications Cloudflare does publish - the alternative is to
  # name the individual tools, or to match `content_categories` instead.
  block_uploads_to_generative_ai = {
    name        = "Block uploads to unsanctioned generative AI"
    type        = "http"
    action      = "block"
    precedence  = 220
    description = "Document and source uploads into generative AI tools the organisation has not assessed"

    match = {
      applications      = ["Generative AI"]
      upload_file_types = ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "csv", "zip"]
    }

    settings = {
      block_reason = "Uploading files to this tool is not permitted. Use an approved service."
    }
  }

  block_uploads_to_unmanaged_storage = {
    name        = "Block uploads to unmanaged storage"
    type        = "http"
    action      = "block"
    precedence  = 230
    description = "Files leaving for storage the organisation does not control"

    # Destination terms are OR'd; the file-type constraint is AND'd against them.
    match = {
      domains           = ["example.org"]
      upload_file_types = ["pdf", "docx", "xlsx"]
    }

    settings = {
      block_reason = "Files may only be uploaded to storage the organisation manages."
    }
  }

  # The softer half of the newly-registered-domain problem. Isolation renders the
  # page in Cloudflare's browser and streams the result, so a drive-by exploit
  # runs somewhere that is not the endpoint and the user still gets to the site.
  #
  # Needs Browser Isolation on the account's Zero Trust plan; without it the
  # policy applies and the traffic is not isolated.
  isolate_low_reputation_sites = {
    name        = "Isolate low-reputation sites"
    type        = "http"
    action      = "isolate"
    precedence  = 300
    description = "New, newly seen and parked domains rendered in Cloudflare's browser rather than on the endpoint"

    match = {
      content_categories = ["New Domains", "Newly Seen Domains", "Parked & For Sale Domains"]
    }
  }

  isolate_contractor_browsing = {
    name        = "Isolate contractor browsing"
    type        = "http"
    action      = "isolate"
    precedence  = 310
    description = "Contractors browse through Browser Isolation, so nothing executes on their device"

    # No traffic selector at all: this policy is scoped by who the user is rather
    # than by where they are going.
    identity = {
      user_group_names = ["Contractors"]
    }
  }

  # Acceptable use rather than security, and off by default because it is the one
  # rule here that people will notice. Out of hours, and only on weekdays.
  block_streaming_during_work_hours = {
    name        = "Block streaming during work hours"
    type        = "http"
    action      = "block"
    precedence  = 400
    description = "Bandwidth management rather than security"
    enabled     = false

    match = {
      domains = ["example.com"]
    }

    schedule = {
      time_zone = "Europe/London"
      mon       = "09:00-12:30,13:30-17:30"
      tue       = "09:00-12:30,13:30-17:30"
      wed       = "09:00-12:30,13:30-17:30"
      thu       = "09:00-12:30,13:30-17:30"
      fri       = "09:00-12:30,13:30-17:30"
    }
  }
}
