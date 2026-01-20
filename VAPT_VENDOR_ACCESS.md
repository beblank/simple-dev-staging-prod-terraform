# VAPT Vendor Access Guide

This document provides comprehensive instructions on how to grant temporary access to Vulnerability Assessment and Penetration Testing (VAPT) vendors for both isolated EC2 instances and EKS (Elastic Kubernetes Service) clusters.

## Table of Contents

1. [Overview](#overview)
2. [EC2 Instance Access](#ec2-instance-access)
   - [Method 1: SSH Key-Based Access](#method-1-ssh-key-based-access)
   - [Method 2: AWS Systems Manager (SSM) Session Manager (Recommended)](#method-2-aws-systems-manager-ssm-session-manager-recommended)
3. [EKS Cluster Access](#eks-cluster-access)
   - [Method 1: IAM User with Limited RBAC Permissions (Recommended)](#method-1-iam-user-with-limited-rbac-permissions-recommended)
   - [Method 2: Temporary Kubeconfig with IAM Role](#method-2-temporary-kubeconfig-with-iam-role)
   - [Method 3: Bastion Host Access](#method-3-bastion-host-access)
4. [Security Best Practices](#security-best-practices)
5. [Access Revocation](#access-revocation)
6. [Audit and Monitoring](#audit-and-monitoring)

---

## Overview

VAPT assessments require temporary, controlled access to infrastructure. This guide provides multiple methods for granting access while maintaining security and audit capabilities.

**Key Principles:**
- **Least Privilege**: Grant only the minimum access required
- **Time-Limited**: Set explicit expiration dates
- **Auditable**: All access should be logged and monitored
- **Revocable**: Access can be revoked immediately if needed

---

## EC2 Instance Access

### Method 1: SSH Key-Based Access

Traditional SSH access using temporary key pairs.

#### Steps:

1. **Create a Temporary IAM User for VAPT Vendor**

   ```bash
   # Create IAM user
   aws iam create-user --user-name vapt-vendor-temp
   
   # Attach EC2 read-only policy (optional, for inventory)
   aws iam attach-user-policy \
     --user-name vapt-vendor-temp \
     --policy-arn arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess
   ```

2. **Add Security Group Rule for VAPT Vendor IP**

   ```bash
   # Get the security group ID of your EC2 instance
   INSTANCE_ID="i-xxxxxxxxx"
   SG_ID=$(aws ec2 describe-instances \
     --instance-ids $INSTANCE_ID \
     --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' \
     --output text)
   
   # Add temporary ingress rule for VAPT vendor IP
   VAPT_VENDOR_IP="203.0.113.10/32"  # Replace with actual IP
   aws ec2 authorize-security-group-ingress \
     --group-id $SG_ID \
     --protocol tcp \
     --port 22 \
     --cidr $VAPT_VENDOR_IP \
     --description "Temporary VAPT vendor access - Expires: 2026-06-30"
   ```

3. **Create and Share SSH Key**

   ```bash
   # Generate temporary SSH key pair
   ssh-keygen -t rsa -b 4096 -f vapt-vendor-key -C "vapt-vendor@assessment"
   
   # Add public key to EC2 instance
   # Option A: Via AWS Systems Manager
   aws ssm send-command \
     --instance-ids $INSTANCE_ID \
     --document-name "AWS-RunShellScript" \
     --parameters 'commands=[
       "echo \"ssh-rsa AAAAB3... vapt-vendor@assessment\" >> /home/ec2-user/.ssh/authorized_keys",
       "chmod 600 /home/ec2-user/.ssh/authorized_keys"
     ]'
   
   # Option B: Via EC2 Instance Connect (if enabled)
   aws ec2-instance-connect send-ssh-public-key \
     --instance-id $INSTANCE_ID \
     --instance-os-user ec2-user \
     --ssh-public-key file://vapt-vendor-key.pub
   ```

4. **Share Private Key Securely**
   - Use encrypted email or secure file sharing
   - Provide connection details:
     ```
     Host: ec2-xx-xx-xx-xx.compute.amazonaws.com (or Elastic IP)
     User: ec2-user (or ubuntu, depending on AMI)
     Key: vapt-vendor-key
     ```

5. **VAPT Vendor Connects**
   ```bash
   ssh -i vapt-vendor-key ec2-user@ec2-xx-xx-xx-xx.compute.amazonaws.com
   ```

#### Limitations:
- Requires public IP or VPN access
- Security group rules need management
- Key rotation is manual

---

### Method 2: AWS Systems Manager (SSM) Session Manager (Recommended)

SSM Session Manager provides secure, audited access without opening inbound ports.

#### Advantages:
- ✅ No SSH keys needed
- ✅ No inbound security group rules required
- ✅ Full audit trail in CloudTrail
- ✅ Session recording available
- ✅ Access revocable instantly via IAM

#### Prerequisites:

1. **Ensure EC2 Instance has SSM Agent Installed**
   - Amazon Linux 2, Ubuntu 16.04+, Windows 2016+ come with SSM agent pre-installed
   - For other AMIs, [install SSM agent](https://docs.aws.amazon.com/systems-manager/latest/userguide/sysman-install-ssm-agent.html)

2. **Attach IAM Role to EC2 Instance**

   ```bash
   # Create IAM role for SSM
   cat > ssm-trust-policy.json <<EOF
   {
     "Version": "2012-10-17",
     "Statement": [{
       "Effect": "Allow",
       "Principal": {"Service": "ec2.amazonaws.com"},
       "Action": "sts:AssumeRole"
     }]
   }
   EOF
   
   aws iam create-role \
     --role-name EC2-SSM-Role \
     --assume-role-policy-document file://ssm-trust-policy.json
   
   # Attach SSM managed policy
   aws iam attach-role-policy \
     --role-name EC2-SSM-Role \
     --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
   
   # Create and attach instance profile
   aws iam create-instance-profile --instance-profile-name EC2-SSM-Profile
   aws iam add-role-to-instance-profile \
     --instance-profile-name EC2-SSM-Profile \
     --role-name EC2-SSM-Role
   
   # Attach to EC2 instance
   aws ec2 associate-iam-instance-profile \
     --instance-id $INSTANCE_ID \
     --iam-instance-profile Name=EC2-SSM-Profile
   ```

#### Steps to Grant VAPT Vendor Access:

1. **Create IAM User for VAPT Vendor**

   ```bash
   # Create user
   aws iam create-user --user-name vapt-vendor-ssm
   
   # Generate access credentials
   aws iam create-access-key --user-name vapt-vendor-ssm > vapt-credentials.json
   ```

2. **Create IAM Policy for Specific Instance Access**

   ```bash
   # Get your AWS account ID
   ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
   
   cat > vapt-ssm-policy.json <<EOF
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": [
           "ssm:StartSession"
         ],
         "Resource": [
           "arn:aws:ec2:us-east-1:${ACCOUNT_ID}:instance/${INSTANCE_ID}",
           "arn:aws:ssm:*:*:document/AWS-StartSSHSession",
           "arn:aws:ssm:*:*:document/AWS-StartPortForwardingSession"
         ]
       },
       {
         "Effect": "Allow",
         "Action": [
           "ssm:DescribeSessions",
           "ssm:GetConnectionStatus",
           "ssm:DescribeInstanceProperties",
           "ec2:DescribeInstances"
         ],
         "Resource": "*"
       },
       {
         "Effect": "Allow",
         "Action": [
           "ssm:TerminateSession"
         ],
         "Resource": "arn:aws:ssm:*:*:session/\${aws:username}-*"
       }
     ]
   }
   EOF
   
   # Create and attach policy
   POLICY_ARN=$(aws iam create-policy \
     --policy-name VAPT-SSM-Access-Policy \
     --policy-document file://vapt-ssm-policy.json \
     --query 'Policy.Arn' \
     --output text)
   
   aws iam attach-user-policy \
     --user-name vapt-vendor-ssm \
     --policy-arn $POLICY_ARN
   ```

3. **Share Credentials with VAPT Vendor**
   - Provide AWS Access Key ID and Secret Access Key from `vapt-credentials.json`
   - Share the instance ID and region

4. **VAPT Vendor Setup (Their Side)**

   ```bash
   # Install AWS CLI and Session Manager Plugin
   # https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html
   
   # Configure AWS credentials
   aws configure
   # Enter Access Key ID
   # Enter Secret Access Key
   # Enter Region (e.g., us-east-1)
   
   # Start SSM session
   aws ssm start-session --target i-xxxxxxxxx
   ```

5. **Enable Session Logging (Optional but Recommended)**

   ```bash
   # Create S3 bucket for session logs with security configurations
   BUCKET_NAME="vapt-session-logs-$(date +%Y%m%d)"
   REGION="us-east-1"
   
   aws s3 mb s3://${BUCKET_NAME} --region ${REGION}
   
   # Block public access
   aws s3api put-public-access-block \
     --bucket ${BUCKET_NAME} \
     --public-access-block-configuration \
       BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
   
   # Enable encryption
   aws s3api put-bucket-encryption \
     --bucket ${BUCKET_NAME} \
     --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
   
   # Create session preferences document
   cat > session-preferences.json <<EOF
   {
     "schemaVersion": "1.0",
     "description": "Document to hold regional settings for Session Manager",
     "sessionType": "Standard_Stream",
     "inputs": {
       "s3BucketName": "${BUCKET_NAME}",
       "s3KeyPrefix": "session-logs/",
       "s3EncryptionEnabled": true,
       "cloudWatchLogGroupName": "/aws/ssm/session-logs",
       "cloudWatchEncryptionEnabled": true
     }
   }
   EOF
   
   # Update Session Manager preferences
   aws ssm create-document \
     --name "SSM-SessionManagerRunShell" \
     --document-type "Session" \
     --content file://session-preferences.json \
     || aws ssm update-document \
       --name "SSM-SessionManagerRunShell" \
       --content file://session-preferences.json \
       --document-version '$LATEST'
   ```

---

## EKS Cluster Access

For EKS clusters, VAPT vendors need access to:
- Kubernetes API server
- Worker nodes (for node-level security assessment)
- Deployed applications and services

### Method 1: IAM User with Limited RBAC Permissions (Recommended)

This method creates an IAM user and maps it to a Kubernetes RBAC role with limited permissions.

#### Steps:

1. **Create IAM User for VAPT Vendor**

   ```bash
   # Create IAM user
   aws iam create-user --user-name vapt-vendor-eks
   
   # Generate access credentials
   aws iam create-access-key --user-name vapt-vendor-eks > vapt-eks-credentials.json
   ```

2. **Update EKS aws-auth ConfigMap**

   This step maps the IAM user to a Kubernetes user.

   ```bash
   # Get current cluster name
   CLUSTER_NAME="simple-eks-dev"  # or staging/prod
   ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
   
   # Get current aws-auth ConfigMap
   kubectl get configmap aws-auth -n kube-system -o yaml > aws-auth-backup.yaml
   
   # Edit aws-auth ConfigMap
   kubectl edit configmap aws-auth -n kube-system
   ```

   Add this section under `mapUsers`:

   ```yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: aws-auth
     namespace: kube-system
   data:
     mapUsers: |
       - userarn: arn:aws:iam::${ACCOUNT_ID}:user/vapt-vendor-eks
         username: vapt-vendor
         groups:
           - vapt-readonly  # For read-only access
           # - vapt-testing  # For write access in testing namespace
   ```

3. **Create Kubernetes RBAC Role and RoleBinding**

   **Option A: Read-Only Access (Recommended for initial assessment)**

   ```yaml
   # vapt-rbac.yaml
   apiVersion: rbac.authorization.k8s.io/v1
   kind: ClusterRole
   metadata:
     name: vapt-readonly
   rules:
   - apiGroups: ["*"]
     resources: ["*"]
     verbs: ["get", "list", "watch"]
   - apiGroups: [""]
     resources: ["pods/log", "pods/status"]
     verbs: ["get", "list"]
   ---
   apiVersion: rbac.authorization.k8s.io/v1
   kind: ClusterRoleBinding
   metadata:
     name: vapt-readonly-binding
   subjects:
   - kind: Group
     name: vapt-readonly
     apiGroup: rbac.authorization.k8s.io
   roleRef:
     kind: ClusterRole
     name: vapt-readonly
     apiGroup: rbac.authorization.k8s.io
   ```

   **Option B: Limited Write Access (For active testing)**

   ```yaml
   # vapt-rbac-testing.yaml
   # Create dedicated namespace for VAPT testing
   apiVersion: v1
   kind: Namespace
   metadata:
     name: vapt-testing
   ---
   # ClusterRole for read-only access to all cluster resources
   apiVersion: rbac.authorization.k8s.io/v1
   kind: ClusterRole
   metadata:
     name: vapt-cluster-readonly
   rules:
   - apiGroups: ["*"]
     resources: ["*"]
     verbs: ["get", "list", "watch"]
   ---
   # Role for write access within vapt-testing namespace only
   apiVersion: rbac.authorization.k8s.io/v1
   kind: Role
   metadata:
     name: vapt-testing-writer
     namespace: vapt-testing
   rules:
   - apiGroups: [""]
     resources: ["pods", "services", "configmaps"]
     verbs: ["create", "delete", "patch", "update", "get", "list", "watch"]
   - apiGroups: ["apps"]
     resources: ["deployments", "replicasets"]
     verbs: ["create", "delete", "patch", "update", "get", "list", "watch"]
   # Note: Secrets access is intentionally excluded for security
   ---
   # ClusterRoleBinding for cluster-wide read access
   apiVersion: rbac.authorization.k8s.io/v1
   kind: ClusterRoleBinding
   metadata:
     name: vapt-cluster-readonly-binding
   subjects:
   - kind: Group
     name: vapt-testing
     apiGroup: rbac.authorization.k8s.io
   roleRef:
     kind: ClusterRole
     name: vapt-cluster-readonly
     apiGroup: rbac.authorization.k8s.io
   ---
   # RoleBinding for namespace-specific write access
   apiVersion: rbac.authorization.k8s.io/v1
   kind: RoleBinding
   metadata:
     name: vapt-testing-writer-binding
     namespace: vapt-testing
   subjects:
   - kind: Group
     name: vapt-testing
     apiGroup: rbac.authorization.k8s.io
   roleRef:
     kind: Role
     name: vapt-testing-writer
     apiGroup: rbac.authorization.k8s.io
   ```

   Apply the RBAC configuration:

   ```bash
   # For read-only access
   kubectl apply -f vapt-rbac.yaml
   
   # For testing with write access in dedicated namespace
   kubectl apply -f vapt-rbac-testing.yaml
   ```

4. **Generate kubeconfig for VAPT Vendor**

   ```bash
   # Install aws-iam-authenticator if not already installed
   # https://docs.aws.amazon.com/eks/latest/userguide/install-aws-iam-authenticator.html
   
   # Create kubeconfig file
   cat > kubeconfig-vapt.yaml <<EOF
   apiVersion: v1
   kind: Config
   clusters:
   - cluster:
       certificate-authority-data: $(aws eks describe-cluster --name $CLUSTER_NAME --query 'cluster.certificateAuthority.data' --output text)
       server: $(aws eks describe-cluster --name $CLUSTER_NAME --query 'cluster.endpoint' --output text)
     name: $CLUSTER_NAME
   contexts:
   - context:
       cluster: $CLUSTER_NAME
       user: vapt-vendor
     name: vapt-context
   current-context: vapt-context
   users:
   - name: vapt-vendor
     user:
       exec:
         apiVersion: client.authentication.k8s.io/v1beta1
         command: aws
         args:
           - eks
           - get-token
           - --cluster-name
           - $CLUSTER_NAME
         env:
           - name: AWS_PROFILE
             value: vapt-vendor
   EOF
   ```

5. **Share with VAPT Vendor**
   - Provide `kubeconfig-vapt.yaml`
   - Provide AWS credentials from `vapt-eks-credentials.json`
   - Share cluster name and region

6. **VAPT Vendor Setup (Their Side)**

   ```bash
   # Configure AWS credentials
   aws configure --profile vapt-vendor
   # Enter Access Key ID
   # Enter Secret Access Key
   # Enter Region
   
   # Set KUBECONFIG environment variable
   export KUBECONFIG=/path/to/kubeconfig-vapt.yaml
   
   # Test access
   kubectl get nodes
   kubectl get pods --all-namespaces
   ```

---

### Method 2: Temporary Kubeconfig with IAM Role

Create a temporary IAM role that VAPT vendor can assume.

#### Steps:

1. **Create IAM Role with Trust Policy**

   Note: Instead of trusting the entire VAPT vendor account root, request specific IAM user or role ARN from the VAPT vendor for better security.

   ```bash
   cat > vapt-trust-policy.json <<EOF
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Principal": {
           "AWS": "arn:aws:iam::VAPT_VENDOR_ACCOUNT_ID:user/vapt-engineer"
         },
         "Action": "sts:AssumeRole",
         "Condition": {
           "StringEquals": {
             "sts:ExternalId": "unique-external-id-12345"
           }
         }
       }
     ]
   }
   EOF
   
   aws iam create-role \
     --role-name VAPT-EKS-Access-Role \
     --assume-role-policy-document file://vapt-trust-policy.json
   ```

2. **Update aws-auth ConfigMap**

   ```bash
   ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
   ```

   ```yaml
   mapRoles: |
     - rolearn: arn:aws:iam::${ACCOUNT_ID}:role/VAPT-EKS-Access-Role
       username: vapt-vendor
       groups:
         - vapt-readonly
   ```

3. **Apply RBAC (Same as Method 1)**

4. **Share with VAPT Vendor**
   - Role ARN
   - External ID
   - Cluster name and region

5. **VAPT Vendor Assumes Role**

   ```bash
   aws sts assume-role \
     --role-arn arn:aws:iam::123456789012:role/VAPT-EKS-Access-Role \
     --role-session-name vapt-session \
     --external-id unique-external-id-12345
   
   # Update AWS credentials with temporary credentials
   # Then use kubectl
   ```

---

### Method 3: Bastion Host Access

For scenarios where direct EKS API access is not desirable, use a bastion host.

#### Steps:

1. **Create Bastion Host in Public Subnet**

   ```hcl
   # bastion.tf (add to Terraform configuration)
   resource "aws_instance" "bastion" {
     ami           = data.aws_ami.amazon_linux_2.id
     instance_type = "t3.micro"
     subnet_id     = aws_subnet.public[0].id
     
     vpc_security_group_ids = [aws_security_group.bastion.id]
     iam_instance_profile   = aws_iam_instance_profile.bastion.name
     
     tags = {
       Name = "${var.environment}-bastion-vapt"
     }
   }
   
   resource "aws_security_group" "bastion" {
     name        = "${var.environment}-bastion-sg"
     description = "Security group for bastion host"
     vpc_id      = aws_vpc.main.id
     
     ingress {
       from_port   = 22
       to_port     = 22
       protocol    = "tcp"
       cidr_blocks = ["VAPT_VENDOR_IP/32"]
       description = "SSH from VAPT vendor"
     }
     
     egress {
       from_port   = 0
       to_port     = 0
       protocol    = "-1"
       cidr_blocks = ["0.0.0.0/0"]
     }
   }
   ```

2. **Install kubectl on Bastion**

   ```bash
   # SSH to bastion
   curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
   sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
   
   # Configure kubectl
   aws eks update-kubeconfig --region us-east-1 --name simple-eks-dev
   ```

3. **Grant SSH Access to VAPT Vendor**
   - Use Method 1 or 2 from EC2 Instance Access section
   - VAPT vendor connects to bastion, then uses kubectl

---

## Security Best Practices

1. **Time-Limited Access**
   - Set explicit expiration dates for all credentials
   - Use IAM user tags to track expiration:
     ```bash
     aws iam tag-user \
       --user-name vapt-vendor-eks \
       --tags Key=ExpiryDate,Value=2026-06-30 Key=Purpose,Value=VAPT-Assessment
     ```

2. **IP Whitelisting**
   - Always restrict access to known VAPT vendor IP addresses
   - Update security groups and IAM policies with IP conditions:
     ```json
     {
       "Condition": {
         "IpAddress": {
           "aws:SourceIp": ["203.0.113.10/32"]
         }
       }
     }
     ```

3. **MFA Enforcement** (Optional but Recommended)
   ```json
   {
     "Condition": {
       "Bool": {
         "aws:MultiFactorAuthPresent": "true"
       }
     }
   }
   ```

4. **Separate Testing Namespace**
   - Create dedicated namespace for VAPT testing
   - Isolate from production workloads
   - Apply resource quotas:
     ```yaml
     apiVersion: v1
     kind: ResourceQuota
     metadata:
       name: vapt-quota
       namespace: vapt-testing
     spec:
       hard:
         requests.cpu: "4"
         requests.memory: 8Gi
         pods: "10"
     ```

5. **Session Recording**
   - Enable CloudTrail logging
   - Enable SSM Session Manager logging to S3
   - Enable Kubernetes audit logs

6. **Network Segmentation**
   - Use network policies to restrict pod-to-pod communication
   - Keep VAPT testing isolated from production services

7. **Regular Access Reviews**
   - Schedule weekly access reviews during assessment period
   - Use AWS Access Analyzer to identify unused permissions

---

## Access Revocation

### Immediate Revocation

**For EC2 SSH Access:**

1. Remove SSH key from instance:
   ```bash
   aws ssm send-command \
     --instance-ids $INSTANCE_ID \
     --document-name "AWS-RunShellScript" \
     --parameters 'commands=["sed -i \"/vapt-vendor/d\" /home/ec2-user/.ssh/authorized_keys"]'
   ```

2. Remove security group rule:
   ```bash
   aws ec2 revoke-security-group-ingress \
     --group-id $SG_ID \
     --protocol tcp \
     --port 22 \
     --cidr $VAPT_VENDOR_IP
   ```

**For SSM Access:**

1. Delete IAM user access keys:
   ```bash
   # List and delete all access keys for the user
   aws iam list-access-keys --user-name vapt-vendor-ssm --query 'AccessKeyMetadata[].AccessKeyId' --output text | \
     xargs -I {} aws iam delete-access-key --user-name vapt-vendor-ssm --access-key-id {}
   ```

2. Terminate active sessions:
   ```bash
   # List active sessions
   aws ssm describe-sessions --state Active
   
   # Terminate specific session
   aws ssm terminate-session --session-id session-id
   ```

**For EKS Access:**

1. Remove user from aws-auth ConfigMap:
   ```bash
   kubectl edit configmap aws-auth -n kube-system
   # Remove the vapt-vendor entry
   ```

2. Delete RBAC resources:
   ```bash
   kubectl delete clusterrolebinding vapt-readonly-binding
   kubectl delete clusterrole vapt-readonly
   ```

3. Delete IAM user:
   ```bash
   # Get the policy ARN (if you need to find it)
   POLICY_ARN=$(aws iam list-attached-user-policies \
     --user-name vapt-vendor-eks \
     --query 'AttachedPolicies[?PolicyName==`VAPT-EKS-Access-Policy`].PolicyArn' \
     --output text)
   
   # Delete access keys first
   aws iam list-access-keys --user-name vapt-vendor-eks --query 'AccessKeyMetadata[].AccessKeyId' --output text | \
     xargs -I {} aws iam delete-access-key --user-name vapt-vendor-eks --access-key-id {}
   
   # Detach and delete the policy
   aws iam detach-user-policy --user-name vapt-vendor-eks --policy-arn $POLICY_ARN
   
   # Delete the user
   aws iam delete-user --user-name vapt-vendor-eks
   ```

### Post-Assessment Cleanup

1. **Delete all temporary IAM users and roles**
2. **Remove all security group rules**
3. **Delete bastion host if created**
4. **Rotate any shared credentials**
5. **Review CloudTrail logs for unauthorized activity**
6. **Generate access report**:
   ```bash
   aws iam generate-credential-report
   aws iam get-credential-report
   ```

---

## Audit and Monitoring

### CloudTrail Monitoring

1. **Enable CloudTrail** (if not already enabled):
   ```bash
   # Create S3 bucket for CloudTrail logs
   TRAIL_BUCKET="vapt-audit-logs-$(date +%Y%m%d)"
   REGION="us-east-1"
   ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
   
   aws s3 mb s3://${TRAIL_BUCKET} --region ${REGION}
   
   # Apply bucket policy for CloudTrail
   cat > cloudtrail-bucket-policy.json <<EOF
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Sid": "AWSCloudTrailAclCheck",
         "Effect": "Allow",
         "Principal": {"Service": "cloudtrail.amazonaws.com"},
         "Action": "s3:GetBucketAcl",
         "Resource": "arn:aws:s3:::${TRAIL_BUCKET}"
       },
       {
         "Sid": "AWSCloudTrailWrite",
         "Effect": "Allow",
         "Principal": {"Service": "cloudtrail.amazonaws.com"},
         "Action": "s3:PutObject",
         "Resource": "arn:aws:s3:::${TRAIL_BUCKET}/AWSLogs/${ACCOUNT_ID}/*",
         "Condition": {
           "StringEquals": {"s3:x-amz-acl": "bucket-owner-full-control"}
         }
       }
     ]
   }
   EOF
   
   aws s3api put-bucket-policy --bucket ${TRAIL_BUCKET} --policy file://cloudtrail-bucket-policy.json
   
   # Create and start the trail
   aws cloudtrail create-trail \
     --name vapt-audit-trail \
     --s3-bucket-name ${TRAIL_BUCKET}
   
   aws cloudtrail start-logging --name vapt-audit-trail
   ```

2. **Monitor Key Events**:
   - IAM user logins
   - SSM session starts/ends
   - kubectl API calls (via EKS audit logs)
   - Security group changes

### EKS Audit Logs

1. **Enable EKS Control Plane Logging**:
   ```bash
   aws eks update-cluster-config \
     --name $CLUSTER_NAME \
     --logging '{"clusterLogging":[{"types":["api","audit","authenticator"],"enabled":true}]}'
   ```

2. **Query Logs in CloudWatch**:
   ```bash
   aws logs filter-log-events \
     --log-group-name /aws/eks/$CLUSTER_NAME/cluster \
     --filter-pattern "vapt-vendor"
   ```

### Real-Time Alerting

Set up CloudWatch alarms for suspicious activities:

```bash
# Example: Alert on unusual API call patterns
aws cloudwatch put-metric-alarm \
  --alarm-name VAPT-Unusual-Activity \
  --alarm-description "Alert on unusual VAPT activity" \
  --metric-name CallCount \
  --namespace AWS/EKS \
  --statistic Sum \
  --period 300 \
  --threshold 1000 \
  --comparison-operator GreaterThanThreshold
```

---

## Quick Reference

### EC2 Access Summary

| Method | Security | Setup Complexity | Use Case |
|--------|----------|------------------|----------|
| SSH Keys | Medium | Low | Quick access, small number of instances |
| SSM Session Manager | High | Medium | Recommended, audit trail, no open ports |

### EKS Access Summary

| Method | Security | Setup Complexity | Use Case |
|--------|----------|------------------|----------|
| IAM User + RBAC | High | Medium | Recommended, granular control |
| IAM Role Assumption | High | High | Cross-account access |
| Bastion Host | Medium | High | Additional network isolation |

### Recommended Approach

For most VAPT assessments, we recommend:

1. **EC2 Instances**: Use SSM Session Manager (Method 2)
2. **EKS Clusters**: Use IAM User with Limited RBAC (Method 1)
3. **Enable**: CloudTrail, Session Logging, and EKS Audit Logs
4. **Create**: Dedicated testing namespace with resource quotas
5. **Review**: Access weekly during assessment period
6. **Revoke**: Immediately upon completion

---

## Support

For questions or issues with VAPT vendor access:
1. Contact your DevOps/Security team
2. Review AWS documentation:
   - [SSM Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)
   - [EKS IAM Access](https://docs.aws.amazon.com/eks/latest/userguide/add-user-role.html)
   - [Kubernetes RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)

---

## Changelog

| Date | Version | Changes |
|------|---------|---------|
| 2026-01-20 | 1.0 | Initial documentation |
