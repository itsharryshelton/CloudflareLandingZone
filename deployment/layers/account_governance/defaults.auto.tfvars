# Layer account_governance - platform baseline. Auto-loaded from this directory.

# Least privilege by default
default_role_names = ["Minimal Account Access"]

# Roles this layer refuses to assign, by name or by ID - added Super Admin as very high risk permission.
restricted_role_names = ["Super Administrator - All Privileges"]

# Domains a member may be invited from, for example ["example.com"]. Empty allows
# any domain. Set this per deployment wherever the account should only ever be
# reachable by staff of one organisation.
allowed_email_domains = []
