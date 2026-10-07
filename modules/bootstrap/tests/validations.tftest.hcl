# Input validations. Every run expects a failure on exactly one variable.

run "rke2_version_must_be_a_full_release" {
  command = plan
  variables {
    rke2_version = "1.37.1"
  }
  expect_failures = [var.rke2_version]
}

run "rke2_version_must_be_1_36_or_newer" {
  command = plan
  variables {
    rke2_version = "v1.35.9+rke2r1"
  }
  expect_failures = [var.rke2_version]
}

run "cni_must_be_known" {
  command = plan
  variables {
    cni = "weave"
  }
  expect_failures = [var.cni]
}

run "disable_components_must_be_packaged" {
  command = plan
  variables {
    disable_components = ["rke2-ingress-nginx"]
  }
  expect_failures = [var.disable_components]
}

run "ingress_controller_must_be_known" {
  command = plan
  variables {
    ingress_controller = "nginx"
  }
  expect_failures = [var.ingress_controller]
}

run "server_taints_follow_the_taint_format" {
  command = plan
  variables {
    server_taints = ["bad"]
  }
  expect_failures = [var.server_taints]
}

run "agent_pool_taints_follow_the_taint_format" {
  command = plan
  variables {
    agent_pools = { general = { taints = ["bad"] } }
  }
  expect_failures = [var.agent_pools]
}

run "extra_server_config_must_be_a_map" {
  command = plan
  variables {
    extra_server_config = "cni: none"
  }
  expect_failures = [var.extra_server_config]
}

run "extra_agent_config_must_be_a_map" {
  command = plan
  variables {
    extra_agent_config = "cni: none"
  }
  expect_failures = [var.extra_agent_config]
}

run "bootstrap_wait_seconds_has_a_floor" {
  command = plan
  variables {
    bootstrap_wait_seconds = 5
  }
  expect_failures = [var.bootstrap_wait_seconds]
}
