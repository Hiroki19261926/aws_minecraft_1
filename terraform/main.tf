terraform {
  backend "s3" {
    key     = "minecraft1/prod/terraform.tfstate"
    region  = "ap-northeast-1"
    encrypt = true
    # bucket と dynamodb_table は terraform init 時に -backend-config で指定
  }
}

provider "aws" {
  region = var.aws_region
}
