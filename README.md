# Capitolis Task Infrastructure Repository

Welcome to the Infrastructure Repository! This repository contains all the necessary infrastructure as code (IaC) scripts, configurations, and documentation to manage and provision our task's infrastructure and more.


## Table of Contents

- [Overview](#overview)
- [Folder Structure](#folder-structure)
- [Setup](#setup)
- [Usage](#usage)

## Overview

This repository serves as the central location for managing our infrastructure resources. It includes configurations for various cloud providers, orchestration tools, networking setups, and other components required to run our applications and services.

The infrastructure provisioning process is almost fully automated, allowing you to deploy a comprehensive environment with just a single Terraform command. This includes setting up a Virtual Private Cloud (VPC), an Amazon Elastic Kubernetes Service (EKS) cluster, as well as all security dependencies and Kubernetes add-ons such as Jenkins, Istio, ArgoCD, Prometheus, and Grafana.

## Folder Structure

- `/terraform`: Contains Terraform configurations for provisioning infrastructure resources on cloud providers such as AWS, Azure, or GCP.
- `/kubernetes`: Houses Ansible playbooks and roles for configuring servers and deploying applications.

## Setup

To set up the infrastructure locally or in your preferred environment, follow these steps:

1. **Clone the Repository:** 

   ```bash
   git clone https://github.com/YanivZl/capitolis-demo-infra.git
   cd capitolis-demo-infra
   ```

2. **Install Required Tools:**

   Before proceeding, ensure you have the following tools installed:
   
   - [Terraform](https://www.terraform.io/downloads.html): For provisioning infrastructure resources.
   - [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/): Kubernetes command-line tool for interacting with Kubernetes clusters.
   - Access to a cloud provider account (e.g., AWS, Azure, GCP) and necessary permissions to create and manage resources.
   - [Helm](https://helm.sh/docs/intro/install/): Package manager for Kubernetes, used for deploying applications.
   
3. **Configure Access to Cloud Provider:**

   Ensure you have your AWS access key ID and secret access key configured. You can do this by either setting environment variables or using AWS CLI configuration. Refer to the [AWS documentation](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html) for detailed instructions.
   
4. **Initialize Terraform:**

   Navigate to the `/terraform` directory and initialize Terraform by running:
   
   ```bash
   cd terraform
   terraform init
   ```
   
5. **Deploy Infrastructure:**

   Once Terraform is initialized, you can plan and apply the infrastructure changes. Make sure to review the Terraform configurations (`*.tf` files) before applying any changes to understand what resources will be provisioned.
   
   ```bash
   terraform plan
   terraform apply
   ```

6. **Verify Deployment:**

After deployment, verify that your infrastructure resources and Kubernetes clusters are provisioned correctly. You can use kubectl commands to interact with your Kubernetes cluster and check the status of deployments, pods, and services.

## Usage
The application is currently exposed on http://cats.yanivzl.com/, and Jenkins is exposed on http://jenkins.yanivzl.com. In the future, as a project for practice, we will expose more applications such as Grafana, Kiali, and ArgoCD.

Additionally, in the future, we plan to add a microservices application to demonstrate the infrastructure further.
