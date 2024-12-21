# Google Cloud OpenVPN Server with OAuth Authentication

This Terraform module deploys an OpenVPN server on Google Cloud Platform with Google OAuth authentication integration. Users can authenticate using their Google Cloud credentials and automatically receive their OVPN configuration files.

## Features

- OpenVPN server with Google OAuth authentication
- Identity-Aware Proxy (IAP) integration
- Automatic OVPN file generation
- Custom VPC network and subnet configuration
- Firewall rules for secure access
- Cost-optimized instance configuration

## Usage

```hcl
module "vpn_server" {
  source = "./modules/gcp-oauth-vpn"

  project_id      = "your-project-id"
  region         = "us-central1"
  support_email  = "admin@yourdomain.com"
  domain         = "yourdomain.com"
}
```

## Requirements

| Name      | Version |
| --------- | ------- |
| terraform | >= 1.0  |
| google    | >= 4.0  |

## Providers

| Name   | Version |
| ------ | ------- |
| google | >= 4.0  |

## Resources Created

- VPC Network and Subnet
- OpenVPN Server Instance
- IAP OAuth Configuration
- Firewall Rules
- DNS Records (optional)

## Inputs

| Name           | Description                                 | Type   | Required | Default       |
| -------------- | ------------------------------------------- | ------ | -------- | ------------- |
| project_id     | GCP Project ID                              | string | yes      | -             |
| project_number | GCP Project Number                          | string | yes      | -             |
| region         | GCP Region                                  | string | no       | "us-central1" |
| support_email  | Support email for OAuth consent screen      | string | yes      | -             |
| domain         | Authorized domain for Google authentication | string | yes      | -             |
| instance_type  | GCP instance type                           | string | no       | "e2-micro"    |
| network_name   | Name of the VPC network                     | string | no       | "vpn-network" |
| subnet_cidr    | CIDR range for the VPN subnet               | string | no       | "10.0.1.0/24" |

## Outputs

| Name           | Description                         |
| -------------- | ----------------------------------- |
| vpn_server_ip  | Public IP address of the VPN server |
| vpn_portal_url | URL of the VPN management portal    |
| network_id     | ID of the created VPC network       |
| subnet_id      | ID of the created subnet            |

## 📄 License

This module is licensed under the MIT License. See LICENSE for full details.

## 👤 Author

Abigail Ranson
- Website: [abbyranson.com](https://abbyranson.com)
- GitHub: [@ranson21](https://github.com/ranson21)