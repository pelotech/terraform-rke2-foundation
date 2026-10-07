locals {
  entra_oidc_issuer_url = coalesce(var.entra_oidc.issuer_url, "https://${local.azure_cloud.entra_login_host}/${data.azurerm_client_config.current.tenant_id}/v2.0")

  entra_oidc_apiserver_args = var.entra_oidc.enabled ? [
    for flag, value in {
      "oidc-issuer-url"      = local.entra_oidc_issuer_url
      "oidc-client-id"       = var.entra_oidc.client_id
      "oidc-username-claim"  = var.entra_oidc.username_claim
      "oidc-groups-claim"    = var.entra_oidc.groups_claim
      "oidc-username-prefix" = var.entra_oidc.username_prefix
    } : "${flag}=${value}" if value != null
  ] : []

  # The block the AKS foundation emits, with the consumer's app registration as the audience.
  kube_exec = var.entra_oidc.enabled ? {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "kubelogin"
    args        = ["get-token", "--login", var.kube_exec_login_mode, "--server-id", var.entra_oidc.client_id, "--environment", local.azure_cloud.environment]
    env         = {}
  } : null
}
