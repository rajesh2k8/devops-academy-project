# DevOps Academy Capstone Project: Jenkins → Terraform → EKS (with ECR and Docker)

This repository delivers a simple web app (Nginx + static UI) through a CI/CD pipeline:
- Build Docker image → push to Amazon ECR
- Provision infra with Terraform → Amazon EKS (cluster, node group, VPC)
- Deploy to EKS via Jenkins stages

## Architecture
- Jenkins Pipeline builds and pushes image to ECR
- Terraform manages VPC, EKS, IAM, and related resources
- Kubernetes manifests deploy the app, exposed by a LoadBalancer Service

## Prerequisites
- AWS account with permissions for ECR/EKS/VPC/IAM (AdministratorAccess recommended for demo)
- Jenkins (Windows agent supported) with AWS CLI, Terraform, kubectl, and Docker installed
- Git credentials for this repository

## Jenkins setup
1. Create two Global “Secret text” credentials:
   - ID: `AWS_ACCESS_KEY_ID`  → value: your AWS access key ID
   - ID: `AWS_SECRET_ACCESS_KEY` → value: your AWS secret access key
2. Create a Pipeline job pointing to this repo (Pipeline script from SCM)
3. Ensure the job uses `Jenkinsfile` (default path)
4. Agent requires: awscli, terraform, kubectl, docker in PATH

## Pipeline parameters
- `AWS_REGION` (default: `ap-south-1`)
- `ECR_REPO` (default: `gl-capstone-project-pan-repo`)
- `CLUSTER_NAME` (default: `capstone-project-eks-cluster`)

## How to run
1. Run the Jenkins job with defaults
2. Stages executed:
   - Checkout
   - Ensure Terraform Backend (create S3 bucket + DynamoDB table if missing)
   - SAST & Manifest Lint (Trivy fs + kubeval + kube-linter)
   - Tools Versions
   - AWS Identity Check (sanity check)
   - Terraform Init/Plan/Apply (VPC, EKS, ECR; uses S3 backend with lock)
   - Docker Build and Push (builds and pushes image to ECR; auto-detects repo from TF outputs)
   - Deploy to EKS (applies manifests; attempts Classic ELB, falls back to NLB if needed)
   - Rollout ECR Image (updates deployment image and waits for rollout)
   - DAST - ZAP Baseline (non-blocking; archives HTML report)
3. After success, get Service External IP:
   ```
   kubectl -n app get svc nginx-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
   ```
   Open `http://<ELB-HOSTNAME>` in the browser

## Local kubectl context
Set kubeconfig to your cluster (if testing locally):
```
aws eks update-kubeconfig --name capstone-project-eks-cluster --region ap-south-1
```

## App UI
- TODO

## Cost notes
- ELB and NAT Gateway incur charges while running
- To lower costs without removing infra:
  - Delete Service: `kubectl delete svc nginx-service`
  - Scale deployment to 0: `kubectl scale deploy nginx-deployment --replicas=0`
  - Scale node group to 0 instances (managed node group):
    ```
    aws eks update-nodegroup-config \
      --cluster-name capstone-project-eks-cluster \
      --nodegroup-name capstone-nodes \
      --scaling-config minSize=0,desiredSize=0,maxSize=1 \
      --region ap-south-1
    ```

## Destroy capability
- The pipeline’s destroy capability has been disabled deliberately to prevent accidental deletion
- `Jenkinsfile.destroy` is a no-op and exits with an error if triggered
- If you need full teardown later, consider switching Terraform backend to S3 and running `terraform destroy` manually from `infra/`

## Troubleshooting
- ECR login 400/“no basic auth credentials” → verify credentials, region, time sync, and proxy rules
- OIDC thumbprint errors → ensure full issuer URL is used by Terraform (handled in this repo)
- Rollout timeouts → check `kubectl describe` for ImagePullBackOff, readiness, or capacity issues
- Service not found in wait loop → ensure namespace `app` is used: `kubectl -n app get svc nginx-service`
- Classic ELB unsupported in your account/region → pipeline falls back to NLB automatically

## What this repo creates
- VPC with 2 public + 2 private subnets across 2 AZs, IGW, 1 NAT, route tables
- Security Groups for HTTP(80) and SSH(22-from-CIDR)
- EKS cluster (`capstone-project-eks-cluster`) + managed node group
- ECR repo (`gl-capstone-project-pan-repo`) with scan-on-push
- Kubernetes manifests (namespace `app`, deployment, services) and Classic ELB exposure
- Jenkins pipeline with:
  - S3+DynamoDB Terraform backend ensure
  - SAST (Trivy fs/image) and DAST (ZAP baseline, non-blocking)
  - End-to-end build → infra → deploy → test flow

## Maintainers
Vivek, Rajesh, and Ravi
