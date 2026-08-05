default_health_check = {
  type           = "https"
  path           = "/healthz"
  port           = 443
  method         = "GET"
  expected_codes = "2xx"

  # timeout must stay below interval or probes overlap; the module enforces it.
  interval = 60
  timeout  = 5
  retries  = 2
}
