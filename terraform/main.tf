resource "azurerm_resource_group" "rg" {
  name     = "rg-voting-app"
  location = var.location
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = "aks-voting-app"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "aks-voting-app"

  default_node_pool {
    name       = "nodepool1"
    node_count = var.node_count
    vm_size    = var.vm_size
  }

  identity {
    type = "SystemAssigned"
  }

  tags = {
    environment = "production"
    project     = "voting-app"
  }
}