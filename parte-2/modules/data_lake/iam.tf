data "aws_iam_policy_document" "glue_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "principal_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
}

resource "aws_iam_role" "ingestion" {
  name               = "${local.prefix}-av2-ingestion"
  assume_role_policy = data.aws_iam_policy_document.principal_assume_role.json
  description        = "Carga idempotente de objetos na camada raw da AV2"
}

resource "aws_iam_role" "pipeline" {
  name               = "${local.prefix}-av2-glue-pipeline"
  assume_role_policy = data.aws_iam_policy_document.glue_assume_role.json
  description        = "Transformação raw para trusted e refined"
}

resource "aws_iam_role_policy" "pipeline_runtime" {
  name = "glue-runtime-minimal"
  role = aws_iam_role.pipeline.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "WriteGlueLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = [
          "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws-glue/*",
          "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws-glue/*:*",
        ]
      },
      {
        Sid    = "DescribeGlueLogs"
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
        ]
        Resource = "*"
      },
      {
        Sid      = "PublishGlueMetrics"
        Effect   = "Allow"
        Action   = ["cloudwatch:PutMetricData"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = "Glue"
          }
        }
      },
    ]
  })
}

resource "aws_iam_role" "analyst" {
  name               = "${local.prefix}-av2-analyst"
  assume_role_policy = data.aws_iam_policy_document.principal_assume_role.json
  description        = "Consulta somente da camada refined com Athena"
}

data "aws_iam_policy_document" "ingestion" {
  statement {
    sid       = "ListRaw"
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.lake["raw"].arn]
  }

  statement {
    sid       = "WriteRawOrders"
    effect    = "Allow"
    actions   = ["s3:DeleteObject", "s3:GetObject", "s3:PutObject"]
    resources = ["${aws_s3_bucket.lake["raw"].arn}/orders/*"]
  }
}

resource "aws_iam_role_policy" "ingestion" {
  name   = "raw-only"
  role   = aws_iam_role.ingestion.id
  policy = data.aws_iam_policy_document.ingestion.json
}

data "aws_iam_policy_document" "pipeline" {
  statement {
    sid    = "ListLakeBuckets"
    effect = "Allow"
    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket",
    ]
    resources = [
      aws_s3_bucket.lake["raw"].arn,
      aws_s3_bucket.lake["trusted"].arn,
      aws_s3_bucket.lake["refined"].arn,
      aws_s3_bucket.support["artifacts"].arn,
    ]
  }

  statement {
    sid     = "ReadRawAndArtifacts"
    effect  = "Allow"
    actions = ["s3:GetObject", "s3:GetObjectVersion"]
    resources = [
      "${aws_s3_bucket.lake["raw"].arn}/orders/*",
      "${aws_s3_bucket.support["artifacts"].arn}/scripts/*",
    ]
  }

  statement {
    sid    = "WriteCuratedAndReports"
    effect = "Allow"
    actions = [
      "s3:DeleteObject",
      "s3:GetObject",
      "s3:PutObject",
    ]
    resources = [
      "${aws_s3_bucket.lake["raw"].arn}/quality/*",
      "${aws_s3_bucket.lake["trusted"].arn}/*",
      "${aws_s3_bucket.lake["refined"].arn}/*",
      "${aws_s3_bucket.support["artifacts"].arn}/reports/*",
    ]
  }

  statement {
    sid    = "LakeFormationAndCatalog"
    effect = "Allow"
    actions = [
      "glue:GetDatabase",
      "glue:GetDatabases",
      "glue:GetPartition",
      "glue:GetPartitions",
      "glue:GetTable",
      "glue:GetTables",
    ]
    resources = [
      "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:catalog",
      "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:database/${local.database_name}",
      "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${local.database_name}/*",
    ]
  }

  statement {
    sid       = "LakeFormationCredentials"
    effect    = "Allow"
    actions   = ["lakeformation:GetDataAccess"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "pipeline" {
  name   = "lake-pipeline"
  role   = aws_iam_role.pipeline.id
  policy = data.aws_iam_policy_document.pipeline.json
}

data "aws_iam_policy_document" "analyst" {
  statement {
    sid       = "ReadRefined"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.lake["refined"].arn}/*"]
  }

  statement {
    sid     = "ListRefinedAndResults"
    effect  = "Allow"
    actions = ["s3:GetBucketLocation", "s3:ListBucket"]
    resources = [
      aws_s3_bucket.lake["refined"].arn,
      aws_s3_bucket.support["results"].arn,
    ]
  }

  statement {
    sid       = "WriteAthenaResults"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${aws_s3_bucket.support["results"].arn}/*"]
  }

  statement {
    sid    = "QueryWorkgroup"
    effect = "Allow"
    actions = [
      "athena:GetQueryExecution",
      "athena:GetQueryResults",
      "athena:GetWorkGroup",
      "athena:StartQueryExecution",
    ]
    resources = [
      "arn:aws:athena:${var.aws_region}:${data.aws_caller_identity.current.account_id}:workgroup/${local.prefix}-av2",
    ]
  }

  statement {
    sid    = "ReadRefinedCatalog"
    effect = "Allow"
    actions = [
      "glue:GetDatabase",
      "glue:GetDatabases",
      "glue:GetPartition",
      "glue:GetPartitions",
      "glue:GetTable",
      "glue:GetTables",
    ]
    resources = [
      "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:catalog",
      "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:database/${local.database_name}",
      "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${local.database_name}/refined_daily_sales",
    ]
  }

  statement {
    sid       = "LakeFormationCredentials"
    effect    = "Allow"
    actions   = ["lakeformation:GetDataAccess"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "analyst" {
  name   = "refined-query-only"
  role   = aws_iam_role.analyst.id
  policy = data.aws_iam_policy_document.analyst.json
}

