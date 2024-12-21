output "vpn_server_ip" {
  description = "The public IP address of the VPN server"
  value       = google_compute_instance.vpn_server.network_interface[0].access_config[0].nat_ip
}

output "vpn_portal_url" {
  description = "The URL of the VPN management portal"
  value       = "https://${google_compute_instance.vpn_server.network_interface[0].access_config[0].nat_ip}"
}

output "network_id" {
  description = "The ID of the created VPC network"
  value       = google_compute_network.vpn_network.id
}

output "subnet_id" {
  description = "The ID of the created subnet"
  value       = google_compute_subnetwork.vpn_subnet.id
}

output "instance_name" {
  description = "The name of the VPN server instance"
  value       = google_compute_instance.vpn_server.name
}

output "instance_self_link" {
  description = "The self-link of the VPN server instance"
  value       = google_compute_instance.vpn_server.self_link
}

output "oauth_client_id" {
  description = "The OAuth client ID for the VPN portal"
  value       = google_iap_client.project_client.client_id
  sensitive   = true
}
