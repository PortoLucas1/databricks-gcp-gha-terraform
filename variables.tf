variable "project_id" {
  description = "The workspace project. bootstrap/ creates the identities this pipeline runs as in it; the project itself is a prerequisite."
  type        = string
}

variable "region" {
  description = "Region for the subnet and bucket."
  type        = string
  default     = "us-central1"
}

variable "network" {
  description = "The test VPC: one custom-mode network with one subnet."
  type = object({
    name        = optional(string, "gha-test-vpc")
    subnet_cidr = optional(string, "10.250.0.0/24")
  })
  default = {}
}
