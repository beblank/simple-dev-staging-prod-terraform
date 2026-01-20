# Production Environment Configuration
environment = "prod"
aws_region  = "us-east-1"

# VPC Configuration
vpc_cidr           = "10.2.0.0/16"
availability_zones = ["us-east-1a", "us-east-1b"]

# EKS Configuration
eks_cluster_version     = "1.28"
eks_node_instance_types = ["t3.xlarge"]
eks_node_desired_size   = 3
eks_node_min_size       = 3
eks_node_max_size       = 10

# High availability - NAT gateway per AZ
single_nat_gateway = false
enable_nat_gateway = true
