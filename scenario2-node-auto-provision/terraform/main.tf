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
  description = "Name of the Azure resource group for AKS"
  type        = string
  default     = "aks-nap-rg"
}
variable "location" {
  description = "Azure region for the resources"
  type        = string
  default     = "centralus"  # change as needed
}
variable "aks_cluster_name" {
  description = "Name of the AKS cluster"
  type        = string
  default     = "aks-nap-cluster"
}
variable "kubernetes_version" {
  description = "Kubernetes version for the AKS cluster"
  type        = string
  default     = "1.30.9"  # AKS Kubernetes version 1.30
}
variable "default_node_vm_size" {
  description = "VM size for the default (system) node pool"
  type        = string
  default     = "Standard_D2s_v5"
}
variable "spot_node_vm_size" {
  description = "VM size for the spot instance node pool"
  type        = string
  default     = "Standard_D2as_v5"  # example size for spot nodes
}
variable "spot_node_count" {
  description = "Number of nodes in the spot node pool (initial count)"
  type        = number
  default     = 1  # start with 1 spot node (adjust as needed)
}
variable "spot_max_price" {
  description = "Maximum price for spot VMs (in USD/hour, -1 for current on-demand price)"
  type        = number
  default     = -1  # -1 means no cap (pay up to on-demand price)
}

############################
# Resource Group and VNet  #
############################

# Resource Group for AKS
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

# Virtual Network for AKS nodes (using Azure CNI overlay, pods use an overlay network)
resource "azurerm_virtual_network" "vnet" {
  name                = "${var.aks_cluster_name}-vnet"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.0.0.0/16"]  # VNet address range for nodes
}

# Subnet for AKS node pools
resource "azurerm_subnet" "aks_subnet" {
  name                 = "aks-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.0.0/24"]  # Subnet for AKS nodes (adjust size as needed)
  # Note: In overlay mode, pods get IPs outside this range (managed by Cilium overlay).
}

#########################################
# AKS Cluster with Node Autoprovisioning #
#########################################

resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.aks_cluster_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  kubernetes_version  = var.kubernetes_version
  dns_prefix          = var.aks_cluster_name

  identity {
    type = "SystemAssigned"  # Use a managed identity for the AKS control plane
  }

  default_node_pool {
    name                         = "system"  # system node pool for core components
    vm_size                      = var.default_node_vm_size
    node_count                   = 2
    type                         = "VirtualMachineScaleSets"
    orchestrator_version         = var.kubernetes_version
    vnet_subnet_id               = azurerm_subnet.aks_subnet.id
    only_critical_addons_enabled = true  # taint to run only critical add-ons
    # Do NOT enable cluster autoscaler here (NAP will handle scaling)
    upgrade_settings {
      drain_timeout_in_minutes      = 0
      max_surge                     = "10%"
      node_soak_duration_in_minutes = 0
    }
  }

  network_profile {
    network_plugin      = "azure"    # Azure CNI plugin
    network_plugin_mode = "overlay"  # enable overlay
    network_policy      = "cilium"   # use Cilium for network policy
    network_data_plane   = "cilium"   # use Cilium dataplane (ebpf)
    dns_service_ip      = "10.2.0.10"    # (optional) DNS IP for cluster service
    service_cidr        = "10.2.0.0/24"  # (optional) Service CIDR
    # Note: Pod CIDR is managed by Cilium overlay (can be left to default)
  }

  # (Optional) Add-ons or other settings can go here (omitted for brevity)
  tags = {
    Environment = "Demo-NAP"
  }
}

# Enable Node Autoprovisioning (NAP) via the AzAPI provider (preview feature)
resource "azapi_update_resource" "enable_nap" {
  type                    = "Microsoft.ContainerService/managedClusters@2024-09-02-preview"
  resource_id             = azurerm_kubernetes_cluster.aks.id
  ignore_missing_property = true
  body = {
    properties = {
      nodeProvisioningProfile = {
        mode = "Auto"  # Enable automatic node provisioning (Karpenter)
      }
    }
  }
  depends_on = [azurerm_kubernetes_cluster.aks]
}

#######################################
# Spot Instance Node Pool (User Pool) #
#######################################

/* resource "azurerm_kubernetes_cluster_node_pool" "spot_pool" {
  name                  = "spotpool"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks.id
  vm_size               = var.spot_node_vm_size
  node_count            = var.spot_node_count
  mode                  = "User"               # user node pool for workloads
  orchestrator_version  = var.kubernetes_version
  availability_zones    = ["1", "2", "3"]      # deploy across zones if region supports
  priority              = "Spot"              # use Spot instances for cost efficiency
  eviction_policy       = "Delete"            # delete VMs if evicted (default for Spot)
  spot_max_price        = var.spot_max_price  # maximum price for Spot VM (in USD/hour)
  vnet_subnet_id        = azurerm_subnet.aks_subnet.id
  # No autoscaler -- NAP will handle scaling needs for unschedulable pods.
  depends_on            = [azapi_update_resource.enable_nap] 
  # (ensure NAP is enabled before using this pool for scaling decisions)
} */

#####################################################
# Grant Network Contributor role to AKS identity    #
# (Required for Karpenter/NAP to manage network)    #
#####################################################

# Use the cluster's system-assigned identity to manage new node network interfaces
resource "azurerm_role_assignment" "aks_vnet_network_contributor" {
  scope                = azurerm_virtual_network.vnet.id
  role_definition_name = "Network Contributor"
  # Assign to the AKS cluster's managed identity principal:
  principal_id         = azurerm_kubernetes_cluster.aks.identity[0].principal_id
  # If using a user-assigned identity, use azurerm_user_assigned_identity.id instead.
}
