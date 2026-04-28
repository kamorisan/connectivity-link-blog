#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENSHIFT_DIR="${SCRIPT_DIR}/openshift"
REALM_FILE="${OPENSHIFT_DIR}/realm-export.json"

echo "======================================"
echo "Keycloak Realm Importer"
echo "======================================"
echo ""

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if realm file exists
if [ ! -f "${REALM_FILE}" ]; then
    echo -e "${RED}✗ Realm file not found: ${REALM_FILE}${NC}"
    exit 1
fi

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

# Check if Keycloak is running
if ! oc get keycloak keycloak -n rhbk &> /dev/null; then
    echo -e "${RED}✗ Keycloak is not installed. Please run './install-rhbk.sh' first.${NC}"
    exit 1
fi

# Get Keycloak URL and credentials
CLUSTER_DOMAIN=$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}')
KEYCLOAK_HOSTNAME="keycloak.${CLUSTER_DOMAIN}"
KEYCLOAK_URL="https://${KEYCLOAK_HOSTNAME}"
KEYCLOAK_ADMIN_PASSWORD=$(oc get secret keycloak-initial-admin -n rhbk -o jsonpath='{.data.password}' | base64 -d)

echo -e "${GREEN}✓ Keycloak URL: ${KEYCLOAK_URL}${NC}"
echo ""

# Step 1: Copy realm file to Keycloak Pod
echo "Step 1: Copying realm file to Keycloak Pod..."
oc cp "${REALM_FILE}" rhbk/keycloak-0:/tmp/realm-export.json
echo -e "${GREEN}✓ Realm file copied${NC}"
echo ""

# Step 2: Configure kcadm.sh
echo "Step 2: Configuring kcadm.sh..."
oc exec -n rhbk keycloak-0 -- /opt/keycloak/bin/kcadm.sh config credentials \
  --server "${KEYCLOAK_URL}" \
  --realm master \
  --user admin \
  --password "${KEYCLOAK_ADMIN_PASSWORD}" \
  --config /tmp/kcadm.config
echo -e "${GREEN}✓ kcadm.sh configured${NC}"
echo ""

# Step 3: Import realm
echo "Step 3: Importing realm 'news-api-realm'..."

# Check if realm already exists
if oc exec -n rhbk keycloak-0 -- /opt/keycloak/bin/kcadm.sh get realms/news-api-realm --config /tmp/kcadm.config &> /dev/null; then
    echo -e "${YELLOW}⚠ Realm 'news-api-realm' already exists.${NC}"
    read -p "Do you want to delete and recreate it? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Deleting existing realm..."
        oc exec -n rhbk keycloak-0 -- /opt/keycloak/bin/kcadm.sh delete realms/news-api-realm --config /tmp/kcadm.config
        echo -e "${GREEN}✓ Existing realm deleted${NC}"
    else
        echo "Import cancelled."
        exit 0
    fi
fi

# Create realm from file
oc exec -n rhbk keycloak-0 -- /opt/keycloak/bin/kcadm.sh create realms -f /tmp/realm-export.json --config /tmp/kcadm.config
echo -e "${GREEN}✓ Realm 'news-api-realm' imported${NC}"
echo ""

# Step 4: Get Client Secret
echo "Step 4: Getting Client Secret for 'news-api-client'..."
CLIENT_SECRET=$(oc exec -n rhbk keycloak-0 -- /opt/keycloak/bin/kcadm.sh get clients \
  -r news-api-realm \
  -q clientId=news-api-client \
  --fields secret \
  --format csv \
  --noquotes \
  --config /tmp/kcadm.config | tail -1)

echo -e "${GREEN}✓ Client Secret: ${CLIENT_SECRET}${NC}"
echo ""

# Step 5: Verify users
echo "Step 5: Verifying imported users..."
USERS=$(oc exec -n rhbk keycloak-0 -- /opt/keycloak/bin/kcadm.sh get users \
  -r news-api-realm \
  --fields username,email \
  --format csv \
  --noquotes \
  --config /tmp/kcadm.config)

echo "Imported users:"
echo "${USERS}" | while read line; do
    if [ ! -z "$line" ]; then
        echo "  - $line"
    fi
done
echo ""

# Step 6: Update environment file
echo "Step 6: Updating environment file..."
cat >> "${SCRIPT_DIR}/keycloak-env.sh" <<EOF

# Client credentials (added by import-realm.sh)
export CLIENT_SECRET="${CLIENT_SECRET}"
EOF

echo -e "${GREEN}✓ Environment file updated${NC}"
echo ""

echo "======================================"
echo "Realm Import Complete!"
echo "======================================"
echo ""
echo "Realm Details:"
echo -e "${GREEN}  Realm Name:${NC} news-api-realm"
echo -e "${GREEN}  Client ID:${NC} news-api-client"
echo -e "${GREEN}  Client Secret:${NC} ${CLIENT_SECRET}"
echo ""
echo "Test Users:"
echo "  1. john.doe (user + premium roles)"
echo "     - Email: john.doe@example.com"
echo "     - Password: password123"
echo ""
echo "  2. admin.user (admin role)"
echo "     - Email: admin@example.com"
echo "     - Password: admin123"
echo ""
echo "  3. guest (no roles)"
echo "     - Email: guest@example.com"
echo "     - Password: guest123"
echo ""
echo "To use these credentials, source the environment file:"
echo "  source keycloak-env.sh"
echo ""
echo "To get an access token:"
echo "  curl -s -X POST \\"
echo "    \"\${KEYCLOAK_URL}/realms/\${KEYCLOAK_REALM}/protocol/openid-connect/token\" \\"
echo "    -H \"Content-Type: application/x-www-form-urlencoded\" \\"
echo "    -d \"grant_type=password\" \\"
echo "    -d \"client_id=news-api-client\" \\"
echo "    -d \"client_secret=\${CLIENT_SECRET}\" \\"
echo "    -d \"username=john.doe\" \\"
echo "    -d \"password=password123\" \\"
echo "    | jq -r '.access_token'"
echo ""
