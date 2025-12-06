# 🚀 Complete Setup Guide - inventory-bot

All kod är klar och pushad! Nu behöver vi bara aktivera repot i Woodpecker och kopiera GitOps-manifests.

## ✅ Status Right Now

- ✅ Kod pushad till GitHub: https://github.com/manpro/infra-doc
- ✅ .woodpecker.yml konfigurerad (matchar analogier)
- ✅ GitOps manifests klara i `gitops/` mappen
- ⏳ Behöver aktiveras i Woodpecker
- ⏳ Behöver kopieras till k8s-gitops repo

---

## 📋 Steg 1: Pusha till Gitea (för Woodpecker)

```bash
cd /home/micke/documents/infra-doc

# Pusha till Gitea (använd gitea-admin token)
git push gitea main
```

Om du inte har credentials än:
```bash
# Hämta från Vault eller logga in manuellt
git push http://gitea-admin:YOUR_TOKEN@172.16.16.161:31000/gitea-admin/inventory-bot.git main
```

---

## 📋 Steg 2: Aktivera i Woodpecker

### Alternativ A: Via Woodpecker GUI (Enklast)

1. **Öppna Woodpecker UI**
   - URL: `http://woodpecker.yourdomain.com` (eller din Woodpecker URL)
   - Logga in

2. **Aktivera Repository**
   - Gå till "Repositories"
   - Klicka på "+" för att aktivera nytt repo
   - Sök efter "inventory-bot"
   - Klicka "Enable"

3. **Secrets finns redan!**
   - Secrets `gitea_user` och `gitea_password` är globala
   - De reuseas från analogier
   - Inget behöver skapas!

### Alternativ B: Via Woodpecker API

Om du vill automatisera via API:

```bash
# 1. Hämta Woodpecker API token från Vault eller generera ny
export WOODPECKER_TOKEN="your-api-token"
export WOODPECKER_URL="http://woodpecker.yourdomain.com"

# 2. Aktivera repot
curl -X POST "${WOODPECKER_URL}/api/repos/gitea-admin/inventory-bot" \
  -H "Authorization: Bearer ${WOODPECKER_TOKEN}"

# 3. Triggera första bygget (optional)
curl -X POST "${WOODPECKER_URL}/api/repos/gitea-admin/inventory-bot/pipelines" \
  -H "Authorization: Bearer ${WOODPECKER_TOKEN}" \
  -d '{"branch":"main","event":"push"}'
```

### Alternativ C: Via Playwright (om GUI-automation behövs)

```bash
# Starta Playwright container
docker run -it --rm \
  -v $(pwd):/work \
  mcr.microsoft.com/playwright:latest \
  /bin/bash

# Inuti containern, skapa script för att aktivera repo
# (Detta är mer komplicerat - använd GUI om möjligt)
```

---

## 📋 Steg 3: Kopiera GitOps Manifests

```bash
# Gå till ditt k8s-gitops repo
cd /path/to/k8s-gitops

# Skapa mapp för inventory-bot
mkdir -p infrastructure/inventory-bot

# Kopiera alla manifests
cp /home/micke/documents/infra-doc/gitops/*.yaml infrastructure/inventory-bot/

# Verifiera
ls -la infrastructure/inventory-bot/
# Borde visa:
# 00-namespace.yaml
# 01-rbac.yaml
# 02-configmap.yaml
# 03-cronjob.yaml

# Commit och pusha
git add infrastructure/inventory-bot/
git commit -m "feat: Add inventory-bot GitOps manifests"
git push origin main
```

---

## 📋 Steg 4: Skapa Git Credentials Secret

Detta är det **enda manuella steget** som inte kan automatiseras:

```bash
# Skapa secret för bot:en att komma åt infrastructure-docs repo
kubectl create secret generic git-credentials \
  --from-literal=username=gitea-admin \
  --from-literal=password=YOUR_GITEA_TOKEN_HERE \
  --from-literal=repo_url=gitea-http.gitea.svc.cluster.local:3000/gitea-admin/infrastructure-docs.git \
  -n infrastructure-docs
```

**Hur får du Gitea token:**
1. Logga in på Gitea: http://172.16.16.161:31000
2. Settings → Applications → Generate New Token
3. Namn: "inventory-bot"
4. Permissions: Read/Write repository
5. Kopiera token och använd i kommandot ovan

---

