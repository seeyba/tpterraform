variable "address_space" {
  type        = string
  description = "Vnet CIDR"
}
variable "subnet_config" {
  type        = map(string)
  description = "Subnet name and cidr"
  default = {}
}
variable "location" {
  type        = string
  default     = "France Central"
  description = "Region"
}

variable "resource_group_name" {
  type = string
}

variable "is_multi_az" {
  type    = bool
  default = false
}

variable "services" {
  type = any
}

variable "storage_configurations" {
  type = any
}

variable "my_public_ip" {
}