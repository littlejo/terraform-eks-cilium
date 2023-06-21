variable "azs" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b"]
}

variable "cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "vpc_name" {
  type    = string
  default = "eks"
}

variable "cluster_name" {
  type    = string
  default = "terraform-cilium"
}

variable "cluster_version" {
  type    = string
  default = "1.27"
}
