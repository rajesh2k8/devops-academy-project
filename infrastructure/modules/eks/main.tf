data "aws_iam_policy_document" "cluster_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster_role" {
  name               = "${var.project_name}-eks-cluster-new-role"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume.json
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSClusterPolicy" {
  role       = aws_iam_role.cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKS_VPC_ResourceController" {
  role       = aws_iam_role.cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
}

# Node group role

data "aws_iam_policy_document" "node_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node_role" {
  name               = "${var.project_name}-eks-node-role"
  assume_role_policy = data.aws_iam_policy_document.node_assume.json
}

resource "aws_iam_role_policy_attachment" "node_AmazonEKSWorkerNodePolicy" {
  role       = aws_iam_role.node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_AmazonEC2ContainerRegistryReadOnly" {
  role       = aws_iam_role.node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "node_AmazonEKS_CNI_Policy" {
  role       = aws_iam_role.node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# Security Groups based on tested setup
resource "aws_security_group" "control_plane" {
  name        = "${var.project_name}-control-plane-sg"
  description = "Control plane ENIs"
  vpc_id      = var.vpc_id
}

resource "aws_security_group_rule" "cp_ingress_https_self" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.control_plane.id
  security_group_id        = aws_security_group.control_plane.id
}

resource "aws_security_group_rule" "cp_egress_kubelet_self" {
  type                     = "egress"
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.control_plane.id
  security_group_id        = aws_security_group.control_plane.id
}

resource "aws_security_group_rule" "cp_egress_https_self" {
  type                     = "egress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.control_plane.id
  security_group_id        = aws_security_group.control_plane.id
}

resource "aws_security_group" "worker" {
  name        = "${var.project_name}-worker-sg"
  description = "Security group for all worker nodes"
  vpc_id      = var.vpc_id
}

resource "aws_security_group_rule" "worker_ingress_all_self" {
  type                     = "ingress"
  protocol                 = "-1"
  from_port                = 0
  to_port                  = 0
  source_security_group_id = aws_security_group.worker.id
  security_group_id        = aws_security_group.worker.id
}

resource "aws_security_group_rule" "worker_ingress_kubelet_from_cp" {
  type                     = "ingress"
  protocol                 = "tcp"
  from_port                = 10250
  to_port                  = 10250
  source_security_group_id = aws_security_group.control_plane.id
  security_group_id        = aws_security_group.worker.id
}

resource "aws_security_group_rule" "worker_ingress_https_from_cp" {
  type                     = "ingress"
  protocol                 = "tcp"
  from_port                = 443
  to_port                  = 443
  source_security_group_id = aws_security_group.control_plane.id
  security_group_id        = aws_security_group.worker.id
}

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  version  = var.eks_version
  role_arn = aws_iam_role.cluster_role.arn

  vpc_config {
    subnet_ids          = var.private_subnet_ids
    security_group_ids  = [aws_security_group.control_plane.id]
  }
}

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.project_name}-nodes"
  node_role_arn   = aws_iam_role.node_role.arn

  subnet_ids = var.private_subnet_ids

  scaling_config {
    desired_size = var.node_desired
    max_size     = var.node_max
    min_size     = var.node_min
  }

  instance_types = [var.node_instance_type]
  disk_size      = var.node_disk_size

  update_config { max_unavailable = 1 }
}

data "tls_certificate" "oidc_thumbprint" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "this" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.oidc_thumbprint.certificates[0].sha1_fingerprint]
}

output "cluster_name" { value = aws_eks_cluster.this.name }
output "oidc_provider_arn" { value = aws_iam_openid_connect_provider.this.arn }
