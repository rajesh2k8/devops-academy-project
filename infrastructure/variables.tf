variable "region" {
  type        = string
  description = "AWS region"
  default     = "ap-south-1"
}

variable "project_name" {
  type        = string
  description = "Common tag/name prefix"
  default     = "capstone"
}

variable "vpc_cidr" {
  type        = string
  default     = "10.168.0.0/23"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  default     = ["10.168.0.0/25", "10.168.0.128/25"]
}

variable "private_subnet_cidrs" {
  type        = list(string)
  default     = ["10.168.1.0/25", "10.168.1.128/25"]
}

variable "azs" {
  type        = list(string)
  description = "Two availability zones"
  default     = ["ap-south-1a", "ap-south-1b"]
}

variable "cluster_name" {
  type        = string
  default     = "gl-devops-academy-batch1-project-eks-cluster"
}

variable "eks_version" {
  type        = string
  default     = "1.30"
}

variable "node_instance_type" {
  type        = string
  default     = "t3.small"
}

variable "node_disk_size" {
  type        = number
  default     = 30
}

variable "node_desired" {
  type        = number
  default     = 2
}

variable "node_min" {
  type        = number
  default     = 1
}

variable "node_max" {
  type        = number
  default     = 3
}

variable "ssh_cidr" {
  type        = string
  description = "CIDR allowed for SSH (22). Set to your IP/CIDR for lockdown."
  default     = "0.0.0.0/0"
}

variable "ecr_repositories" {
  type        = list(string)
  description = "ECR repositories to create"
  default     = ["gl-devops-academy-batch1-project-repo"]
}
