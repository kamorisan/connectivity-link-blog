#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "======================================"
echo "Gateway and Policy Setup"
echo "Red Hat Connectivity Link - Article 2"
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

# Check for required environment variables
REQUIRED_VARS=(
    "KUADRANT_GATEWAY_NS"
    "KUADRANT_GATEWAY_NAME"
    "KUADRANT_DEVELOPER_NS"
    "KUADRANT_AWS_ACCESS_KEY_ID"
    "KUADRANT_AWS_SECRET_ACCESS_KEY"
    "KUADRANT_ZONE_ROOT_DOMAIN"
    "KUADRANT_CLUSTER_ISSUER_NAME"
    "KUADRANT_AWS_REGION"
    "KUADRANT_LETSENCRYPT_EMAIL"
)

MISSING_VARS=()
for VAR in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!VAR}" ]; then
        MISSING_VARS+=("$VAR")
    fi
done

if [ ${#MISSING_VARS[@]} -gt 0 ]; then
    echo -e "${RED}✗ Missing required environment variables:${NC}"
    for VAR in "${MISSING_VARS[@]}"; do
        echo "  - $VAR"
    done
    echo ""
    echo "Please set the following environment variables:"
    echo "  export KUADRANT_GATEWAY_NS=api-gateway"
    echo "  export KUADRANT_GATEWAY_NAME=external"
    echo "  export KUADRANT_DEVELOPER_NS=news-api"
    echo "  export KUADRANT_AWS_ACCESS_KEY_ID=<your-aws-access-key>"
    echo "  export KUADRANT_AWS_SECRET_ACCESS_KEY=<your-aws-secret-key>"
    echo "  export KUADRANT_ZONE_ROOT_DOMAIN=<your-route53-domain>"
    echo "  export KUADRANT_CLUSTER_ISSUER_NAME=letsencrypt-prod"
    echo "  export KUADRANT_AWS_REGION=<your-aws-region>"
    echo "  export KUADRANT_LETSENCRYPT_EMAIL=<your-email>"
    exit 1
fi

echo -e "${GREEN}✓ All required environment variables are set${NC}"
echo ""

# ============================================
# Step 1: Create Namespaces
# ============================================

echo "======================================"
echo "Step 1: Creating Namespaces"
echo "======================================"
echo ""

# Gateway namespace
if oc get namespace ${KUADRANT_GATEWAY_NS} &> /dev/null; then
    echo -e "${YELLOW}⚠ Namespace '${KUADRANT_GATEWAY_NS}' already exists. Skipping.${NC}"
else
    oc create namespace ${KUADRANT_GATEWAY_NS}
    echo -e "${GREEN}✓ Namespace '${KUADRANT_GATEWAY_NS}' created${NC}"
fi

# Developer namespace
if oc get namespace ${KUADRANT_DEVELOPER_NS} &> /dev/null; then
    echo -e "${YELLOW}⚠ Namespace '${KUADRANT_DEVELOPER_NS}' already exists. Skipping.${NC}"
else
    oc create namespace ${KUADRANT_DEVELOPER_NS}
    echo -e "${GREEN}✓ Namespace '${KUADRANT_DEVELOPER_NS}' created${NC}"
fi
echo ""

# ============================================
# Step 2: Deploy News API Application
# ============================================

echo "======================================"
echo "Step 2: Deploying News API Application"
echo "======================================"
echo ""

oc apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: news-api
  namespace: ${KUADRANT_DEVELOPER_NS}
  labels:
    app: news-api
spec:
  replicas: 1
  selector:
    matchLabels:
      app: news-api
  template:
    metadata:
      labels:
        app: news-api
    spec:
      containers:
      - name: news-api
        image: quay.io/kuadrant/authorino-examples:news-api
        env:
        - name: PORT
          value: "3000"
        ports:
        - containerPort: 3000
          name: http
---
apiVersion: v1
kind: Service
metadata:
  name: news-api
  namespace: ${KUADRANT_DEVELOPER_NS}
spec:
  selector:
    app: news-api
  ports:
  - name: http
    port: 80
    protocol: TCP
    targetPort: 3000
EOF

echo -e "${GREEN}✓ News API application deployed${NC}"
echo ""

# ============================================
# Step 3: Create AWS Credentials Secrets
# ============================================

echo "======================================"
echo "Step 3: Creating AWS Credentials Secrets"
echo "======================================"
echo ""

# Gateway namespace
if oc get secret aws-credentials -n ${KUADRANT_GATEWAY_NS} &> /dev/null; then
    echo -e "${YELLOW}⚠ Secret 'aws-credentials' in '${KUADRANT_GATEWAY_NS}' already exists. Skipping.${NC}"
else
    oc -n ${KUADRANT_GATEWAY_NS} create secret generic aws-credentials \
      --type=kuadrant.io/aws \
      --from-literal=AWS_ACCESS_KEY_ID=$KUADRANT_AWS_ACCESS_KEY_ID \
      --from-literal=AWS_SECRET_ACCESS_KEY=$KUADRANT_AWS_SECRET_ACCESS_KEY
    echo -e "${GREEN}✓ AWS credentials secret created in '${KUADRANT_GATEWAY_NS}'${NC}"
fi

# cert-manager namespace
if oc get secret aws-credentials -n cert-manager &> /dev/null; then
    echo -e "${YELLOW}⚠ Secret 'aws-credentials' in 'cert-manager' already exists. Skipping.${NC}"
else
    oc -n cert-manager create secret generic aws-credentials \
      --type=kuadrant.io/aws \
      --from-literal=AWS_ACCESS_KEY_ID=$KUADRANT_AWS_ACCESS_KEY_ID \
      --from-literal=AWS_SECRET_ACCESS_KEY=$KUADRANT_AWS_SECRET_ACCESS_KEY
    echo -e "${GREEN}✓ AWS credentials secret created in 'cert-manager'${NC}"
fi
echo ""

# ============================================
# Step 4: Create ClusterIssuer
# ============================================

echo "======================================"
echo "Step 4: Creating ClusterIssuer"
echo "======================================"
echo ""

if oc get clusterissuer ${KUADRANT_CLUSTER_ISSUER_NAME} &> /dev/null; then
    echo -e "${YELLOW}⚠ ClusterIssuer '${KUADRANT_CLUSTER_ISSUER_NAME}' already exists. Skipping.${NC}"
else
    oc apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: ${KUADRANT_CLUSTER_ISSUER_NAME}
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: ${KUADRANT_LETSENCRYPT_EMAIL}
    privateKeySecretRef:
      name: ${KUADRANT_CLUSTER_ISSUER_NAME}
    solvers:
    - dns01:
        route53:
          region: ${KUADRANT_AWS_REGION}
          accessKeyIDSecretRef:
            name: aws-credentials
            key: AWS_ACCESS_KEY_ID
          secretAccessKeySecretRef:
            name: aws-credentials
            key: AWS_SECRET_ACCESS_KEY
EOF
    echo -e "${GREEN}✓ ClusterIssuer created${NC}"
fi
echo ""

# ============================================
# Step 5: Create Gateway
# ============================================

echo "======================================"
echo "Step 5: Creating Gateway"
echo "======================================"
echo ""

if oc get gateway ${KUADRANT_GATEWAY_NAME} -n ${KUADRANT_GATEWAY_NS} &> /dev/null; then
    echo -e "${YELLOW}⚠ Gateway '${KUADRANT_GATEWAY_NAME}' already exists. Skipping.${NC}"
else
    oc apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: ${KUADRANT_GATEWAY_NAME}
  namespace: ${KUADRANT_GATEWAY_NS}
  labels:
    kuadrant.io/gateway: "true"
spec:
  gatewayClassName: istio
  listeners:
  - name: api
    hostname: "api.${KUADRANT_ZONE_ROOT_DOMAIN}"
    port: 443
    protocol: HTTPS
    allowedRoutes:
      namespaces:
        from: All
    tls:
      mode: Terminate
      certificateRefs:
      - name: api-${KUADRANT_GATEWAY_NAME}-tls
        kind: Secret
EOF
    echo -e "${GREEN}✓ Gateway created${NC}"
fi
echo ""

# ============================================
# Step 6: Apply TLSPolicy
# ============================================

echo "======================================"
echo "Step 6: Applying TLSPolicy"
echo "======================================"
echo ""

if oc get tlspolicy ${KUADRANT_GATEWAY_NAME}-tls -n ${KUADRANT_GATEWAY_NS} &> /dev/null; then
    echo -e "${YELLOW}⚠ TLSPolicy '${KUADRANT_GATEWAY_NAME}-tls' already exists. Skipping.${NC}"
else
    oc apply -f - <<EOF
apiVersion: kuadrant.io/v1
kind: TLSPolicy
metadata:
  name: ${KUADRANT_GATEWAY_NAME}-tls
  namespace: ${KUADRANT_GATEWAY_NS}
spec:
  targetRef:
    name: ${KUADRANT_GATEWAY_NAME}
    group: gateway.networking.k8s.io
    kind: Gateway
  issuerRef:
    group: cert-manager.io
    kind: ClusterIssuer
    name: ${KUADRANT_CLUSTER_ISSUER_NAME}
EOF
    echo -e "${GREEN}✓ TLSPolicy applied${NC}"
fi
echo ""

# ============================================
# Step 7: Create HTTPRoute
# ============================================

echo "======================================"
echo "Step 7: Creating HTTPRoute"
echo "======================================"
echo ""

if oc get httproute news-api -n ${KUADRANT_DEVELOPER_NS} &> /dev/null; then
    echo -e "${YELLOW}⚠ HTTPRoute 'news-api' already exists. Skipping.${NC}"
else
    oc apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: news-api
  namespace: ${KUADRANT_DEVELOPER_NS}
  labels:
    app: news-api
spec:
  parentRefs:
  - name: ${KUADRANT_GATEWAY_NAME}
    namespace: ${KUADRANT_GATEWAY_NS}
  hostnames:
  - "api.${KUADRANT_ZONE_ROOT_DOMAIN}"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: "/"
    backendRefs:
    - name: news-api
      port: 80
EOF
    echo -e "${GREEN}✓ HTTPRoute created${NC}"
fi
echo ""

# ============================================
# Step 8: Apply DNSPolicy
# ============================================

echo "======================================"
echo "Step 8: Applying DNSPolicy"
echo "======================================"
echo ""

if oc get dnspolicy ${KUADRANT_GATEWAY_NAME}-dnspolicy -n ${KUADRANT_GATEWAY_NS} &> /dev/null; then
    echo -e "${YELLOW}⚠ DNSPolicy '${KUADRANT_GATEWAY_NAME}-dnspolicy' already exists. Skipping.${NC}"
else
    oc apply -f - <<EOF
apiVersion: kuadrant.io/v1
kind: DNSPolicy
metadata:
  name: ${KUADRANT_GATEWAY_NAME}-dnspolicy
  namespace: ${KUADRANT_GATEWAY_NS}
spec:
  targetRef:
    name: ${KUADRANT_GATEWAY_NAME}
    group: gateway.networking.k8s.io
    kind: Gateway
  loadBalancing:
    defaultGeo: true
    geo: GEO-NA
    weight: 120
  providerRefs:
  - name: aws-credentials
EOF
    echo -e "${GREEN}✓ DNSPolicy applied${NC}"
fi
echo ""

# ============================================
# Step 9: Apply AuthPolicy (Gateway level)
# ============================================

echo "======================================"
echo "Step 9: Applying AuthPolicy (Gateway level)"
echo "======================================"
echo ""

if oc get authpolicy ${KUADRANT_GATEWAY_NAME}-auth -n ${KUADRANT_GATEWAY_NS} &> /dev/null; then
    echo -e "${YELLOW}⚠ AuthPolicy '${KUADRANT_GATEWAY_NAME}-auth' already exists. Skipping.${NC}"
else
    oc apply -f - <<EOF
apiVersion: kuadrant.io/v1
kind: AuthPolicy
metadata:
  name: ${KUADRANT_GATEWAY_NAME}-auth
  namespace: ${KUADRANT_GATEWAY_NS}
spec:
  targetRef:
    group: gateway.networking.k8s.io
    kind: Gateway
    name: ${KUADRANT_GATEWAY_NAME}
  defaults:
    rules:
      authorization:
        deny-all:
          opa:
            rego: "allow = false"
      response:
        unauthorized:
          headers:
            "content-type":
              value: application/json
          body:
            value: |
              {
                "error": "Forbidden",
                "message": "Access denied by default. Please configure a specific auth policy."
              }
EOF
    echo -e "${GREEN}✓ AuthPolicy applied${NC}"
fi
echo ""

# ============================================
# Step 10: Apply RateLimitPolicy (Gateway level)
# ============================================

echo "======================================"
echo "Step 10: Applying RateLimitPolicy (Gateway level)"
echo "======================================"
echo ""

if oc get ratelimitpolicy ${KUADRANT_GATEWAY_NAME}-rlp -n ${KUADRANT_GATEWAY_NS} &> /dev/null; then
    echo -e "${YELLOW}⚠ RateLimitPolicy '${KUADRANT_GATEWAY_NAME}-rlp' already exists. Skipping.${NC}"
else
    oc apply -f - <<EOF
apiVersion: kuadrant.io/v1
kind: RateLimitPolicy
metadata:
  name: ${KUADRANT_GATEWAY_NAME}-rlp
  namespace: ${KUADRANT_GATEWAY_NS}
spec:
  targetRef:
    group: gateway.networking.k8s.io
    kind: Gateway
    name: ${KUADRANT_GATEWAY_NAME}
  defaults:
    limits:
      "low-limit":
        rates:
        - limit: 5
          window: 10s
EOF
    echo -e "${GREEN}✓ RateLimitPolicy applied${NC}"
fi
echo ""

# ============================================
# Step 11: Create API Keys Secret
# ============================================

echo "======================================"
echo "Step 11: Creating API Keys Secret"
echo "======================================"
echo ""

if oc get secret api-keys -n kuadrant-system &> /dev/null; then
    echo -e "${YELLOW}⚠ Secret 'api-keys' already exists. Skipping.${NC}"
else
    oc apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: api-keys
  namespace: kuadrant-system
  labels:
    authorino.kuadrant.io/managed-by: authorino
    app: news-api
stringData:
  api_key: "secret-key-12345"
type: Opaque
EOF
    echo -e "${GREEN}✓ API Keys Secret created${NC}"
fi
echo ""

# ============================================
# Step 12: Apply HTTPRoute-level AuthPolicy
# ============================================

echo "======================================"
echo "Step 12: Applying AuthPolicy (HTTPRoute level)"
echo "======================================"
echo ""

if oc get authpolicy news-api-auth -n ${KUADRANT_DEVELOPER_NS} &> /dev/null; then
    echo -e "${YELLOW}⚠ AuthPolicy 'news-api-auth' already exists. Skipping.${NC}"
else
    oc apply -f - <<EOF
apiVersion: kuadrant.io/v1
kind: AuthPolicy
metadata:
  name: news-api-auth
  namespace: ${KUADRANT_DEVELOPER_NS}
spec:
  targetRef:
    group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: news-api
  rules:
    authentication:
      api-key:
        apiKey:
          selector:
            matchLabels:
              app: news-api
        credentials:
          authorizationHeader:
            prefix: APIKEY
    authorization:
      allow-all:
        opa:
          rego: "allow = true"
    response:
      unauthenticated:
        headers:
          "content-type":
            value: application/json
        body:
          value: |
            {
              "error": "Unauthenticated",
              "message": "Valid API key is required. Use header: Authorization: APIKEY <your-key>"
            }
EOF
    echo -e "${GREEN}✓ HTTPRoute-level AuthPolicy applied${NC}"
fi
echo ""

# ============================================
# Step 13: Apply HTTPRoute-level RateLimitPolicy
# ============================================

echo "======================================"
echo "Step 13: Applying RateLimitPolicy (HTTPRoute level)"
echo "======================================"
echo ""

if oc get ratelimitpolicy news-api-ratelimit -n ${KUADRANT_DEVELOPER_NS} &> /dev/null; then
    echo -e "${YELLOW}⚠ RateLimitPolicy 'news-api-ratelimit' already exists. Skipping.${NC}"
else
    oc apply -f - <<EOF
apiVersion: kuadrant.io/v1
kind: RateLimitPolicy
metadata:
  name: news-api-ratelimit
  namespace: ${KUADRANT_DEVELOPER_NS}
spec:
  targetRef:
    group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: news-api
  limits:
    "authenticated-user-limit":
      rates:
      - limit: 10
        window: 1m
      counters:
      - expression: auth.identity.api_key
EOF
    echo -e "${GREEN}✓ HTTPRoute-level RateLimitPolicy applied${NC}"
fi
echo ""

# ============================================
# Installation Summary
# ============================================

echo "======================================"
echo "Setup Complete!"
echo "======================================"
echo ""
echo -e "${GREEN}Gateway and Policy resources have been successfully created.${NC}"
echo ""
echo "Created resources:"
echo "  1. Namespaces:"
echo "     - ${KUADRANT_GATEWAY_NS} (Gateway)"
echo "     - ${KUADRANT_DEVELOPER_NS} (Application)"
echo ""
echo "  2. Application:"
echo "     - News API Deployment and Service"
echo ""
echo "  3. DNS and TLS:"
echo "     - AWS Credentials Secrets"
echo "     - ClusterIssuer: ${KUADRANT_CLUSTER_ISSUER_NAME}"
echo ""
echo "  4. Gateway API:"
echo "     - Gateway: ${KUADRANT_GATEWAY_NAME}"
echo "     - HTTPRoute: news-api"
echo ""
echo "  5. Gateway-level Policies:"
echo "     - TLSPolicy: ${KUADRANT_GATEWAY_NAME}-tls"
echo "     - DNSPolicy: ${KUADRANT_GATEWAY_NAME}-dnspolicy (health checks disabled)"
echo "     - AuthPolicy: ${KUADRANT_GATEWAY_NAME}-auth (deny-all by default)"
echo "     - RateLimitPolicy: ${KUADRANT_GATEWAY_NAME}-rlp (5 req/10s)"
echo ""
echo "  6. HTTPRoute-level Policies (overrides):"
echo "     - API Keys Secret: api-keys (kuadrant-system namespace)"
echo "     - AuthPolicy: news-api-auth (API key authentication)"
echo "     - RateLimitPolicy: news-api-ratelimit (10 req/min per user)"
echo ""
echo "API Endpoint:"
echo "  https://api.${KUADRANT_ZONE_ROOT_DOMAIN}/"
echo ""
echo "Note:"
echo "  - DNS propagation may take a few minutes"
echo "  - TLS certificate issuance via Let's Encrypt may take several minutes"
echo "  - DNSPolicy health checks are disabled to avoid circular dependency during bootstrap"
echo "  - AuthPolicy is set to deny all requests by default"
echo "  - RateLimitPolicy limits requests to 5 per 10 seconds"
echo ""
echo "To verify:"
echo "  # DNS resolution"
echo "  nslookup api.${KUADRANT_ZONE_ROOT_DOMAIN}"
echo ""
echo "  # API access with API key (HTTPRoute-level auth policy)"
echo "  curl -k -H \"Authorization: APIKEY secret-key-12345\" https://api.${KUADRANT_ZONE_ROOT_DOMAIN}/technology"
echo ""
echo "  # Without API key (should return 401)"
echo "  curl -k https://api.${KUADRANT_ZONE_ROOT_DOMAIN}/technology"
echo ""
echo "To clean up:"
echo "  ./cleanup-gateway-and-policy.sh"
echo ""
