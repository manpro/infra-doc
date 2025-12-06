# 🚀 Deployment Guide - The DevOps Way

This guide follows the **"Zero Manual Work"** philosophy. The inventory bot is treated as Application #41 in your infrastructure.

## 🎯 Philosophy

> "If you do it manually now ('just this once'), you break the principle. Next time you want to change the script, you'll have to remember those manual commands. You'll stop updating because it's 'annoying'."

**Solution:** Treat Inventory Bot like any other application with:
- Git repository ✅
- CI/CD pipeline ✅
- GitOps deployment ✅
- Automatic updates forever ✅

## 📋 One-Time Setup (3 Steps)

### Step 1: Create the Gitea Repository

```bash
# Option A: Via Gitea Web UI
# 1. Login to Gitea
# 2. Click "+" → "New Repository"
# 3. Name: "inventory-bot"
# 4. Initialize with README: No
# 5. Create Repository

# Option B: Via CLI (if you have tea/gitea CLI)
tea repos create --name inventory-bot --description "Auto-Inventory Bot for K8s Infrastructure"
```

### Step 2: Push to GitHub and Gitea

```bash
cd /home/micke/documents/infra-doc

# Already pushed to GitHub (done!)

# Add Gitea mirror (optional, for local Woodpecker CI)
git remote add gitea http://172.16.16.161:31000/gitea-admin/inventory-bot.git
git push gitea main

# Enable in Woodpecker
# 1. Woodpecker UI → Repositories
# 2. Enable "inventory-bot"
# 3. Add secrets: gitea-user, gitea-password (reuse existing ones)
```

### Step 3: Setup GitOps

```bash
# Navigate to your k8s-gitops repository
cd /path/to/k8s-gitops

# Copy GitOps manifests
mkdir -p infrastructure/inventory-bot
cp /home/micke/documents/infra-doc/gitops/*.yaml infrastructure/inventory-bot/

# Commit to GitOps repo
git add infrastructure/inventory-bot/
git commit -m "feat: Add auto-inventory-bot GitOps manifests"
git push origin main

# ArgoCD will detect and deploy automatically
```

### Step 4: Create the Secret (The ONLY Manual Command)

This is the only manual step that can't be automated (unless you use Vault):

```bash
# Create git credentials secret
kubectl create secret generic git-credentials \
  --from-literal=username=gitea-admin \
  --from-literal=password=YOUR_GITEA_TOKEN_HERE \
  --from-literal=repo_url=gitea-http.gitea.svc.cluster.local:3000/gitea-admin/infrastructure-docs.git \
  -n infrastructure-docs

# Verify secret was created
kubectl get secret git-credentials -n infrastructure-docs
```

