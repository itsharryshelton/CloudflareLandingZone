# Cloudflare Notifications: which events are sent where.
#
# Its own layer rather than part of each product's, because one policy can watch
# several of them and every one sends to the same small set of destinations. A
# webhook declared here is shared by every policy that names it; spreading the
# policies across waf, zones and load_balancing would mean either duplicating
# the destinations or having layers read each other's state.
#
# It also keeps the credential where it can be scoped. A chat webhook URL is the
# credential for that channel, and this layer's token and state are the only
# places that hold it.
#
# What this layer cannot check is whether anybody is listening. See
# modules/notifications/main.tf, and the notification_webhooks output.
#
# Downstream deployments pin an immutable tag instead of the local path:
#   source = "git::https://github.com/Your-Org/cloudflare-platform-modules//notifications?ref=v1.0.0"
module "notifications" {
  source = "../../../modules/notifications"

  account_id = var.cloudflare_account_id

  webhooks = local.webhooks

  # From notifications.tfvars or TF_VAR_notification_webhook_secrets, never
  # both - see locals.tf.
  webhook_urls    = local.webhook_urls
  webhook_secrets = local.webhook_secrets

  policies = local.policies
}
