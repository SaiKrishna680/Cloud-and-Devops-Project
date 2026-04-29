# ─────────────────────────────────────────────────────────────────────────────
# scripts/terraform-setup.ps1 — Bootstrap Terraform State & Deploy AWS Infra
#
# WHAT THIS DOES:
#   1. Checks AWS CLI is configured
#   2. Creates S3 bucket for Terraform remote state
#   3. Creates DynamoDB table for state locking
#   4. Copies tfvars.example → terraform.tfvars
#   5. Runs terraform init, plan, apply
#
# USAGE:
#   .\scripts\terraform-setup.ps1 -BucketName "my-tf-state-devsecops-xyz"
#
# PREREQUISITES:
#   - AWS CLI installed: https://awscli.amazonaws.com/AWSCLIV2.msi
#   - Configured: aws configure (enter Access Key, Secret, Region)
#   - Terraform installed: https://developer.hashicorp.com/terraform/downloads
# ─────────────────────────────────────────────────────────────────────────────

param(
    [Parameter(Mandatory=$true)]
    [string]$BucketName,

    [string]$Region      = "us-east-1",
    [string]$DynamoTable = "terraform-devsecops-lock",
    [switch]$AutoApprove = $false
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Step { param($msg) Write-Host "`n🔷 $msg" -ForegroundColor Cyan }
function Write-Ok   { param($msg) Write-Host "  ✅ $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "  ⚠️  $msg" -ForegroundColor Yellow }
function Write-Info { param($msg) Write-Host "  ℹ️  $msg" -ForegroundColor White }

Write-Host @"

╔══════════════════════════════════════════════════════════════╗
║   DevSecOps AWS Infrastructure Setup — Terraform             ║
╚══════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Magenta

# ════════════════════════════════════════════════════════════════════════════
# STEP 1: Verify AWS CLI + Credentials
# ════════════════════════════════════════════════════════════════════════════
Write-Step "STEP 1: Verifying AWS CLI and credentials..."

try {
    $awsVersion = aws --version 2>&1
    Write-Ok "AWS CLI: $awsVersion"
} catch {
    Write-Host "❌ AWS CLI not found. Install from: https://awscli.amazonaws.com/AWSCLIV2.msi" -ForegroundColor Red
    exit 1
}

try {
    $identity = aws sts get-caller-identity --output json 2>&1 | ConvertFrom-Json
    Write-Ok "AWS Account: $($identity.Account)"
    Write-Ok "AWS User/Role: $($identity.Arn)"
} catch {
    Write-Host "❌ AWS credentials not configured. Run: aws configure" -ForegroundColor Red
    exit 1
}

# ════════════════════════════════════════════════════════════════════════════
# STEP 2: Verify Terraform
# ════════════════════════════════════════════════════════════════════════════
Write-Step "STEP 2: Verifying Terraform..."

try {
    $tfVersion = terraform version -json 2>&1 | ConvertFrom-Json
    Write-Ok "Terraform: $($tfVersion.terraform_version)"
} catch {
    Write-Host "❌ Terraform not found." -ForegroundColor Red
    Write-Host "   Download from: https://developer.hashicorp.com/terraform/downloads"
    Write-Host "   Or use: choco install terraform"
    exit 1
}

# ════════════════════════════════════════════════════════════════════════════
# STEP 3: Create S3 Bucket for Terraform State
# ════════════════════════════════════════════════════════════════════════════
Write-Step "STEP 3: Creating S3 bucket for Terraform state: $BucketName"

$null = aws s3api head-bucket --bucket $BucketName 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Ok "S3 bucket already exists: $BucketName"
} else {
    if ($Region -eq "us-east-1") {
        aws s3api create-bucket `
            --bucket $BucketName `
            --region $Region | Out-Null
    } else {
        aws s3api create-bucket `
            --bucket $BucketName `
            --region $Region `
            --create-bucket-configuration LocationConstraint=$Region | Out-Null
    }

    # Enable versioning (allows rollback to previous state)
    aws s3api put-bucket-versioning `
        --bucket $BucketName `
        --versioning-configuration Status=Enabled | Out-Null

    # Enable encryption at rest
    aws s3api put-bucket-encryption `
        --bucket $BucketName `
        --server-side-encryption-configuration '{
            "Rules": [{
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                }
            }]
        }' | Out-Null

    # Block public access
    aws s3api put-public-access-block `
        --bucket $BucketName `
        --public-access-block-configuration `
            "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" | Out-Null

    Write-Ok "S3 bucket created and secured: $BucketName"
}

# ════════════════════════════════════════════════════════════════════════════
# STEP 4: Create DynamoDB Table for State Locking
# ════════════════════════════════════════════════════════════════════════════
Write-Step "STEP 4: Creating DynamoDB table for Terraform state locking..."

$null = aws dynamodb describe-table --table-name $DynamoTable --region $Region 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Ok "DynamoDB table already exists: $DynamoTable"
} else {
    aws dynamodb create-table `
        --table-name $DynamoTable `
        --attribute-definitions AttributeName=LockID,AttributeType=S `
        --key-schema AttributeName=LockID,KeyType=HASH `
        --billing-mode PAY_PER_REQUEST `
        --region $Region | Out-Null

    Write-Ok "DynamoDB lock table created: $DynamoTable"
}

# ════════════════════════════════════════════════════════════════════════════
# STEP 5: Set up terraform.tfvars
# ════════════════════════════════════════════════════════════════════════════
Write-Step "STEP 5: Setting up terraform.tfvars..."

$tfvarsPath = "$PSScriptRoot\..\terraform\terraform.tfvars"
$tfvarsExamplePath = "$PSScriptRoot\..\terraform\terraform.tfvars.example"

if (Test-Path $tfvarsPath) {
    Write-Warn "terraform.tfvars already exists — skipping copy."
    Write-Info "Edit it manually: $tfvarsPath"
} else {
    Copy-Item $tfvarsExamplePath $tfvarsPath
    Write-Ok "Copied terraform.tfvars.example → terraform.tfvars"

    # Auto-fill the bucket name
    $content = Get-Content $tfvarsPath -Raw
    $content = $content -replace 'my-tf-state-devsecops-123', $BucketName
    $content = $content -replace '"us-east-1"', '"' + $Region + '"'
    Set-Content $tfvarsPath $content

    Write-Warn "IMPORTANT: Edit terraform/terraform.tfvars before continuing!"
    Write-Info "  - Set 'allowed_ssh_cidr' to your IP (run: curl ifconfig.me)"
    Write-Info "  - Set 'allowed_access_cidr' to your IP"
    Write-Info "  - Set 'owner' to your name"
    Write-Info ""

    $proceed = Read-Host "Have you edited terraform.tfvars? (yes/no)"
    if ($proceed -ne "yes") {
        Write-Host "Edit the file and re-run this script." -ForegroundColor Yellow
        exit 0
    }
}

# ════════════════════════════════════════════════════════════════════════════
# STEP 6: Enable S3 Backend in providers.tf
# ════════════════════════════════════════════════════════════════════════════
Write-Step "STEP 6: Enabling S3 backend in providers.tf..."

$providersPath = "$PSScriptRoot\..\terraform\providers.tf"
$content = Get-Content $providersPath -Raw

# Uncomment the backend block
$content = $content -replace '  # backend "s3" \{', '  backend "s3" {'
$content = $content -replace '  #   bucket', '    bucket'
$content = $content -replace '  #   key', '    key'
$content = $content -replace '  #   region', '    region'
$content = $content -replace '  #   dynamodb_table', '    dynamodb_table'
$content = $content -replace '  #   encrypt', '    encrypt'
$content = $content -replace '  # \}', '  }'

# Inject actual bucket name
$content = $content -replace 'your-terraform-state-bucket-devsecops', $BucketName
$content = $content -replace '"us-east-1"  # backend region', "`"$Region`""

Set-Content $providersPath $content
Write-Ok "S3 backend configured in providers.tf"

# ════════════════════════════════════════════════════════════════════════════
# STEP 7: Terraform Init
# ════════════════════════════════════════════════════════════════════════════
Write-Step "STEP 7: Running terraform init..."

Set-Location "$PSScriptRoot\..\terraform"

terraform init `
    -backend-config="bucket=$BucketName" `
    -backend-config="key=devsecops/terraform.tfstate" `
    -backend-config="region=$Region" `
    -backend-config="dynamodb_table=$DynamoTable" `
    -backend-config="encrypt=true"

Write-Ok "Terraform initialized."

# ════════════════════════════════════════════════════════════════════════════
# STEP 8: Terraform Plan
# ════════════════════════════════════════════════════════════════════════════
Write-Step "STEP 8: Running terraform plan..."

terraform plan -out=tfplan

Write-Ok "Plan complete. Review above before applying."

# ════════════════════════════════════════════════════════════════════════════
# STEP 9: Terraform Apply
# ════════════════════════════════════════════════════════════════════════════
if ($AutoApprove) {
    Write-Step "STEP 9: Applying Terraform plan (auto-approved)..."
    terraform apply tfplan
} else {
    Write-Host ""
    $confirm = Read-Host "Apply the plan? This will CREATE AWS RESOURCES and incur COSTS. (yes/no)"
    if ($confirm -eq "yes") {
        Write-Step "STEP 9: Applying Terraform plan..."
        terraform apply tfplan
        Write-Ok "Infrastructure deployed!"
        Write-Host ""
        Write-Host "==========================================================" -ForegroundColor Green
        Write-Host "   Run 'terraform output' to see all URLs and next steps  " -ForegroundColor Green
        Write-Host "==========================================================" -ForegroundColor Green
    } else {
        Write-Warn "Apply cancelled. Plan saved as 'tfplan'."
        Write-Info "Run 'terraform apply tfplan' manually when ready."
    }
}
