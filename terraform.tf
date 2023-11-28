resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}
/*
resource "azurerm_policy_definition" "rg_policy" {
  name         = "only-deploy-in-francecentral"
  policy_type  = "Custom"
  mode         = "All"
  display_name = "my-policy-definition"
  policy_rule  = file("./policy.json")
}

#resource "azurerm_resource_group_policy_assignment" "policy_assignment" {
#  name                 = "rg-policy-assignment"
#  resource_group_id    = azurerm_resource_group.rg.id
#  policy_definition_id = azurerm_policy_definition.rg_policy.id
#}
*/
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet${trim(azurerm_resource_group.rg.name, "rg")}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = tolist([var.address_space])

  tags = {
    Environment = terraform.workspace
  }
}

locals {
  zones = {
    "francecentral" = ["0", "1", "2"]
    "westeurope"    = ["0", "1"]
  }
}

resource "azurerm_subnet" "public_subnets" {
  count                = var.is_multi_az == true ? length(lookup(local.zones, azurerm_resource_group.rg.location)) : 1
  name                 = format("pub-subnet-%s", count.index)
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  #address_prefixes     = tolist(["10.0.${count.index}.0/24"])
  address_prefixes  = tolist([cidrsubnet(var.address_space, 8, count.index + 1)])
  service_endpoints = ["Microsoft.Storage"]
}

resource "azurerm_subnet" "private_subnets" {
  count                = var.is_multi_az == true ? length(lookup(local.zones, azurerm_resource_group.rg.location)) : 1
  name                 = format("priv-subnet-%s", count.index)
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  #address_prefixes     = tolist(["10.0.${count.index}.0/24"])
  address_prefixes = tolist([cidrsubnet(var.address_space, 8, count.index + 10)])
}

resource "azurerm_nat_gateway" "nat_gw" {
  count                   = var.is_multi_az == true ? length(lookup(local.zones, azurerm_resource_group.rg.location)) : 1
  name                    = format("nat-gw-%s", count.index)
  location                = azurerm_resource_group.rg.location
  resource_group_name     = azurerm_resource_group.rg.name
  sku_name                = "Standard"
  idle_timeout_in_minutes = 10
  zones                   = [count.index + 1]
  tags = {
    "Environment" = terraform.workspace
  }
}

resource "azurerm_public_ip" "public_ips" {
  count               = var.is_multi_az == true ? length(lookup(local.zones, azurerm_resource_group.rg.location)) : 1
  name                = format("nat-gw-pip-%s", count.index)
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags = {
    "Environment" = terraform.workspace
  }
  zones = [count.index + 1]
}

resource "azurerm_nat_gateway_public_ip_association" "natgw_pip_assoc" {
  count                = var.is_multi_az == true ? length(lookup(local.zones, azurerm_resource_group.rg.location)) : 1
  nat_gateway_id       = azurerm_nat_gateway.nat_gw[count.index].id
  public_ip_address_id = azurerm_public_ip.public_ips[count.index].id
}

resource "azurerm_subnet_nat_gateway_association" "natgw_subnet_assoc" {
  count          = var.is_multi_az == true ? length(lookup(local.zones, azurerm_resource_group.rg.location)) : 1
  subnet_id      = azurerm_subnet.private_subnets[count.index].id
  nat_gateway_id = azurerm_nat_gateway.nat_gw[count.index].id
}
resource "azurerm_public_ip" "public_ip" {
  for_each = var.services
  name = format("pip-%s-%s", each.key, terraform.workspace)
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  allocation_method   = "Static"
  tags = {
    "Environment" = terraform.workspace
  }
}

resource "azurerm_network_interface" "nic" {
  for_each = var.services
  name                = format("network-interface-%s",each.key)
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    # Attention c'est une VM avec une IP publique donc on l'ajoute a une reseau public
    # Si vous l'ajoutez au reseau prive qui contient une NATGW vous ne pourra pas SSH dessus
    name                          = format("ip-configuration-%s",each.key)
    subnet_id                     = azurerm_subnet.public_subnets[0].id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.public_ip[each.key].id
  }
  tags = {
    "Environment" = terraform.workspace
  }
}

resource "azurerm_linux_virtual_machine" "wordpress" {
  for_each = var.services
  name                            = title(each.key)
  resource_group_name             = azurerm_resource_group.rg.name
  location                        = azurerm_resource_group.rg.location
  size                            = var.services[each.key].size
  admin_username                  = var.services[each.key].admin_username
  admin_password                  = var.services[each.key].admin_password
  disable_password_authentication = var.services[each.key].disable_password_authentication
  network_interface_ids           = [azurerm_network_interface.nic[each.key].id]
  custom_data = base64encode(templatefile(var.services[each.key].custom_data_path, {
    nfs_endpoint      = azurerm_storage_account.wordpress_data[each.key].primary_blob_host,
    blob_storage_name = "wp-data"
    wordpress_version = var.services[each.key].wordpress_version
  }))


  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = var.services[each.key].source_image_reference.publisher
    offer     = var.services[each.key].source_image_reference.offer
    sku       = var.services[each.key].source_image_reference.sku
    version   = var.services[each.key].source_image_reference.version
  }
  tags = {
    "Environment" = terraform.workspace
  }
}
resource "azurerm_storage_account" "wordpress_data" {
  for_each = var.storage_configurations
  name                     = each.key
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = var.storage_configurations[each.key].account_tier
  account_replication_type = var.storage_configurations[each.key].account_replication_type
  account_kind             = var.storage_configurations[each.key].account_kind
  is_hns_enabled           = var.storage_configurations[each.key].is_hns_enabled
  nfsv3_enabled            = var.storage_configurations[each.key].nfsv3_enabled
  tags = {
    "Environment" = terraform.workspace
  }
  network_rules {
    default_action             = "Deny"
    virtual_network_subnet_ids = [azurerm_subnet.public_subnets[0].id]
    ip_rules                   = [var.my_public_ip]
  }

}


