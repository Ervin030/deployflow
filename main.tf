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
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 2.1"
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

# --- Provider Helm ---
# Utilisé pour installer ArgoCD via Helm chart
provider "helm" {
  kubernetes = {
    host                   = module.aks.kube_config_host
    client_certificate     = base64decode(module.aks.kube_config_client_certificate)
    client_key             = base64decode(module.aks.kube_config_client_key)
    cluster_ca_certificate = base64decode(module.aks.kube_config_cluster_ca_certificate)
  }
}

# --- Provider kubectl ---
# Utilisé pour créer les CRDs ArgoCD Application
provider "kubectl" {
  host                   = module.aks.kube_config_host
  client_certificate     = base64decode(module.aks.kube_config_client_certificate)
  client_key             = base64decode(module.aks.kube_config_client_key)
  cluster_ca_certificate = base64decode(module.aks.kube_config_cluster_ca_certificate)
  load_config_file       = false
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
variable "keycloak_admin_password" {
  description = "Mot de passe administrateur Keycloak"
  type        = string
  sensitive   = true
  default     = "Keycloak@2024!"
}
variable "grafana_admin_password" {
  description = "Mot de passe administrateur Grafana"
  type        = string
  sensitive   = true
  default     = "Grafana@2024!"
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
  node_count          = 3

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
# Module : ArgoCD (GitOps - orchestrateur des applications)
# Installé via Helm sur le cluster AKS
# =============================================================================
module "argocd" {
  source = "../../modules/argocd"

  depends_on = [module.aks]
}

# =============================================================================
# Module : Keycloak (IAM/SSO - déployé via Kubernetes natif)
# Image Quay.io officielle keycloak:26.0
# =============================================================================
module "keycloak" {
  source = "../../modules/keycloak"

  admin_password           = var.keycloak_admin_password
  postgres_server_fqdn     = module.postgres.server_fqdn
  postgres_admin_username  = "pgadmin"
  postgres_admin_password  = var.postgres_admin_password

  depends_on = [module.aks, module.postgres]
}

# =============================================================================
# Module : Prometheus + Grafana (Monitoring - via ArgoCD)
# Chart Helm kube-prometheus-stack
# =============================================================================
module "prometheus" {
  source = "../../modules/prometheus"

  argocd_namespace       = module.argocd.namespace
  grafana_admin_password = var.grafana_admin_password

  depends_on = [module.aks, module.argocd]
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
output "argocd_namespace" {
  description = "Namespace ArgoCD"
  value       = module.argocd.namespace
}
output "keycloak_namespace" {
  description = "Namespace Keycloak"
  value       = module.keycloak.namespace
}
output "prometheus_namespace" {
  description = "Namespace Prometheus + Grafana"
  value       = module.prometheus.namespace
}
output "odoo_namespace" {
  description = "Namespace Odoo"
  value       = module.odoo.namespace
}
