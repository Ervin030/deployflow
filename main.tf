# =============================================================================
# Template Scriban : main.tf.scriban
# Description : G├⌐n├¿re dynamiquement un fichier main.tf Terraform
#               en fonction de la configuration YAML du client.
#
# Variables disponibles :
#   - client       : nom du client
#   - environment  : environnement (dev, staging, prod)
#   - services     : dictionnaire des services demand├⌐s
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
  }
}

# =============================================================================
# Authentification Azure CLI
# L'utilisateur doit ├¬tre connect├⌐ via 'az login' avant d'ex├⌐cuter Terraform.
# La souscription active est d├⌐finie via 'az account set'.
# =============================================================================

# --- Provider Azure ---
# Authentification via Azure CLI (azurerm v4+)
provider "azurerm" {
  features {}
  resource_provider_registrations = "none"
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

# =============================================================================
# Module : Network (toujours inclus)
# Le r├⌐seau est le socle de toute l'infrastructure
# =============================================================================
module "network" {
  source = "../../modules/azure-network"

  client      = "deploy"
  environment = "dev"
}

# =============================================================================
# Module : PostgreSQL
# D├⌐pend du module network pour le resource group et la localisation
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
# Outputs
# =============================================================================
output "resource_group_name" {
  description = "Nom du Resource Group"
  value       = module.network.resource_group_name
}
output "postgres_server_fqdn" {
  description = "FQDN du serveur PostgreSQL"
  value       = module.postgres.server_fqdn
}
