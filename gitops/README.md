# GitOps Manifests for Auto-Inventory Bot

This directory contains the Kubernetes manifests ready for your `k8s-gitops` repository.

## 📋 How to Deploy (One-Time Setup)

### Step 1: Copy to k8s-gitops Repository

```bash
# Navigate to your k8s-gitops repo
cd /path/to/k8s-gitops

# Create the infrastructure directory if it doesn't exist
mkdir -p infrastructure/inventory-bot

# Copy all manifests
cp /home/micke/documents/infra-doc/gitops/*.yaml infrastructure/inventory-bot/

# Commit to GitOps repo
git add infrastructure/inventory-bot/
git commit -m "feat: Add auto-inventory-bot GitOps manifests"
git push origin main
```

### Step 2: Create the Git Credentials Secret (ONCE)

This is the ONLY manual step required:

```bash
kubectl create secret generic git-credentials \
  --from-literal=username=gitea-admin \
  --from-literal=password=YOUR_GITEA_TOKEN_HERE \
  --from-literal=repo_url=gitea-http.gitea.svc.cluster.local:3000/gitea-admin/infrastructure-docs.git \
  -n infrastructure-docs
```

**How to get a Gitea token:**
1. Login to Gitea web interface
2. Go to Settings → Applications → Generate New Token
3. Give it a name like "inventory-bot"
4. Copy the token and use it in the command above

### Step 3: Let ArgoCD Deploy

ArgoCD will automatically detect the new manifests and deploy the inventory bot to `prod3`.

## 🔄 Automated Workflow

Once set up, the workflow is fully automated:

1. **Code Change** → Push to `infra-doc` repository
2. **CI/CD** → Woodpecker builds new Docker image
3. **GitOps Update** → Woodpecker updates the manifest in `k8s-gitops`
4. **Auto-Deploy** → ArgoCD syncs and deploys to Kubernetes
5. **Bot Runs** → Daily at 2 AM on `prod3`, auto-commits docs

## 📁 Manifest Structure

```
infrastructure/inventory-bot/
├── 00-namespace.yaml      # Creates infrastructure-docs namespace
├── 01-rbac.yaml          # ServiceAccount, ClusterRole, Binding
├── 02-configmap.yaml     # Git wrapper script
└── 03-cronjob.yaml       # The main CronJob resource
```

## 🔍 Monitoring

Check bot status:
```bash
# View CronJob
kubectl get cronjob -n infrastructure-docs

# View recent job runs
kubectl get jobs -n infrastructure-docs

# View logs from latest run
kubectl logs -n infrastructure-docs -l app=inventory-bot --tail=100
```

## 🛠️ Troubleshooting

**Bot not running?**
```bash
# Check if secret exists
kubectl get secret git-credentials -n infrastructure-docs

# Manually trigger a run
kubectl create job --from=cronjob/auto-inventory-bot manual-test -n infrastructure-docs
kubectl logs -f job/manual-test -n infrastructure-docs
```

**Image pull errors?**
- Verify the image exists: `docker images | grep inventory-bot`
- Check registry is accessible from prod3
- Verify image tag in cronjob.yaml matches what Woodpecker built
