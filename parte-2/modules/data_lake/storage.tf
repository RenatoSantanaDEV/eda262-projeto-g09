resource "terraform_data" "workspace_guard" {
  input = local.workspace

  lifecycle {
    precondition {
      condition     = terraform.workspace != "default"
      error_message = "Use um workspace explícito, por exemplo av2."
    }
  }
}

resource "aws_s3_bucket" "lake" {
  for_each = {
    raw     = local.bucket_names.raw
    trusted = local.bucket_names.trusted
    refined = local.bucket_names.refined
  }

  bucket        = each.value
  force_destroy = true

  depends_on = [terraform_data.workspace_guard]
}

resource "aws_s3_bucket_public_access_block" "lake" {
  for_each = aws_s3_bucket.lake

  bucket                  = each.value.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "lake" {
  for_each = aws_s3_bucket.lake

  bucket = each.value.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "lake" {
  for_each = aws_s3_bucket.lake

  bucket = each.value.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "raw" {
  bucket = aws_s3_bucket.lake["raw"].id

  versioning_configuration {
    status = "Enabled"
  }
}

data "aws_iam_policy_document" "lake_tls" {
  for_each = aws_s3_bucket.lake

  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      each.value.arn,
      "${each.value.arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "lake_tls" {
  for_each = aws_s3_bucket.lake

  bucket = each.value.id
  policy = data.aws_iam_policy_document.lake_tls[each.key].json

  depends_on = [aws_s3_bucket_public_access_block.lake]
}

resource "aws_s3_bucket" "support" {
  for_each = {
    artifacts = local.bucket_names.artifacts
    results   = local.bucket_names.results
  }

  bucket        = each.value
  force_destroy = true

  depends_on = [terraform_data.workspace_guard]
}

resource "aws_s3_bucket_public_access_block" "support" {
  for_each = aws_s3_bucket.support

  bucket                  = each.value.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "support" {
  for_each = aws_s3_bucket.support

  bucket = each.value.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "support" {
  for_each = aws_s3_bucket.support

  bucket = each.value.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.support["artifacts"].id

  versioning_configuration {
    status = "Enabled"
  }
}

data "aws_iam_policy_document" "support_tls" {
  for_each = aws_s3_bucket.support

  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      each.value.arn,
      "${each.value.arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "support_tls" {
  for_each = aws_s3_bucket.support

  bucket = each.value.id
  policy = data.aws_iam_policy_document.support_tls[each.key].json

  depends_on = [aws_s3_bucket_public_access_block.support]
}

