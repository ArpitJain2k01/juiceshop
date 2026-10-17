terraform {
  backend "s3" {
    bucket       = "itsajsince2k01"
    key          = "juiceshop/terraform.tfstate"
    region       = "ap-southeast-2"
    encrypt      = true
    use_lockfile = true
  }
}