## 📋 Steg 5: (Optional) Skapa ArgoCD Application

Om du vill att ArgoCD ska hantera deployment:en:

```yaml
# argocd-app-inventory-bot.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: inventory-bot
  namespace: gitops
spec:
  project: default
  source:
    repoURL: http://gitea-http.gitea.svc.cluster.local:3000/gitea-admin/k8s-gitops.git
    targetRevision: main
    path: infrastructure/inventory-bot
  destination:
    server: https://kubernetes.default.svc
    namespace: infrastructure-docs
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

Applicera:
```bash
kubectl apply -f argocd-app-inventory-bot.yaml
```

---

## 🧪 Steg 6: Testa Pipelinen

Trigga första bygget:

```bash
cd /home/micke/documents/infra-doc

# Gör en liten ändring
echo "# Test" >> README.md
git add README.md
git commit -m "test: Trigger first pipeline run"
git push gitea main

# Följ bygget i Woodpecker UI
# http://woodpecker.yourdomain.com
```

Vad som händer:
1. ✅ Woodpecker detekterar push
2. ✅ Bygger Docker image med Kaniko
3. ✅ Pushar till 172.16.16.161:30551/inventory-bot:xxxxx
4. ✅ Uppdaterar k8s-gitops/infrastructure/inventory-bot/03-cronjob.yaml
5. ✅ ArgoCD detekterar ändring och deployar till prod3

---

## 🔍 Verifiera Deployment

```bash
# Kolla CronJob
kubectl get cronjob -n infrastructure-docs

# Kolla senaste jobb
kubectl get jobs -n infrastructure-docs --sort-by=.metadata.creationTimestamp

# Testa manuell körning
kubectl create job --from=cronjob/auto-inventory-bot manual-test-$(date +%s) -n infrastructure-docs

# Följ logs
kubectl logs -n infrastructure-docs -l app=inventory-bot --follow
```

---

## ✅ Success Criteria

Du vet att allt fungerar när:

1. ✅ Woodpecker visar "inventory-bot" som enabled
2. ✅ Push till main triggrar bygge
3. ✅ Bygget går igenom alla steg (clone, build-push, update-gitops)
4. ✅ k8s-gitops repo uppdateras automatiskt
5. ✅ ArgoCD visar "inventory-bot" som Synced & Healthy
6. ✅ CronJob existerar i infrastructure-docs namespace
7. ✅ Manuell körning genererar Markdown-filer
8. ✅ Bot committar till infrastructure-docs repo

---

## 🐛 Troubleshooting

### Woodpecker bygget failar på "update-gitops"

**Symptom:** `fatal: could not read Username`

**Fix:** Secrets saknas eller har fel namn
```bash
# I Woodpecker UI, under Settings → Secrets:
# Lägg till:
gitea_user = gitea-admin
gitea_password = YOUR_GITEA_TOKEN
```

### ArgoCD deployar inte

**Symptom:** Manifests finns i k8s-gitops men inget händer

**Fix:** Skapa ArgoCD Application (se Steg 5)

### Bot kan inte pusha till infrastructure-docs

**Symptom:** Job loggar visar `Authentication failed`

**Fix:** Skapa `git-credentials` secret (se Steg 4)

### CronJob körs inte

**Symptom:** Inga jobb skapas

**Fix:**
1. Kolla schema: `kubectl get cronjob auto-inventory-bot -n infrastructure-docs -o yaml | grep schedule`
2. Triggera manuellt: `kubectl create job --from=cronjob/auto-inventory-bot test -n infrastructure-docs`
3. Kolla secret: `kubectl get secret git-credentials -n infrastructure-docs`

---

## 🎯 Nästa Gång (Future Updates)

När du vill uppdatera bot:en:

```bash
# 1. Editera kod
nano inventory.py

# 2. Commit och pusha
git add inventory.py
git commit -m "feat: Add new scanning feature"
git push gitea main

# 3. Done!
# Woodpecker bygger → GitOps uppdateras → ArgoCD deployar → Automatically!
```

**Ingen manuell docker build eller kubectl apply behövs längre!** 🚀

---

## 📚 Related Documentation

- **Pipeline Details:** `.woodpecker.yml` in repo
- **Deployment Flow:** `DEPLOYMENT.md`
- **GitOps Manifests:** `gitops/README.md`
- **Main README:** `README.md`