**Getting a Gitea Token:**
1. Login to Gitea → Settings → Applications
2. Generate New Token → Name: "inventory-bot"
3. Copy the token immediately (it won't be shown again)
4. Use it in the command above

## 🔄 Automated Workflow

Once setup is complete, the entire workflow is automated:

```
┌─────────────────┐
│ 1. Push Code    │  Developer pushes to GitHub/Gitea
│    to Repo      │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 2. Woodpecker   │  Kaniko builds → 172.16.16.161:30551/inventory-bot:abc123
│    CI/CD        │  (Simplified pipeline - it's just a utility!)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 3. Update       │  Updates k8s-gitops (Gitea)
│    GitOps Repo  │  infrastructure/inventory-bot/03-cronjob.yaml
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 4. ArgoCD       │  Auto-sync to prod3
│    Auto-Sync    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 5. Bot Runs     │  Daily at 2 AM UTC → scans → commits docs
│    on Schedule  │  (Zero manual work!)
└─────────────────┘
```

## 🧪 Testing

### Test the Pipeline

```bash
# Make a small change to inventory.py
echo "# Test change" >> inventory.py

# Commit and push
git add inventory.py
git commit -m "test: Verify CI/CD pipeline"
git push gitea main

# Watch Woodpecker build
# Go to Woodpecker UI and watch the pipeline run

# Check ArgoCD
# Go to ArgoCD UI and see the inventory-bot sync status

# Verify deployment on prod3
kubectl get pods -n infrastructure-docs -l app=inventory-bot
```

### Test Manual Run

```bash
# Trigger a manual job run (outside of schedule)
kubectl create job --from=cronjob/auto-inventory-bot manual-test-$(date +%s) -n infrastructure-docs

# Watch logs
kubectl logs -n infrastructure-docs -l app=inventory-bot --follow

# Check if docs were committed
# Go to your infrastructure-docs repo and see the latest commit
```

## 🔍 Monitoring & Debugging

### Check CronJob Status

```bash
# View CronJob
kubectl get cronjob auto-inventory-bot -n infrastructure-docs

# View recent job runs
kubectl get jobs -n infrastructure-docs --sort-by=.metadata.creationTimestamp

# View pods
kubectl get pods -n infrastructure-docs -l app=inventory-bot
```

### View Logs

```bash
# Latest job logs
kubectl logs -n infrastructure-docs -l app=inventory-bot --tail=100

# Specific job logs
kubectl logs -n infrastructure-docs job/auto-inventory-bot-28934710

# Follow live logs
kubectl logs -n infrastructure-docs -l app=inventory-bot --follow
```

### Troubleshooting

**Pipeline fails to build?**
- Check Woodpecker UI for build logs
- Verify Docker registry is accessible
- Check .woodpecker.yml syntax

**ArgoCD not syncing?**
- Check if ArgoCD is watching the infrastructure/inventory-bot path
- Verify manifest syntax: `kubectl apply --dry-run=client -f gitops/`
- Check ArgoCD application logs

**Bot not scanning?**
- Check RBAC permissions: `kubectl auth can-i list nodes --as=system:serviceaccount:infrastructure-docs:inventory-bot`
- Verify secret exists and is correct
- Check pod logs for errors

**Git push fails?**
- Verify secret has correct credentials
- Check if Gitea service is accessible from pod
- Ensure token has write permissions to infrastructure-docs repo

## 🎨 Making Changes

### Updating the Bot Logic

```bash
# Edit inventory.py locally
nano inventory.py

# Commit and push
git add inventory.py
git commit -m "feat: Add new scanning feature"
git push gitea main

# Pipeline automatically:
# 1. Builds new image
# 2. Updates GitOps manifest
# 3. ArgoCD deploys to prod3
# → Done! No manual work needed!
```

### Changing the Schedule

```bash
# Edit the schedule in GitOps repo
cd /path/to/k8s-gitops
nano infrastructure/inventory-bot/03-cronjob.yaml

# Change schedule line:
# schedule: "0 2 * * *"  # 2 AM daily
# To:
# schedule: "0 */6 * * *"  # Every 6 hours

git add infrastructure/inventory-bot/03-cronjob.yaml
git commit -m "chore: Change bot schedule to every 6 hours"
git push origin main

# ArgoCD deploys the change automatically
```

## 📚 Next Steps

1. **Monitor First Run:** Watch the logs when the bot runs at 2 AM (or trigger manually)
2. **Verify Output:** Check that docs are being committed to infrastructure-docs repo
3. **Customize:** Add more scanning logic to inventory.py as needed
4. **Integrate:** Link the docs to your Obsidian vault

## 🎯 Success Criteria

You know it's working when:
- ✅ Woodpecker builds on every push to inventory-bot repo
- ✅ GitOps repo is updated automatically with new image tags
- ✅ ArgoCD shows inventory-bot as "Synced" and "Healthy"
- ✅ Bot runs daily at 2 AM on prod3
- ✅ infrastructure-docs repo gets daily commits with updated Markdown files
- ✅ You never have to run `docker build` or `kubectl apply` manually again!

---

**This is the DevOps Way.** Set it up once, it works forever. 🚀
