terraform {
  required_providers {
    flux = {
      source  = "fluxcd/flux"
      version = "0.1.6"
    }

    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "1.10.0"
    }
  }
}