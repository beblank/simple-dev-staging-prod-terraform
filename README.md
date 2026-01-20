# Simple Dev-Staging-Prod Terraform

A complete Terraform configuration for deploying Amazon EKS (Elastic Kubernetes Service) clusters across three environments: Development, Staging, and Production.

## Features

- **Multi-Environment Support**: Separate configurations for dev, staging, and prod
- **Complete VPC Setup**: Custom VPC with public and private subnets across multiple availability zones
- **EKS Cluster**: Fully managed Kubernetes cluster with customizable configurations
- **Auto Scaling Node Groups**: Worker nodes with configurable scaling policies
- **Security**: IAM roles, security groups, and network isolation
- **Cost Optimization**: Different resource sizes per environment

## Architecture

Each environment includes:
- VPC with configurable CIDR blocks
- Public and private subnets across 2 availability zones
- Internet Gateway for public subnet access
- NAT Gateway(s) for private subnet internet access
- EKS Cluster with control plane
- EKS Node Group with auto-scaling worker nodes
- IAM roles and policies for cluster and node groups
- Security groups for cluster access

## Environment Configurations

### Development
- **Instance Type**: t3.medium
- **Node Count**: 1-3 nodes (desired: 2)
- **VPC CIDR**: 10.0.0.0/16
- **NAT Gateway**: Single (cost-optimized)
- **Use Case**: Development and testing

### Staging
- **Instance Type**: t3.large
- **Node Count**: 2-4 nodes (desired: 2)
- **VPC CIDR**: 10.1.0.0/16
- **NAT Gateway**: Single (cost-optimized)
- **Use Case**: Pre-production testing and validation

### Production
- **Instance Type**: t3.xlarge
- **Node Count**: 3-10 nodes (desired: 3)
- **VPC CIDR**: 10.2.0.0/16
- **NAT Gateway**: Multi-AZ (high availability)
- **Use Case**: Production workloads

## Prerequisites

- [Terraform](https://www.terraform.io/downloads.html) >= 1.0
- [AWS CLI](https://aws.amazon.com/cli/) configured with appropriate credentials
- [kubectl](https://kubernetes.io/docs/tasks/tools/) for cluster management
- AWS account with permissions to create:
  - VPC and networking resources
  - EKS clusters
  - IAM roles and policies
  - EC2 instances

## Usage

### 1. Clone the Repository

```bash
git clone https://github.com/beblank/simple-dev-staging-prod-terraform.git
cd simple-dev-staging-prod-terraform
```

### 2. Initialize Terraform

```bash
terraform init
```

### 3. Deploy to an Environment

#### Development Environment

```bash
terraform plan -var-file="environments/dev/terraform.tfvars"
terraform apply -var-file="environments/dev/terraform.tfvars"
```

#### Staging Environment

```bash
terraform plan -var-file="environments/staging/terraform.tfvars"
terraform apply -var-file="environments/staging/terraform.tfvars"
```

#### Production Environment

```bash
terraform plan -var-file="environments/prod/terraform.tfvars"
terraform apply -var-file="environments/prod/terraform.tfvars"
```

### 4. Configure kubectl

After successful deployment, configure kubectl to access your cluster:

```bash
aws eks update-kubeconfig --region us-east-1 --name simple-eks-dev
# or
aws eks update-kubeconfig --region us-east-1 --name simple-eks-staging
# or
aws eks update-kubeconfig --region us-east-1 --name simple-eks-prod
```

### 5. Verify Cluster Access

```bash
kubectl get nodes
kubectl get pods --all-namespaces
```

## Customization

You can customize the configuration by modifying the `terraform.tfvars` files in each environment directory:

- `environment`: Environment name
- `aws_region`: AWS region for deployment
- `vpc_cidr`: VPC CIDR block
- `availability_zones`: List of availability zones
- `eks_cluster_version`: Kubernetes version
- `eks_node_instance_types`: EC2 instance types for worker nodes
- `eks_node_desired_size`: Desired number of nodes
- `eks_node_min_size`: Minimum number of nodes
- `eks_node_max_size`: Maximum number of nodes
- `enable_nat_gateway`: Enable/disable NAT gateway
- `single_nat_gateway`: Use single or multiple NAT gateways

## Outputs

After deployment, Terraform will output:

- `cluster_endpoint`: EKS cluster endpoint URL
- `cluster_name`: Name of the EKS cluster
- `cluster_id`: EKS cluster ID
- `vpc_id`: VPC ID
- `configure_kubectl`: Command to configure kubectl

View outputs:

```bash
terraform output
```

## Cleanup

To destroy the infrastructure:

```bash
terraform destroy -var-file="environments/dev/terraform.tfvars"
# or
terraform destroy -var-file="environments/staging/terraform.tfvars"
# or
terraform destroy -var-file="environments/prod/terraform.tfvars"
```

**Warning**: This will permanently delete all resources created by Terraform.

## File Structure

```
.
├── README.md                           # This file
├── main.tf                             # EKS cluster and node group configuration
├── vpc.tf                              # VPC and networking configuration
├── variables.tf                        # Variable definitions
├── outputs.tf                          # Output definitions
├── versions.tf                         # Provider and version constraints
├── .gitignore                          # Git ignore file
└── environments/
    ├── dev/
    │   └── terraform.tfvars           # Development environment variables
    ├── staging/
    │   └── terraform.tfvars           # Staging environment variables
    └── prod/
        └── terraform.tfvars           # Production environment variables
```

## Security Considerations

- Store `terraform.tfstate` files securely (use S3 backend with encryption)
- Never commit `.tfvars` files with sensitive data to version control
- Use AWS IAM roles with least privilege principle
- Enable AWS CloudTrail for audit logging
- Regularly update EKS cluster version and node AMIs
- Implement network policies in Kubernetes
- Use AWS Secrets Manager or AWS Systems Manager Parameter Store for sensitive data

## Cost Estimation

Approximate monthly costs (us-east-1):

- **Development**: ~$150-200/month
  - EKS control plane: $73
  - 2x t3.medium nodes: ~$60
  - NAT Gateway: ~$30
  - Data transfer: Variable

- **Staging**: ~$250-300/month
  - EKS control plane: $73
  - 2x t3.large nodes: ~$120
  - NAT Gateway: ~$30
  - Data transfer: Variable

- **Production**: ~$600-800/month
  - EKS control plane: $73
  - 3x t3.xlarge nodes: ~$360
  - 2x NAT Gateways: ~$60
  - Data transfer: Variable

*Note: Costs vary based on usage, data transfer, and additional resources.*

## Troubleshooting

### Issue: Insufficient permissions

**Solution**: Ensure your AWS credentials have the necessary permissions for creating VPC, EKS, IAM, and EC2 resources.

### Issue: Resource already exists

**Solution**: Check if resources with the same name exist. Modify the `project_name` variable or destroy existing resources.

### Issue: kubectl can't connect to cluster

**Solution**: 
1. Verify cluster is active: `aws eks describe-cluster --name <cluster-name>`
2. Update kubeconfig: `aws eks update-kubeconfig --region <region> --name <cluster-name>`
3. Check AWS credentials: `aws sts get-caller-identity`

## License

MIT License

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Support

For issues and questions, please open an issue in the GitHub repository.