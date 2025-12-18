pipeline {
  agent any

  parameters {
    string(name: 'AWS_REGION', defaultValue: 'ap-south-1', description: 'AWS region')
    string(name: 'ECR_REPO', defaultValue: 'gl-devops-academy-batch1-project-repo', description: 'ECR repository name')
    string(name: 'CLUSTER_NAME', defaultValue: 'gl-devops-academy-batch1-project-eks-cluster', description: 'EKS cluster name')
  }

  options {
    timestamps()
  }

  environment {
    // Ensure Homebrew bin paths are available for Jenkins on macOS (pwsh, aws, terraform, kubectl, docker)
    PATH = "/usr/local/bin:/opt/homebrew/bin:/Applications/PowerShell.app/Contents/MacOS:${PATH}"
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Ensure Terraform Backend') {
      steps {
        withCredentials([
          string(credentialsId: 'AWS_ACCESS_KEY_ID', variable: 'AWS_ACCESS_KEY_ID'),
          string(credentialsId: 'AWS_SECRET_ACCESS_KEY', variable: 'AWS_SECRET_ACCESS_KEY')
        ]) {
          pwsh '''
            # Do not fail the stage on non-terminating errors from native commands
            $ErrorActionPreference = "Continue"
            $bucketBase = 'gl-capstone-project-pan-2025'
            $table  = 'gl-capstone-project-pan-2025'
            $region = $env:AWS_REGION
            $account = $(aws sts get-caller-identity --query Account --output text 2>$null)
            if (-not $account) { throw "Unable to resolve AWS account id" }

            # Try base bucket; if globally taken by someone else, fallback to account-suffixed bucket
            $bucket = $bucketBase

            Write-Host "Ensuring S3 bucket $bucket exists in $region..."
            $exists = $false
            # Suppress all output; rely on exit code only
            & aws s3api head-bucket --bucket $bucket 1>$null 2>$null
            if ($LASTEXITCODE -eq 0) { $exists = $true }
            if (-not $exists) {
              if ($region -eq 'us-east-1') {
                & aws s3api create-bucket --bucket $bucket 1>$null 2>$null
              } else {
                & aws s3api create-bucket --bucket $bucket --create-bucket-configuration LocationConstraint=$region 1>$null 2>$null
              }
              if ($LASTEXITCODE -ne 0) {
                Write-Host "Base bucket creation failed; trying account-suffixed bucket..."
                $bucket = "$bucketBase-$account"
                if ($region -eq 'us-east-1') {
                  & aws s3api create-bucket --bucket $bucket 1>$null 2>$null
                } else {
                  & aws s3api create-bucket --bucket $bucket --create-bucket-configuration LocationConstraint=$region 1>$null 2>$null
                }
                if ($LASTEXITCODE -ne 0) { throw "Failed to create S3 bucket $bucket" }
              }
              & aws s3api put-bucket-versioning --bucket $bucket --versioning-configuration Status=Enabled 1>$null 2>$null
              & aws s3api put-public-access-block --bucket $bucket --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true 1>$null 2>$null
              # Wait until bucket is reachable
              $max=10; $ok=$false
              for ($i=0; $i -lt $max -and -not $ok; $i++) {
                Start-Sleep -Seconds 3
                & aws s3api head-bucket --bucket $bucket 1>$null 2>$null
                if ($LASTEXITCODE -eq 0) { $ok=$true }
              }
              if (-not $ok) { throw "S3 bucket $bucket not reachable after creation" }
            }

            Write-Host "Ensuring DynamoDB table $table exists..."
            & aws dynamodb describe-table --table-name $table 1>$null 2>$null
            if ($LASTEXITCODE -ne 0) {
              & aws dynamodb create-table --table-name $table --attribute-definitions AttributeName=LockID,AttributeType=S --key-schema AttributeName=LockID,KeyType=HASH --billing-mode PAY_PER_REQUEST 1>$null 2>$null
              if ($LASTEXITCODE -ne 0) { throw "Failed to create DynamoDB table $table" }
              Write-Host "Waiting for DynamoDB table to be ACTIVE..."
              & aws dynamodb wait table-exists --table-name $table 1>$null 2>$null
            }
          '''
        }
      }
    }

    stage('SAST & Manifest Lint') {
      steps {
        pwsh '''
          $ErrorActionPreference = "Continue"
          Write-Host "Running Trivy filesystem scan (HIGH,CRITICAL) on repo..."
          # Prepare local cache dir for Trivy DB to speed up (Windows path fix to forward slashes for Docker)
          $cachePath = Join-Path $env:WORKSPACE ".trivy-cache"
          if (-not (Test-Path $cachePath)) { New-Item -ItemType Directory -Path $cachePath | Out-Null }
          $cacheMount = ("$cachePath").Replace('\\','/')
          $wsMount = ("$env:WORKSPACE").Replace('\\','/')
          docker run --rm -v "$($wsMount):/repo" -v "$($cacheMount):/root/.cache/trivy" -w /repo aquasec/trivy:0.50.0 fs --no-progress --scanners vuln --severity HIGH,CRITICAL --timeout 15m --exit-code 0 .
          if ($LASTEXITCODE -ne 0) { Write-Host "Trivy filesystem scan returned non-zero; proceeding (informational only)."; $global:LASTEXITCODE = 0 }

          if (Test-Path "manifests") {
            Write-Host "Linting Kubernetes manifests with kubeval (Docker Hub mirror)..."
            docker run --rm -v "$env:WORKSPACE/manifests:/manifests" cytopia/kubeval:latest -d /manifests
            Write-Host "Running kube-linter for richer checks..."
            docker run --rm -v "$env:WORKSPACE/manifests:/manifests" stackrox/kube-linter:v0.6.8 lint /manifests
          }
        '''
      }
    }

    stage('Tools Versions') {
      steps {
        pwsh '''
          $ErrorActionPreference = "Continue"
          aws --version
          terraform version
          kubectl version --client
          docker --version
        '''
      }
    }

    stage('AWS Identity Check') {
      steps {
        withCredentials([
          string(credentialsId: 'AWS_ACCESS_KEY_ID', variable: 'AWS_ACCESS_KEY_ID'),
          string(credentialsId: 'AWS_SECRET_ACCESS_KEY', variable: 'AWS_SECRET_ACCESS_KEY')
        ]) {
          pwsh '''
            $ErrorActionPreference = "Stop"
            Write-Host "Checking AWS identity..."
            aws sts get-caller-identity
          '''
        }
      }
    }

    stage('Terraform Init/Plan/Apply') {
      steps {
        dir('infra') {
          withCredentials([
            string(credentialsId: 'AWS_ACCESS_KEY_ID', variable: 'AWS_ACCESS_KEY_ID'),
            string(credentialsId: 'AWS_SECRET_ACCESS_KEY', variable: 'AWS_SECRET_ACCESS_KEY')
          ]) {
            pwsh '''
              $ErrorActionPreference = "Stop"
              # Compute backend bucket/table same as ensure stage
              $bucketBase = 'gl-capstone-project-pan-2025'
              $table  = 'gl-capstone-project-pan-2025'
              $account = $(aws sts get-caller-identity --query Account --output text)
              if (-not $account) { throw "Unable to resolve AWS account id" }
              $bucket = $bucketBase
              & aws s3api head-bucket --bucket $bucket 1>$null 2>$null
              if ($LASTEXITCODE -ne 0) { $bucket = "$bucketBase-$account" }

              terraform init -reconfigure -upgrade -input=false `
                -backend-config="bucket=$bucket" `
                -backend-config="key=envs/dev/terraform.tfstate" `
                -backend-config="region=$env:AWS_REGION" `
                -backend-config="dynamodb_table=$table" `
                -backend-config="encrypt=true"
              # Ensure workspace 'dev'
              try { terraform workspace select dev } catch { terraform workspace new dev }
              terraform plan -input=false -out=tfplan
              terraform apply -input=false -auto-approve tfplan
            '''
          }
        }
      }
    }

    stage('Docker Build and Push to ECR') {
      environment {
        IMAGE_TAG = "${env.GIT_COMMIT?.take(7) ?: env.BUILD_NUMBER}"
      }
      steps {
        withCredentials([
          string(credentialsId: 'AWS_ACCESS_KEY_ID', variable: 'AWS_ACCESS_KEY_ID'),
          string(credentialsId: 'AWS_SECRET_ACCESS_KEY', variable: 'AWS_SECRET_ACCESS_KEY')
        ]) {
          pwsh '''
            $ErrorActionPreference = "Stop"
            $ACCOUNT_ID = (aws sts get-caller-identity --query Account --output text)
            $ECR_REG = "$ACCOUNT_ID.dkr.ecr.$env:AWS_REGION.amazonaws.com"
            # Try to auto-detect repo URL from Terraform outputs; fallback to parameter if not found
            $repoParam = $env:ECR_REPO
            $repoOut = $null
            if (Test-Path 'infra') {
              Push-Location infra
              try {
                $json = terraform output -json ecr_repo_urls 2>$null
                if ($LASTEXITCODE -eq 0 -and $json) {
                  $obj = $json | ConvertFrom-Json
                  if ($obj.PSObject.Properties.Name.Count -gt 0) {
                    if ($obj.PSObject.Properties.Name -contains $repoParam) {
                      $repoOut = $obj.$repoParam
                    } else {
                      # take the first output entry
                      $firstKey = $obj.PSObject.Properties.Name | Select-Object -First 1
                      $repoOut = $obj.$firstKey
                      $repoParam = $firstKey
                    }
                  }
                }
              } catch {}
              Pop-Location
            }
            if (-not $repoOut) { $repoOut = "$ECR_REG/$repoParam" }
            $REPO_URL = $repoOut

            Write-Host "ECR Registry: $ECR_REG"
            Write-Host "Repo URL:     $REPO_URL"
            # Clear any stale auth (ignore errors)
            try { docker logout $ECR_REG | Out-Null } catch { }
            # Quick connectivity check
            try { Invoke-WebRequest -UseBasicParsing -Uri "https://$ECR_REG/v2/" -Method GET -TimeoutSec 10 | Out-Null } catch { Write-Host "Connectivity check (expected 401/200) -> $($_.Exception.Message)" }

            $loginOk = $false
            for ($i=0; $i -lt 2 -and -not $loginOk; $i++) {
              try {
                $pwd = $(aws ecr get-login-password --region $env:AWS_REGION)
                if (-not $pwd) { throw "Empty ECR password" }
                if ($i -eq 0) {
                  docker login --username AWS --password $pwd $ECR_REG
                } else {
                  docker login --username AWS --password $pwd "https://$ECR_REG"
                }
                if ($LASTEXITCODE -eq 0) { $loginOk = $true }
              } catch {
                Start-Sleep -Seconds 3
              }
            }
            if (-not $loginOk) { throw "ECR login failed after retries" }

            # Compute image tag consistently (7-char commit or build number)
            if ($env:GIT_COMMIT -and $env:GIT_COMMIT.Length -ge 7) { $TAG = $env:GIT_COMMIT.Substring(0,7) } else { $TAG = $env:BUILD_NUMBER }
            $localTag = "$($repoParam):$TAG"
            $remoteTag = "$($REPO_URL):$TAG"

            docker build -t "$localTag" .
            docker tag "$localTag" "$remoteTag"

            # Push image first, then scan the remote tag in ECR with Trivy (auth via ECR password)
            Write-Host "Pushing image to ECR..."
            docker push "$remoteTag"

            Write-Host "Scanning pushed image in ECR with Trivy (HIGH,CRITICAL) [informational only]..."
            $ecrPwd = $(aws ecr get-login-password --region $env:AWS_REGION)
            if (-not $ecrPwd) { throw "Failed to obtain ECR password for Trivy auth" }
            # Reuse same cache dir for image scan
            $cachePath = Join-Path $env:WORKSPACE ".trivy-cache"
            if (-not (Test-Path $cachePath)) { New-Item -ItemType Directory -Path $cachePath | Out-Null }
            $cacheMount = ("$cachePath").Replace('\\','/')
            docker run --rm -v "$($cacheMount):/root/.cache/trivy" aquasec/trivy:0.50.0 image --no-progress --scanners vuln --severity HIGH,CRITICAL --timeout 15m --exit-code 0 --username AWS --password "$ecrPwd" "$remoteTag"
            if ($LASTEXITCODE -ne 0) { Write-Host "Trivy remote image scan returned non-zero; proceeding (informational only)."; $global:LASTEXITCODE = 0 }
          '''
        }
      }
    }

    stage('Deploy to EKS') {
      when { expression { return fileExists('manifests') } }
      steps {
        withCredentials([
          string(credentialsId: 'AWS_ACCESS_KEY_ID', variable: 'AWS_ACCESS_KEY_ID'),
          string(credentialsId: 'AWS_SECRET_ACCESS_KEY', variable: 'AWS_SECRET_ACCESS_KEY')
        ]) {
          pwsh '''
            $ErrorActionPreference = "Stop"
            aws eks update-kubeconfig --name $env:CLUSTER_NAME --region $env:AWS_REGION
            aws eks wait cluster-active --name $env:CLUSTER_NAME --region $env:AWS_REGION

            # Namespace, config, deployment
            if (Test-Path 'manifests/namespace.yaml') { kubectl apply -f manifests/namespace.yaml }
            if (Test-Path 'manifests/configmap.yaml') { kubectl apply -f manifests/configmap.yaml }
            if (Test-Path 'manifests/secret.yaml') { kubectl apply -f manifests/secret.yaml }
            kubectl apply -f manifests/deployment.yaml

            # Attempt Classic ELB first
            $svcClassic = 'manifests/service-classic.yaml'
            $svcNlb = 'manifests/service-nlb.yaml'
            $created = $false
            if (Test-Path $svcClassic) {
              Write-Host 'Applying Service (Classic ELB attempt)...'
              kubectl apply -f $svcClassic
              # Wait up to ~6 minutes for ELB hostname
              $deadline = (Get-Date).AddMinutes(6)
              do {
                Start-Sleep -Seconds 15
                $svcHost = kubectl get svc -n app nginx-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>$null
                if ($svcHost) { $created = $true; Write-Host "Service ELB hostname: $svcHost" }
              } while (-not $created -and (Get-Date) -lt $deadline)
            }

            if (-not $created -and (Test-Path $svcNlb)) {
              Write-Host 'Classic ELB not ready/unsupported. Falling back to NLB...'
              kubectl apply -f $svcNlb
              $deadline = (Get-Date).AddMinutes(6)
              do {
                Start-Sleep -Seconds 15
                $svcHost = kubectl get svc -n app nginx-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>$null
                if ($svcHost) { Write-Host "Service NLB hostname: $svcHost"; break }
              } while ((Get-Date) -lt $deadline)
            }
          '''
        }
      }
    }

    stage('Rollout ECR Image') {
      when {
        allOf {
          expression { return params.ECR_REPO?.trim() }
          expression { return fileExists('manifests') }
        }
      }
      steps {
        withCredentials([
          string(credentialsId: 'AWS_ACCESS_KEY_ID', variable: 'AWS_ACCESS_KEY_ID'),
          string(credentialsId: 'AWS_SECRET_ACCESS_KEY', variable: 'AWS_SECRET_ACCESS_KEY')
        ]) {
          pwsh '''
            $ErrorActionPreference = "Stop"
            $ACCOUNT_ID = (aws sts get-caller-identity --query Account --output text)
            $REPO_URL = "$ACCOUNT_ID.dkr.ecr.$env:AWS_REGION.amazonaws.com/$env:ECR_REPO"
            if ($env:GIT_COMMIT -and $env:GIT_COMMIT.Length -ge 7) { $TAG = $env:GIT_COMMIT.Substring(0,7) } else { $TAG = $env:BUILD_NUMBER }
            $remoteTag = "$($REPO_URL):$TAG"
            kubectl set image -n app deployment/nginx-deployment nginx=$remoteTag
            # Wait up to 5 minutes for rollout
            if (-not (kubectl rollout status -n app deployment/nginx-deployment --timeout=5m)) {
              Write-Host "Rollout status timed out - collecting diagnostics"
              kubectl get deployment -n app nginx-deployment -o wide
              kubectl describe deployment -n app nginx-deployment
              kubectl get rs -n app -o wide
              kubectl get pods -n app -o wide
              kubectl describe pods -n app
              kubectl get events --sort-by=.lastTimestamp | Select-Object -Last 100
              throw "Deployment rollout timed out"
            }
          '''
        }
      }
    }

    stage('DAST - ZAP Baseline') {
      steps {
        withCredentials([
          string(credentialsId: 'AWS_ACCESS_KEY_ID', variable: 'AWS_ACCESS_KEY_ID'),
          string(credentialsId: 'AWS_SECRET_ACCESS_KEY', variable: 'AWS_SECRET_ACCESS_KEY')
        ]) {
          pwsh '''
            $ErrorActionPreference = "Continue"
            aws eks update-kubeconfig --name $env:CLUSTER_NAME --region $env:AWS_REGION
            $svcHost = (kubectl get svc -n app nginx-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
            if (-not $svcHost) { Write-Host "Service hostname not ready, skipping ZAP"; exit 0 }
            $url = "http://$svcHost"

            # Pre-pull ZAP image with retries (prefer GHCR, fallback to Docker Hub)
            $zapImageGhcr = "ghcr.io/zaproxy/zaproxy:stable"
            $zapImageHub  = "owasp/zap2docker-stable"
            $pulled = $false
            foreach ($img in @($zapImageGhcr, $zapImageHub)) {
              for ($i=0; $i -lt 2 -and -not $pulled; $i++) {
                try {
                  Write-Host "Pulling ZAP image: $img (attempt $($i+1))"
                  docker pull $img
                  if ($LASTEXITCODE -eq 0) { $pulled = $true; $zapImage = $img }
                } catch { Start-Sleep -Seconds 3 }
              }
              if ($pulled) { break }
            }

            if (-not $pulled) {
              Write-Host "Could not pull any ZAP image; skipping ZAP baseline (non-blocking)."
              exit 0
            }

            # Prepare writable artifacts directory and mount it for report output
            $artDir = Join-Path $env:WORKSPACE "zap-artifacts"
            if (-not (Test-Path $artDir)) { New-Item -ItemType Directory -Path $artDir | Out-Null }
            $artMount = ("$artDir").Replace('\\','/')

            Write-Host "Running ZAP Baseline scan against $url using $zapImage"
            docker run --rm -u 0:0 -v "$($artMount):/zap/wrk" -t $zapImage zap-baseline.py -t $url -r zap.html
            if ($LASTEXITCODE -ne 0) { Write-Host "ZAP baseline returned non-zero ($LASTEXITCODE). Proceeding (non-blocking)."; $global:LASTEXITCODE = 0 }
          '''
        }
      }
      post {
        always {
          archiveArtifacts artifacts: 'zap-artifacts/zap.html', allowEmptyArchive: true
        }
      }
    }
  }

  post {
    always {
      echo 'Pipeline finished.'
    }
  }
}
