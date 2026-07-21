# Read the existing stack to discover its OTLP endpoint, instance id, and region.
data "grafana_cloud_stack" "this" {
  slug = var.stack_slug
}

# A least-privilege, write-only policy for the local Alloy collector.
resource "grafana_cloud_access_policy" "alloy" {
  region       = data.grafana_cloud_stack.this.region_slug
  name         = "claude-code-alloy"
  display_name = "Claude Code Alloy writer"
  scopes       = ["metrics:write", "logs:write", "traces:write"]

  realm {
    type       = "stack"
    identifier = data.grafana_cloud_stack.this.id
  }
}

resource "grafana_cloud_access_policy_token" "alloy" {
  region           = grafana_cloud_access_policy.alloy.region
  access_policy_id = grafana_cloud_access_policy.alloy.policy_id
  name             = "claude-code-alloy"
  display_name     = "Claude Code Alloy writer token"
}
