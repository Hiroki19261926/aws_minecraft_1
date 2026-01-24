terraform {
  backend "s3" {
    bucket         = "YOUR_BUCKET_NAME"
    key            = "minecraft1/prod/terraform.tfstate"
    region         = "ap-northeast-1"
    dynamodb_table = "YOUR_DYNAMODB_TABLE"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}
