# EKS with Istio Network and Managed Node Group

This repository contains Terraform code to deploy an Amazon EKS cluster with Istio network and managed node group using the blueprint available at [aws-ia/terraform-aws-eks-blueprints](https://github.com/aws-ia/terraform-aws-eks-blueprints/tree/main/patterns/istio).

## Prerequisites

Before you begin, ensure you have the following prerequisites:

- [Terraform](https://www.terraform.io/downloads.html) installed.
- AWS CLI installed and configured with appropriate permissions.
- IAM Authenticator for AWS installed.
- kubectl installed.
- Istioctl installed.

## Getting Started

1. Clone this repository:

    ```bash
    git clone https://github.com/capitolis-devops-project-infra/terraform-aws-eks-blueprints.git
    ```

2. Navigate to the Istio pattern directory:

    ```bash
    cd terraform-aws-eks-blueprints/patterns/istio
    ```

3. Initialize Terraform:

    ```bash
    terraform init
    ```

4. Customize the variables in `terraform.tfvars` file as needed.

5. Review and modify the resources in `main.tf` file if necessary.

6. Apply the Terraform configuration:

    ```bash
    terraform apply
    ```

7. After the successful deployment, configure `kubectl` to access the EKS cluster:

    ```bash
    aws eks --region <region> update-kubeconfig --name <cluster_name>
    ```

8. Install Istio by following the instructions provided in the [Istio documentation](https://istio.io/latest/docs/setup/getting-started/).

## Cleaning Up

To avoid incurring unnecessary charges, it's recommended to destroy the resources once they are no longer needed:

```bash
terraform destroy
