# General Variables

variable "azure_location" {
  description = "The region to deploy Rubrik Cloud Cluster resources."
}

variable "azure_resource_group" {
  description = "The Azure Resource Group into which deploy Rubrik Cloud Cluster resources."
  type        = string
  default     = "RubrikCloudCluster"
}

variable "azure_resource_lock" {
  description = "Enable the Azure Resource Lock on critical components that are created by this module."
  type        = bool
  default     = true
}

variable "azure_subscription_id" {
  description = "Subscription ID of the Azure account to deploy Rubrik Cloud Cluster resources. Deprecated: This variable is no longer required as the subscription ID is now determined by the provider configuration."
  type        = string
  default     = null

  validation {
    condition     = var.azure_subscription_id == null ? true : can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.azure_subscription_id))
    error_message = "The subscription ID must be a valid UUID format if provided."
  }
}

variable "azure_tags" {
  description = "Tags to add to the Azure resources that this Terraform script creates, including the Rubrik cluster nodes."
  type        = map(string)
  default     = {}
}

# Cloud Cluster Node Information

variable "azure_cces_plan_name" {
  description = "The Azure Marketplace Plan Name/ID of the CCES image to deploy. See the README.MD file of this module for information on finding the plan name."
}

variable "azure_cces_sku" {
  description = "The SKU for the Azure Marketplace Image of CCES to deploy. See the README.MD file of this module for information on finding the SKU."
  type        = string

  validation {
    condition     = can(regex("^rubrik-cdm-(\\d+)$", var.azure_cces_sku))
    error_message = "The SKU must be in the format 'rubrik-cdm-<version>'. For example, 'rubrik-cdm-92'."
  }
}

variable "azure_cces_version" {
  description = "The version of CCES to deploy. Use 'latest' to deploy the latest available version. Note: This only applies to the version within a SKU (major/minor version)."
  type        = string
  default     = "latest"

  validation {
    condition     = can(regex("^(\\d+).(\\d+).(\\d+)$|^(latest)$", var.azure_cces_version))
    error_message = "The version must be in the format '<minor>.<maintenance>.<build>' for CDM version 8.1 and later or '<major>.<minor>.<maintenance>' for CDM 8.0 and earlier. For example, '2.1.29213'."
  }
}

variable "azure_cces_vm_size" {
  description = "The Azure VM Machine Type to use for the Cloud Cluster nodes."
  type        = string
  default     = "Standard_D16s_v5"
}

variable "azure_key_vault_name" {
  description = "The name of the Azure Key Vault to create, into which the CCES private ssh key will be stored."
  type        = string
  default     = ""
}

variable "cluster_name" {
  description = "Unique name to assign to the Rubrik Cloud Cluster. This will also be used as part of the Storage Account name. For example, rubrik-cloud-cluster-1, rubrik-cloud-cluster-2 etc."
  type        = string
  default     = "rubrik-cloud-cluster"
}

variable "number_of_nodes" {
  description = "The total number of nodes in Rubrik Cloud Cluster."
  type        = number
  default     = 3
}

# Networking

variable "azure_subnet_name" {
  description = "Name of the Azure subnet to deploy Rubrik Cloud Cluster into. This subnet must be in the VNet that is defined in the 'azure_vnet_name' variable."
  type        = string
}

variable "azure_vnet_name" {
  description = "Name of the Azure Virtual Network (VNet) to deploy Rubrik Cloud Cluster ES into."
  type        = string
}

variable "azure_vnet_rg_name" {
  description = "Name of the Resource Group of the Azure VNet that is defined in the 'azure_vnet_name' variable."
  type        = string
}

# Storage Variables

variable "azure_enable_subnet_storage_endpoint" {
  description = "Whether to enable the Storage service endpoint on the VPC subnet. Defaults to `true`."
  type        = bool
  default     = true
}

variable "azure_sa_name" {
  description = "The name of the Azure Storage Account to create for Rubrik Cloud Cluster resources."
  type        = string
}

variable "azure_sa_replication_type" {
  description = "The type of replication to use with the the Azure Storage Account for Rubrik Cloud Cluster."
  type        = string
  default     = "LRS"
}

variable "enableImmutability" {
  description = "Enables object lock and versioning on the Storage Account and Container. Sets the object lock flag during bootstrap. Not supported on CDM v8.0.1 and earlier."
  type        = bool
  default     = true
}

# Bootstrap Information

variable "admin_email" {
  description = "The Rubrik Cloud Cluster sends messages for the admin account to this email address."
  type        = string
}

variable "admin_password" {
  description = "Password for the Rubrik Cloud Cluster admin account."
  type        = string
  sensitive   = true
  default     = "ChangeMe"
}

variable "dns_search_domain" {
  type        = list(any)
  description = "List of search domains that the DNS Service will use to resolve host names that are not fully qualified."
  default     = []
}

variable "dns_name_servers" {
  type        = list(any)
  description = "List of the IPv4 addresses of the DNS servers."
  default     = ["169.254.169.253"]
}

variable "ntp_server1_name" {
  description = "The FQDN or IPv4 addresses of network time protocol (NTP) server #1."
  type        = string
  default     = "8.8.8.8"
}

variable "ntp_server1_key_id" {
  description = "The ID number of the symmetric key used with NTP server #1. (Typically this is 0)"
  type        = number
  default     = 0
}

variable "ntp_server1_key" {
  description = "Symmetric key material for NTP server #1."
  type        = string
  sensitive   = true
  default     = ""
}

variable "ntp_server1_key_type" {
  description = "Symmetric key type for NTP server #1."
  type        = string
  sensitive   = true
  default     = ""
}

variable "ntp_server2_name" {
  description = "The FQDN or IPv4 addresses of network time protocol (NTP) server #2."
  type        = string
  default     = "8.8.4.4"
}

variable "ntp_server2_key_id" {
  description = "The ID number of the symmetric key used with NTP server #2. (Typically this is 0)"
  type        = number
  default     = 0
}

variable "ntp_server2_key" {
  description = "Symmetric key material for NTP server #2."
  type        = string
  sensitive   = true
  default     = ""
}

variable "ntp_server2_key_type" {
  description = "Symmetric key type for NTP server #2."
  type        = string
  sensitive   = true
  default     = ""
}

variable "register_cluster_with_rsc" {
  description = "Register the Rubrik Cloud Cluster with Rubrik Security Cloud."
  type        = bool
  default     = false
}

variable "timeout" {
  description = "The number of seconds to wait to establish a connection the Rubrik cluster before returning a timeout error."
  type        = string
  default     = "4m"
}

check "deprecations" {
  assert {
    condition     = var.azure_subscription_id == null
    error_message = "The 'azure_subscription_id' variable is deprecated and should not be used as it will be removed in a future release. Configure the subscription ID in the azurerm provider configuration instead."
  }
}

variable "azure_enable_public_ip" {
  description = "Enable public IPs on CCES nodes for bootstrap access."
  type        = bool
  default     = false
}
