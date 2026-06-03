#############################
# Dynamic Variable Creation #
#############################

locals {
  enableImmutability = var.enableImmutability == true ? 1 : 0
  cluster_node_names = formatlist("${var.cluster_name}-%02s", range(1, var.number_of_nodes + 1))
  cluster_node_ips   = var.azure_enable_public_ip ? [for i in azurerm_linux_virtual_machine.cces_node : i.public_ip_address] : [for i in azurerm_linux_virtual_machine.cces_node : i.private_ip_address]
}

##################
# Data Gathering #
##################

data "azurerm_subscription" "current" {}

data "azurerm_subnet" "cces_subnet" {
  name                 = var.azure_subnet_name
  virtual_network_name = var.azure_vnet_name
  resource_group_name  = var.azure_vnet_rg_name
}

data "azurerm_client_config" "current" {}

####################################
# Create a Resource Group for CCES #
####################################

resource "azurerm_resource_group" "cc_rg" {
  name     = var.azure_resource_group
  location = var.azure_location

  tags = var.azure_tags
}

#####################################################
# Create the storage account and container for CCES #
#####################################################

resource "azurerm_storage_account" "cc_storage_account" {
  name                          = var.azure_sa_name
  resource_group_name           = azurerm_resource_group.cc_rg.name
  location                      = azurerm_resource_group.cc_rg.location
  account_tier                  = "Standard"
  account_replication_type      = var.azure_sa_replication_type
  public_network_access_enabled = true

  blob_properties {
    versioning_enabled = var.enableImmutability
  }

  tags = var.azure_tags
}

# Workaround until azurerm_storage_container supports setting the version level immutability option.
# See https://github.com/hashicorp/terraform-provider-azurerm/issues/21512 
# and https://github.com/hashicorp/terraform-provider-azurerm/issues/3722 for more details.

resource "azapi_resource" "cc_container" {
  type = "Microsoft.Storage/storageAccounts/blobServices/containers@2022-09-01"
  name = var.cluster_name

  # We append '/blobServices/default' to the storage_account.id see desc. above
  parent_id = "${azurerm_storage_account.cc_storage_account.id}/blobServices/default"

  body = {
    properties = {
      immutableStorageWithVersioning = {
        enabled = "${var.enableImmutability}"
      }
      publicAccess = "None"
    }
  }
}

# Note. this azapi_resource can be replaced with the "service_endpoints = ["Microsoft.Storage"]"
# option on the azurerm_subnet resource if the subnet is also created by Terraform.

resource "azapi_update_resource" "cces_subnet_storage_endpoint" {
  count       = var.azure_enable_subnet_storage_endpoint ? 1 : 0
  type        = "Microsoft.Network/virtualNetworks/subnets@2023-02-01"
  resource_id = data.azurerm_subnet.cces_subnet.id

  body = {
    properties = {
      serviceEndpoints = [{
        service = "Microsoft.Storage"
      }]
    }
  }
}

########$$$$$$$#######################
# Create SSH KEY PAIR FOR CCES Nodes #
###############$$$$$$#################

# Create RSA key of size 4096 bits
resource "tls_private_key" "cc-key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "azurerm_key_vault" "cc_key_vault" {
  name                        = var.azure_key_vault_name == "" ? "${var.cluster_name}" : var.azure_key_vault_name
  location                    = azurerm_resource_group.cc_rg.location
  resource_group_name         = azurerm_resource_group.cc_rg.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false

  sku_name = "standard"

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    key_permissions = [
      "Create",
      "Get",
    ]

    secret_permissions = [
      "Set",
      "Get",
      "Delete",
      "Purge",
      "Recover"
    ]
  }

  tags = var.azure_tags
}

resource "azurerm_key_vault_secret" "cc_private_ssh_key" {
  name         = "${var.cluster_name}-ssh-private-key"
  value        = tls_private_key.cc-key.private_key_pem
  content_type = "SSH Key"
  key_vault_id = azurerm_key_vault.cc_key_vault.id
}

resource "azurerm_ssh_public_key" "cc_public_ssh_key" {
  name                = "${var.cluster_name}-public-key"
  resource_group_name = azurerm_resource_group.cc_rg.name
  location            = azurerm_resource_group.cc_rg.location
  public_key          = tls_private_key.cc-key.public_key_openssh

  tags = var.azure_tags
}

