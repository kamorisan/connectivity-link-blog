#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "======================================"
echo "Prerequisites Cleanup"
echo "Red Hat Connectivity Link"
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

echo -e "${YELLOW}WARNING: This will delete the following resources:${NC}"
echo "  - OpenShift Service Mesh 3 (Istio CR and Operator)"
echo "  - Namespace 'istio-system'"
echo ""
echo -e "${YELLOW}This may affect other components that depend on Service Mesh.${NC}"
echo ""
read -p "Are you sure you want to continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cleanup cancelled."
    exit 0
fi
echo ""

# ============================================
# Delete OpenShift Service Mesh 3
# ============================================

echo "======================================"
echo "OpenShift Service Mesh 3"
echo "======================================"
echo ""

# Step 1: Delete Istio CR
echo "Step 1: Deleting Istio CR..."
if oc get namespace istio-system &> /dev/null; then
    if oc get istio default -n istio-system &> /dev/null; then
        oc delete istio default -n istio-system
        echo -e "${GREEN}✓ Istio CR deleted${NC}"
    else
        echo -e "${YELLOW}⚠ Istio CR not found. Skipping.${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Namespace 'istio-system' not found. Skipping.${NC}"
fi
echo ""

# Step 2: Wait for Istio resources to be deleted
if oc get namespace istio-system &> /dev/null; then
    echo "Step 2: Waiting for Istio resources to be deleted..."
    for i in {1..30}; do
        if ! oc get istio default -n istio-system &> /dev/null; then
            break
        fi
        echo -n "."
        sleep 2
    done
    echo ""
    echo -e "${GREEN}✓ Istio resources deleted${NC}"
    echo ""
fi

# Step 3: Delete Service Mesh Operator Subscription
if oc get namespace istio-system &> /dev/null; then
    echo "Step 3: Deleting OpenShift Service Mesh Operator Subscription..."
    if oc get subscription servicemeshoperator3 -n istio-system &> /dev/null; then
        oc delete subscription servicemeshoperator3 -n istio-system
        echo -e "${GREEN}✓ Subscription deleted${NC}"
    else
        echo -e "${YELLOW}⚠ Subscription not found. Skipping.${NC}"
    fi

    # Delete CSV
    CSV_NAME=$(oc get csv -n istio-system 2>/dev/null | grep servicemeshoperator3 | awk '{print $1}' || true)
    if [ ! -z "$CSV_NAME" ]; then
        oc delete csv "$CSV_NAME" -n istio-system
        echo -e "${GREEN}✓ ClusterServiceVersion deleted${NC}"
    fi

    # Delete OperatorGroup
    if oc get operatorgroup istio-system -n istio-system &> /dev/null; then
        oc delete operatorgroup istio-system -n istio-system
        echo -e "${GREEN}✓ OperatorGroup deleted${NC}"
    fi
    echo ""
fi

# Step 4: Delete istio-system namespace
if oc get namespace istio-system &> /dev/null; then
    echo "Step 4: Deleting namespace 'istio-system'..."
    oc delete namespace istio-system
    echo -e "${GREEN}✓ Namespace 'istio-system' deleted${NC}"
    echo ""
fi

echo "======================================"
echo "Cleanup Complete!"
echo "======================================"
echo ""
echo "All prerequisite resources have been removed."
echo ""
echo "To reinstall, run: ./install-prerequisites.sh"
echo ""
