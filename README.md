# 🔐 Google Cloud OpenVPN Server with IAP Authentication

A production-ready Terraform module that deploys a secure OpenVPN server on Google Cloud Platform with Identity-Aware Proxy (IAP) authentication. This module enables users to securely access their VPN using Google Workspace credentials.

## 🌟 Features

- **Secure Authentication**: Integrates with Google Cloud IAP for robust authentication
- **Automated Setup**: One-click deployment of all necessary infrastructure
- **Cost-Optimized**: Defaults to e2-micro instance type for cost-effective deployment
- **Production-Ready**: Includes all necessary security configurations and best practices
- **Easy Management**: Automatic OVPN configuration file generation
- **Custom Networking**: Dedicated VPC network and subnet configuration

## 📋 Prerequisites

- Terraform >= 1.0
- Google Cloud Project with billing enabled
- Domain verified with Google Workspace
- Service Account with necessary permissions
- Custom OpenVPN image built and available in your project (see Dependencies section)

## 🔄 Dependencies

This module requires a custom OpenVPN server image to be available in your GCP project. The image should be built using:
- [ansible-openvpn](https://github.com/ranson21/ansible-openvpn) - Ansible playbook for building the OpenVPN server image

Before using this module, ensure you have:
1. Cloned and configured the ansible-openvpn repository
2. Built and pushed the OpenVPN server image to your GCP project
3. Verified the image is available with the family name `vpn-server`

```bash
# Quick setup of dependencies
git clone https://github.com/ranson21/ansible-openvpn.git
cd ansible-openvpn
# Follow the repository's README for build instructions
```

## 🚀 Quick Start

1. Configure your Google Cloud provider:

```hcl
provider "google" {
  project = "your-project-id"
  region  = "us-central1"
}
```

2. Create a basic VPN server:

```hcl
module "vpn_server" {
  source = "github.com/ranson21/tf-gcp-ovpn"

  project_id     = "your-project-id"
  client_id      = "your-oauth-client-id"
  support_email  = "admin@yourdomain.com"
  allowed_domain = "yourdomain.com"
  domain_name    = "vpn.yourdomain.com"
}
```

## 📝 Required Inputs

| Name           | Description                            | Type   |
| -------------- | -------------------------------------- | ------ |
| project_id     | GCP Project ID                         | string |
| client_id      | OAuth 2.0 Client ID for IAP            | string |
| support_email  | Support email for OAuth consent screen | string |
| allowed_domain | Authorized domain for authentication   | string |
| domain_name    | DNS name for the VPN server            | string |

## 📊 Optional Inputs

| Name          | Description               | Type   | Default       |
| ------------- | ------------------------- | ------ | ------------- |
| region        | GCP Region                | string | "us-central1" |
| network_name  | Name prefix for network   | string | "vpn-network" |
| subnet_cidr   | CIDR range for VPN subnet | string | "10.0.1.0/24" |
| instance_type | GCP instance type         | string | "e2-micro"    |
| disk_size_gb  | Boot disk size in GB      | number | 10            |

## 📤 Outputs

| Name            | Description                         |
| --------------- | ----------------------------------- |
| vpn_server_ip   | Public IP address of the VPN server |
| vpn_portal_url  | URL of the VPN management portal    |
| network_id      | ID of the VPC network               |
| subnet_id       | ID of the subnet                    |
| oauth_client_id | OAuth client ID (sensitive)         |

## 🔒 Security Features

- IAP authentication for management portal access
- Dedicated VPC network with custom subnet
- Minimal firewall rules (only required ports)
- SSL certificate management through Secret Manager
- Service account with minimal required permissions

## 🛠️ Architecture

The module creates the following core components:
- VPC Network & Subnet
- OpenVPN Server Instance
- IAP OAuth Configuration
- Firewall Rules
- Secret Manager for SSL Certificates

## 📜 License

This module is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 👤 Author

Abigail Ranson
- Website: [abbyranson.com](https://abbyranson.com)
- GitHub: [@ranson21](https://github.com/ranson21)