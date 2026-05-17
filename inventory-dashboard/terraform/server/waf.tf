####################################################################
# WAF resources MUST be in us-east-1 for CloudFront
####################################################################

resource "aws_wafv2_ip_set" "allowed_ips" {
  provider           = aws.us_east_1
  name               = "${local.name_prefix}-allowed-ips"
  description        = "IP addresses allowed to access the Inventory Dashboard"
  scope              = "CLOUDFRONT"
  ip_address_version = "IPV4"
  addresses          = var.allowed_ip_cidrs
}

resource "aws_wafv2_web_acl" "cloudfront" {
  provider    = aws.us_east_1
  name        = "${local.name_prefix}-web-acl"
  description = "WAF for Inventory Dashboard - IP allowlist and AWS managed rule groups"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  ####################################################################
  # Priority 1 – IP allowlist (custom rule)
  # Explicitly blocks any source IP not in the approved CIDR set.
  # Evaluated first so unapproved IPs never reach the managed rules.
  ####################################################################
  rule {
    name     = "BlockNonApprovedIPs"
    priority = 1

    action {
      block {}
    }

    statement {
      not_statement {
        statement {
          ip_set_reference_statement {
            arn = aws_wafv2_ip_set.allowed_ips.arn
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-block-non-approved-ips"
      sampled_requests_enabled   = true
    }
  }

  ####################################################################
  # Priority 10 – Amazon IP Reputation List (managed)
  # Blocks IPs flagged by Amazon threat intelligence: known botnets,
  # scanners, and malicious actors. All rules default to BLOCK.
  ####################################################################
  rule {
    name     = "AWSManagedRulesAmazonIpReputationList"
    priority = 10

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-ip-reputation"
      sampled_requests_enabled   = true
    }
  }

  ####################################################################
  # Priority 20 – Core Rule Set / OWASP Top 10 (managed)
  # Protects against XSS, LFI, RFI, SSRF (EC2 metadata endpoint),
  # bad bots, and oversized requests.
  # Two rules that AWS ships as COUNT are overridden to BLOCK here:
  #   SizeRestrictions_BODY  – large request bodies (>8 KB)
  #   NoUserAgent_HEADER     – requests missing a User-Agent header
  ####################################################################
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 20

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"

        rule_action_override {
          name = "SizeRestrictions_BODY"
          action_to_use {
            block {}
          }
        }

        rule_action_override {
          name = "NoUserAgent_HEADER"
          action_to_use {
            block {}
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-core-rule-set"
      sampled_requests_enabled   = true
    }
  }

  ####################################################################
  # Priority 30 – Known Bad Inputs (managed)
  # Blocks request patterns associated with exploitation of known
  # vulnerabilities including Log4JRCE, SSRF, and path traversal.
  # Especially relevant given Python Lambda handlers that log inputs.
  # All rules default to BLOCK.
  ####################################################################
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 30

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-known-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  ####################################################################
  # Priority 40 – Linux OS rule set (managed)
  # Blocks payloads targeting Linux-specific vulnerabilities such as
  # command injection and local file inclusion. Lambda runs on Amazon
  # Linux, making this directly applicable.
  # All rules default to BLOCK.
  ####################################################################
  rule {
    name     = "AWSManagedRulesLinuxRuleSet"
    priority = 40

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesLinuxRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-linux-rule-set"
      sampled_requests_enabled   = true
    }
  }

  ####################################################################
  # Priority 50 – SQL Injection rule set (managed)
  # Blocks SQL injection patterns in URI, query string, body, and
  # headers. Relevant even for DynamoDB-backed APIs because injection
  # patterns in API inputs can still exploit application-layer parsing
  # (e.g. expression injection, filter injection). All rules BLOCK.
  ####################################################################
  rule {
    name     = "AWSManagedRulesSQLiRuleSet"
    priority = 50

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-sqli-rule-set"
      sampled_requests_enabled   = true
    }
  }

  ####################################################################
  # Priority 60 – Rate limiting per IP (custom rule)
  # Blocks any single IP that exceeds waf_rate_limit requests within
  # any 5-minute rolling window. Mitigates brute-force and DDoS.
  # Default: 1 000 req / 5 min  (~3.3 req/s sustained).
  ####################################################################
  rule {
    name     = "RateLimitPerIP"
    priority = 60

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name_prefix}-web-acl"
    sampled_requests_enabled   = true
  }
}
