run "offline_path_reaches_each_role" {
  command = plan
  variables {
    install_artifact_path = "/opt/rke2/artifacts"
    agent_pools           = { default = {} }
  }
  assert {
    condition = (
      strcontains(output.server_user_data.init_candidate, "INSTALL_ARTIFACT_PATH=/opt/rke2/artifacts") &&
      strcontains(output.server_user_data.member, "INSTALL_ARTIFACT_PATH=/opt/rke2/artifacts") &&
      strcontains(output.agent_user_data["default"], "INSTALL_ARTIFACT_PATH=/opt/rke2/artifacts")
    )
    error_message = "Every node role must receive the local artifact path."
  }
}