############################################
# Launch the Rubrik Cloud Cluster ES Nodes #
######################k#####################

resource "azurerm_network_interface" "cces_nic" {
  for_each                       = toset(local.cluster_node_names)
  name                           = "${each.value}-nic"
  resource_group_name            = azurerm_resource_group.cc_rg.name
  location                       = azurerm_resource_group.cc_rg.location
  accelerated_networking_enabled = true

  ip_configuration {
    name                          = each.value
    subnet_id                     = data.azurerm_subnet.cces_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = var.azure_enable_public_ip ? azurerm_public_ip.cces_public_ip[each.value].id : null
  }

  tags = var.azure_tags
}

resource "azurerm_public_ip" "cces_public_ip" {
  for_each            = var.azure_enable_public_ip ? toset(local.cluster_node_names) : []
  name                = "${each.value}-pip"
  resource_group_name = azurerm_resource_group.cc_rg.name
  location            = azurerm_resource_group.cc_rg.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.azure_tags
}

resource "azurerm_management_lock" "cces_nic" {
  for_each   = var.azure_resource_lock == true ? toset(local.cluster_node_names) : []
  name       = "${each.value}-nic"
  scope      = azurerm_network_interface.cces_nic[each.value].id
  lock_level = "CanNotDelete"
  notes      = "Locked because this is a critical resource."
}

# User needs to make sure that the marketplace agreement for CCES has been accepted before this runs.

