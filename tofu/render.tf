# tofu owns only the NON-secret Alloy env — the OTLP endpoint + instance id (SSOT from
# the stack) plus the 1Password reference for the token. No secret is written to disk;
# `op run --env-file alloy/op.env` resolves the op:// reference at launch.
resource "local_file" "alloy_env" {
  filename        = "${local.alloy_dir}/op.env"
  file_permission = "0644"
  content         = <<-EOT
    GRAFANA_CLOUD_OTLP_ENDPOINT=${data.grafana_cloud_stack.this.otlp_url}/otlp
    GRAFANA_CLOUD_INSTANCE_ID=${data.grafana_cloud_stack.this.id}
    GRAFANA_CLOUD_OTLP_TOKEN=${var.onepassword_token_ref}
  EOT
}
