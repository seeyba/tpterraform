address_space       = "10.16.0.0/16"
resource_group_name = "rg-dev"
my_public_ip = "46.193.67.209"

# ATTENTION les clé de services et storage_configurations doivent etre identique pour que ca fonctionne

services = {
  wpmomodev = {
    size = "Standard_F2"
    admin_username = "adminuser"
    admin_password = "Plop09"
    disable_password_authentication = false
    custom_data_path = "templates/start.sh"
    wordpress_version = "6.3.1"
    source_image_reference = {
      publisher = "Canonical"
      offer     = "UbuntuServer"
      sku       = "18.04-LTS"
      version   = "latest"
    }
  }
}

storage_configurations = {
  wpmomodev = {
    account_tier = "Standard"
    account_replication_type = "LRS"
    account_kind =  "StorageV2"
    is_hns_enabled = true
    nfsv3_enabled = true
    container = {
      name = "wp-data"
      container_access_type = "private"
    }

  }
}