resource "azurerm_linux_virtual_machine" "cces_node" {
  for_each              = toset(local.cluster_node_names)
  name                  = "${each.value}-vm"
  location              = azurerm_resource_group.cc_rg.location
  resource_group_name   = azurerm_resource_group.cc_rg.name
  network_interface_ids = [azurerm_network_interface.cces_nic[each.value].id]
  size                  = var.azure_cces_vm_size
  admin_username        = "azureuser"

  admin_ssh_key {
    username   = "azureuser"
    public_key = tls_private_key.cc-key.public_key_openssh
  }

  source_image_reference {
    publisher = "rubrik-inc"
    offer     = "rubrik-data-protection"
    sku       = var.azure_cces_sku
    version   = var.azure_cces_version
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  plan {
    name      = var.azure_cces_plan_name
    publisher = "rubrik-inc"
    product   = "rubrik-data-protection"
  }

  tags = var.azure_tags

}

resource "azurerm_management_lock" "cces_node" {
  for_each   = var.azure_resource_lock == true ? toset(local.cluster_node_names) : []
  name       = "${each.value}-vm"
  scope      = azurerm_linux_virtual_machine.cces_node[each.value].id
  lock_level = "CanNotDelete"
  notes      = "Locked because this is a critical resource."
}

resource "azurerm_managed_disk" "cces_data_disk" {
  for_each             = toset(local.cluster_node_names)
  name                 = "${each.value}-disk"
  location             = azurerm_resource_group.cc_rg.location
  resource_group_name  = azurerm_resource_group.cc_rg.name
  storage_account_type = "Premium_LRS"
  create_option        = "Empty"
  disk_size_gb         = "512"
  tags                 = var.azure_tags
}

resource "azurerm_management_lock" "cces_data_disk" {
  for_each   = var.azure_resource_lock == true ? toset(local.cluster_node_names) : []
  name       = "${each.value}-disk"
  scope      = azurerm_managed_disk.cces_data_disk[each.value].id
  lock_level = "CanNotDelete"
  notes      = "Locked because this is a critical resource."
}

resource "azurerm_virtual_machine_data_disk_attachment" "cces_data_disk" {
  for_each           = toset(local.cluster_node_names)
  managed_disk_id    = azurerm_managed_disk.cces_data_disk[each.value].id
  virtual_machine_id = azurerm_linux_virtual_machine.cces_node[each.value].id
  lun                = "0"
  caching            = "ReadWrite"
}

# Create 2 additional disks, one for metadata and for cache, per cluster node
# for CDM version 9.2.2 and later.

resource "azurerm_managed_disk" "cces_metadata_disk" {
  for_each             = local.split_disk ? toset(local.cluster_node_names) : []
  name                 = "${each.value}-metadata-disk"
  location             = azurerm_resource_group.cc_rg.location
  resource_group_name  = azurerm_resource_group.cc_rg.name
  storage_account_type = "Premium_LRS"
  create_option        = "Empty"
  disk_size_gb         = "132"
  tags                 = var.azure_tags
}

resource "azurerm_management_lock" "cces_metadata_disk" {
  for_each   = local.split_disk && var.azure_resource_lock ? toset(local.cluster_node_names) : []
  name       = "${each.value}-metadata-disk"
  scope      = azurerm_managed_disk.cces_metadata_disk[each.value].id
  lock_level = "CanNotDelete"
  notes      = "Locked because this is a critical resource."
}

resource "azurerm_virtual_machine_data_disk_attachment" "cces_metadata_disk" {
  for_each           = local.split_disk ? toset(local.cluster_node_names) : []
  managed_disk_id    = azurerm_managed_disk.cces_metadata_disk[each.value].id
  virtual_machine_id = azurerm_linux_virtual_machine.cces_node[each.value].id
  lun                = "1"
  caching            = "ReadWrite"
}

resource "azurerm_managed_disk" "cces_cache_disk" {
  for_each             = local.split_disk ? toset(local.cluster_node_names) : []
  name                 = "${each.value}-cache-disk"
  location             = azurerm_resource_group.cc_rg.location
  resource_group_name  = azurerm_resource_group.cc_rg.name
  storage_account_type = "Premium_LRS"
  create_option        = "Empty"
  disk_size_gb         = "206"
  tags                 = var.azure_tags
}

resource "azurerm_management_lock" "cces_cache_disk" {
  for_each   = local.split_disk && var.azure_resource_lock ? toset(local.cluster_node_names) : []
  name       = "${each.value}-cache-disk"
  scope      = azurerm_managed_disk.cces_cache_disk[each.value].id
  lock_level = "CanNotDelete"
  notes      = "Locked because this is a critical resource."
}

resource "azurerm_virtual_machine_data_disk_attachment" "cces_cache_disk" {
  for_each           = local.split_disk ? toset(local.cluster_node_names) : []
  managed_disk_id    = azurerm_managed_disk.cces_cache_disk[each.value].id
  virtual_machine_id = azurerm_linux_virtual_machine.cces_node[each.value].id
  lun                = "2"
  caching            = "ReadWrite"
}

######################################
# Bootstrap the Rubrik Cloud Cluster #
###########################k##########

resource "time_sleep" "wait_for_nodes_to_boot" {
  create_duration = "300s"

  depends_on = [
    azurerm_virtual_machine_data_disk_attachment.cces_data_disk,
    azurerm_virtual_machine_data_disk_attachment.cces_metadata_disk,
    azurerm_virtual_machine_data_disk_attachment.cces_cache_disk,
  ]
}

resource "polaris_cdm_bootstrap_cces_azure" "bootstrap_cces_azure" {
  cluster_name           = var.cluster_name
  cluster_nodes          = zipmap(local.cluster_node_names, local.cluster_node_ips)
  admin_email            = var.admin_email
  admin_password         = var.admin_password
  management_gateway     = cidrhost(data.azurerm_subnet.cces_subnet.address_prefixes.0, 1)
  management_subnet_mask = cidrnetmask(data.azurerm_subnet.cces_subnet.address_prefixes.0)
  dns_search_domain      = var.dns_search_domain
  dns_name_servers       = var.dns_name_servers
  ntp_server1_name       = var.ntp_server1_name
  ntp_server2_name       = var.ntp_server2_name
  connection_string      = azurerm_storage_account.cc_storage_account.primary_connection_string
  container_name         = var.cluster_name
  enable_immutability    = var.enableImmutability
  timeout                = var.timeout
  depends_on             = [time_sleep.wait_for_nodes_to_boot]
}

##############################################
# Register the Rubrik Cloud Cluster with RSC #
##############################################

resource "polaris_cdm_registration" "cces_azure_registration" {
  count                   = var.register_cluster_with_rsc ? 1 : 0
  admin_password          = var.admin_password
  cluster_name            = var.cluster_name
  cluster_node_ip_address = local.cluster_node_ips[0]
  depends_on              = [polaris_cdm_bootstrap_cces_azure.bootstrap_cces_azure]
}
