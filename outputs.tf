output update_kubeconfig {
  value = "aws eks update-kubeconfig --name ${var.cluster_name} --kubeconfig ~/.kube/config"
}
