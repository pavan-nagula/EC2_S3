provider "aws" {
  region = var.aws_region
}

module "EC2-Read_S3" {
  source = "./modules/ec2_s3_downloader"
}
