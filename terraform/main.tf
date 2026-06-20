terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project
  region  = var.region
  zone    = var.zone
}

# --- Persistent data disk ---

resource "google_compute_disk" "data" {
  name = "fleet-memory-data"
  type = "pd-standard"
  size = var.data_disk_size_gb
  zone = var.zone
}

# --- Snapshot schedule (daily, 30-day retention) ---

resource "google_compute_resource_policy" "daily_snapshots" {
  name   = "fleet-memory-daily-snapshots"
  region = var.region

  snapshot_schedule_policy {
    schedule {
      daily_schedule {
        days_in_cycle = 1
        start_time    = "04:00"
      }
    }
    retention_policy {
      max_retention_days    = 30
      on_source_disk_delete = "KEEP_AUTO_SNAPSHOTS"
    }
  }
}

resource "google_compute_disk_resource_policy_attachment" "data_snapshots" {
  name = google_compute_resource_policy.daily_snapshots.name
  disk = google_compute_disk.data.name
  zone = var.zone
}

# --- Firewall: deny all inbound (Tailscale bypasses via userspace) ---

resource "google_compute_firewall" "deny_all_inbound" {
  name    = "fleet-memory-deny-all"
  network = "default"

  direction = "INGRESS"
  priority  = 1000

  deny {
    protocol = "all"
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["fleet-memory"]
}

# Allow SSH from GCP IAP (for emergency access via gcloud compute ssh)
resource "google_compute_firewall" "allow_iap_ssh" {
  name    = "fleet-memory-allow-iap-ssh"
  network = "default"

  direction = "INGRESS"
  priority  = 900

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # IAP's IP range
  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["fleet-memory"]
}

# --- Cloud NAT (outbound internet without external IP) ---

resource "google_compute_router" "fleet_memory" {
  name    = "fleet-memory-router"
  network = "default"
  region  = var.region
}

resource "google_compute_router_nat" "fleet_memory" {
  name                               = "fleet-memory-nat"
  router                             = google_compute_router.fleet_memory.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

# --- VM ---

resource "google_compute_instance" "fleet_memory" {
  name         = "fleet-memory"
  machine_type = var.machine_type
  zone         = var.zone

  tags = ["fleet-memory"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 50
    }
  }

  attached_disk {
    source      = google_compute_disk.data.self_link
    device_name = "fleet-memory-data"
  }

  network_interface {
    network = "default"
    # No external IP — outbound via Cloud NAT, inbound via Tailscale
  }

  metadata_startup_script = templatefile("${path.module}/startup.sh", {
    tailscale_auth_key = var.tailscale_auth_key
  })

  service_account {
    scopes = ["cloud-platform"]
  }

  allow_stopping_for_update = true
}
