variable "cluster_name" {
  description = "Name of the cluster"
  type        = string
  default = "capitolis-task-eks"
}

variable "region" {
  description = "Code of the region"
  type        = string
  default = "us-west-2"
}

variable "azs" {
  description = "List of availabity zones"
  type        = list(string)
  default = ["us-west-2a", "us-west-2b", "us-west-2c"]
}

variable "vpc_cidr" {
  description = "CIDR of vpc"
  type        = string
  default = "10.0.0.0/16"
}

variable "istio_chart_url" {
  description = "Istio Chart URL"
  type = string
  default = "https://istio-release.storage.googleapis.com/charts"
}

variable "istio_chart_version" {
  description = "The vesrion of the Istion chart to be installed"
  type = string
  default = "1.20.2"
}

variable "jenkins_chart_url" {
  description = "Istio Chart URL"
  type = string
  default = "https://istio-release.storage.googleapis.com/charts"
}

variable "jenkins_chart_version" {
  description = "The vesrion of the Istion chart to be installed"
  type = string
  default = "lastest"
}

variable "jenkins_admin_user" {
    description = "Jenkins admin user name"
    type = string
    sensitive = true
}

variable "jenkins_admin_password" {
    description = "Jenkins admin user password"
    type = string
    sensitive = true
}