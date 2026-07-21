output "grafana_url" {
  value       = data.grafana_cloud_stack.this.url
  description = "Grafana UI URL for this stack (used later for dashboards)."
}

output "otlp_url" {
  value       = data.grafana_cloud_stack.this.otlp_url
  description = "OTLP gateway base URL Alloy forwards to."
}

output "otlp_instance_id" {
  value       = data.grafana_cloud_stack.this.id
  description = "OTLP basic-auth username (stack id)."
}

output "alloy_token" {
  value       = grafana_cloud_access_policy_token.alloy.token
  sensitive   = true
  description = "Alloy write token. `just sync-token` pipes this into 1Password; never written to a file."
}
