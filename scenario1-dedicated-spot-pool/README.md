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
  Description: This command fetches and updates your local kubeconfig with credentials to access the AKS cluster. It ensures that you are authenticated to manage the cluster via kubectl. Ensure that the $RESOURCE_GROUP and $CLUSTER_NAME variables correspond with those defined in your Terraform configuration.

- **Create the Demo Namespace:**  
  Command:
  ```
  kubectl create namespace demo
  ```  
  Description: Creates a namespace called "demo" to logically isolate and manage the resources of the sample application. 

- **Deploy the Sample Application:**  
  Command:
  ```
  kubectl apply -R -f ./sample-app/ --namespace demo
  ```  
  Description: This command deploys all manifests for the sample application into the demo namespace. Scheduling of pods is optimized through carefully configured node affinity rules and tolerations:
  -  Tolerations: Pods include tolerations for the taint kubernetes.azure.com/scalesetpriority on spot nodes, explicitly allowing them to run on these resources. If the deployment doesn't include this toleration, the pods will not be scheduled in the spot node pool. 
  - Node Affinity: Node affinity rules help with scheduling by prioritizing nodes labeled for spot workloads, but they can also use nodes labeled as a fallback in case no spots are available. This ensures that pods are scheduled in a cost-effective way and highly available. Also, check the weight in each affinity rule:
    - Weight 100: Strongly prefers nodes labeled kubernetes.azure.com/scalesetpriority: spot. This maximizes cost-efficiency by scheduling pods onto lower-cost Spot Virtual Machines.
    - Weight 1: Provides a fallback option by preferring nodes labeled scalepriority: fallback. If spot nodes are unavailable, pods will gracefully fall back to these nodes to maintain high availability and service continuity.

### 3. Manage Node Pools and Validate Deployment
- **Verify Pod Deployment:**  
  Command:
  ```
  kubectl get pods -o wide --namespace demo
  ```  
  Description: Checks that all pods are running and displays their node pool assignments. Due the the affinity rules, you should see the pods being scheduled to run on the spot node pool.

- **Stop the Spot Node Pool:**  
  Command:
  ```
  az aks nodepool scale --resource-group $RESOURCE_GROUP --cluster-name $CLUSTER_NAME --name spot --node-count 0
  ```  
  Description: Now let's simulate a spot eviction by scaling down the spot node pool. After the node pool is scaled to 0, you should see all the other application pods being rebalanced to the fallback node pool:
  ```
  kubectl get pods -o wide --namespace demo
  ```  

- **Restart the Spot Node Pool:**  
  Command:
  ```
  az aks nodepool scale --resource-group $RESOURCE_GROUP --cluster-name $CLUSTER_NAME --name spot --node-count 1
  ```  
  Description: Now let's restart the spot node pool. After the spot node pool is available, note that the workloads will continue running on the same fallback node pool. This is intentional, as Kubernetes will only reschedule pods if there is a reason to do so. Having the spot node available will just provide an extra option if new pods need to be created. For cost efficiency, it would be ideal to rebalance all the pods. But how can we do that?

- **Install Kubernetes Descheduler:**  
  This is where Descheduler can help. This tool is designed to improve the efficiency and performance of a Kubernetes cluster by evicting pods that are not optimally placed. It works by identifying pods that violate certain policies or constraints and then evicting them so that the Kubernetes scheduler can place them on more suitable nodes. You can learn more about it [here](https://github.com/kubernetes-sigs/descheduler).

  Descheduler can be run as a job, cron or deployment. I all depends what is your strategy to rebalance the pods. For this example, we are going to run it as a job, using the latest Descheduler realease at the time, which is [v0.32.2](https://github.com/kubernetes-sigs/descheduler/blob/release-1.32/README.md).

  Command:
  ```
  kubectl create -f descheduler/rbac.yaml
  kubectl create -f descheduler/configmap.yaml
  kubectl create -f descheduler/job.yaml
  ```  
  The most important part to understand is the [configmap.yaml]()file, which is configuring a Kubernetes ConfigMap for the Descheduler. The Descheduler remove pods from nodes based on certain policies, which can help to optimize resource usage and improve cluster efficiency.

  In this case we plugin RemovePodsViolatingNodeAffinity that is looking for nodeAffinityType with preferredDuringSchedulingIgnoredDuringExecution or requiredDuringSchedulingIgnoredDuringExecution. 

  In this case, our policy configures the Descheduler to remove pods that no longer comply with node affinity rules defined during scheduling. Specifically, it enables the RemovePodsViolatingNodeAffinity plugin, targeting pods violating both types of node affinity rules: requiredDuringSchedulingIgnoredDuringExecution (mandatory rules that must be satisfied during initial pod scheduling) and preferredDuringSchedulingIgnoredDuringExecution (soft preferences guiding pod placement). If conditions in the cluster change—such as spot nodes being available again, it will allow those pods to be reschedule into the spot nodes.

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
