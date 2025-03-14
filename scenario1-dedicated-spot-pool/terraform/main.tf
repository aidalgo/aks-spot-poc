terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      # Use the latest azurerm provider version that supports AKS 1.30
      version = "=4.23.0"
    }
    azapi = {
      source  = "azure/azapi"
      # AzAPI provider is used to enable the preview Node Autoprovisioning feature
      version = "=2.3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

provider "azapi" {
  # (no configuration needed for azapi)
}

#######################
# Terraform Variables #
#######################

variable "resource_group_name" {
  description = "Name of the resource group to create or use for AKS"
  type        = string
  default     = "aks-spot-rg"
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "centralus"
}

variable "aks_cluster_name" {
  description = "Name of the AKS cluster"
  type        = string
  default     = "aks-spot-cluster"
}

variable "kubernetes_version" {
  description = "Kubernetes version for the AKS cluster"
  type        = string
  default     = "1.30.9"
}

variable "node_vm_size" {
  description = "VM size for nodes in all node pools"
  type        = string
  default     = "Standard_D2s_v5"
}

############################
# Resource Group and VNet  #
############################

resource "azurerm_resource_group" "aks_rg" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_virtual_network" "aks_vnet" {
  name                = "${var.aks_cluster_name}-vnet"
  location            = var.location
  resource_group_name = azurerm_resource_group.aks_rg.name
  address_space       = ["10.0.0.0/16"]  # VNet address range for nodes
}

resource "azurerm_subnet" "aks_system_subnet" {
  name                 = "${var.aks_cluster_name}-subnet"
  resource_group_name  = azurerm_resource_group.aks_rg.name
  virtual_network_name = azurerm_virtual_network.aks_vnet.name
  address_prefixes     = ["10.0.1.0/24"]  # Subnet for AKS nodes (adjust size as needed)
}

resource "azurerm_subnet" "aks_fallback_subnet" {
  name                 = "${var.aks_cluster_name}-subnet"
  resource_group_name  = azurerm_resource_group.aks_rg.name
  virtual_network_name = azurerm_virtual_network.aks_vnet.name
  address_prefixes     = ["10.0.2.0/24"]  # Subnet for AKS nodes (adjust size as needed)
}

resource "azurerm_subnet" "aks_spot_subnet" {
  name                 = "${var.aks_cluster_name}-subnet"
  resource_group_name  = azurerm_resource_group.aks_rg.name
  virtual_network_name = azurerm_virtual_network.aks_vnet.name
  address_prefixes     = ["10.0.3.0/24"]  # Subnet for AKS nodes (adjust size as needed)
}

#########################################
# AKS Cluster with Node Pools           #
#########################################

resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.aks_cluster_name
  location            = var.location
  resource_group_name = azurerm_resource_group.aks_rg.name
  kubernetes_version  = var.kubernetes_version

  dns_prefix          = "${var.aks_cluster_name}"  # DNS name prefix for the AKS API server

  identity {
    type = "SystemAssigned"  # Enable managed identity for AKS
  }

  # System node pool (default pool)
  default_node_pool {
    name                = "system"
    vm_size             = var.node_vm_size
    auto_scaling_enabled = true
    min_count           = 1
    max_count           = 3
    node_count          = 1                   # initial node count (within min/max)
    vnet_subnet_id      = azurerm_subnet.aks_system_subnet.id
    only_critical_addons_enabled = true # Enable only critical add-ons (e.g., kube-proxy, CoreDNS)
  }

  # Network configuration: kubenet + Calico
  network_profile {
    network_plugin    = "kubenet"
    network_policy    = "calico"
    dns_service_ip      = "10.2.0.10"    # (optional) DNS IP for cluster service
    service_cidr        = "10.2.0.0/24"  # (optional) Service CIDR
  }

  # Enable Web Application Routing add-on for managed ingress
  web_app_routing {
    dns_zone_ids = []  # Use an auto-generated DNS zone (no custom DNS zone)
  }

  tags = {
    Environment = "Dev"
    AKSCluster  = var.aks_cluster_name
  }
}

#######################################
# Spot Instance Node Pool (User Pool) #
#######################################

resource "azurerm_kubernetes_cluster_node_pool" "spot" {
  name                  = "spot"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks.id
  vm_size               = var.node_vm_size
  mode                  = "User"
  orchestrator_version  = var.kubernetes_version

  auto_scaling_enabled   = true
  min_count             = 1
  max_count             = 3
  node_count            = 1

  priority              = "Spot"                       # Use Spot instances for this pool
  eviction_policy       = "Delete"                     # Delete VMs if evicted (do not count against quota)
  spot_max_price        = -1                           # -1 means no max price limit (pay market price)

  vnet_subnet_id        = azurerm_subnet.aks_spot_subnet.id

  # Taint and label to designate Spot nodes (so workloads only use them if tolerated)
  node_labels = {
    "kubernetes.azure.com/scalesetpriority" = "spot"
  }
  node_taints = [
    "kubernetes.azure.com/scalesetpriority=spot:NoSchedule"
  ]

  tags = {
    Environment = "Dev"
    PoolType    = "Spot"
  }
}

#######################################
# Fallback Node Pool (User Pool)      #
#######################################

resource "azurerm_kubernetes_cluster_node_pool" "fallback" {
  name                  = "fallback"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks.id
  vm_size               = var.node_vm_size
  mode                  = "User"
  orchestrator_version  = var.kubernetes_version

  auto_scaling_enabled   = true
  min_count             = 1
  max_count             = 3
  node_count            = 1

  # This pool uses regular priority (on-demand VMs) by default
  vnet_subnet_id        = azurerm_subnet.aks_fallback_subnet.id

  # Taint and label to designate Spot nodes (so workloads only use them if tolerated)
  node_labels = {
    "scalepriority" = "fallback"
  }

  tags = {
    Environment = "Dev"
    PoolType    = "Fallback"
  }
}
