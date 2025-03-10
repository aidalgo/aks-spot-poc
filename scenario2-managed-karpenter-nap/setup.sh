#!/bin/bash

# Set variables
RESOURCE_GROUP="aks-spot-poc-rg"
CLUSTER_NAME="aks-spot-poc-cluster"
LOCATION="eastus"
NODE_POOL_NAME="spot-pool"
FALLBACK_NODE_POOL_NAME="fallback-pool"

# Create resource group
az group create --name $RESOURCE_GROUP --location $LOCATION

# Create AKS cluster with managed Karpenter
az aks create --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME --enable-managed-identity --node-count 0 --enable-addons monitoring --generate-ssh-keys

# Configure Karpenter
kubectl apply -f managed-karpenter-config.yaml

# Create node auto-provisioning configuration
kubectl apply -f node-auto-provisioning.yaml

# Deploy sample application
kubectl apply -f sample-app/deployment.yaml
kubectl apply -f sample-app/service.yaml
kubectl apply -f sample-app/pod-disruption-budget.yaml

echo "AKS cluster with managed Karpenter setup completed."