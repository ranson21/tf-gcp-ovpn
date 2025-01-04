# Network Resources
resource "google_compute_network" "vpn_network" {
  name                    = var.network_name
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "vpn_subnet" {
  name          = "${var.network_name}-subnet"
  ip_cidr_range = var.subnet_cidr
  network       = google_compute_network.vpn_network.id
  region        = var.region
}

# Project Data Source
data "google_project" "current" {
  project_id = var.project_id
}

# IAP Resources
resource "google_iap_client" "project_client" {
  display_name = "OpenVPN Client"
  brand        = "projects/${data.google_project.current.number}/brands/${data.google_project.current.number}"
}

resource "google_iap_web_iam_binding" "binding" {
  project = var.project_id
  role    = "roles/iap.httpsResourceAccessor"
  members = [
    "domain:${var.allowed_domain}",
    "serviceAccount:${google_compute_instance.vpn_server.service_account[0].email}"
  ]
}

# IP Address
resource "google_compute_address" "vpn_ip" {
  name   = "${var.network_name}-ip"
  region = var.region
}

# Server Image
data "google_compute_image" "vpn_server" {
  family  = "vpn-server"
  project = var.project_id
}

# Instance Configuration
resource "google_compute_instance" "vpn_server" {
  name         = "${var.network_name}-server"
  machine_type = var.instance_type
  zone         = "${var.region}-a"

  boot_disk {
    initialize_params {
      image = data.google_compute_image.vpn_server.self_link
      size  = var.disk_size_gb
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.vpn_subnet.id
    access_config {
      nat_ip = google_compute_address.vpn_ip.address
    }
  }

  metadata = {
    server_admin   = var.support_email
    client_id      = var.client_id
    allowed_domain = var.allowed_domain
    domain_name    = var.domain_name
  }

  service_account {
    scopes = ["cloud-platform"]
  }

  tags = ["vpn-server"]

  metadata_startup_script = <<EOF
    systemctl start runtime-config
  EOF

  allow_stopping_for_update = true
}

# Firewall Rules
resource "google_compute_firewall" "vpn_server" {
  name    = "${var.network_name}-allow-vpn"
  network = google_compute_network.vpn_network.name

  allow {
    protocol = "udp"
    ports    = ["1194"]
  }

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["vpn-server"]
}

resource "google_compute_firewall" "vpn_server_ssh" {
  name    = "${var.network_name}-allow-ssh"
  network = google_compute_network.vpn_network.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["vpn-server"]
}

resource "google_compute_firewall" "vpn_server_icmp" {
  name    = "${var.network_name}-allow-icmp"
  network = google_compute_network.vpn_network.name

  allow {
    protocol = "icmp"
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["vpn-server"]
}

resource "google_compute_firewall" "health_check" {
  name    = "${var.network_name}-allow-health-check"
  network = google_compute_network.vpn_network.name

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }

  source_ranges = [
    "35.191.0.0/16",
    "130.211.0.0/22"
  ]

  target_tags = ["vpn-server"]
}

# Health Check and Backend Service
resource "google_compute_health_check" "vpn_health_check" {
  name               = "${var.network_name}-health-check"
  timeout_sec        = 5
  check_interval_sec = 10

  https_health_check {
    port         = "443"
    request_path = "/health"
  }

  unhealthy_threshold = 3
  healthy_threshold   = 2
}

resource "google_compute_backend_service" "vpn_portal" {
  name        = "${var.network_name}-portal"
  port_name   = "https"
  protocol    = "HTTPS"
  timeout_sec = 10

  health_checks = [google_compute_health_check.vpn_health_check.id]

  backend {
    group = google_compute_instance_group.vpn_group.self_link
  }

  iap {
    oauth2_client_id     = google_iap_client.project_client.client_id
    oauth2_client_secret = google_iap_client.project_client.secret
  }
}

# Instance Group
resource "google_compute_instance_group" "vpn_group" {
  name      = "${var.network_name}-group"
  zone      = "${var.region}-a"
  instances = [google_compute_instance.vpn_server.self_link]

  named_port {
    name = "https"
    port = 443
  }
}
