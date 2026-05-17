####################################################################
# Origin Access Control – signed S3 requests via SigV4
####################################################################
resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${local.name_prefix}-oac"
  description                       = "OAC for Inventory Dashboard frontend bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

####################################################################
# CloudFront distribution
####################################################################
resource "aws_cloudfront_distribution" "frontend" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  comment             = "Inventory Dashboard – ${var.environment}"
  price_class         = "PriceClass_100"  # North America + Europe only
  web_acl_id          = aws_wafv2_web_acl.cloudfront.arn

  lifecycle {
    # Cross-variable validation must live here, not in variable{} blocks
    precondition {
      condition     = var.custom_domain_name == "" || var.acm_certificate_arn != ""
      error_message = "acm_certificate_arn must be set when custom_domain_name is provided."
    }
  }

  aliases = local.has_custom_domain ? [var.custom_domain_name] : []

  # ── S3 origin ────────────────────────────────────────────────
  origin {
    origin_id                = "S3Frontend"
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id

    s3_origin_config {
      origin_access_identity = ""
    }
  }

  # ── Default behavior (frontend assets) ───────────────────────
  default_cache_behavior {
    target_origin_id       = "S3Frontend"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    # AWS managed CachingOptimized policy
    cache_policy_id          = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    # AWS managed CORS-S3Origin request policy
    origin_request_policy_id = "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf"
  }

  # ── SPA routing: return index.html on 403/404 ────────────────
  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  # ── TLS ──────────────────────────────────────────────────────
  viewer_certificate {
    acm_certificate_arn            = local.has_custom_domain ? var.acm_certificate_arn : null
    cloudfront_default_certificate = !local.has_custom_domain
    ssl_support_method             = local.has_custom_domain ? "sni-only" : null
    minimum_protocol_version       = local.has_custom_domain ? "TLSv1.2_2021" : null
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
}
