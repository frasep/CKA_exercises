###########################################################
# Declare all variables
###########################################################

variable "admin_username" {
    type = string
    description = "Administrator user name for virtual machine"
}

variable "admin_password" {
    type = string
    description = "Password must meet Azure complexity requirements"
}

variable "location" {
    type = string
}

variable "vm1vmtype" {
    type = string
}

variable "vm2vmtype" {
    type = string
}

variable "vm3vmtype" {
    type = string
}

variable "vm4vmtype" {
    type = string
}


###########################################################
# End of variable declaration block
###########################################################

# Configure the Azure provider
terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = ">= 2.26"
    }
  }

  required_version = ">= 0.14.9"
}

provider "azurerm" {
  features {
    resource_group {
       prevent_deletion_if_contains_resources = false
    }
  }
}

resource "azurerm_resource_group" "rg" {
  name     = "frasepK8s_rg"
  location = var.location
  tags = {
        Environment = "Multi node cluster for k8s demo and training"
        resourceowner = "frasep"
    }
}

###########################################################
# Create a virtual network
resource "azurerm_virtual_network" "vnet" {
    name                = "frasepK8s_vnet"
    address_space       = ["10.0.0.0/16"]
    location            = var.location
    resource_group_name = azurerm_resource_group.rg.name
}

###########################################################
# Create subnet
resource "azurerm_subnet" "subnet" {
  name                 = "frasepK8s_Subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

###########################################################
# Create public IP
resource "azurerm_public_ip" "vm1publicip" {
  name                = "frasepK8svm1_PublicIP"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
}

data "azurerm_public_ip" "vm1ip" {
  name                = azurerm_public_ip.vm1publicip.name
  resource_group_name = azurerm_linux_virtual_machine.vm1.resource_group_name
  depends_on          = [azurerm_linux_virtual_machine.vm1]
}

###########################################################
# Create Network Security Group and rule
resource "azurerm_network_security_group" "nsg" {
  name                = "frasepK8s_NSG"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "k8s_nsg"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefixes    = ["149.173.0.0/16","90.127.106.134/32","90.127.103.11/32","10.0.0.0/16","194.206.69.177/32","90.127.146.120/32"]
    destination_address_prefix = "*"
  }

}

# Associate NSG and created subnet to apply it to all VMS in the subnet
resource "azurerm_subnet_network_security_group_association" "subnet_nsg" {
  subnet_id                 = azurerm_subnet.subnet.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

###########################################################
# Create network interface for vm1 (service and compute)
resource "azurerm_network_interface" "vm1nic" {
  name                      = "frasepK8svm1_NIC"
  location                  = var.location
  resource_group_name       = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "vm1NICConfg"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.1.4"
    public_ip_address_id          = azurerm_public_ip.vm1publicip.id
  }

}

###########################################################
# Create network interface for vm2 (controller)
resource "azurerm_network_interface" "vm2nic" {
  name                      = "frasepK8svm2_NIC"
  location                  = var.location
  resource_group_name       = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "vm2NICConfg"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.1.5"
  }
}

###########################################################
# Create network interface for vm3 (worker 1)
resource "azurerm_network_interface" "vm3nic" {
  name                      = "frasepK8svm3_NIC"
  location                  = var.location
  resource_group_name       = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "vm3NICConfg"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.1.6"
  }
}

###########################################################
# Create network interface for vm4 (worker 2)
resource "azurerm_network_interface" "vm4nic" {
  name                      = "frasepK8svm4_NIC"
  location                  = var.location
  resource_group_name       = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "vm4NICConfg"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.1.7"
  }
}


###########################################################
# Create a Linux virtual machine control plane

resource "azurerm_linux_virtual_machine" "vm1" {
  name                  = "c1-cp1"
  location              = var.location
  resource_group_name   = azurerm_resource_group.rg.name
  network_interface_ids = [azurerm_network_interface.vm1nic.id]
  size                  = var.vm1vmtype
  depends_on            = [azurerm_linux_virtual_machine.vm2, azurerm_linux_virtual_machine.vm3, azurerm_linux_virtual_machine.vm4]

  disable_password_authentication = false
  computer_name  = "c1-cp1"
  admin_username = var.admin_username
  admin_password = var.admin_password

  os_disk {
    name              = "c1-cp1-disk"
    caching           = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts-gen2"
    version   = "latest"
  }
}



###########################################################
# Create a Linux virtual machine (controller)

resource "azurerm_linux_virtual_machine" "vm2" {
  name                  = "c1-node1"
  location              = var.location
  resource_group_name   = azurerm_resource_group.rg.name
  network_interface_ids = [azurerm_network_interface.vm2nic.id]
  size                  = var.vm2vmtype

  disable_password_authentication = false
  computer_name  = "c1-node1"
  admin_username = var.admin_username
  admin_password = var.admin_password

  os_disk {
    name              = "c1-node1-disk"
    caching           = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts-gen2"
    version   = "latest"
  }
}


###########################################################
# Create a Linux virtual machine (worker 1)

resource "azurerm_linux_virtual_machine" "vm3" {
  name                  = "c1-node2"
  location              = var.location
  resource_group_name   = azurerm_resource_group.rg.name
  network_interface_ids = [azurerm_network_interface.vm3nic.id]
  size                  = var.vm3vmtype

  disable_password_authentication = false
  computer_name  = "c1-node2"
  admin_username = var.admin_username
  admin_password = var.admin_password

  os_disk {
    name              = "c1-node2-disk"
    caching           = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts-gen2"
    version   = "latest"
  }
}

###########################################################
# Create a Linux virtual machine (worker 2)

resource "azurerm_linux_virtual_machine" "vm4" {
  name                  = "c1-node3"
  location              = var.location
  resource_group_name   = azurerm_resource_group.rg.name
  network_interface_ids = [azurerm_network_interface.vm4nic.id]
  size                  = var.vm4vmtype

  disable_password_authentication = false
  computer_name  = "c1-node3"
  admin_username = var.admin_username
  admin_password = var.admin_password

  os_disk {
    name              = "c1-node3-disk"
    caching           = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts-gen2"
    version   = "latest"
  }
}


