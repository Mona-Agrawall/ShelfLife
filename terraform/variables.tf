variable "region" {
  description = "AWS region to deploy resources in"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type. t3.small recommended. t2.micro works on personal free tier only with swap enabled."
  type        = string
  default     = "t3.small"
}

variable "project_name" {
  description = "Project name used for tagging and naming resources"
  type        = string
  default     = "shelflife"
}

variable "allowed_cidr" {
  description = "CIDR block allowed to access the servers. Default 0.0.0.0/0 is open to the internet - restrict to your IP in production (e.g. 203.0.113.0/32)"
  type        = string
  default     = "0.0.0.0/0"
}

variable "instance_profile_name" {
  description = "IAM instance profile name. Set to 'LabInstanceProfile' on AWS Academy. Leave empty for personal accounts."
  type        = string
  default     = ""
}
