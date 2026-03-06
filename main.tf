# =============================================================================
# Template Scriban : main.tf.scriban
# Description : Génère dynamiquement un fichier main.tf Terraform
#               en fonction de la configuration YAML du client.
#
# Variables disponibles :
#   - client       : nom du client
#   - environment  : environnement (dev, staging, prod)
#   - services     : dictionnaire des services demandés
# =============================================================================# =============================================================================
# Configuration Terraform
# =============================================================================
terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

# =============================================================================
# Authentification Azure CLI
# L'utilisateur doit être connecté via 'az login' avant d'exécuter Terraform.
# La souscription active est définie via 'az account set'.
# =============================================================================

# --- Provider Azure ---
# Authentification via Azure CLI (azurerm v4+)
provider "azurerm" {
  features {}
  resource_provider_registrations = "none"
}

# --- Provider Kubernetes ---
# Configuré dynamiquement à partir des credentials AKS
provider "kubernetes" {
  host                   = module.aks.kube_config_host
  client_certificate     = base64decode(module.aks.kube_config_client_certificate)
  client_key             = base64decode(module.aks.kube_config_client_key)
  cluster_ca_certificate = base64decode(module.aks.kube_config_cluster_ca_certificate)
}

# =============================================================================
# Variables
# =============================================================================
variable "postgres_admin_password" {
  description = "Mot de passe administrateur PostgreSQL"
  type        = string
  sensitive   = true
  default     = "P@ssw0rd2024!"
}
variable "odoo_image_token" {
  description = "Token d'authentification pour l'image Docker Odoo Enterprise"
  type        = string
  sensitive   = true
}

# =============================================================================
# Module : Network (toujours inclus)
# Le réseau est le socle de toute l'infrastructure
# =============================================================================
module "network" {
  source = "../../modules/azure-network"

  client      = "deploy"
  environment = "dev"
}

# =============================================================================
# Module : AKS (Kubernetes)
# Dépend du module network pour le subnet
# =============================================================================
module "aks" {
  source = "../../modules/azure-aks"

  client              = "deploy"
  environment         = "dev"
  location            = module.network.resource_group_location
  resource_group_name = module.network.resource_group_name
  subnet_id           = module.network.subnet_id
  node_count          = 2

  depends_on = [module.network]
}

# =============================================================================
# Module : PostgreSQL
# Dépend du module network pour le resource group et la localisation
# =============================================================================
module "postgres" {
  source = "../../modules/azure-postgres"

  client              = "deploy"
  environment         = "dev"
  location            = module.network.resource_group_location
  resource_group_name = module.network.resource_group_name
  admin_password      = var.postgres_admin_password

  depends_on = [module.network]
}

# =============================================================================
# Module : Odoo (ERP - déployé via Kubernetes natif)
# Image Docker officielle odoo:18.0
# =============================================================================
module "odoo" {
  source = "../../modules/odoo-helm"

  postgres_host     = module.postgres.server_fqdn
  postgres_user     = "pgadmin"
  postgres_password = var.postgres_admin_password
  postgres_database = module.postgres.database_name
  edition           = "enterprise"
  image_url         = "ghcr.io/cellenza-lu/lu.cellenza.deployflow.infra/odoo-enterprise:19.0"
  image_token       = var.odoo_image_token

  depends_on = [module.aks, module.postgres]
}

# =============================================================================
# Outputs
# =============================================================================
output "resource_group_name" {
  description = "Nom du Resource Group"
  value       = module.network.resource_group_name
}
output "aks_cluster_name" {
  description = "Nom du cluster AKS"
  value       = module.aks.cluster_name
}
output "postgres_server_fqdn" {
  description = "FQDN du serveur PostgreSQL"
  value       = module.postgres.server_fqdn
}
output "odoo_namespace" {
  description = "Namespace Odoo"
  value       = module.odoo.namespace
}
