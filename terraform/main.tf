terraform {
  backend "s3" {
    bucket         = "minecraft-tfstate-1-hn"
    key            = "minecraft1/prod/terraform.tfstate"
    region         = "ap-northeast-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}
