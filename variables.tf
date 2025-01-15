# ---------------------------------------------------------------------------------------------------------------------
# REQUIRED VARIABLES
# ---------------------------------------------------------------------------------------------------------------------

variable "project_id" {
  description = "The ID of the GCP project"
  type        = string
}

variable "client_id" {
  description = "The OAuth 2.0 Client ID for IAP authentication"
  type        = string
}

variable "support_email" {
  description = "Support email address for OAuth consent screen"
  type        = string
}

variable "allowed_domain" {
  description = "Authorized domain for Google authentication (e.g., example.com)"
  type        = string
}

variable "domain_name" {
  description = "DNS name for the OpenVPN server (e.g., vpn.example.com)"
  type        = string
}

# ---------------------------------------------------------------------------------------------------------------------
# OPTIONAL VARIABLES
# ---------------------------------------------------------------------------------------------------------------------

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