resource "azurerm_storage_container" "container" {
  for_each = var.storage_configurations
  name                  = var.storage_configurations[each.key].container.name
  storage_account_name  = azurerm_storage_account.wordpress_data[each.key].name
  container_access_type = var.storage_configurations[each.key].container.container_access_type
  depends_on            = [
    azurerm_storage_account.wordpress_data]
}

resource "azurerm_linux_virtual_machine_scale_set" "vm-ss"{
  for_each = var.services
  name                = "myvm-vmss"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  instances           = 1
  sku                         = var.services[each.key].size
  admin_username                  = var.services[each.key].admin_username
  admin_password                  = var.services[each.key].admin_password
  disable_password_authentication = var.services[each.key].disable_password_authentication
  custom_data = base64encode(templatefile(var.services[each.key].custom_data_path, {
    nfs_endpoint      = azurerm_storage_account.wordpress_data[each.key].primary_blob_host,
    blob_storage_name = "wp-data"
    wordpress_version = var.services[each.key].wordpress_version
  }))


  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  os_disk {
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
  }

  network_interface {
    name    = "nic-wor"
    primary = true
ip_configuration {
      name      = "internal"
      primary   = true
      subnet_id = azurerm_subnet.private_subnets[0].id
    }
  }
} 

resource "azurerm_lb" "example" {
  name                = "TestLoadBalancer"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.public_ip["wpmomodev"].id
  }
}
resource "azurerm_lb_backend_address_pool" "example" {
  loadbalancer_id = azurerm_lb.example.id
  name            = "BackEndAddressPool"
}

resource "azurerm_lb_nat_rule" "example1" {
  resource_group_name            = azurerm_resource_group.rg.name
  loadbalancer_id                = azurerm_lb.example.id
  name                           = "wor"
  protocol                       = "Tcp"
  frontend_port_start            = 80
  frontend_port_end              = 80
  backend_port                   = 80
  backend_address_pool_id        = azurerm_lb_backend_address_pool.example.id
  frontend_ip_configuration_name = "PublicIPAddress"
}


# scaling cpu 
resource "azurerm_monitor_autoscale_setting" "example" {
  name                = "mycpu-AutoscaleSetting"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  target_resource_id  = azurerm_linux_virtual_machine_scale_set.vm-ss["wpmomodev"].id

  profile {
    name = "defaultProfile"

    capacity {
      default = 1
      minimum = 1
      maximum = 50
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.vm-ss["wpmomodev"].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 50
        metric_namespace   = "microsoft.compute/virtualmachinescalesets"
        dimensions {
          name     = "AppName"
          operator = "Equals"
          values   = ["App1"]
        }
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT1M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.vm-ss["wpmomodev"].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 25
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT1M"
      }
    }
  }

  predictive {
    scale_mode      = "Enabled"
    look_ahead_time = "PT5M"
  }

  notification {
    email {
      send_to_subscription_administrator    = true
      send_to_subscription_co_administrator = true
      custom_emails                         = ["mamadou.coulibalymalle@.ynov.com"]
    }
  }
}
#bulget 
resource "azurerm_monitor_action_group" "example" {
  name                = "example"
  resource_group_name = azurerm_resource_group.rg.name
  short_name          = "example"
}

resource "azurerm_consumption_budget_resource_group" "example" {
  name              = "example"
  resource_group_id = azurerm_resource_group.rg.id

  amount     = 10
  time_grain = "Monthly"

  time_period {
    start_date = "2023-11-01T00:00:00Z"
    end_date   = "2023-11-30T00:00:00Z"
  }

  filter {
    dimension {
      name = "ResourceId"
      values = [
        azurerm_monitor_action_group.example.id,
      ]
    }

    tag {
      name = "foo"
      values = [
        "bar",
        "baz",
      ]
    }
  }

  notification {
    enabled        = true
    threshold      = 90.0
    operator       = "EqualTo"
    threshold_type = "Forecasted"

    contact_emails = [
      "mamadou.coulibalymalle@ynov.com",
      "mamadou.coulibalymalle@ynov.com",
    ]

    contact_groups = [
      azurerm_monitor_action_group.example.id,
    ]

    contact_roles = [
      "Owner",
    ]
  }

  notification {
    enabled   = false
    threshold = 100.0
    operator  = "GreaterThan"

    contact_emails = [
      "mamadou.coulibalymalle@ynov.com",
      "mamadou.coulibalymalle@ynov.com",
    ]
  }
}