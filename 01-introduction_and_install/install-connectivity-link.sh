#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "======================================"
echo "Red Hat Connectivity Link Installer"
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

# Step 1: Create namespace
echo "Step 1: Creating namespace 'kuadrant-system'..."
if oc get namespace kuadrant-system &> /dev/null; then
    echo -e "${YELLOW}⚠ Namespace 'kuadrant-system' already exists. Skipping creation.${NC}"
else
    oc create namespace kuadrant-system
    echo -e "${GREEN}✓ Namespace 'kuadrant-system' created${NC}"
fi
echo ""

# Step 2: Install Red Hat Connectivity Link Operator
echo "Step 2: Installing Red Hat Connectivity Link Operator..."

# Create OperatorGroup
if oc get operatorgroup kuadrant -n kuadrant-system &> /dev/null; then
    echo -e "${YELLOW}⚠ OperatorGroup 'kuadrant' already exists. Skipping.${NC}"
else
    oc apply -f - <<EOF
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: kuadrant
  namespace: kuadrant-system
spec: {}
EOF
    echo -e "${GREEN}✓ OperatorGroup created${NC}"
fi

# Create Subscription
if oc get subscription rhcl-operator -n kuadrant-system &> /dev/null; then
    echo -e "${YELLOW}⚠ Subscription 'rhcl-operator' already exists. Skipping.${NC}"
else
    oc apply -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: rhcl-operator
  namespace: kuadrant-system
spec:
  channel: stable
  installPlanApproval: Automatic
  name: rhcl-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
    echo -e "${GREEN}✓ Subscription created${NC}"
fi

# Wait for Operator to be ready
echo "Waiting for Red Hat Connectivity Link Operator to be ready..."
for i in {1..30}; do
    CSV_NAME=$(oc get csv -n kuadrant-system 2>/dev/null | grep rhcl-operator | awk '{print $1}' || echo "")
    if [ ! -z "$CSV_NAME" ]; then
        CSV_PHASE=$(oc get csv "$CSV_NAME" -n kuadrant-system -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        if [ "$CSV_PHASE" == "Succeeded" ]; then
            break
        fi
    fi
    echo -n "."
    sleep 10
done
echo ""

CSV_NAME=$(oc get csv -n kuadrant-system 2>/dev/null | grep rhcl-operator | awk '{print $1}' || echo "")
if [ -z "$CSV_NAME" ]; then
    echo -e "${RED}✗ Timeout waiting for Red Hat Connectivity Link Operator${NC}"
    exit 1
fi

CSV_PHASE=$(oc get csv "$CSV_NAME" -n kuadrant-system -o jsonpath='{.status.phase}')
if [ "$CSV_PHASE" != "Succeeded" ]; then
    echo -e "${RED}✗ Red Hat Connectivity Link Operator installation failed. CSV phase: ${CSV_PHASE}${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Red Hat Connectivity Link Operator is ready${NC}"
echo ""

# Step 3: Create GatewayClass
echo "Step 3: Creating GatewayClass for Istio..."
GATEWAYCLASS_CREATED=false
if oc get gatewayclass istio &> /dev/null; then
    echo -e "${YELLOW}⚠ GatewayClass 'istio' already exists. Skipping.${NC}"
else
    oc apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: istio
spec:
  controllerName: istio.io/gateway-controller
  description: The default Istio GatewayClass
EOF
    echo -e "${GREEN}✓ GatewayClass created${NC}"
    GATEWAYCLASS_CREATED=true
fi
echo ""

# Step 3.5: Restart Kuadrant Operator if GatewayClass was just created
if [ "$GATEWAYCLASS_CREATED" = true ]; then
    echo "Step 3.5: Restarting Kuadrant Operator to recognize GatewayClass..."
    oc delete pod -n kuadrant-system -l app.kubernetes.io/name=kuadrant-operator 2>/dev/null || true
    echo "Waiting for Kuadrant Operator to restart..."
    sleep 10
    oc wait --for=condition=ready pod -n kuadrant-system -l app.kubernetes.io/name=kuadrant-operator --timeout=60s 2>/dev/null || true
    echo -e "${GREEN}✓ Kuadrant Operator restarted${NC}"
    echo ""
fi

# Step 4: Create Kuadrant CR
echo "Step 4: Creating Kuadrant custom resource..."
KUADRANT_EXISTS=false
if oc get kuadrant kuadrant -n kuadrant-system &> /dev/null; then
    echo -e "${YELLOW}⚠ Kuadrant CR 'kuadrant' already exists.${NC}"
    # Check if it's in error state due to missing GatewayClass
    KUADRANT_READY=$(oc get kuadrant kuadrant -n kuadrant-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
    if [ "$KUADRANT_READY" != "True" ]; then
        echo "Deleting existing Kuadrant CR to recreate with GatewayClass..."
        oc delete kuadrant kuadrant -n kuadrant-system
        sleep 5
    else
        KUADRANT_EXISTS=true
        echo -e "${GREEN}✓ Kuadrant CR is already ready${NC}"
    fi
fi

if [ "$KUADRANT_EXISTS" = false ]; then
    oc apply -f - <<EOF
apiVersion: kuadrant.io/v1beta1
kind: Kuadrant
metadata:
  name: kuadrant
  namespace: kuadrant-system
EOF
    echo -e "${GREEN}✓ Kuadrant CR created${NC}"
fi
echo ""

# Step 5: Wait for Kuadrant CR to be ready
if [ "$KUADRANT_EXISTS" = false ]; then
    echo "Step 5: Waiting for Kuadrant to be ready (this may take several minutes)..."
    oc wait kuadrant/kuadrant \
      --for="condition=Ready=true" \
      -n kuadrant-system \
      --timeout=300s
    echo -e "${GREEN}✓ Kuadrant is ready${NC}"
else
    echo "Step 5: Kuadrant is already ready, skipping wait."
fi
echo ""

# Step 6: Verify installation
echo "Step 6: Verifying installation..."
echo ""
echo "Installed Operators:"
oc get csv -n kuadrant-system --no-headers | awk '{print "  - " $1}'
echo ""
echo "Running Pods:"
oc get pods -n kuadrant-system --no-headers | awk '{print "  - " $1 " (" $3 ")"}'
echo ""

echo "======================================"
echo "Installation Complete!"
echo "======================================"
echo ""
echo -e "${GREEN}Red Hat Connectivity Link has been successfully installed.${NC}"
echo ""
echo "Key resources created:"
echo "  - Namespace: kuadrant-system"
echo "  - Kuadrant CR: kuadrant"
echo ""
echo "Installed Operators:"
echo "  - Red Hat Connectivity Link Operator"
echo "  - Authorino Operator"
echo "  - DNS Operator"
echo "  - Limitador Operator"
echo ""
echo "Next steps:"
echo "  1. Enable Console Plugin (optional):"
echo "     - Navigate to Home > Overview in OpenShift Web Console"
echo "     - Enable 'kuadrant-console-plugin' in Dynamic Plugins"
echo "     - Refresh your browser"
echo ""
echo "  2. Create a Gateway:"
echo "     - See the blog article or GitHub README for examples"
echo ""
echo "For more information:"
echo "  - Official Documentation: https://access.redhat.com/documentation/ja-jp/red_hat_connectivity_link/"
echo "  - Blog Article Series: https://developers.redhat.com/"
echo ""
