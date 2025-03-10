# Spot Nodes in AKS - Setup and Configuration Guide

## Overview
Spot node pools offer cost-effective compute by using surplus Azure capacity with the trade-off of potential eviction. This guide outlines a dual node pool approach:
- **Spot Node Pool:** Uses discounted spot VMs.
- **Fallback Node Pool:** Uses regular VMs to ensure workload continuity.

## Prerequisites
- Azure CLI installed and configured
- kubectl installed
- Sufficient subscription permissions

### Environment Variables
Before starting, configure the following environment variables:
```
export RESOURCE_GROUP="aks-spot-rg"
export CLUSTER_NAME="aks-spot-cluster"
```

## Setup Instructions

### 1. Prepare the Infrastructure
- **Initialize Terraform:**  
  Command: 
  ```
  terraform init
  ```  
  Description: Initializes the Terraform working directory and downloads necessary plugins.

- **Plan Changes:**  
  Command:
  ```
  terraform plan
  ```  
  Description: Previews the planned infrastructure changes.

- **Apply Changes:**  
  Command:
  ```
  terraform apply
  ```  
  Description: Deploys the AKS cluster with configured node pools.

### 2. Configure AKS and Deploy the Application
- **Retrieve AKS Credentials:**  
  Command:
  ```
  az aks get-credentials --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME
  ```  
  Description: Fetches cluster credentials for kubectl management.

- **Create the Demo Namespace:**  
  Command:
  ```
  kubectl create namespace demo
  ```  
  Description: Establishes a dedicated namespace for the sample application.

- **Deploy the Sample Application:**  
  Command:
  ```
  kubectl apply -R -f ./sample-app/ --namespace demo
  ```  
  Description: Deploys all sample application manifests into the "demo" namespace.

### 3. Manage Node Pools and Validate Deployment
- **Verify Pod Deployment:**  
  Command:
  ```
  kubectl get pods -o wide --namespace demo
  ```  
  Description: Checks that all pods are running and displays their node pool assignments.

- **Stop the Spot Node Pool:**  
  Command:
  ```
  az aks nodepool scale --resource-group $RESOURCE_GROUP --cluster-name $CLUSTER_NAME --name spot --node-count 0
  ```  
  Description: Scales down the spot node pool to simulate a shutdown.

- **Restart the Spot Node Pool:**  
  Command:
  ```
  az aks nodepool scale --resource-group $RESOURCE_GROUP --cluster-name $CLUSTER_NAME --name spot --node-count 1
  ```  
  Description: Scales the spot node pool back to one node.

- **Install Kubernetes Descheduler:**  
  Command:
  ```
  kubectl create -f descheduler/rbac.yaml
  kubectl create -f descheduler/configmap.yaml
  kubectl create -f descheduler/job.yaml
  ```  
  Description: Deploys Descheduler components to periodically rebalance pods across nodes.

- **Review Pod Distribution:**  
  Command:
  ```
  kubectl get pods -o wide --namespace demo
  ```  
  Description: Confirms balanced workload scheduling across node pools.

## Additional Information

### Cluster & Node Pool Creation
A setup script is provided to:
- Create an AKS cluster.
- Configure a spot node pool with custom taints and labels.
- Set up a fallback node pool using regular VMs.

### Application Deployment Details
The sample application demonstrates:
- How to target spot nodes using appropriate pod tolerations.
- A fallback mechanism leveraging node affinity with preferred scheduling.

### Terraform Configuration
Use the provided Terraform files for infrastructure-as-code deployment.

### Best Practices
- Implement Pod Disruption Budgets (PDBs) for critical workloads.
- Set proper resource requests and limits.
- Use multi-replica deployments instead of standalone pods.
- Manage graceful shutdown to adhere to the 30-second eviction notice.

### Troubleshooting
- **Pods Pending:** Verify node capacity and tolerations.
- **Eviction Issues:** Ensure PDBs do not block pod evictions.
- **Cost Monitoring:** Use Azure Cost Management to analyze VM usage patterns.
