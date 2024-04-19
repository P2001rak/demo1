provider "aws" {
  access_key = var.aws_access_key_id
  secret_key = var.aws_secret_access_key
  region     = var.aws_region
}

provider "github" {
  token = var.github_token
}

module "template_files" {
  source   = "hashicorp/dir/template"
  base_dir = "${path.module}/files"
}

resource "random_password" "custom_header" {
  length      = 13
  special     = false
  lower       = true
  upper       = true
  numeric     = true
  min_lower   = 1
  min_numeric = 1
  min_upper   = 1
}

resource "aws_s3_bucket" "my_bucket" {
  bucket = "rakhi-bucket-07"

  website {
    index_document = "index.html"
  }
}

# Upload all files from the local directory to the S3 bucket
resource "aws_s3_bucket_object" "files" {
  for_each      = module.template_files.files
  bucket        = aws_s3_bucket.my_bucket.id
  key           = each.key
  content_type  = each.value.content_type
  source        = each.value.source_path
  content       = each.value.content
  etag          = each.value.digests.md5
}

resource "aws_cloudfront_distribution" "my_distribution" {
  origin {
    domain_name = aws_s3_bucket.my_bucket.website_endpoint
    origin_id   = aws_s3_bucket.my_bucket.id
    custom_header {
      name  = "Referer"
      value = random_password.custom_header.result
    }
    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_keepalive_timeout = 5
      origin_protocol_policy   = "http-only"
      origin_read_timeout      = 30
      origin_ssl_protocols     = ["TLSv1.2"]
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "My first CDN"
  
  default_cache_behavior {
    target_origin_id      = aws_s3_bucket.my_bucket.id
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl        = 0
    default_ttl    = 3600
    max_ttl        = 86400
  }

  viewer_certificate {
    acm_certificate_arn      = "arn:aws:acm:us-east-1:891377018135:certificate/e397f490-a6c2-4f89-886e-53686636ad00" 
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2019"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "my_bucket" {
  bucket = aws_s3_bucket.my_bucket.id

  block_public_policy     = false // This is default, so you can probably remove this line
  restrict_public_buckets = false // same as above
  block_public_acls       = true 
  ignore_public_acls      = true 
}

# Allow CloudFront read access to objects in the S3 bucket
resource "aws_s3_bucket_policy" "allow_access" {
  bucket = aws_s3_bucket.my_bucket.id
  policy = data.aws_iam_policy_document.allow_access.json
  depends_on = [aws_s3_bucket_public_access_block.my_bucket]
}

data "aws_iam_policy_document" "allow_access" {
  policy_id = "PolicyForCloudFrontPrivateContent"
  statement {
    sid       = "AllowCloudFrontServicePrincipal"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.my_bucket.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "StringLike"
      variable = "aws:Referer"
    }
  }
}

resource "null_resource" "refresh_static_site" {
  triggers = {
    bucket_arn = aws_s3_bucket.my_bucket.arn
  }

  provisioner "local-exec" {
    command = <<EOF
      aws s3 website s3://${aws_s3_bucket.my_bucket.id}/ --index-document index.html
    EOF
  }
}

# Create GitHub repository
resource "github_repository" "my_repo" {
  name        = "my-repo"
  description = "My GitHub repository"
  visibility  = "public"  # or "private" if you want it to be private
}

# Output GitHub repository URL
output "github_repo_url" {
  value = github_repository.my_repo.html_url
}
