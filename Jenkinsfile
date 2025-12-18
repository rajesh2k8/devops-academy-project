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
          sh '''
            set -euo pipefail
            bucketBase="devops-academy-project"
            table="devops-academy-project"
            region="${AWS_REGION}"
            account="$(aws sts get-caller-identity --query Account --output text 2>/dev/null || true)"
            if [ -z "${account}" ]; then
              echo "Unable to resolve AWS account id" >&2
              exit 1
            fi

            bucket="${bucketBase}"
            echo "Ensuring S3 bucket ${bucket} exists in ${region}..."
            if ! aws s3api head-bucket --bucket "${bucket}" >/dev/null 2>&1; then
              if [ "${region}" = "us-east-1" ]; then
                aws s3api create-bucket --bucket "${bucket}" >/dev/null 2>&1 || true
              else
                aws s3api create-bucket --bucket "${bucket}" --create-bucket-configuration "LocationConstraint=${region}" >/dev/null 2>&1 || true
              fi
              if ! aws s3api head-bucket --bucket "${bucket}" >/dev/null 2>&1; then
                echo "Base bucket creation failed; trying account-suffixed bucket..."
                bucket="${bucketBase}-${account}"
                if [ "${region}" = "us-east-1" ]; then
                  aws s3api create-bucket --bucket "${bucket}"
                else
                  aws s3api create-bucket --bucket "${bucket}" --create-bucket-configuration "LocationConstraint=${region}"
                fi
              fi
              aws s3api put-bucket-versioning --bucket "${bucket}" --versioning-configuration Status=Enabled
              aws s3api put-public-access-block --bucket "${bucket}" --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
              ok=""
              for i in $(seq 1 10); do
                if aws s3api head-bucket --bucket "${bucket}" >/dev/null 2>&1; then ok="yes"; break; fi
                sleep 3
              done
              if [ -z "${ok}" ]; then
                echo "S3 bucket ${bucket} not reachable after creation" >&2
                exit 1
              fi
            fi

            echo "Ensuring DynamoDB table ${table} exists..."
            if ! aws dynamodb describe-table --table-name "${table}" >/dev/null 2>&1; then
              aws dynamodb create-table --table-name "${table}" \
                --attribute-definitions AttributeName=LockID,AttributeType=S \
                --key-schema AttributeName=LockID,KeyType=HASH \
                --billing-mode PAY_PER_REQUEST
              echo "Waiting for DynamoDB table to be ACTIVE..."
              aws dynamodb wait table-exists --table-name "${table}"
            fi
          '''
        }
      }
    }

    stage('SAST & Manifest Lint') {
      steps {
        sh '''
          set +e
          echo "Running Trivy filesystem scan (HIGH,CRITICAL) on repo..."
          cachePath="$WORKSPACE/.trivy-cache"
          mkdir -p "$cachePath"
          docker run --rm -v "$WORKSPACE:/repo" -v "$cachePath:/root/.cache/trivy" -w /repo aquasec/trivy:0.50.0 fs --no-progress --scanners vuln --severity HIGH,CRITICAL --timeout 15m --exit-code 0 .
          if [ $? -ne 0 ]; then echo "Trivy filesystem scan returned non-zero; proceeding (informational only)."; fi

          if [ -d "manifests" ]; then
            echo "Linting Kubernetes manifests with kubeval (Docker Hub mirror)..."
            docker run --rm -v "$WORKSPACE/manifests:/manifests" cytopia/kubeval:latest -d /manifests
            echo "Running kube-linter for richer checks..."
            docker run --rm -v "$WORKSPACE/manifests:/manifests" stackrox/kube-linter:v0.6.8 lint /manifests
          fi
          true
        '''
      }
    }

    stage('Tools Versions') {
      steps {
        sh '''
          set +e
          aws --version || true
          terraform version || true
          kubectl version --client || true
          docker --version || true
          true
        '''
      }
    }

    stage('AWS Identity Check') {
      steps {
        withCredentials([
          string(credentialsId: 'AWS_ACCESS_KEY_ID', variable: 'AWS_ACCESS_KEY_ID'),
          string(credentialsId: 'AWS_SECRET_ACCESS_KEY', variable: 'AWS_SECRET_ACCESS_KEY')
        ]) {
          sh '''
            set -euo pipefail
            echo "Checking AWS identity..."
            aws sts get-caller-identity
          '''
        }
      }
    }

    stage('Terraform Init/Plan/Apply') {
      steps {
        dir('infrastructure') {
          withCredentials([
            string(credentialsId: 'AWS_ACCESS_KEY_ID', variable: 'AWS_ACCESS_KEY_ID'),
            string(credentialsId: 'AWS_SECRET_ACCESS_KEY', variable: 'AWS_SECRET_ACCESS_KEY')
          ]) {
            sh '''
              set -euo pipefail
              bucketBase="devops-academy-project"
              table="devops-academy-project"
              account="$(aws sts get-caller-identity --query Account --output text)"
              bucket="${bucketBase}"
              if ! aws s3api head-bucket --bucket "${bucket}" >/dev/null 2>&1; then
                bucket="${bucketBase}-${account}"
              fi

              terraform init -reconfigure -upgrade -input=false \
                -backend-config="bucket=${bucket}" \
                -backend-config="key=envs/dev/terraform.tfstate" \
                -backend-config="region=${AWS_REGION}" \
                -backend-config="dynamodb_table=${table}" \
                -backend-config="encrypt=true"
              terraform workspace select dev || terraform workspace new dev
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
          sh '''
            set -euo pipefail
            ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
            ECR_REG="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
            REPO="${ECR_REPO}"
            REPO_URL="${ECR_REG}/${REPO}"

            echo "ECR Registry: ${ECR_REG}"
            echo "Repo URL:     ${REPO_URL}"
            docker logout "${ECR_REG}" >/dev/null 2>&1 || true

            aws ecr get-login-password --region "${AWS_REGION}" | docker login --username AWS --password-stdin "${ECR_REG}"

            if [ -n "${GIT_COMMIT:-}" ] && [ "${#GIT_COMMIT}" -ge 7 ]; then TAG="${GIT_COMMIT:0:7}"; else TAG="${BUILD_NUMBER}"; fi
            localTag="${REPO}:${TAG}"
            remoteTag="${REPO_URL}:${TAG}"

            docker build -t "${localTag}" .
            docker tag "${localTag}" "${remoteTag}"

            echo "Pushing image to ECR..."
            docker push "${remoteTag}"

            # Trivy remote image scan (informational only)
            cachePath="${WORKSPACE}/.trivy-cache"
            mkdir -p "${cachePath}"
            ecrPwd="$(aws ecr get-login-password --region "${AWS_REGION}")"
            docker run --rm -v "${cachePath}:/root/.cache/trivy" aquasec/trivy:0.50.0 image --no-progress --scanners vuln --severity HIGH,CRITICAL --timeout 15m --exit-code 0 --username AWS --password "${ecrPwd}" "${remoteTag}" || true
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
          sh '''
            set -euo pipefail
            aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${AWS_REGION}"
            aws eks wait cluster-active --name "${CLUSTER_NAME}" --region "${AWS_REGION}"

            [ -f manifests/namespace.yaml ] && kubectl apply -f manifests/namespace.yaml
            [ -f manifests/configmap.yaml ] && kubectl apply -f manifests/configmap.yaml
            [ -f manifests/secret.yaml ] && kubectl apply -f manifests/secret.yaml
            kubectl apply -f manifests/deployment.yaml

            svcClassic="manifests/service-classic.yaml"
            svcNlb="manifests/service-nlb.yaml"
            created=""
            if [ -f "$svcClassic" ]; then
              echo "Applying Service (Classic ELB attempt)..."
              kubectl apply -f "$svcClassic"
              deadline=$(( $(date +%s) + 360 ))
              while [ -z "$created" ] && [ "$(date +%s)" -lt "$deadline" ]; do
                sleep 15
                svcHost=$(kubectl get svc -n app nginx-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
                if [ -n "$svcHost" ]; then created="yes"; echo "Service ELB hostname: $svcHost"; fi
              done
            fi

            if [ -z "$created" ] && [ -f "$svcNlb" ]; then
              echo "Classic ELB not ready/unsupported. Falling back to NLB..."
              kubectl apply -f "$svcNlb"
              deadline=$(( $(date +%s) + 360 ))
              while [ "$(date +%s)" -lt "$deadline" ]; do
                sleep 15
                svcHost=$(kubectl get svc -n app nginx-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
                if [ -n "$svcHost" ]; then echo "Service NLB hostname: $svcHost"; break; fi
              done
            fi
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
          sh '''
            set -euo pipefail
            ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
            REPO_URL="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}"
            if [ -n "${GIT_COMMIT:-}" ] && [ "${#GIT_COMMIT}" -ge 7 ]; then TAG="${GIT_COMMIT:0:7}"; else TAG="${BUILD_NUMBER}"; fi
            remoteTag="${REPO_URL}:${TAG}"
            kubectl set image -n app deployment/nginx-deployment nginx="${remoteTag}"
            set +e
            kubectl rollout status -n app deployment/nginx-deployment --timeout=5m
            rc=$?
            set -e
            if [ $rc -ne 0 ]; then
              echo "Rollout status timed out - collecting diagnostics"
              kubectl get deployment -n app nginx-deployment -o wide || true
              kubectl describe deployment -n app nginx-deployment || true
              kubectl get rs -n app -o wide || true
              kubectl get pods -n app -o wide || true
              kubectl describe pods -n app || true
              kubectl get events --sort-by=.lastTimestamp | tail -n 100 || true
              exit 1
            fi
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
          sh '''
            set -euo pipefail
            aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${AWS_REGION}"
            svcHost="$(kubectl get svc -n app nginx-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
            if [ -z "${svcHost}" ]; then echo "Service hostname not ready, skipping ZAP"; exit 0; fi
            url="http://${svcHost}"

            zapImage=""
            for img in "ghcr.io/zaproxy/zaproxy:stable" "owasp/zap2docker-stable"; do
              for i in 1 2; do
                echo "Pulling ZAP image: $img (attempt $i)"
                if docker pull "$img"; then zapImage="$img"; break 2; fi
                sleep 3
              done
            done

            if [ -z "${zapImage}" ]; then
              echo "Could not pull any ZAP image; skipping ZAP baseline (non-blocking)."
              exit 0
            fi

            artDir="${WORKSPACE}/zap-artifacts"
            mkdir -p "${artDir}"

            echo "Running ZAP Baseline scan against ${url} using ${zapImage}"
            docker run --rm -u 0:0 -v "${artDir}:/zap/wrk" -t "${zapImage}" zap-baseline.py -t "${url}" -r zap.html || true
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
