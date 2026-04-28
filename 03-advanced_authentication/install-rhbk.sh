#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENSHIFT_DIR="${SCRIPT_DIR}/openshift"

echo "======================================"
echo "Red Hat build of Keycloak Installer"
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

# Get cluster domain
echo "Getting OpenShift cluster domain..."
CLUSTER_DOMAIN=$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}')
KEYCLOAK_HOSTNAME="keycloak.${CLUSTER_DOMAIN}"
echo -e "${GREEN}✓ Keycloak hostname: ${KEYCLOAK_HOSTNAME}${NC}"
echo ""

# Step 1: Create namespace
echo "Step 1: Creating namespace 'rhbk'..."
if oc get namespace rhbk &> /dev/null; then
    echo -e "${YELLOW}⚠ Namespace 'rhbk' already exists. Skipping.${NC}"
else
    oc create namespace rhbk
    echo -e "${GREEN}✓ Namespace 'rhbk' created${NC}"
fi
echo ""

# Step 2: Install RHBK Operator
echo "Step 2: Installing RHBK Operator..."

# Check if OperatorGroup exists
if oc get operatorgroup rhbk-operator-group -n rhbk &> /dev/null; then
    echo -e "${YELLOW}⚠ OperatorGroup already exists. Skipping.${NC}"
else
    cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: rhbk-operator-group
  namespace: rhbk
spec:
  targetNamespaces:
  - rhbk
EOF
    echo -e "${GREEN}✓ OperatorGroup created${NC}"
fi

# Check if Subscription exists
if oc get subscription rhbk-operator -n rhbk &> /dev/null; then
    echo -e "${YELLOW}⚠ Subscription already exists. Skipping.${NC}"
else
    cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: rhbk-operator
  namespace: rhbk
spec:
  channel: stable-v26.4
  installPlanApproval: Automatic
  name: rhbk-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
    echo -e "${GREEN}✓ Subscription created${NC}"
fi

# Wait for operator to be ready
echo "Waiting for RHBK Operator to be ready..."
for i in {1..60}; do
    if oc get csv -n rhbk | grep rhbk-operator | grep Succeeded &> /dev/null; then
        echo -e "${GREEN}✓ RHBK Operator is ready${NC}"
        break
    fi
    if [ $i -eq 60 ]; then
        echo -e "${RED}✗ Timeout waiting for RHBK Operator${NC}"
        exit 1
    fi
    echo -n "."
    sleep 5
done
echo ""

# Step 3: Deploy PostgreSQL
echo "Step 3: Deploying PostgreSQL..."

# Generate random password
POSTGRES_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)

# Create Secret
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: postgres-credentials
  namespace: rhbk
type: Opaque
stringData:
  username: keycloak
  password: ${POSTGRES_PASSWORD}
EOF
echo -e "${GREEN}✓ PostgreSQL credentials secret created${NC}"

# Deploy PostgreSQL
oc apply -f "${OPENSHIFT_DIR}/postgres-deployment.yaml"
echo -e "${GREEN}✓ PostgreSQL deployment created${NC}"

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to be ready..."
oc wait --for=condition=available --timeout=300s deployment/postgres -n rhbk
echo -e "${GREEN}✓ PostgreSQL is ready${NC}"
echo ""

# Step 4: Deploy Keycloak
echo "Step 4: Deploying Keycloak..."
oc apply -f "${OPENSHIFT_DIR}/keycloak-cr.yaml"
echo -e "${GREEN}✓ Keycloak CR created${NC}"

# Wait for Keycloak to be ready
echo "Waiting for Keycloak to be ready (this may take several minutes)..."
for i in {1..120}; do
    if oc get keycloak keycloak -n rhbk -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep True &> /dev/null; then
        echo -e "${GREEN}✓ Keycloak is ready${NC}"
        break
    fi
    if [ $i -eq 120 ]; then
        echo -e "${RED}✗ Timeout waiting for Keycloak${NC}"
        exit 1
    fi
    echo -n "."
    sleep 5
done
echo ""

# Step 5: Create Route
echo "Step 5: Creating Keycloak Route..."
sed "s|REPLACE_WITH_KEYCLOAK_HOSTNAME|${KEYCLOAK_HOSTNAME}|g" "${OPENSHIFT_DIR}/keycloak-route.yaml" | oc apply -f -
echo -e "${GREEN}✓ Keycloak Route created${NC}"
echo ""

# Step 6: Get admin credentials
echo "Step 6: Getting Keycloak admin credentials..."
KEYCLOAK_ADMIN_PASSWORD=$(oc get secret keycloak-initial-admin -n rhbk -o jsonpath='{.data.password}' | base64 -d)
KEYCLOAK_URL="https://${KEYCLOAK_HOSTNAME}"

echo ""
echo "======================================"
echo "Installation Complete!"
echo "======================================"
echo ""
echo -e "${GREEN}Keycloak URL:${NC} ${KEYCLOAK_URL}"
echo -e "${GREEN}Admin Username:${NC} temp-admin"
echo -e "${GREEN}Admin Password:${NC} ${KEYCLOAK_ADMIN_PASSWORD}"
echo ""
echo "To import the sample realm, run:"
echo "  ./import-realm.sh"
echo ""
echo "Environment variables saved to: keycloak-env.sh"
echo "Source it with: source keycloak-env.sh"
echo ""

# Save environment variables
cat > "${SCRIPT_DIR}/keycloak-env.sh" <<EOF
#!/bin/bash
# Keycloak environment variables
export KEYCLOAK_URL="${KEYCLOAK_URL}"
export KEYCLOAK_REALM="news-api-realm"
export KEYCLOAK_ADMIN_USER="temp-admin"
export KEYCLOAK_ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD}"
export KUADRANT_ZONE_ROOT_DOMAIN="${CLUSTER_DOMAIN}"
export KUADRANT_DEVELOPER_NS="news-api"
export KUADRANT_GATEWAY_NAME="external"
EOF

chmod +x "${SCRIPT_DIR}/keycloak-env.sh"
echo -e "${GREEN}✓ Environment file created: keycloak-env.sh${NC}"
