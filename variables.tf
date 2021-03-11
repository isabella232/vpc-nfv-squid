variable "ibmcloud_api_key" {}
variable "ssh_key_name" {}
variable "resource_group_name" {}
variable "basename" {}
variable "region" {
  default = "us-south"
}
variable "profile" {
  default = "cx2-2x4"
}
variable "image_name" {
  default = "ibm-ubuntu-18-04-1-minimal-amd64-2"
}
