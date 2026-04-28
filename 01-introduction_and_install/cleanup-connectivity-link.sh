#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "======================================"
echo "Red Hat Connectivity Link Cleanup"
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
if ! oc get namespace kuadrant-system &> /dev/null; then
    echo -e "${YELLOW}⚠ Namespace 'kuadrant-system' does not exist. Nothing to clean up.${NC}"
    exit 0
fi

echo -e "${YELLOW}WARNING: This will delete the following resources:${NC}"
echo "  - Kuadrant CR and all managed resources"
echo "  - GatewayClass 'istio'"
echo "  - Red Hat Connectivity Link Operator"
echo "  - Authorino Operator"
echo "  - DNS Operator"
echo "  - Limitador Operator"
echo "  - Namespace 'kuadrant-system'"
echo ""
echo -e "${YELLOW}This may also affect resources in other namespaces:${NC}"
echo "  - Gateways managed by Connectivity Link"
echo "  - HTTPRoutes with applied Policies"
echo "  - AuthPolicy, RateLimitPolicy, DNSPolicy, TLSPolicy resources"
echo ""
read -p "Are you sure you want to continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cleanup cancelled."
    exit 0
fi
echo ""

# Step 1: Delete Kuadrant CR
echo "Step 1: Deleting Kuadrant CR..."
if oc get kuadrant kuadrant -n kuadrant-system &> /dev/null; then
    oc delete kuadrant kuadrant -n kuadrant-system
    echo -e "${GREEN}✓ Kuadrant CR deleted${NC}"
else
    echo -e "${YELLOW}⚠ Kuadrant CR not found. Skipping.${NC}"
fi
echo ""

# Step 2: Delete GatewayClass
echo "Step 2: Deleting GatewayClass..."
if oc get gatewayclass istio &> /dev/null; then
    oc delete gatewayclass istio
    echo -e "${GREEN}✓ GatewayClass deleted${NC}"
else
    echo -e "${YELLOW}⚠ GatewayClass not found. Skipping.${NC}"
fi
echo ""

# Step 3: Wait for Kuadrant resources to be deleted
echo "Step 3: Waiting for Kuadrant resources to be deleted..."
for i in {1..30}; do
    if ! oc get kuadrant kuadrant -n kuadrant-system &> /dev/null; then
        break
    fi
    echo -n "."
    sleep 2
done
echo ""
echo -e "${GREEN}✓ Kuadrant resources deleted${NC}"
echo ""

# Step 4: Delete Operator Subscription
echo "Step 4: Deleting Red Hat Connectivity Link Operator Subscription..."
if oc get subscription rhcl-operator -n kuadrant-system &> /dev/null; then
    oc delete subscription rhcl-operator -n kuadrant-system
    echo -e "${GREEN}✓ Subscription deleted${NC}"
else
    echo -e "${YELLOW}⚠ Subscription not found. Skipping.${NC}"
fi
echo ""

# Step 5: Delete CSV
echo "Step 5: Deleting ClusterServiceVersion..."
CSV_NAME=$(oc get csv -n kuadrant-system | grep rhcl-operator | awk '{print $1}' || true)
if [ ! -z "$CSV_NAME" ]; then
    oc delete csv "$CSV_NAME" -n kuadrant-system
    echo -e "${GREEN}✓ ClusterServiceVersion deleted${NC}"
else
    echo -e "${YELLOW}⚠ CSV not found. Skipping.${NC}"
fi
echo ""

# Step 6: Delete dependent Operator CSVs
echo "Step 6: Deleting dependent Operator CSVs..."
DEPENDENT_CSVS=$(oc get csv -n kuadrant-system --no-headers | grep -E 'authorino-operator|dns-operator|limitador-operator' | awk '{print $1}' || true)
if [ ! -z "$DEPENDENT_CSVS" ]; then
    for CSV in $DEPENDENT_CSVS; do
        oc delete csv "$CSV" -n kuadrant-system
        echo -e "${GREEN}✓ CSV '$CSV' deleted${NC}"
    done
else
    echo -e "${YELLOW}⚠ No dependent CSVs found. Skipping.${NC}"
fi
echo ""

# Step 7: Delete OperatorGroup
echo "Step 7: Deleting OperatorGroup..."
if oc get operatorgroup kuadrant -n kuadrant-system &> /dev/null; then
    oc delete operatorgroup kuadrant -n kuadrant-system
    echo -e "${GREEN}✓ OperatorGroup deleted${NC}"
else
    echo -e "${YELLOW}⚠ OperatorGroup not found. Skipping.${NC}"
fi
echo ""

# Step 8: Delete namespace
echo "Step 8: Deleting namespace 'kuadrant-system'..."
oc delete namespace kuadrant-system
echo -e "${GREEN}✓ Namespace deleted${NC}"
echo ""

echo "======================================"
echo "Cleanup Complete!"
echo "======================================"
echo ""
echo "All Red Hat Connectivity Link resources have been removed."
echo ""
echo -e "${YELLOW}Note:${NC} Resources in other namespaces (Gateways, HTTPRoutes, Policies) may need to be cleaned up manually."
echo ""
echo "To reinstall, run: ./install-connectivity-link.sh"
echo ""
