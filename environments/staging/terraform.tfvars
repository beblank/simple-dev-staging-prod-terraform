# Staging Environment Configuration
environment = "staging"
aws_region  = "us-east-1"

# VPC Configuration
vpc_cidr           = "10.1.0.0/16"
availability_zones = ["us-east-1a", "us-east-1b"]

# EKS Configuration
eks_cluster_version     = "1.28"
eks_node_instance_types = ["t3.large"]
eks_node_desired_size   = 2
eks_node_min_size       = 2
eks_node_max_size       = 4

# Use single NAT gateway for cost optimization
single_nat_gateway = true
enable_nat_gateway = true
