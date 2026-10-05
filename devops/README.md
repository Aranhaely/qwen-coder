# DevOps Toolkit

Production-grade, copy-paste-ready IaC & automation for a typical web app on AWS + Kubernetes.
Everything here is parameterized (`myapp` → your project) and validated where possible in this sandbox.

## Layout

```
devops/
├── infra/
│   ├── terraform/        # VPC + EKS (on-demand & spot node groups) + RDS + S3
│   │   ├── main.tf           # modules: vpc, eks, rds, security-group, s3-bucket
│   │   ├── variables.tf      # all knobs typed + validated
│   │   ├── backend.tf        # S3 + DynamoDB state locking (values via -backend-config)
│   │   ├── dev.tfvars / prod.tfvars  # env profiles (HA vs cheap)
│   └── ansible/          # CIS-style Ubuntu hardening
│       ├── playbooks/harden.yml   # ssh, ufw, sysctl, fail2ban, unattended-upgrades, docker
│       └── inventory/prod.ini     # example inventory (INI format)
├── k8s/                  # Kustomize layered manifests
│   ├── base/             # Deployment(probes,securityContext,PDB,HPA,NetworkPolicy,Ingress)
│   └── overlays/{dev,prod}
├── ci/github-actions.yml # test→security(gitleaks,pip-audit,tfsec,trivy,kubeconform)→image(cosign+SBOM)→infra(OIDC plan/apply)→deploy(staging→prod w/ approval + auto-rollback)
├── monitoring/
│   ├── prometheus-values.yaml  # kube-prometheus-stack: Grafana, Alertmanager→Slack
│   └── slo-alerts.yaml         # PrometheusRule: error-budget & infra alerts
└── scripts/bootstrap-backend.sh  # one-time S3 bucket + DynamoDB lock table
```

## Design decisions baked in

- **No long-lived cloud keys**: CI assumes an IAM role via GitHub OIDC; DB password comes from SSM Parameter Store at apply time, never from tfvars/git.
- **State safety**: remote S3 state with versioning + encryption + DynamoDB locking; `terraform fmt/validate` gate in CI; prod apply requires a protected GitHub Environment (manual approval).
- **Cost-aware HA**: single NAT gateway in dev, one-per-AZ in prod; spot node group scales to 0 when idle; RDS burstable in dev, memory-optimized multi-AZ in prod.
- **K8s resilience**: startup/readiness/liveness probes, rolling update with `maxUnavailable=0`, PDB, HPA on CPU *and* custom RPS metric, topology spread across nodes/zones, non-root read-only containers, NetworkPolicy least-privilege.
- **Supply chain**: images pinned by digest at deploy time, signed keyless with cosign, SBOM attached; Trivy/tfsec/gitleaks/pip-audit as blocking gates.
- **Observability**: Prometheus scrape annotations on the pod template, SLO burn-rate alerts (5xx >1%, p99 >500ms), Slack routing with severity grouping.

## Quick start

```bash
# 1. bootstrap state backend (needs admin creds once)
STATE_BUCKET=mycompany-tfstate ./scripts/bootstrap-backend.sh

# 2. infra
cd infra/terraform && terraform init \
  -backend-config="bucket=$STATE_BUCKET" -backend-config="key=env/dev.tfstate" ...
terraform plan -var-file=dev.tfvars

# 3. apps
kubectl apply -k k8s/overlays/dev

# 4. monitoring
helm upgrade -i kps prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace -f monitoring/prometheus-values.yaml
kubectl apply -f monitoring/slo-alerts.yaml

# 5. servers (non-k8s boxes)
ansible-playbook -i infra/ansible/inventory/prod.ini infra/ansible/playbooks/harden.yml --check --diff
```

## Placeholders you must replace

| Placeholder | Where | What to set |
|---|---|---|
| `myapp` | everywhere | real project name |
| `ghcr.io/OWNER/REPO` | k8s base, CI | your image repo |
| `arn:aws:iam::123456789012:...` | SA annotation | real account/role ARN |
| `example.com` hosts | Ingress/Grafana | real DNS |
| Slack webhook | prometheus-values | secret-managed URL |
| admin SSH key | harden.yml | your pubkey |

## Validated in-sandbox

- All YAML files parse cleanly (`yaml.safe_load_all`).
- Terraform syntax reviewed manually (no provider binary available offline); run `terraform validate` in CI before first apply.
