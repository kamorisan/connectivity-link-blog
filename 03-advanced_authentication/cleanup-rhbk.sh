#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "======================================"
echo "Red Hat build of Keycloak Cleanup"
echo "======================================"
echo ""

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if oc is installed
if ! command -v oc &> /dev/null; then
    echo -e "${RED}✗ oc command not found. Please install OpenShift CLI.${NC}"
    exit 1
fi

# Check if logged in to OpenShift
if ! oc whoami &> /dev/null; then
    echo -e "${RED}✗ Not logged in to OpenShift. Please run 'oc login' first.${NC}"
    exit 1
fi

# Check if namespace exists
if ! oc get namespace rhbk &> /dev/null; then
    echo -e "${YELLOW}⚠ Namespace 'rhbk' does not exist. Nothing to clean up.${NC}"
    exit 0
fi

echo -e "${YELLOW}WARNING: This will delete the following resources:${NC}"
echo "  - Keycloak instance and all realms"
echo "  - PostgreSQL database (all data will be lost)"
echo "  - RHBK Operator subscription"
echo "  - Namespace 'rhbk'"
echo ""
read -p "Are you sure you want to continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cleanup cancelled."
    exit 0
fi
echo ""

# Step 1: Delete Keycloak CR
echo "Step 1: Deleting Keycloak CR..."
if oc get keycloak keycloak -n rhbk &> /dev/null; then
    oc delete keycloak keycloak -n rhbk
    echo -e "${GREEN}✓ Keycloak CR deleted${NC}"
else
    echo -e "${YELLOW}⚠ Keycloak CR not found. Skipping.${NC}"
fi
echo ""

# Step 2: Delete Route
echo "Step 2: Deleting Keycloak Route..."
if oc get route keycloak -n rhbk &> /dev/null; then
    oc delete route keycloak -n rhbk
    echo -e "${GREEN}✓ Keycloak Route deleted${NC}"
else
    echo -e "${YELLOW}⚠ Keycloak Route not found. Skipping.${NC}"
fi
echo ""

# Step 3: Delete PostgreSQL
echo "Step 3: Deleting PostgreSQL..."
if oc get deployment postgres -n rhbk &> /dev/null; then
    oc delete deployment postgres -n rhbk
    echo -e "${GREEN}✓ PostgreSQL Deployment deleted${NC}"
else
    echo -e "${YELLOW}⚠ PostgreSQL Deployment not found. Skipping.${NC}"
fi

if oc get service postgres -n rhbk &> /dev/null; then
    oc delete service postgres -n rhbk
    echo -e "${GREEN}✓ PostgreSQL Service deleted${NC}"
fi

if oc get pvc postgres-pvc -n rhbk &> /dev/null; then
    oc delete pvc postgres-pvc -n rhbk
    echo -e "${GREEN}✓ PostgreSQL PVC deleted${NC}"
fi

if oc get secret postgres-credentials -n rhbk &> /dev/null; then
    oc delete secret postgres-credentials -n rhbk
    echo -e "${GREEN}✓ PostgreSQL credentials deleted${NC}"
fi
echo ""

# Step 4: Wait for Keycloak resources to be deleted
echo "Step 4: Waiting for Keycloak resources to be deleted..."
for i in {1..30}; do
    if ! oc get keycloak keycloak -n rhbk &> /dev/null; then
        break
    fi
    echo -n "."
    sleep 2
done
echo ""
echo -e "${GREEN}✓ Keycloak resources deleted${NC}"
echo ""

# Step 5: Delete Operator Subscription
echo "Step 5: Deleting RHBK Operator Subscription..."
if oc get subscription rhbk-operator -n rhbk &> /dev/null; then
    oc delete subscription rhbk-operator -n rhbk
    echo -e "${GREEN}✓ Subscription deleted${NC}"
else
    echo -e "${YELLOW}⚠ Subscription not found. Skipping.${NC}"
fi

# Delete CSV
CSV_NAME=$(oc get csv -n rhbk | grep rhbk-operator | awk '{print $1}' || true)
if [ ! -z "$CSV_NAME" ]; then
    oc delete csv "$CSV_NAME" -n rhbk
    echo -e "${GREEN}✓ ClusterServiceVersion deleted${NC}"
fi
echo ""

# Step 6: Delete OperatorGroup
echo "Step 6: Deleting OperatorGroup..."
if oc get operatorgroup rhbk-operator-group -n rhbk &> /dev/null; then
    oc delete operatorgroup rhbk-operator-group -n rhbk
    echo -e "${GREEN}✓ OperatorGroup deleted${NC}"
else
    echo -e "${YELLOW}⚠ OperatorGroup not found. Skipping.${NC}"
fi
echo ""

# Step 7: Delete namespace
echo "Step 7: Deleting namespace 'rhbk'..."
oc delete namespace rhbk
echo -e "${GREEN}✓ Namespace deleted${NC}"
echo ""

# Step 8: Delete environment file
echo "Step 8: Cleaning up environment file..."
if [ -f "${SCRIPT_DIR}/keycloak-env.sh" ]; then
    rm "${SCRIPT_DIR}/keycloak-env.sh"
    echo -e "${GREEN}✓ Environment file deleted${NC}"
fi
echo ""

echo "======================================"
echo "Cleanup Complete!"
echo "======================================"
echo ""
echo "All RHBK resources have been removed."
echo "To reinstall, run: ./install-rhbk.sh"
echo ""
