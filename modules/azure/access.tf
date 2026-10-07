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

  # Subject names as the API server derives them: the raw group id, and the username prefix before an object id.
  entra_user_name = { for id in concat(var.entra_oidc.admin_object_ids, var.entra_oidc.reader_object_ids) : id => "${coalesce(var.entra_oidc.username_prefix, "")}${id}" }
  entra_admin_subjects = concat(
    [for id in var.entra_oidc.admin_group_object_ids : { apiGroup = "rbac.authorization.k8s.io", kind = "Group", name = id }],
    [for id in var.entra_oidc.admin_object_ids : { apiGroup = "rbac.authorization.k8s.io", kind = "User", name = local.entra_user_name[id] }],
  )
  entra_reader_subjects = [for id in var.entra_oidc.reader_object_ids : { apiGroup = "rbac.authorization.k8s.io", kind = "User", name = local.entra_user_name[id] }]

  # Applied by every server from its manifests directory, so the first Entra login already has its rights.
  entra_access_manifests = var.entra_oidc.enabled && length(concat(local.entra_admin_subjects, local.entra_reader_subjects)) > 0 ? {
    "entra-access.yaml" = join("---\n", concat(
      length(local.entra_admin_subjects) == 0 ? [] : [yamlencode({
        apiVersion = "rbac.authorization.k8s.io/v1"
        kind       = "ClusterRoleBinding"
        metadata   = { name = "entra-cluster-admins" }
        roleRef    = { apiGroup = "rbac.authorization.k8s.io", kind = "ClusterRole", name = "cluster-admin" }
        subjects   = local.entra_admin_subjects
      })],
      length(local.entra_reader_subjects) == 0 ? [] : [
        yamlencode({
          apiVersion = "rbac.authorization.k8s.io/v1"
          kind       = "ClusterRoleBinding"
          metadata   = { name = "entra-readers" }
          roleRef    = { apiGroup = "rbac.authorization.k8s.io", kind = "ClusterRole", name = "view" }
          subjects   = local.entra_reader_subjects
        }),
        # Terraform plans refresh Helm releases, which live in kube-system Secrets that view does not cover.
        yamlencode({
          apiVersion = "rbac.authorization.k8s.io/v1"
          kind       = "Role"
          metadata   = { name = "entra-readers-helm-releases", namespace = "kube-system" }
          rules      = [{ apiGroups = [""], resources = ["secrets"], verbs = ["get", "list", "watch"] }]
        }),
        yamlencode({
          apiVersion = "rbac.authorization.k8s.io/v1"
          kind       = "RoleBinding"
          metadata   = { name = "entra-readers-helm-releases", namespace = "kube-system" }
          roleRef    = { apiGroup = "rbac.authorization.k8s.io", kind = "Role", name = "entra-readers-helm-releases" }
          subjects   = local.entra_reader_subjects
        }),
      ],
    ))
  } : {}

  # Kubeconfig for people and pipelines: no secret in it, kubelogin fetches the token.
  kubeconfig_entra = var.entra_oidc.enabled ? yamlencode({
    apiVersion = "v1"
    kind       = "Config"
    clusters = [{
      name = var.name
      cluster = {
        server                       = local.cluster_endpoint
        "certificate-authority-data" = base64encode(module.bootstrap.server_ca_certificate)
      }
    }]
    users = [{
      name = "entra"
      user = {
        exec = {
          apiVersion         = local.kube_exec.api_version
          command            = local.kube_exec.command
          args               = local.kube_exec.args
          env                = null
          interactiveMode    = "IfAvailable"
          provideClusterInfo = false
        }
      }
    }]
    contexts          = [{ name = var.name, context = { cluster = var.name, user = "entra" } }]
    "current-context" = var.name
  }) : null
}
