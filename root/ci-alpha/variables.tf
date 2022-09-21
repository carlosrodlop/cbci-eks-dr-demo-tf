variable "name" {
  description = "Name of the demo"
  type        = string
}

variable "aws_region" {
  type        = string
  description = "Alpha AWS region"
}

variable "aws_profile" {
  type        = string
  description = "AWS profile"
}

variable "domain_name" {
  type = string
}

variable "dr_cluster" {
  default = "alpha"
  type    = string

  validation {
    condition     = contains(["alpha", "beta"], var.dr_cluster)
    error_message = "Provided DR cluster code is not valid. Valid values are alpha and beta."
  }
}

variable "primary_cluster" {
  description = "Flag to set primary cluster."
  type        = bool
  default     = false
}

variable "tags" {
  default = {}
  type    = map(string)
}

variable "s3_bucket_arn" {
  type        = string
  description = "ARN of the S3 bucket to use for backups"
}

variable "s3_bucket_id" {
  type        = string
  description = "ID of the S3 bucket to use for backups"
}

variable "s3_bucket_region" {
  type        = string
  description = "Region of the S3 bucket to use for backups"
}