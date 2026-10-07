# The custom CA set RKE2 reads before first start, the join tokens, the admin credential and the
# secret names the cloud module stores.

run "ca_set" {
  command = plan
  assert {
    condition     = length(tls_self_signed_cert.ca) == 5 && alltrue([for c in tls_self_signed_cert.ca : c.is_ca_certificate])
    error_message = "server, client, request-header, etcd peer and etcd server CAs, all CA certificates"
  }
  assert {
    condition     = alltrue([for k in tls_private_key.ca : k.algorithm == "ECDSA" && k.ecdsa_curve == "P256"])
    error_message = "CA keys are ECDSA P-256, as RKE2 generates itself"
  }
  assert {
    condition     = tls_private_key.service_account.algorithm == "RSA" && tls_private_key.service_account.rsa_bits == 2048
    error_message = "the service account signing key is RSA 2048"
  }
  assert {
    condition     = tls_self_signed_cert.ca["server_ca"].subject[0].common_name == "platformdev-server-ca" && tls_self_signed_cert.ca["server_ca"].validity_period_hours == 87600
    error_message = "CA common names carry the cluster name; ten year validity by default"
  }
  assert {
    condition     = tls_self_signed_cert.ca["etcd_peer_ca"].subject[0].common_name == "platformdev-etcd-peer-ca"
    error_message = "etcd CAs are named by their role"
  }
}

run "admin_credential" {
  command = plan
  assert {
    condition     = tls_cert_request.admin.subject[0].common_name == "system:admin" && tls_cert_request.admin.subject[0].organization == "system:masters"
    error_message = "the admin certificate is system:admin in system:masters"
  }
  assert {
    condition     = tls_locally_signed_cert.admin.validity_period_hours == 8760 && tls_locally_signed_cert.admin.early_renewal_hours == 720 && contains(tls_locally_signed_cert.admin.allowed_uses, "client_auth")
    error_message = "one year validity, renewed thirty days early, client auth"
  }
}

run "pki_validity_is_configurable" {
  command = plan
  variables {
    pki = { ca_validity_hours = 1000, admin_validity_hours = 100, admin_early_renewal_hours = 10 }
  }
  assert {
    condition     = tls_self_signed_cert.ca["client_ca"].validity_period_hours == 1000 && tls_locally_signed_cert.admin.validity_period_hours == 100 && tls_locally_signed_cert.admin.early_renewal_hours == 10
    error_message = "pki settings pass through"
  }
}

run "secret_names_and_paths" {
  command = plan
  assert {
    condition     = output.server_secret_paths["rke2-tls-etcd-peer-ca-key"] == "tls/etcd/peer-ca.key" && output.server_secret_paths["rke2-tls-service-key"] == "tls/service.key"
    error_message = "TLS secret names flatten the file path; paths keep the RKE2 layout under tls/"
  }
  assert {
    condition     = output.server_secret_paths["rke2-token"] == "token" && output.server_secret_paths["rke2-agent-token"] == "agent-token"
    error_message = "both tokens are server secrets"
  }
  assert {
    condition     = length(output.server_secret_paths) == 13 && output.agent_secret_paths == { "rke2-agent-token" = "agent-token" }
    error_message = "eleven TLS files plus two tokens for servers; agents only read the agent token"
  }
}

run "tokens_and_credential_contents" {
  command = apply
  assert {
    condition     = length(output.server_secret_contents["rke2-token"]) == 48 && length(output.server_secret_contents["rke2-agent-token"]) == 48 && output.server_secret_contents["rke2-token"] != output.server_secret_contents["rke2-agent-token"]
    error_message = "two distinct 48 character tokens"
  }
  assert {
    condition     = output.server_secret_contents["rke2-tls-server-ca-crt"] == output.server_ca_certificate && output.server_secret_contents["rke2-token"] == output.server_secret_contents["rke2-token"]
    error_message = "secret contents are the CA set and the tokens"
  }
  assert {
    condition     = strcontains(output.admin_client_certificate, "BEGIN CERTIFICATE") && strcontains(output.service_account_public_key, "BEGIN PUBLIC KEY")
    error_message = "PEM outputs"
  }
}
