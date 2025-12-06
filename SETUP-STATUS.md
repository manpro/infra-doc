# 🎯 Setup Status - inventory-bot

## ✅ What's DONE (Automated)

### 1. Code Ready ✅
- ✅ All code pushed to GitHub: https://github.com/manpro/infra-doc
- ✅ `.woodpecker.yml` configured (matches analogier pattern)
- ✅ Uses correct secrets: `gitea_user`, `gitea_password`
- ✅ Simplified pipeline (build → push → update GitOps)

### 2. GitOps Manifests Deployed ✅
- ✅ Copied to: `/home/micke/k8s-gitops/infrastructure/inventory-bot/`
- ✅ Committed to k8s-gitops (Gitea)
- ✅ Files deployed:
  - `00-namespace.yaml` - Creates infrastructure-docs namespace
  - `01-rbac.yaml` - ServiceAccount + ClusterRole
  - `02-configmap.yaml` - Git wrapper script
  - `03-cronjob.yaml` - Main CronJob resource

### 3. Kubernetes Secret Created ✅
- ✅ Namespace created: `infrastructure-docs`
- ✅ Secret created: `git-credentials`
  - Username: gitea-admin
  - Password: [SET]
  - Repo URL: gitea-http.gitea.svc.cluster.local:3000/gitea-admin/infrastructure-docs.git

---

## ⏳ What's PENDING (Manual Steps)

### 1. Create Gitea Repositories (2 repos needed)

#### Repo #1: `inventory-bot` (source code)
```
URL: http://172.16.16.161:31000
Login: gitea-admin
Location: Create new repository

Settings:
- Owner: gitea-admin
- Repository Name: inventory-bot
- Visibility: Private or Public
- Initialize: NO (we'll push existing code)
```

#### Repo #2: `infrastructure-docs` (bot output)
```
URL: http://172.16.16.161:31000
Login: gitea-admin
Location: Create new repository

Settings:
- Owner: gitea-admin
- Repository Name: infrastructure-docs
- Visibility: Private or Public
- Initialize: YES with README (or push empty commit)
```

**After creating repos:**
```bash
cd /home/micke/documents/infra-doc

# Push inventory-bot code
git push http://gitea-admin:NxQcWqVDzDDR6lgzAOPacbNQzzgnodUY@gmk1:30002/gitea-admin/inventory-bot.git main

# Initialize infrastructure-docs (if not auto-init)
cd /tmp
git clone http://gitea-admin:NxQcWqVDzDDR6lgzAOPacbNQzzgnodUY@gmk1:30002/gitea-admin/infrastructure-docs.git
cd infrastructure-docs
echo "# Infrastructure Documentation" > README.md
git add README.md
git commit -m "Initial commit"
git push origin main
```

### 2. Enable in Woodpecker

**Option A: Via Woodpecker UI** (Recommended)
```
1. Open: http://172.16.16.161:30800
2. Login (use Gitea SSO)
3. Repositories → Click "+"
4. Find "inventory-bot" in list
5. Click "Enable"
6. Done! (Secrets gitea_user, gitea_password already exist globally)
```

**Option B: Via API** (if you have token)
```bash
# Get Gitea repo ID first
REPO_ID=$(curl -s "http://172.16.16.161:31000/api/v1/repos/gitea-admin/inventory-bot" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)

# Enable in Woodpecker
WOODPECKER_TOKEN=$(cat /home/micke/.woodpecker-token)
curl -X POST \
  -H "Authorization: Bearer $WOODPECKER_TOKEN" \
  "http://172.16.16.161:30800/api/repos?forge_remote_id=$REPO_ID"
```

### 3. Trigger First Build

Once Woodpecker is enabled and code is pushed to Gitea:

```bash
cd /home/micke/documents/infra-doc
echo "# Trigger" >> README.md
git add README.md
git commit -m "test: Trigger first pipeline run"
git push gitea main
```

Watch build at: http://172.16.16.161:30800

---

## 🚀 Automated Workflow (After Setup)

Once the 2 manual steps above are done, everything is automated:

```
┌─────────────────┐
│ Push Code       │  git push gitea main
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Woodpecker      │  Builds with Kaniko
│ CI/CD           │  → 172.16.16.161:30551/inventory-bot:abc123
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Update GitOps   │  Updates k8s-gitops/infrastructure/inventory-bot/
│ (Automatic)     │  03-cronjob.yaml with new image tag
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ ArgoCD          │  Detects change in k8s-gitops
│ Auto-Sync       │  Deploys to prod3
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Bot Runs        │  Daily at 2 AM UTC
│ on Schedule     │  Scans K8s → Generates Markdown → Commits to infrastructure-docs
└─────────────────┘
```

**Zero manual work needed after initial setup!**

---

## 🧪 Verification Commands

### Check GitOps Deployment
```bash
export KUBECONFIG=~/.kube/config

# Check if ArgoCD has deployed
kubectl get all -n infrastructure-docs

# Check CronJob
kubectl get cronjob auto-inventory-bot -n infrastructure-docs

# Check secret
kubectl get secret git-credentials -n infrastructure-docs

# Manual test run
kubectl create job --from=cronjob/auto-inventory-bot test-$(date +%s) -n infrastructure-docs

# View logs
kubectl logs -n infrastructure-docs -l app=inventory-bot --follow
```

### Check Woodpecker Status
```bash
# Via CLI (if installed)
export WOODPECKER_SERVER="http://172.16.16.161:30800"
export WOODPECKER_TOKEN=$(cat /home/micke/.woodpecker-token)

woodpecker-cli repo ls
woodpecker-cli pipeline ls gitea-admin/inventory-bot
```

---

## 📊 Summary

| Task | Status | Method |
|------|--------|--------|
| Code to GitHub | ✅ Done | Automated |
| GitOps manifests in k8s-gitops | ✅ Done | Automated |
| K8s namespace created | ✅ Done | Automated |
| K8s secret created | ✅ Done | Automated |
| Create Gitea repos (2x) | ⏳ Pending | Manual (UI) |
| Push code to Gitea | ⏳ Pending | Command ready |
| Enable in Woodpecker | ⏳ Pending | Manual (UI or API) |
| Trigger first build | ⏳ Pending | After above steps |

---

## 🎯 Next Action Items

**Do these 2 things and you're done:**

1. **Create 2 Gitea repos** (5 minutes via UI)
   - `inventory-bot` (source code)
   - `infrastructure-docs` (bot output)

2. **Enable in Woodpecker** (1 minute via UI)
   - Repositories → Enable "inventory-bot"

Then push code and watch the magic happen! 🚀

---

## 🆘 Need Help?

All commands are in this file. If you want me to automate the Gitea repo creation via Playwright, I can do that - just ask!

**Playwright automation available:**
```bash
# I can create a script that:
# 1. Logs into Gitea
# 2. Creates both repositories
# 3. Pushes initial code
# Want me to do that?
```
