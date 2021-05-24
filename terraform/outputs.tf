output "kubectl_config" {
  description = "kubectl config"
  value       = module.eks.kubeconfig
}

output "flux_deploy_key" {
  description = "The deploy key to add to the Git reposityory"
  value       = tls_private_key.flux_ssh_key.public_key_openssh
}