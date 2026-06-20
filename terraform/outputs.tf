output "instance_name" {
  value = google_compute_instance.fleet_memory.name
}

output "instance_zone" {
  value = google_compute_instance.fleet_memory.zone
}

output "tailscale_hostname" {
  value = "fleet-memory"
}

output "ssh_command" {
  value = "gcloud compute ssh ubuntu@${google_compute_instance.fleet_memory.name} --zone=${var.zone}"
}

output "cognee_api" {
  value = "http://fleet-memory:8000"
}

output "cognee_mcp" {
  value = "http://fleet-memory:8001"
}
