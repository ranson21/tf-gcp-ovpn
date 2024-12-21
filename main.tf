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

# Add to main.tf
data "google_project" "current" {
  project_id = var.project_id
}

# Then modify the IAP brand resource
resource "google_iap_client" "project_client" {
  display_name = "OpenVPN Client"
  brand        = "projects/${data.google_project.current.number}/brands/${data.google_project.current.number}"
}

# Modify the IAP web binding to include more specific roles
resource "google_iap_web_iam_binding" "binding" {
  project = var.project_id
  role    = "roles/iap.httpsResourceAccessor"
  members = [
    "domain:${var.domain}",
    "serviceAccount:${google_compute_instance.vpn_server.service_account[0].email}"
  ]
}


# Add this to your main.tf
resource "google_compute_address" "vpn_ip" {
  name   = "${var.network_name}-ip"
  region = var.region
}

# Instance Resources
resource "google_compute_instance" "vpn_server" {
  name         = "${var.network_name}-server"
  machine_type = var.instance_type
  zone         = "${var.region}-a"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
      size  = var.disk_size_gb
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.vpn_subnet.id
    access_config {
      nat_ip = google_compute_address.vpn_ip.address
      // Ephemeral IP
    }
  }

  # metadata_startup_script = templatefile("${path.module}/templates/startup.sh", {
  #   client_id = google_iap_client.project_client.client_id
  #   domain    = var.domain
  # })

  # Add these to the instance metadata
  metadata = {
    startup-script = templatefile("${path.module}/templates/startup.sh", {
      client_id   = google_iap_client.project_client.client_id
      domain      = var.domain
      vpn_auth_py = file("${path.module}/templates/vpn_auth.py") # Add this line
    })

    # Add a timestamp to force replacement
    startup-script-timestamp = timestamp()

    # Enable OS login
    enable-oslogin = "TRUE"
  }

  service_account {
    scopes = ["cloud-platform"]
  }

  tags = ["vpn-server"]

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
    ports    = ["443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["vpn-server"]
}

# SSH Access Firewall Rule
resource "google_compute_firewall" "vpn_server_ssh" {
  name    = "${var.network_name}-allow-ssh"
  network = google_compute_network.vpn_network.name

  allow {
    protocol = "tcp"
    ports    = ["22"] # SSH
  }

  # You can restrict this to your IP or corporate network
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["vpn-server"]
}

# ICMP (ping) Firewall Rule - useful for debugging
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

  # Health checker IP ranges
  source_ranges = [
    "35.191.0.0/16",
    "130.211.0.0/22"
  ]

  target_tags = ["vpn-server"]
}

# Health Check for the Flask Auth Service
resource "google_compute_health_check" "vpn_health_check" {
  name               = "${var.network_name}-health-check"
  timeout_sec        = 5
  check_interval_sec = 10 # Increased to reduce load on the service

  https_health_check {
    port         = "443"
    request_path = "/health" # Match the Flask endpoint
  }

  # Add a longer initial delay to allow the startup script to complete
  unhealthy_threshold = 3
  healthy_threshold   = 2
}


# Modified Backend Service
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

# Add a local file resource to verify template rendering
resource "local_file" "startup_script_debug" {
  content = templatefile("${path.module}/templates/startup.sh", {
    client_id   = google_iap_client.project_client.client_id
    domain      = var.domain
    vpn_auth_py = file("${path.module}/templates/vpn_auth.py") # Add this line

  })
  filename = "${path.module}/startup-script-debug.sh"
}

# Add to your main.tf
resource "local_file" "auth_app" {
  content  = file("${path.module}/templates/vpn_auth.py") # You'll create this file
  filename = "${path.module}/generated/vpn_auth.py"
}
