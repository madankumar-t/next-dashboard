####################################################################
# Frontend S3 bucket (static Next.js export)
####################################################################
resource "aws_s3_bucket" "frontend" {
  bucket = var.frontend_bucket_name
}

# aws_s3_bucket_public_access_block is managed by an org-level SCP in this
# account; the Spacelift role does not have s3:PutBucketPublicAccessBlock.
# Public access is already denied via org policy.

resource "aws_s3_bucket_versioning" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

####################################################################
# Bucket policy – allow CloudFront OAC to read objects
####################################################################
resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  policy = data.aws_iam_policy_document.frontend_bucket.json

  # Policy must be set after CloudFront distribution exists
  depends_on = [aws_cloudfront_distribution.frontend]
}

data "aws_iam_policy_document" "frontend_bucket" {
  statement {
    sid     = "AllowCloudFrontOAC"
    effect  = "Allow"
    actions = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.frontend.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.frontend.arn]
    }
  }
}

####################################################################
# Frontend build + S3 deploy
#
# Runs `npm ci && next build && aws s3 sync` as part of the Terraform
# apply.  Triggered only when frontend source files change (hash of
# src/, package.json, next.config.js).  After syncing, invalidates
# the CloudFront cache so users see the new version immediately.
#
# Spacelift public runners have Python and the AWS CLI but NOT npm.
# The provisioner detects the runner libc: on Alpine (musl) it fetches
# the unofficial musl build; on glibc systems it fetches the official
# LTS tarball.  Both paths extract into /tmp — no root required.
####################################################################
resource "null_resource" "deploy_frontend" {
  triggers = {
    # Rebuild when any file under frontend/src/ changes
    src_hash = sha256(join("", [
      for f in sort(fileset("${path.root}/../../frontend/src", "**"))
      : filesha256("${path.root}/../../frontend/src/${f}")
    ]))
    # Also rebuild when dependencies or the Next.js config change
    pkg_hash    = filesha256("${path.root}/../../frontend/package.json")
    config_hash = filesha256("${path.root}/../../frontend/next.config.js")
  }

  provisioner "local-exec" {
    # Use bash explicitly — avoids /bin/sh (dash) edge cases with arrays
    # and ensures reliable command-substitution behaviour.
    interpreter = ["/bin/bash", "-c"]

    # ----------------------------------------------------------------
    # Terraform interpolates ${...} only.
    # Plain $VAR, $(cmd), and $PATH in this heredoc pass through to bash
    # as-is — no $$-escaping needed for bare shell variables.
    # ----------------------------------------------------------------
    command = <<-EOT
      set -euo pipefail
      cd "${path.root}/../../frontend"

      # Spacelift public runners have Python + AWS CLI but not Node.js.
      # Two runner types are handled:
      #   Alpine (musl libc) — official Node.js glibc tarball won't run AND
      #                        apk requires root.  Download the unofficial
      #                        x64-musl build from unofficial-builds.nodejs.org
      #                        into /tmp (no root needed).
      #   glibc Linux (Debian/Ubuntu/Amazon) — download official LTS tarball
      #                        into /tmp; detect arch for x64 or ARM64.
      if ! command -v npm > /dev/null 2>&1; then
        if [ -f /etc/alpine-release ]; then
          echo "==> Alpine/musl detected — downloading Node.js 20.18.1 musl build"
          curl -fsSL \
            "https://unofficial-builds.nodejs.org/download/release/v20.18.1/node-v20.18.1-linux-x64-musl.tar.gz" \
            | tar -xzf - -C /tmp
          export PATH="/tmp/node-v20.18.1-linux-x64-musl/bin:$PATH"
        else
          ARCH=$(uname -m)
          NODE_ARCH=x64
          if [ "$ARCH" = "aarch64" ]; then NODE_ARCH=arm64; fi
          echo "==> Downloading Node.js 20.18.1 LTS ($ARCH -> $NODE_ARCH)"
          curl -fsSL \
            "https://nodejs.org/dist/v20.18.1/node-v20.18.1-linux-$NODE_ARCH.tar.gz" \
            | tar -xzf - -C /tmp
          export PATH="/tmp/node-v20.18.1-linux-$NODE_ARCH/bin:$PATH"
        fi
      fi

      echo "==> Node $(node --version) / npm $(npm --version)"

      echo "==> Installing frontend dependencies"
      npm ci --no-audit --no-fund --quiet

      echo "==> Building Next.js static export"
      NEXT_PUBLIC_API_URL="https://${aws_api_gateway_rest_api.main.id}.execute-api.${var.aws_region}.amazonaws.com/${var.environment}" \
      NEXT_PUBLIC_COGNITO_USER_POOL_ID="${aws_cognito_user_pool.main.id}" \
      NEXT_PUBLIC_COGNITO_CLIENT_ID="${aws_cognito_user_pool_client.frontend.id}" \
      NEXT_PUBLIC_COGNITO_DOMAIN="${aws_cognito_user_pool_domain.main.domain}" \
      NEXT_PUBLIC_COGNITO_REGION="${var.aws_region}" \
        npm run build

      echo "==> Syncing to S3: s3://${aws_s3_bucket.frontend.bucket}"
      aws s3 sync out/ "s3://${aws_s3_bucket.frontend.bucket}" --delete --quiet

      echo "==> Invalidating CloudFront distribution ${aws_cloudfront_distribution.frontend.id}"
      aws cloudfront create-invalidation \
        --distribution-id "${aws_cloudfront_distribution.frontend.id}" \
        --paths "/*" \
        --query 'Invalidation.Id' \
        --output text

      echo "==> Frontend deployed successfully"
    EOT
  }

  depends_on = [
    aws_s3_bucket_policy.frontend,
    aws_cloudfront_distribution.frontend,
  ]
}
