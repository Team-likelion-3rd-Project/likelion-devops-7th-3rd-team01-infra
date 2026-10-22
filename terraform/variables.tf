variable "aws_region" {
  description = "Team-approved region; deliberately no default."
  type        = string
}

variable "availability_zones" {
  description = "Two approved AZ names, ordered A then B."
  type        = list(string)
  validation {
    condition     = length(var.availability_zones) == 2 && length(distinct(var.availability_zones)) == 2
    error_message = "Provide exactly two distinct AZ names."
  }
}

variable "environment" {
  type    = string
  default = "practice"
}

variable "alb_target_ports" {
  description = "Confirmed worker NodePort target and health ports; not the container port."
  type        = set(number)
  validation {
    condition     = length(var.alb_target_ports) > 0 && alltrue([for p in var.alb_target_ports : p >= 1 && p <= 65535 && floor(p) == p])
    error_message = "Supply at least one confirmed integer TCP port (1-65535)."
  }
}
