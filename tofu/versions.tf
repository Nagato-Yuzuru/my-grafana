terraform {
  required_version = ">= 1.7.0"

  required_providers {
    grafana = {
      source  = "grafana/grafana"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }

  # State + plan encrypted at rest (AES-GCM). The passphrase arrives as
  # TF_VAR_state_passphrase, which `op run` resolves from 1Password — so the only
  # secret in state (the write token) is never on disk in plaintext.
  encryption {
    key_provider "pbkdf2" "state" {
      passphrase = var.state_passphrase
    }
    method "aes_gcm" "state" {
      keys = key_provider.pbkdf2.state
    }
    state {
      method = method.aes_gcm.state
    }
    plan {
      method = method.aes_gcm.state
    }
  }
}
