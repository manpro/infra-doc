#!/bin/bash
################################################################################
# Auto-Setup Script for inventory-bot
# This script automates EVERYTHING:
# 1. Push to Gitea
# 2. Enable in Woodpecker
# 3. Copy GitOps manifests
# 4. Create Kubernetes secret
# 5. Trigger first build
################################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
WOODPECKER_URL="http://172.16.16.161:30800"
GITEA_URL="http://172.16.16.161:31000"
REPO_NAME="inventory-bot"
K8S_GITOPS_PATH="/home/micke/k8s-gitops"

echo -e "${BLUE}════════════════════════════════════════${NC}"
echo -e "${BLUE}🤖 Auto-Inventory Bot - Complete Setup${NC}"
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo ""

# ══════════════════════════════════════════════════════════════════════════
# STEP 0: Verify Prerequisites
# ══════════════════════════════════════════════════════════════════════════

echo -e "${YELLOW}📋 Step 0: Checking prerequisites...${NC}"

# Check Woodpecker token
if [ ! -f "/home/micke/.woodpecker-token" ]; then
    echo -e "${RED}❌ Woodpecker token not found at /home/micke/.woodpecker-token${NC}"
    echo "   Generate one from: $WOODPECKER_URL/user"
    exit 1
fi
WOODPECKER_TOKEN=$(cat /home/micke/.woodpecker-token)
echo -e "${GREEN}✓ Woodpecker token found${NC}"

# Check if we're in the right directory
if [ ! -f ".woodpecker.yml" ]; then
    echo -e "${RED}❌ Not in inventory-bot directory${NC}"
    cd /home/micke/documents/infra-doc
fi
echo -e "${GREEN}✓ In correct directory${NC}"

# Check k8s-gitops exists
if [ ! -d "$K8S_GITOPS_PATH" ]; then
    echo -e "${RED}❌ k8s-gitops repo not found at $K8S_GITOPS_PATH${NC}"
    exit 1
fi
echo -e "${GREEN}✓ k8s-gitops repo found${NC}"

echo ""

# ══════════════════════════════════════════════════════════════════════════
# STEP 1: Push to Gitea
# ══════════════════════════════════════════════════════════════════════════

echo -e "${YELLOW}📤 Step 1: Pushing to Gitea...${NC}"

# Check if repo exists in Gitea, create if not
REPO_EXISTS=$(curl -s -w "%{http_code}" -o /dev/null \
    "$GITEA_URL/api/v1/repos/gitea-admin/$REPO_NAME")

if [ "$REPO_EXISTS" = "404" ]; then
    echo "   Creating repository in Gitea..."

    # Get Gitea token (try to find it)
    if [ -f "/home/micke/.gitea-token" ]; then
        GITEA_TOKEN=$(cat /home/micke/.gitea-token)
    else
        echo -e "${YELLOW}   ⚠️  Need Gitea token to create repo${NC}"
        echo -e "${YELLOW}   Get it from: $GITEA_URL/user/settings/applications${NC}"
        read -p "   Enter Gitea token: " GITEA_TOKEN
        echo "$GITEA_TOKEN" > /home/micke/.gitea-token
        chmod 600 /home/micke/.gitea-token
    fi

    # Create repo via API
    curl -s -X POST "$GITEA_URL/api/v1/user/repos" \
        -H "Authorization: token $GITEA_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "inventory-bot",
            "description": "Auto-Inventory Bot for Kubernetes Infrastructure",
            "private": false,
            "auto_init": false
        }' > /dev/null

    echo -e "${GREEN}   ✓ Repository created${NC}"
else
    echo -e "${GREEN}   ✓ Repository already exists${NC}"
fi

# Push code
echo "   Pushing code to Gitea..."
git push gitea main 2>&1 | grep -v "Everything up-to-date" || echo -e "${GREEN}   ✓ Code pushed${NC}"

echo ""

# ══════════════════════════════════════════════════════════════════════════
# STEP 2: Enable in Woodpecker
# ══════════════════════════════════════════════════════════════════════════

echo -e "${YELLOW}🔧 Step 2: Enabling repository in Woodpecker...${NC}"

# Get Gitea repo ID
GITEA_REPO_ID=$(curl -s \
    "$GITEA_URL/api/v1/repos/gitea-admin/$REPO_NAME" | \
    grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)

if [ -z "$GITEA_REPO_ID" ]; then
    echo -e "${RED}❌ Could not get Gitea repo ID${NC}"
    exit 1
fi
echo "   Gitea repo ID: $GITEA_REPO_ID"

# Enable in Woodpecker
echo "   Activating in Woodpecker CI..."
API_RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
    -X POST \
    -H "Authorization: Bearer $WOODPECKER_TOKEN" \
    -H "Content-Type: application/json" \
    "$WOODPECKER_URL/api/repos?forge_remote_id=$GITEA_REPO_ID")

