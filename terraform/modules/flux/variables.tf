variable "target_path" {
  type        = string
  description = "The path in the Git repository where Flux will sync from"
}

variable "git_repository" {
  type        = string
  description = "The Git repository URL that Flux will use"
}

variable "git_branch" {
  type        = string
  description = "The Git branch that Flux will sync from"
}

variable "flux_ssh_key_public" {
  type        = string
  description = "The public SSH key Flux will use to authenticate against the git repository"
}

variable "flux_ssh_key_private" {
  type        = string
  description = "The private SSH key Flux will use to authenticate against the git repository"
}
