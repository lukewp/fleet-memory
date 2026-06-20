variable "project" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone"
  type        = string
  default     = "us-central1-a"
}

variable "machine_type" {
  description = "VM machine type"
  type        = string
  default     = "e2-standard-2"
}

variable "data_disk_size_gb" {
  description = "Size of the persistent data disk in GB"
  type        = number
  default     = 100
}

variable "tailscale_auth_key" {
  description = "Tailscale auth key (ephemeral or reusable). Generate at https://login.tailscale.com/admin/settings/keys"
  type        = string
  sensitive   = true
}
