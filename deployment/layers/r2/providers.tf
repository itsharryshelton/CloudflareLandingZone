#The token is read from CLOUDFLARE_API_TOKEN
#
# Minimum token scope for this layer: Account Workers R2 Storage:Edit, which
# covers the bucket itself and every configuration object hanging off it - CORS,
# lifecycle, object lock and the r2.dev public URL.
#
# Custom domains need two more, and only if var.r2_buckets declares any:
#   Zone:Read     so data.cloudflare_zone can resolve a domain to its ID
#   Zone DNS:Edit because attaching a custom domain writes the record that points
#                 the hostname at the bucket
#
# The token does NOT need Zone:Edit, and it deliberately grants nothing over
# object data: R2 object reads and writes go through an S3 access key, which is a
# separate credential this layer neither creates nor holds. Terraform manages the
# bucket; the application owns what is in it.
provider "cloudflare" {}