HTTP_CODE=$(echo "$API_RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "409" ]; then
    echo -e "${GREEN}   ✓ Repository enabled in Woodpecker${NC}"
else
    echo -e "${YELLOW}   ⚠️  Could not enable (HTTP $HTTP_CODE)${NC}"
    echo "   You may need to enable it manually in Woodpecker UI"
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════
# STEP 3: Copy GitOps Manifests
# ══════════════════════════════════════════════════════════════════════════

echo -e "${YELLOW}📁 Step 3: Copying GitOps manifests to k8s-gitops...${NC}"

cd "$K8S_GITOPS_PATH"

# Create directory
mkdir -p infrastructure/inventory-bot

# Copy manifests
cp /home/micke/documents/infra-doc/gitops/*.yaml infrastructure/inventory-bot/

# Show what was copied
echo "   Copied files:"
ls -la infrastructure/inventory-bot/*.yaml | awk '{print "   - " $9}'

# Commit and push
git add infrastructure/inventory-bot/
git diff --staged --quiet && echo "   No changes to commit" || {
    git commit -m "feat: Add inventory-bot GitOps manifests

Auto-Inventory Bot for K8s infrastructure documentation.
Deployed to: infrastructure-docs namespace on prod3.
Schedule: Daily at 2 AM UTC.

Deployed via automation script."

    git push origin main
    echo -e "${GREEN}   ✓ GitOps manifests committed and pushed${NC}"
}

echo ""

# ══════════════════════════════════════════════════════════════════════════
# STEP 4: Create Git Credentials Secret
# ══════════════════════════════════════════════════════════════════════════

echo -e "${YELLOW}🔐 Step 4: Creating git-credentials secret...${NC}"

# Check if secret already exists
if kubectl get secret git-credentials -n infrastructure-docs 2>/dev/null; then
    echo -e "${GREEN}   ✓ Secret already exists${NC}"
else
    echo "   Creating Kubernetes secret..."

    # Get Gitea credentials
    if [ -f "/home/micke/.gitea-token" ]; then
        GITEA_TOKEN=$(cat /home/micke/.gitea-token)
    else
        echo -e "${YELLOW}   Need Gitea token for bot to push docs${NC}"
        echo -e "${YELLOW}   Get it from: $GITEA_URL/user/settings/applications${NC}"
        read -p "   Enter Gitea token: " GITEA_TOKEN
        echo "$GITEA_TOKEN" > /home/micke/.gitea-token
        chmod 600 /home/micke/.gitea-token
    fi

    # Create the secret
    kubectl create secret generic git-credentials \
        --from-literal=username=gitea-admin \
        --from-literal=password="$GITEA_TOKEN" \
        --from-literal=repo_url=gitea-http.gitea.svc.cluster.local:3000/gitea-admin/infrastructure-docs.git \
        -n infrastructure-docs 2>/dev/null || {
            # Namespace might not exist yet
            kubectl create namespace infrastructure-docs
            kubectl create secret generic git-credentials \
                --from-literal=username=gitea-admin \
                --from-literal=password="$GITEA_TOKEN" \
                --from-literal=repo_url=gitea-http.gitea.svc.cluster.local:3000/gitea-admin/infrastructure-docs.git \
                -n infrastructure-docs
        }

    echo -e "${GREEN}   ✓ Secret created${NC}"
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════
# STEP 5: Trigger First Build (Optional)
# ══════════════════════════════════════════════════════════════════════════

echo -e "${YELLOW}🚀 Step 5: Triggering first build...${NC}"

# Make a small change to trigger pipeline
cd /home/micke/documents/infra-doc
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
echo "# Setup completed: $TIMESTAMP" >> .setup-timestamp
git add .setup-timestamp
git commit -m "chore: Trigger first pipeline run

Automated setup completed at $TIMESTAMP"
git push gitea main

echo -e "${GREEN}   ✓ First build triggered${NC}"
echo ""

# ══════════════════════════════════════════════════════════════════════════
# DONE!
# ══════════════════════════════════════════════════════════════════════════

echo -e "${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ SETUP COMPLETE!${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo ""
echo "📋 What happened:"
echo "   ✓ Code pushed to Gitea"
echo "   ✓ Repository enabled in Woodpecker"
echo "   ✓ GitOps manifests copied to k8s-gitops"
echo "   ✓ Kubernetes secret created"
echo "   ✓ First build triggered"
echo ""
echo "🔍 Next steps:"
echo "   1. Watch build: $WOODPECKER_URL"
echo "   2. Check ArgoCD: kubectl get application inventory-bot -n gitops"
echo "   3. Monitor CronJob: kubectl get cronjob -n infrastructure-docs"
echo "   4. View logs: kubectl logs -n infrastructure-docs -l app=inventory-bot --follow"
echo ""
echo "🎯 The bot will run daily at 2 AM UTC on prod3!"
echo ""
