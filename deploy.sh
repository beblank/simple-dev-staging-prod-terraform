#!/bin/bash

# Terraform EKS Deployment Script
# This script helps deploy EKS clusters across different environments

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show usage
usage() {
    cat << EOF
Usage: $0 [COMMAND] [ENVIRONMENT]

Commands:
    init        Initialize Terraform
    plan        Show execution plan
    apply       Apply infrastructure changes
    destroy     Destroy infrastructure
    output      Show output values
    kubeconfig  Update kubectl configuration

Environments:
    dev         Development environment
    staging     Staging environment
    prod        Production environment

Examples:
    $0 init dev
    $0 plan staging
    $0 apply prod
    $0 kubeconfig dev
    $0 destroy staging

EOF
    exit 1
}

# Check if required arguments are provided
if [ $# -lt 2 ]; then
    usage
fi

COMMAND=$1
ENVIRONMENT=$2

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
    print_error "Invalid environment: $ENVIRONMENT"
    usage
fi

VAR_FILE="environments/$ENVIRONMENT/terraform.tfvars"

# Check if var file exists
if [ ! -f "$VAR_FILE" ]; then
    print_error "Variable file not found: $VAR_FILE"
    exit 1
fi

print_info "Environment: $ENVIRONMENT"
print_info "Variable file: $VAR_FILE"

# Execute command
case $COMMAND in
    init)
        print_info "Initializing Terraform..."
        terraform init
        ;;
    
    plan)
        print_info "Creating execution plan..."
        terraform plan -var-file="$VAR_FILE"
        ;;
    
    apply)
        print_warn "This will create/modify infrastructure in $ENVIRONMENT environment"
        print_warn "Press Ctrl+C to cancel, or Enter to continue..."
        read
        print_info "Applying changes..."
        terraform apply -var-file="$VAR_FILE"
        
        # Get cluster name and region from output
        CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null || echo "")
        AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "us-east-1")
        if [ -n "$CLUSTER_NAME" ]; then
            print_info "Deployment complete!"
            print_info "To configure kubectl, run:"
            echo "aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME"
        fi
        ;;
    
    destroy)
        print_warn "This will DESTROY all infrastructure in $ENVIRONMENT environment"
        print_warn "Type 'yes' to confirm:"
        read CONFIRM
        if [ "$CONFIRM" != "yes" ]; then
            print_error "Aborted"
            exit 1
        fi
        print_info "Destroying infrastructure..."
        terraform destroy -var-file="$VAR_FILE"
        ;;
    
    output)
        print_info "Showing outputs..."
        terraform output
        ;;
    
    kubeconfig)
        CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null || echo "")
        AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "us-east-1")
        if [ -z "$CLUSTER_NAME" ]; then
            print_error "Could not get cluster name. Is the infrastructure deployed?"
            exit 1
        fi
        print_info "Updating kubectl configuration for cluster: $CLUSTER_NAME"
        aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"
        print_info "kubectl configured successfully"
        print_info "Verifying connection..."
        kubectl get nodes
        ;;
    
    *)
        print_error "Unknown command: $COMMAND"
        usage
        ;;
esac

print_info "Done!"
