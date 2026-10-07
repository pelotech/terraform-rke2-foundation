locals {
  # The CA set RKE2 reads from its TLS directory before first start. Keys are the file stem.
  cas = {
    server_ca         = "server-ca"
    client_ca         = "client-ca"
    request_header_ca = "request-header-ca"
    etcd_peer_ca      = "etcd/peer-ca"
    etcd_server_ca    = "etcd/server-ca"
  }
  tls_files = merge(
    merge([for key, file in local.cas : {
      "${file}.crt" = tls_self_signed_cert.ca[key].cert_pem
      "${file}.key" = tls_private_key.ca[key].private_key_pem
    }]...),
    { "service.key" = tls_private_key.service_account.private_key_pem },
  )

  # Every server secret once; the path and content maps the outputs expose are projections of it.
  server_secrets = merge(
    { for file, content in local.tls_files : "rke2-tls-${replace(replace(file, "/", "-"), ".", "-")}" => { path = "tls/${file}", content = content } },
    {
      "rke2-token"       = { path = "token", content = random_password.token.result }
      "rke2-agent-token" = { path = "agent-token", content = random_password.agent_token.result }
    },
  )
  server_secret_paths = { for name, secret in local.server_secrets : name => secret.path }
  agent_secret_paths  = { "rke2-agent-token" = "agent-token" }
  secret_contents     = { for name, secret in local.server_secrets : name => secret.content }
}

resource "tls_private_key" "ca" {
  for_each    = local.cas
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_self_signed_cert" "ca" {
  for_each              = local.cas
  private_key_pem       = tls_private_key.ca[each.key].private_key_pem
  is_ca_certificate     = true
  validity_period_hours = var.pki.ca_validity_hours
  allowed_uses          = ["cert_signing", "crl_signing", "digital_signature"]

  subject {
    common_name = "${var.name}-${replace(each.value, "/", "-")}"
  }
}

# RSA because the JWKS the servers publish advertises RS256.
resource "tls_private_key" "service_account" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_private_key" "admin" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_cert_request" "admin" {
  private_key_pem = tls_private_key.admin.private_key_pem

  subject {
    common_name  = "system:admin"
    organization = "system:masters"
  }
}

resource "tls_locally_signed_cert" "admin" {
  cert_request_pem      = tls_cert_request.admin.cert_request_pem
  ca_private_key_pem    = tls_private_key.ca["client_ca"].private_key_pem
  ca_cert_pem           = tls_self_signed_cert.ca["client_ca"].cert_pem
  validity_period_hours = var.pki.admin_validity_hours
  early_renewal_hours   = var.pki.admin_early_renewal_hours
  allowed_uses          = ["digital_signature", "key_encipherment", "client_auth"]
}

resource "random_password" "token" {
  length  = 48
  special = false
}

resource "random_password" "agent_token" {
  length  = 48
  special = false
}
