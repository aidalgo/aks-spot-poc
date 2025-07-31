# AKS Spot Instance POC

This project evaluates Azure Kubernetes Service (AKS) with spot virtual machines for cost optimization. It demonstrates two scenarios for leveraging spot instances while ensuring application availability and resilience.

## Scenarios Overview

1. **AKS with Dedicated Spot Node Pool**  
   Uses a manual configuration with a primary spot node pool and a fallback regular node pool if spot capacity isn’t available.

2. **AKS with Managed Karpenter for Node Auto Provisioning**  
   Demonstrates dynamic provisioning with Managed Karpenter prioritizing spot instances and automatically falling back to regular VMs as needed.

## Project Structure

```
aks-spot-poc/  
└── scenario1-dedicated-spot-pool/     // Scenario 1: Dedicated Spot Nodes  
    ├── descheduler/                   // Kubernetes descheduler configuration  
    │   ├── configmap.yaml  
    │   ├── job.yaml  
    │   ├── rbac.yaml  
    │   └── values.yaml  
    ├── README.md                      // Setup instructions for spot nodes  
    ├── sample-app/                    // Demo application manifest  
    │   └── ingress.yaml  
    ├── spot-node-pool.yaml            // Spot node pool configuration  
    └── terraform/                     // Terraform configuration for spot nodes 
├── scenario2-node-auto-provision/   // Scenario 2: Node Auto Provisioning  
│   ├── multiple-nodepools.yaml        // Config for multiple node pools  
│   ├── node-auto-provisioning.yaml    // NAP main configuration with AKSNodeClass  
│   ├── system-node-pool.yml           // System node pool for critical workloads  
│   ├── README.md                      // Setup instructions for NAP  
│   ├── sample-app/                    // Demo application manifests  
│   │   ├── ingress.yaml  
│   │   ├── order-service.yaml  
│   │   ├── product-service.yaml  
│   │   ├── rabbitmq.yaml  
│   │   └── store-front.yaml   
│   └── terraform/                     // Terraform configuration for NAP  
├── README.md                          // Main project documentation  
```

## Scenario 1: AKS with Dedicated Spot Node Pool and Fallback

In this scenario, the AKS cluster is set up with:
- **Spot Node Pool:** To leverage cost-effective spot VMs.
- **Fallback Node Pool:** To automatically run workload on regular VMs if spot capacity is exhausted.
- **Use of Descheduler:** To rebalance the workload if new spot nodes are available. 

### Setup & Testing

Please check the [README.me](scenario1-dedicated-spot-pool/README.md) file more all the details.

## Scenario 2: AKS with Node Auto Provisioning

This scenario uses AKS Node Auto Provision (NAP) to dynamically provision nodes. It prioritizes spot instances while ensuring a fallback to regular VMs when necessary. To learn more about NAP, check our official documentation [here](https://learn.microsoft.com/en-us/azure/aks/node-autoprovision). 

### Setup & Testing

Please check the [README.me](scenario2-node-auto-provision/README.md) file more all the details.

## Infrastructure Setup with Terraform

The `terraform/` directory of each scenario contains the necessary configuration files to deploy the test environment:
```bash
cd terraform
export ARM_SUBSCRIPTION_ID=<your-subscription-id>
terraform init
terraform apply
```

## Prerequisites

- Azure CLI
- kubectl
- Terraform
- Azure subscription with contributor access

## Getting Started

Follow the setup instructions under each scenario's directory. Ensure all dependencies are installed and configured correctly.