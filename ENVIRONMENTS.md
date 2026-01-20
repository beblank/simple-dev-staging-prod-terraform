# Environment Comparison

| Feature | Dev | Staging | Production |
|---------|-----|---------|------------|
| **Instance Type** | t3.medium | t3.large | t3.xlarge |
| **Desired Nodes** | 2 | 2 | 3 |
| **Min Nodes** | 1 | 2 | 3 |
| **Max Nodes** | 3 | 4 | 10 |
| **VPC CIDR** | 10.0.0.0/16 | 10.1.0.0/16 | 10.2.0.0/16 |
| **NAT Gateway** | Single | Single | Multi-AZ |
| **Estimated Cost/Month** | $150-200 | $250-300 | $600-800 |

## Quick Start Commands

### Development
```bash
terraform init
terraform plan -var-file="environments/dev/terraform.tfvars"
terraform apply -var-file="environments/dev/terraform.tfvars"
aws eks update-kubeconfig --region us-east-1 --name simple-eks-dev
```

### Staging
```bash
terraform init
terraform plan -var-file="environments/staging/terraform.tfvars"
terraform apply -var-file="environments/staging/terraform.tfvars"
aws eks update-kubeconfig --region us-east-1 --name simple-eks-staging
```

### Production
```bash
terraform init
terraform plan -var-file="environments/prod/terraform.tfvars"
terraform apply -var-file="environments/prod/terraform.tfvars"
aws eks update-kubeconfig --region us-east-1 --name simple-eks-prod
```

## Best Practices

1. **Always use workspaces or separate state files** for different environments
2. **Test in dev first**, then staging, then production
3. **Review terraform plan** output carefully before applying
4. **Enable S3 backend** for state file management:
   ```hcl
   terraform {
     backend "s3" {
       bucket = "your-terraform-state-bucket"
       key    = "eks/dev/terraform.tfstate"
       region = "us-east-1"
     }
   }
   ```
5. **Use separate AWS accounts** for production isolation (recommended)
6. **Enable VPC Flow Logs** for network monitoring
7. **Implement pod security policies** in Kubernetes
8. **Regular updates**: Keep EKS version and node AMIs up to date

## Scaling Considerations

### Development
- Use for feature development and testing
- Can be shut down during non-working hours
- Single NAT gateway is sufficient

### Staging
- Mirror production configuration as closely as possible
- Use for integration testing and UAT
- Keep running 24/7 for automated tests

### Production
- High availability with multi-AZ NAT gateways
- Larger instance types for better performance
- Higher node counts for redundancy
- Monitor and adjust scaling based on actual usage
