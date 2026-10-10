# The registries config is a node secret for every role; the registry CA travels in cloud-init.

run "registries_are_fetched_by_every_role" {
  command = plan
  variables {
    agent_pools       = { default = {} }
    registries_config = "mirrors: {}\n"
    registry_ca_pem   = "-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----\n"
  }
  assert {
    condition     = output.server_secret_paths["rke2-registries"] == "registries.yaml" && output.agent_secret_paths["rke2-registries"] == "registries.yaml"
    error_message = "both roles fetch the registries config as a secret"
  }
  assert {
    condition     = strcontains(output.server_user_data.member, "rke2-registries=registries.yaml") && strcontains(output.agent_user_data["default"], "rke2-registries=registries.yaml")
    error_message = "the env file lists the registries secret for servers and agents"
  }
  assert {
    condition     = strcontains(output.server_user_data.member, "/etc/rancher/rke2/registry-ca.pem") && strcontains(output.agent_user_data["default"], "/etc/rancher/rke2/registry-ca.pem") && !strcontains(output.agent_user_data["default"], "mirrors: {}")
    error_message = "the CA is a cloud-init file and the config never is"
  }
}

run "registries_are_optional" {
  command = plan
  variables {
    agent_pools = { default = {} }
  }
  assert {
    condition     = !contains(keys(output.server_secret_paths), "rke2-registries") && !contains(keys(output.agent_secret_paths), "rke2-registries") && !strcontains(output.agent_user_data["default"], "registry-ca.pem")
    error_message = "without registries_config nothing is fetched or written"
  }
}
