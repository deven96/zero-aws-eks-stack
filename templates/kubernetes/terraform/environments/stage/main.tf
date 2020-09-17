terraform {
  backend "s3" {
    bucket         = "<% .Name %>-stage-terraform-state"
    key            = "infrastructure/terraform/environments/stage/kubernetes"
    encrypt        = true
    region         = "<% index .Params `region` %>"
    dynamodb_table = "<% .Name %>-stage-terraform-state-locks"
  }
}

provider "aws" {
  region = "<% index .Params `region` %>"
}

# Provision kubernetes resources required to run services/applications
module "kubernetes" {
  source = "../../modules/kubernetes"

  project = "<% .Name %>"

  environment         = "stage"
  region              = "<% index .Params `region` %>"
  allowed_account_ids = ["<% index .Params `accountId` %>"]
  random_seed         = "<% index .Params `randomSeed` %>"

  # Authenticate with the EKS cluster via the cluster id
  cluster_name = "<% .Name %>-stage-<% index .Params `region` %>"

  external_dns_zone     = "<% index .Params `stagingHostRoot` %>"
  external_dns_owner_id = "<% GenerateUUID %>" # randomly generated ID

  # Registration email for LetsEncrypt
  cert_manager_acme_registration_email = "devops@<% index .Params `stagingHostRoot` %>"

  # Logging configuration
  logging_type = "<% index .Params `loggingType` %>"

  # Application policy list - This allows applications running in kubernetes to have access to AWS resources.
  # Specify the service account name, the namespace, and the policy that should be applied.
  # This makes use of IRSA: https://aws.amazon.com/blogs/opensource/introducing-fine-grained-iam-roles-service-accounts/
  application_policy_list = [
    {
      service_account = "backend-service"
      namespace       = "<% .Name %>"
      policy          = data.aws_iam_policy_document.resource_access_backendservice
    }
    # Add additional mappings here
  ]


  # Wireguard configuration
  vpn_server_address = "10.10.199.0/24"
  vpn_client_publickeys = [
    ["Max C", "10.10.199.201/32", "/B3Q/Hlf+ILInjpehTLk9DZGgybdGdbm0SsG87OnWV0="],
    ["Carter L", "10.10.199.202/32", "h2jMuaXNIlx7Z0a3owWFjPsAA8B+ZpQH3FbZK393+08="],
  ]
}
