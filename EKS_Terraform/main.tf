
# ============================================================
# GET DEFAULT VPC
# ============================================================

data "aws_vpc" "default" {
  default = true
}


# ============================================================
# GET ALL SUBNETS FROM DEFAULT VPC
# ============================================================

data "aws_subnets" "default" {

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}


# ============================================================
# GET EXISTING TERRAFORM EKS IAM ROLE
#
# IMPORTANT:
# This role already exists in AWS and is attached to the
# EC2 instance profile.
#
# We are NOT creating another role here.
# ============================================================

data "aws_iam_role" "terraform_eks" {

  name = "terraform-eks"
}


# ============================================================
# EKS CLUSTER IAM ROLE
# ============================================================

data "aws_iam_policy_document" "eks_cluster_assume_role" {

  statement {

    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }

    actions = [
      "sts:AssumeRole"
    ]
  }
}


resource "aws_iam_role" "eks_cluster_role" {

  name = "devops-eks-cluster-role"

  assume_role_policy = data.aws_iam_policy_document.eks_cluster_assume_role.json

  tags = {
    Name        = "devops-eks-cluster-role"
    Environment = "Dev"
    Project     = "DevOps-EKS"
  }
}


# ============================================================
# EKS CLUSTER IAM POLICY
# ============================================================

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {

  role = aws_iam_role.eks_cluster_role.name

  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}


# ============================================================
# EKS CLUSTER
# ============================================================

resource "aws_eks_cluster" "eks_cluster" {

  name = "devops-eks-cluster"

  role_arn = aws_iam_role.eks_cluster_role.arn

  # Current Kubernetes version for this lab
  version = "1.35"


  # ==========================================================
  # EKS AUTHENTICATION CONFIGURATION
  #
  # API_AND_CONFIG_MAP allows:
  #
  # 1. EKS Access Entries
  # 2. Existing aws-auth ConfigMap
  #
  # This is important for our permanent IAM Role based access.
  # ==========================================================

  access_config {

    authentication_mode = "API_AND_CONFIG_MAP"
  }


  vpc_config {

    subnet_ids = data.aws_subnets.default.ids

    # Allow kubectl from your machine
    endpoint_public_access = true

    # Keep private endpoint disabled for this basic lab
    endpoint_private_access = false
  }


  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy
  ]


  tags = {

    Name        = "devops-eks-cluster"
    Environment = "Dev"
    Project     = "DevOps-EKS"
  }
}


# ============================================================
# EKS WORKER NODE IAM ROLE
# ============================================================

data "aws_iam_policy_document" "eks_node_assume_role" {

  statement {

    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = [
      "sts:AssumeRole"
    ]
  }
}


resource "aws_iam_role" "eks_node_role" {

  name = "devops-eks-node-role"

  assume_role_policy = data.aws_iam_policy_document.eks_node_assume_role.json

  tags = {

    Name        = "devops-eks-node-role"
    Environment = "Dev"
    Project     = "DevOps-EKS"
  }
}


# ============================================================
# WORKER NODE POLICY
# ============================================================

resource "aws_iam_role_policy_attachment" "worker_node_policy" {

  role = aws_iam_role.eks_node_role.name

  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}


# ============================================================
# AWS VPC CNI POLICY
# ============================================================

resource "aws_iam_role_policy_attachment" "cni_policy" {

  role = aws_iam_role.eks_node_role.name

  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}


# ============================================================
# ECR PULL POLICY
# ============================================================

resource "aws_iam_role_policy_attachment" "ecr_policy" {

  role = aws_iam_role.eks_node_role.name

  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"
}


# ============================================================
# EKS MANAGED NODE GROUP
# ============================================================

resource "aws_eks_node_group" "eks_nodes" {

  cluster_name = aws_eks_cluster.eks_cluster.name

  node_group_name = "devops-node-group"

  node_role_arn = aws_iam_role.eks_node_role.arn

  subnet_ids = data.aws_subnets.default.ids


  # EC2 instance type
  instance_types = [
    "t3.medium"
  ]


  # Root volume size
  disk_size = 20


  # Node scaling
  scaling_config {

    desired_size = 2

    min_size = 1

    max_size = 3
  }


  # Wait for IAM policies before creating nodes
  depends_on = [

    aws_iam_role_policy_attachment.worker_node_policy,

    aws_iam_role_policy_attachment.cni_policy,

    aws_iam_role_policy_attachment.ecr_policy
  ]


  tags = {

    Name        = "devops-eks-node"

    Environment = "Dev"

    Project = "DevOps-EKS"
  }
}


# ============================================================
# EKS ACCESS ENTRY
#
# This gives the EXISTING terraform-eks IAM ROLE permission
# to authenticate to this EKS cluster.
#
# EC2/Jenkins will assume this role automatically through
# the EC2 Instance Profile.
#
# NO ACCESS KEY
# NO SECRET KEY
# ============================================================

resource "aws_eks_access_entry" "terraform_eks" {

  cluster_name = aws_eks_cluster.eks_cluster.name

  principal_arn = data.aws_iam_role.terraform_eks.arn

  type = "STANDARD"


  depends_on = [
    aws_eks_cluster.eks_cluster
  ]
}


# ============================================================
# EKS ACCESS POLICY
#
# Give terraform-eks role cluster administrator permissions
# for this training/lab cluster.
#
# IMPORTANT:
# For a production Jenkins deployment role, we should later
# replace this with a least-privilege deployment policy.
# ============================================================

resource "aws_eks_access_policy_association" "terraform_eks_cluster_admin" {

  cluster_name = aws_eks_cluster.eks_cluster.name

  principal_arn = data.aws_iam_role.terraform_eks.arn

  policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"


  access_scope {

    type = "cluster"
  }


  depends_on = [

    aws_eks_access_entry.terraform_eks
  ]
}


# ============================================================
# OUTPUTS
# ============================================================

output "eks_cluster_name" {

  description = "EKS cluster name"

  value = aws_eks_cluster.eks_cluster.name
}


output "eks_cluster_endpoint" {

  description = "EKS API server endpoint"

  value = aws_eks_cluster.eks_cluster.endpoint
}


output "eks_cluster_version" {

  description = "Kubernetes version"

  value = aws_eks_cluster.eks_cluster.version
}


output "eks_cluster_arn" {

  description = "EKS cluster ARN"

  value = aws_eks_cluster.eks_cluster.arn
}


output "eks_node_group_name" {

  description = "EKS managed node group name"

  value = aws_eks_node_group.eks_nodes.node_group_name
}


output "eks_vpc_id" {

  description = "VPC used by EKS"

  value = data.aws_vpc.default.id
}


output "eks_subnet_ids" {

  description = "Subnets used by EKS"

  value = data.aws_subnets.default.ids
}


# ============================================================
# NEW OUTPUTS - EKS AUTHENTICATION
# ============================================================

output "eks_access_role_arn" {

  description = "IAM role used by EC2/Jenkins for EKS access"

  value = data.aws_iam_role.terraform_eks.arn
}


output "eks_authentication_mode" {

  description = "EKS cluster authentication mode"

  value = aws_eks_cluster.eks_cluster.access_config[0].authentication_mode
}

