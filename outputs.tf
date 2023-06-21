output "update_kubeconfig" {
  description = "Command to launch to use kubectl"
  value       = "aws eks update-kubeconfig --name ${var.cluster_name} --kubeconfig ~/.kube/config"
}
