variable "project_id" {
  description = "The ID of the GCP project"
  type        = string
}

variable "client_id" {
  description = "The OAUTH 2.0 Client ID for the web app"
  type        = string
}

variable "region" {
  description = "The GCP region where resources will be created"
  type        = string
  default     = "us-central1"
}

variable "network_name" {
  description = "Name prefix for network resources"
  type        = string
  default     = "vpn-network"
}

variable "subnet_cidr" {
  description = "CIDR range for the VPN subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "instance_type" {
  description = "The machine type for the VPN server"
  type        = string
  default     = "e2-micro"
}

variable "disk_size_gb" {
  description = "Size of the boot disk in GB"
  type        = number
  default     = 10
}

variable "support_email" {
  description = "Support email for OAuth consent screen"
  type        = string
}

variable "domain" {
  description = "Authorized domain for Google authentication"
  type        = string
}

variable "portal_title" {
  description = "Title for the VPN portal"
  type        = string
  default     = "OpenVPN Access Portal"
}
