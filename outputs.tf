# ---------------------------------------------------------------------------------------------------------------------
# OUTPUTS
# ---------------------------------------------------------------------------------------------------------------------

# Network Outputs
output "network_id" {
  description = "The ID of the VPC network"
  value       = google_compute_network.vpn_network.id
}

output "subnet_id" {
  description = "The ID of the subnet"
  value       = google_compute_subnetwork.vpn_subnet.id
}

# VPN Server Outputs
output "vpn_server_ip" {
  description = "The public IP address of the VPN server"
  value       = google_compute_address.vpn_ip.address
}

output "vpn_portal_url" {
  description = "The URL of the VPN management portal"
  value       = "https://${google_compute_address.vpn_ip.address}"
}

output "instance_name" {
  description = "The name of the VPN server instance"
  value       = google_compute_instance.vpn_server.name
}

# IAP Outputs
output "oauth_client_id" {
  description = "The OAuth client ID for IAP authentication"
  value       = google_iap_client.project_client.client_id
  sensitive   = true
}
