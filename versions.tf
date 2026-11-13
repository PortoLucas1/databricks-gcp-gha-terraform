terraform {
  required_version = "~> 1.15"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.10"
    }
  }

  # Bucket and prefix come from the workflow (-backend-config). The bucket is
  # bootstrap/'s, in the workspace project.
  backend "gcs" {}
}

provider "google" {
  project = var.project_id
  region  = var.region
}
