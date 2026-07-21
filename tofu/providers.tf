# Cloud-level operations (read the stack, manage access policies + tokens) authenticate
# with a bootstrap Grafana Cloud Access Policy token — NOT a stack service-account token.
provider "grafana" {
  cloud_access_policy_token = var.grafana_cloud_access_policy_token
}
