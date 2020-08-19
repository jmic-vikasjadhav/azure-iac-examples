locals {
  fw_pip_name         = "${var.prefix}-fw-pip"
  fw_name             = "${var.prefix}-fw"
  fw_diagnostics_name = "${var.prefix}-fw-diagnostics"
}

resource azurerm_public_ip "az_firewall_pip" {
  name                = local.fw_pip_name
  location            = azurerm_resource_group.rg["network-rg"].location
  resource_group_name = azurerm_resource_group.rg["network-rg"].name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource azurerm_firewall "az_firewall" {
  name                = local.fw_name
  location            = azurerm_resource_group.rg["network-rg"].location
  resource_group_name = azurerm_resource_group.rg["network-rg"].name

  ip_configuration {
    name                 = "configuration"
    subnet_id            = element(tolist(azurerm_virtual_network.vnet["hub-vnet"].subnet),1).id
    public_ip_address_id = azurerm_public_ip.az_firewall_pip.id
  }

  tags = var.tags
}

resource "azurerm_monitor_diagnostic_setting" "az_firewall_diagnostics" {
  name                       = local.fw_diagnostics_name
  target_resource_id         = azurerm_firewall.az_firewall.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.workspace.id

  log {
    category = "AzureFirewallApplicationRule"
    enabled  = true

    retention_policy {
      enabled = true
      days    = 7
    }
  }

  log {
    category = "AzureFirewallNetworkRule"
    enabled  = true

    retention_policy {
      enabled = true
      days    = 7
    }
  }

  metric {
    category = "AllMetrics"

    retention_policy {
      enabled = true
      days    = 7
    }
  }
}
