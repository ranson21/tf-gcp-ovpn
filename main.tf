# ---------------------------------------------------------------------------------------------------------------------
# DATA SOURCES
# ---------------------------------------------------------------------------------------------------------------------
data "google_project" "current" {
  project_id = var.project_id
}

data "google_compute_image" "vpn_server" {
  family  = "vpn-server"
  project = var.project_id
}

# ---------------------------------------------------------------------------------------------------------------------
# NETWORKING
# Base networking resources including VPC and subnet
# ---------------------------------------------------------------------------------------------------------------------
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

resource "google_compute_address" "vpn_ip" {
  name   = "${var.network_name}-ip"
  region = var.region
}

# ---------------------------------------------------------------------------------------------------------------------
# SECURITY
# Secret Manager resources for SSL certificates
# ---------------------------------------------------------------------------------------------------------------------
resource "google_secret_manager_secret" "ssl_cert" {
  secret_id = "${var.network_name}-ssl-cert"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "ssl_key" {
  secret_id = "${var.network_name}-ssl-key"

  replication {
    auto {}
  }
}

# Secret Manager IAM permissions
resource "google_secret_manager_secret_iam_member" "cert_accessor" {
  secret_id = google_secret_manager_secret.ssl_cert.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_compute_instance.vpn_server.service_account[0].email}"
}

resource "google_secret_manager_secret_iam_member" "key_accessor" {
  secret_id = google_secret_manager_secret.ssl_key.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_compute_instance.vpn_server.service_account[0].email}"
}

resource "google_secret_manager_secret_iam_member" "cert_writer" {
  secret_id = google_secret_manager_secret.ssl_cert.id
  role      = "roles/secretmanager.secretVersionAdder"
  member    = "serviceAccount:${google_compute_instance.vpn_server.service_account[0].email}"
}

resource "google_secret_manager_secret_iam_member" "key_writer" {
  secret_id = google_secret_manager_secret.ssl_key.id
  role      = "roles/secretmanager.secretVersionAdder"
  member    = "serviceAccount:${google_compute_instance.vpn_server.service_account[0].email}"
}

# ---------------------------------------------------------------------------------------------------------------------
# IDENTITY-AWARE PROXY (IAP)
# IAP configuration for secure access
# ---------------------------------------------------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------------------------------------------------
# COMPUTE INSTANCE
# VPN server instance configuration
# ---------------------------------------------------------------------------------------------------------------------
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
    network_name   = var.network_name
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

# ---------------------------------------------------------------------------------------------------------------------
# FIREWALL RULES
# Network security rules for the VPN server
# ---------------------------------------------------------------------------------------------------------------------
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
