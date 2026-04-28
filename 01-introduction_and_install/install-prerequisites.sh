#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "======================================"
echo "Prerequisites Installer"
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

echo -e "${GREEN}✓ OpenShift CLI ready${NC}"
echo ""

# Check OpenShift version
OCP_VERSION=$(oc version -o json | jq -r '.openshiftVersion' | cut -d. -f1,2)
REQUIRED_VERSION="4.19"

if [ "$(printf '%s\n' "$REQUIRED_VERSION" "$OCP_VERSION" | sort -V | head -n1)" != "$REQUIRED_VERSION" ]; then
    echo -e "${RED}✗ OpenShift version $OCP_VERSION is below the required version $REQUIRED_VERSION${NC}"
    exit 1
fi

echo -e "${GREEN}✓ OpenShift version: ${OCP_VERSION}${NC}"
echo ""

echo "This script will install the following prerequisites:"
echo "  1. OpenShift Service Mesh 3 (v3.2+)"
echo ""

# ============================================
# Install OpenShift Service Mesh 3
# ============================================

echo "======================================"
echo "OpenShift Service Mesh 3"
echo "======================================"
echo ""

# Step 1: Create namespace for Istio
echo "Step 3: Creating namespace 'istio-system'..."
if oc get namespace istio-system &> /dev/null; then
    echo -e "${YELLOW}⚠ Namespace 'istio-system' already exists. Skipping.${NC}"
else
    oc create namespace istio-system
    echo -e "${GREEN}✓ Namespace 'istio-system' created${NC}"
fi
echo ""

# Step 2: Install OpenShift Service Mesh Operator (Sailmaker)
echo "Step 2: Installing OpenShift Service Mesh Operator..."

# Create OperatorGroup
if oc get operatorgroup istio-system -n istio-system &> /dev/null; then
    echo -e "${YELLOW}⚠ OperatorGroup already exists. Skipping.${NC}"
else
    oc apply -f - <<EOF
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: istio-system
  namespace: istio-system
spec: {}
EOF
    echo -e "${GREEN}✓ OperatorGroup created${NC}"
fi

# Create Subscription
if oc get subscription servicemeshoperator3 -n istio-system &> /dev/null; then
    echo -e "${YELLOW}⚠ Subscription already exists. Skipping.${NC}"
else
    oc apply -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: servicemeshoperator3
  namespace: istio-system
spec:
  channel: stable
  installPlanApproval: Automatic
  name: servicemeshoperator3
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
    echo -e "${GREEN}✓ Subscription created${NC}"
fi

# Wait for Service Mesh Operator to be ready
echo "Waiting for OpenShift Service Mesh Operator to be ready..."
for i in {1..30}; do
    CSV_NAME=$(oc get csv -n istio-system 2>/dev/null | grep servicemeshoperator3 | awk '{print $1}' || echo "")
    if [ ! -z "$CSV_NAME" ]; then
        CSV_PHASE=$(oc get csv "$CSV_NAME" -n istio-system -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        if [ "$CSV_PHASE" == "Succeeded" ]; then
            break
        fi
    fi
    echo -n "."
    sleep 10
done
echo ""

CSV_NAME=$(oc get csv -n istio-system 2>/dev/null | grep servicemeshoperator3 | awk '{print $1}' || echo "")
if [ -z "$CSV_NAME" ]; then
    echo -e "${RED}✗ Timeout waiting for OpenShift Service Mesh Operator${NC}"
    exit 1
fi

CSV_PHASE=$(oc get csv "$CSV_NAME" -n istio-system -o jsonpath='{.status.phase}')
if [ "$CSV_PHASE" != "Succeeded" ]; then
    echo -e "${RED}✗ OpenShift Service Mesh Operator installation failed. CSV phase: ${CSV_PHASE}${NC}"
    exit 1
fi

echo -e "${GREEN}✓ OpenShift Service Mesh Operator is ready${NC}"
echo ""

# Step 3: Create Istio CR
echo "Step 3: Creating Istio custom resource..."
if oc get istio default -n istio-system &> /dev/null; then
    echo -e "${YELLOW}⚠ Istio CR 'default' already exists. Skipping.${NC}"
else
    oc apply -f - <<EOF
apiVersion: sailoperator.io/v1
kind: Istio
metadata:
  name: default
  namespace: istio-system
spec:
  namespace: istio-system
  updateStrategy:
    type: InPlace
  version: v1.28-latest
EOF
    echo -e "${GREEN}✓ Istio CR created${NC}"
fi
echo ""

# Step 4: Wait for Istio to be ready
#echo "Step 4: Waiting for Istio to be ready (this may take several minutes)..."
#for i in {1..60}; do
#    ISTIO_READY=$(oc get istio default -n istio-system -o jsonpath='{.status.state}' 2>/dev/null || echo "")
#    if [ "$ISTIO_READY" == "Healthy" ]; then
#        break
#    fi
#    echo -n "."
#    sleep 5
#done
#echo ""
#
#ISTIO_STATE=$(oc get istio default -n istio-system -o jsonpath='{.status.state}' 2>/dev/null || echo "Unknown")
#if [ "$ISTIO_STATE" != "Healthy" ]; then
#    echo -e "${YELLOW}⚠ Istio state: ${ISTIO_STATE}${NC}"
#    echo -e "${YELLOW}⚠ Istio may still be initializing. Please check the status manually.${NC}"
#else
#    echo -e "${GREEN}✓ Istio is ready${NC}"
#fi
#echo ""

# ============================================
# Installation Summary
# ============================================

echo "======================================"
echo "Installation Complete!"
echo "======================================"
echo ""
echo -e "${GREEN}Prerequisites have been successfully installed.${NC}"
echo ""
echo "Installed components:"
echo ""
echo "1. OpenShift Service Mesh 3:"
oc get csv -n istio-system --no-headers | awk '{print "   - " $1 " (" $NF ")"}'
echo ""
echo "2. Running Pods:"
echo "   istio-system namespace:"
oc get pods -n istio-system --no-headers | awk '{print "     - " $1 " (" $3 ")"}'
echo ""
echo "Next step:"
echo "  Install Red Hat Connectivity Link:"
echo "    ./install-connectivity-link.sh"
echo ""
echo "For more information:"
echo "  - Service Mesh: https://docs.openshift.com/container-platform/latest/service_mesh/v3x/ossm-about.html"
echo ""
