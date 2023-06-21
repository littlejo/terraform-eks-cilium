variable "azs" {
  description = "List of availability zones to install eks"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "10.0.0.0/16"
}

variable "vpc_name" {
  description = "VPC name"
  type        = string
  default     = "eks"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "terraform-cilium"
}

variable "cluster_version" {
  description = "kubernetes cluster version"
  type        = string
  default     = "1.27"
}

variable "install_cilium" {
  description = "Do you want to install cilium"
  type        = bool
  default     = true
}
