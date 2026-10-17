variable "aws_region" {
  type    = string
  default = "ap-south-1"
}
variable "dockerhub_username" {
  type = string
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9_-]*$", var.dockerhub_username))
    error_message = "Enter a valid lowercase Docker Hub username."
  }
}
variable "image_tag" {
  type    = string
  default = "v1"
  validation {
    condition     = can(regex("^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$", var.image_tag))
    error_message = "Enter a valid Docker image tag."
  }
}
variable "instance_type" {
  type    = string
  default = "t3.small"
}
variable "key_name" {
  type        = string
  description = "Existing EC2 key pair name in the selected region."
}
variable "admin_cidr" {
  type        = string
  description = "Your public IPv4 address with /32, for SSH."
  validation {
    condition     = can(cidrnetmask(var.admin_cidr)) && can(regex("/32$", var.admin_cidr))
    error_message = "Use your public IPv4 address followed by /32."
  }
}
