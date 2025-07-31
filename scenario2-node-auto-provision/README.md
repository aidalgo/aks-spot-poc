# AKS Node Auto Provisioning (NAP) with Spot VMs - Setup Guide

## Overview
This proof of concept demonstrates Azure Kubernetes Service (AKS) with Node Auto Provisioning (NAP), which leverages Karpenter technology behind the scenes for dynamic, cost-efficient node management. The solution prioritizes Spot VMs for significant cost savings (up to 60-80% compared to pay-as-you-go pricing) while maintaining workload availability through intelligent node provisioning.

## About Node Auto Provisioning (NAP)
NAP is Microsoft's implementation of the Karpenter open-source project, integrated directly into AKS. It dynamically provisions nodes based on workload demands and can intelligently select between Spot and regular VMs based on configuration parameters. This setup includes advanced features for production use:

**Core Benefits:**
- **Cost optimization**: Automatically scales with the most cost-effective VM types
- **Reduced management overhead**: No need to manually configure multiple node pools
- **Faster scaling**: Directly responds to pending pods without intermediary steps
- **Spot VM integration**: Seamlessly fails over to on-demand VMs when spot capacity is unavailable

**Advanced Features in This Configuration:**
- **Pod density control**: Maximum 30 pods per node via AKSNodeClass configuration
- **Workload isolation**: Separate system and application node pools with appropriate taints
- **Business hours protection**: Consolidation budgets prevent disruptions during peak hours
- **High availability**: Dedicated on-demand system nodes for critical workloads

## Prerequisites
- Azure CLI installed and configured
- kubectl installed
- Terraform installed
- Sufficient Azure subscription permissions

### Environment Variables
Configure the following environment variables for easier command execution:
```
export RESOURCE_GROUP="aks-nap-rg"
export CLUSTER_NAME="aks-nap-cluster"
```

## Setup Instructions

### 1. Prepare the Infrastructure
- **Initialize Terraform:**  
  Command: 
  ```
  export ARM_SUBSCRIPTION_ID=<your-subscription-id>
  terraform init
  ```  
  Description: Initializes the Terraform working directory and downloads necessary plugins. If you want to change the default values, check the variables in the terraform [main file](terraform/main.tf).

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
  Description: Fetches cluster credentials for kubectl management. Make sure the variables are the same as configured in the main terraform file.

- **Create the Demo Namespace:**  
  Command:
  ```
  kubectl create namespace demo
  ```  
  Description: Creates a dedicated namespace for the sample application.

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
  Description: Checks that all pods are running and displays their node pool assignments, since the default NAP node pool doesn't use spot, you won't see spot instances until we update the nodepool configuration. If you want to check the default node pool configuration, you can use the command below:
  Command:
  ```
  kubectl get NodePool default -o yaml
  ```  

- **Examine the NAP Configuration:**
  Command:
  ```
  cat node-auto-provisioning.yaml
  ```
  Description: Review the configuration to understand how spot VMs are prioritized over regular VMs, including VM sizes, disruption configuration, and limits. The file contains both an **AKSNodeClass** (which defines node specifications like maxPods limit of 30) and a **NodePool** (which defines scaling and scheduling policies). You can also examine the system node pool configuration:
  Command:
  ```
  cat system-node-pool.yml
  ```
  Description: This shows a dedicated NodePool for system workloads with on-demand instances only and specific taints for critical add-ons. It is also possible to create multiple node pools using NAP in case you want to have more control on where to put different workloads.
  
- **Apply NAP Configuration for Spot VMs:**  
  Command:
  ```
  kubectl apply -f node-auto-provisioning.yaml
  ```  
  Description: Applies the node auto-provisioning configuration which includes both the **AKSNodeClass** (defining node specifications with maxPods: 30 limit) and the **NodePool** (defining scaling policies) to enable dynamic provisioning with spot and on-demand VMs in the same node pool. 

- **Apply System Node Pool Configuration:**  
  Command:
  ```
  kubectl apply -f system-node-pool.yml
  ```  
  Description: Applies a dedicated system node pool that uses on-demand instances only for high availability of critical system workloads. This pool has `CriticalAddonsOnly: true` taint to ensure only system pods can be scheduled on these nodes.

  Both configurations work together: Karpenter reduces cluster compute costs by continuously monitoring node utilization and making intelligent decisions to optimize resource usage. It prioritizes the use of spot VMs for application workloads and automatically falls back to on-demand VMs when spot capacity is unavailable. Additionally, Karpenter consolidates workloads onto fewer, more efficient nodes and removes under-utilized nodes to minimize expenses.

- **Monitor Node Pool Status:**  
  Command:
  ```
  kubectl get nodepools
  kubectl get aksnodeclass
  ```  
  Description: Check the status of your NodePools and AKSNodeClass. NodePools will show the number of nodes they manage (initially 0 until workloads trigger node provisioning).

- **Monitor Karpenter-Managed Nodes:**  
  Command:
  ```
  kubectl get nodes -l 'karpenter.sh/nodepool'
  kubectl get nodeclaims
  ```  
  Description: View nodes specifically managed by Karpenter and their corresponding nodeclaims. This shows the actual provisioned capacity.

- **Monitor Spot Node Creation:**  
  Command:
  ```
  kubectl get nodes -L karpenter.sh/capacity-type,node.kubernetes.io/instance-type
  ```  
  Description: Display all nodes with their capacity type (spot/on-demand) and instance type. Karpenter-managed spot nodes will have `karpenter.sh/capacity-type=spot` label. Note that for spot nodes, Karpenter enables deletion consolidation by default. To enable replacement with spot consolidation, activate the [SpotToSpotConsolidation](https://karpenter.sh/docs/reference/settings/#features-gates) feature flag.

- **Check if all nodes are ready:**  
  Command:
  ```
  kubectl get nodes -o wide
  ```  
  Description: Verifies that all nodes have become ready and are available for scheduling.

- **Verify Pod Limit Configuration:**
  Command:
  ```
  kubectl describe node <node-name> | grep -E "(Capacity|Allocatable):" -A 10
  ```  
  Description: Check that Karpenter-managed nodes have the correct pod limit (30 pods maximum as configured in the AKSNodeClass). You can see this in the node's capacity and allocatable resources.

- **Verify Pod Migration to Spot VMs:**
  Command:
  ```
  kubectl get pods -o wide --namespace demo
  kubectl get nodes -L karpenter.sh/capacity-type,node.kubernetes.io/instance-type
  ```
  Description: Cross-reference pod placement with node types to confirm workloads are running on spot VMs.

- **Scale the Application Services:**
  Commands:
  ```
  # View current HPA configurations
  kubectl get hpa -n demo

  # Scale the order service HPA (min and max replicas)
  kubectl patch hpa order-service-hpa -n demo --patch '{"spec":{"minReplicas": 50, "maxReplicas": 50}}'
  
  # Scale the product service HPA (min and max replicas)
  kubectl patch hpa product-service-hpa -n demo --patch '{"spec":{"minReplicas": 50, "maxReplicas": 50}}'
  
  # Scale the store front service HPA (min and max replicas)
  kubectl patch hpa store-front-hpa -n demo --patch '{"spec":{"minReplicas": 50, "maxReplicas": 50}}'
  
  ```
  Description: Increases both minimum and maximum replicas for the HPAs of each service. This demonstrates NAP automatically provisioning additional spot nodes to accommodate the increased workload.

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