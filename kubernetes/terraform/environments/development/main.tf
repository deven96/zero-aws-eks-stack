terraform {
  backend "s3" {
    bucket         = "<% .Name %>-development-terraform-state"
    key            = "infrastructure/terraform/environments/development/kubernetes"
    encrypt        = true
    region         = "<% index .Params `region` %>"
    dynamodb_table = "<% .Name %>-development-terraform-state-locks"
  }
}

# Provision kubernetes resources required to run services/applications
module "kubernetes" {
  source = "../../modules/kubernetes"

  environment = "development"
  region      = "<% index .Params `region` %>"

  # Authenticate with the EKS cluster via the cluster id
  cluster_name = "<% .Name %>-dev-<% index .Params `region` %>"

  external_dns_zone = "<% index .Params `stagingHost` %>"
  external_dns_owner_id = "<% GenerateUUID %>" # randomly generated ID

  # Registration email for LetsEncrypt
  cert_manager_acme_registration_email = "devops@<% index .Params `stagingHost` %>"
}
