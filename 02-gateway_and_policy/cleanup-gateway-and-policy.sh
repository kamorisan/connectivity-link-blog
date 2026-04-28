#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "======================================"
echo "Gateway and Policy Cleanup"
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

# Check for environment variables
if [ -z "$KUADRANT_GATEWAY_NS" ] || [ -z "$KUADRANT_DEVELOPER_NS" ]; then
    echo -e "${YELLOW}⚠ Environment variables not set. Using default values.${NC}"
    KUADRANT_GATEWAY_NS=${KUADRANT_GATEWAY_NS:-api-gateway}
    KUADRANT_DEVELOPER_NS=${KUADRANT_DEVELOPER_NS:-news-api}
    KUADRANT_GATEWAY_NAME=${KUADRANT_GATEWAY_NAME:-external}
    KUADRANT_CLUSTER_ISSUER_NAME=${KUADRANT_CLUSTER_ISSUER_NAME:-letsencrypt-prod}
fi

echo -e "${YELLOW}WARNING: This will delete the following resources:${NC}"
echo "  - Gateway: ${KUADRANT_GATEWAY_NAME} (namespace: ${KUADRANT_GATEWAY_NS})"
echo "  - All Policies (TLSPolicy, DNSPolicy, AuthPolicy, RateLimitPolicy)"
echo "  - HTTPRoute: news-api (namespace: ${KUADRANT_DEVELOPER_NS})"
echo "  - News API application"
echo "  - Namespaces: ${KUADRANT_GATEWAY_NS}, ${KUADRANT_DEVELOPER_NS}"
echo "  - AWS Credentials Secrets"
echo "  - ClusterIssuer: ${KUADRANT_CLUSTER_ISSUER_NAME}"
echo ""
read -p "Are you sure you want to continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cleanup cancelled."
    exit 0
fi
echo ""

# ============================================
# Step 1: Delete HTTPRoute-level Policies
# ============================================

echo "======================================"
echo "Step 1: Deleting HTTPRoute-level Policies"
echo "======================================"
echo ""

# HTTPRoute-level RateLimitPolicy
if oc get ratelimitpolicy news-api-ratelimit -n ${KUADRANT_DEVELOPER_NS} &> /dev/null; then
    oc delete ratelimitpolicy news-api-ratelimit -n ${KUADRANT_DEVELOPER_NS}
    echo -e "${GREEN}✓ HTTPRoute-level RateLimitPolicy deleted${NC}"
else
    echo -e "${YELLOW}⚠ HTTPRoute-level RateLimitPolicy not found. Skipping.${NC}"
fi

# HTTPRoute-level AuthPolicy
if oc get authpolicy news-api-auth -n ${KUADRANT_DEVELOPER_NS} &> /dev/null; then
    oc delete authpolicy news-api-auth -n ${KUADRANT_DEVELOPER_NS}
    echo -e "${GREEN}✓ HTTPRoute-level AuthPolicy deleted${NC}"
else
    echo -e "${YELLOW}⚠ HTTPRoute-level AuthPolicy not found. Skipping.${NC}"
fi
echo ""

# ============================================
# Step 2: Delete Gateway-level Policies
# ============================================

echo "======================================"
echo "Step 2: Deleting Gateway-level Policies"
echo "======================================"
echo ""

# RateLimitPolicy
if oc get ratelimitpolicy ${KUADRANT_GATEWAY_NAME}-rlp -n ${KUADRANT_GATEWAY_NS} &> /dev/null; then
    oc delete ratelimitpolicy ${KUADRANT_GATEWAY_NAME}-rlp -n ${KUADRANT_GATEWAY_NS}
    echo -e "${GREEN}✓ RateLimitPolicy deleted${NC}"
else
    echo -e "${YELLOW}⚠ RateLimitPolicy not found. Skipping.${NC}"
fi

# AuthPolicy
if oc get authpolicy ${KUADRANT_GATEWAY_NAME}-auth -n ${KUADRANT_GATEWAY_NS} &> /dev/null; then
    oc delete authpolicy ${KUADRANT_GATEWAY_NAME}-auth -n ${KUADRANT_GATEWAY_NS}
    echo -e "${GREEN}✓ AuthPolicy deleted${NC}"
else
    echo -e "${YELLOW}⚠ AuthPolicy not found. Skipping.${NC}"
fi

# DNSPolicy
if oc get dnspolicy ${KUADRANT_GATEWAY_NAME}-dnspolicy -n ${KUADRANT_GATEWAY_NS} &> /dev/null; then
    oc delete dnspolicy ${KUADRANT_GATEWAY_NAME}-dnspolicy -n ${KUADRANT_GATEWAY_NS}
    echo -e "${GREEN}✓ DNSPolicy deleted${NC}"
else
    echo -e "${YELLOW}⚠ DNSPolicy not found. Skipping.${NC}"
fi

# TLSPolicy
if oc get tlspolicy ${KUADRANT_GATEWAY_NAME}-tls -n ${KUADRANT_GATEWAY_NS} &> /dev/null; then
    oc delete tlspolicy ${KUADRANT_GATEWAY_NAME}-tls -n ${KUADRANT_GATEWAY_NS}
    echo -e "${GREEN}✓ TLSPolicy deleted${NC}"
else
    echo -e "${YELLOW}⚠ TLSPolicy not found. Skipping.${NC}"
fi
echo ""

# ============================================
# Step 3: Delete HTTPRoute
# ============================================

echo "======================================"
echo "Step 3: Deleting HTTPRoute"
echo "======================================"
echo ""

if oc get httproute news-api -n ${KUADRANT_DEVELOPER_NS} &> /dev/null; then
    oc delete httproute news-api -n ${KUADRANT_DEVELOPER_NS}
    echo -e "${GREEN}✓ HTTPRoute deleted${NC}"
else
    echo -e "${YELLOW}⚠ HTTPRoute not found. Skipping.${NC}"
fi
echo ""

# ============================================
# Step 4: Delete Gateway
# ============================================

echo "======================================"
echo "Step 4: Deleting Gateway"
echo "======================================"
echo ""

if oc get gateway ${KUADRANT_GATEWAY_NAME} -n ${KUADRANT_GATEWAY_NS} &> /dev/null; then
    oc delete gateway ${KUADRANT_GATEWAY_NAME} -n ${KUADRANT_GATEWAY_NS}
    echo -e "${GREEN}✓ Gateway deleted${NC}"
else
    echo -e "${YELLOW}⚠ Gateway not found. Skipping.${NC}"
fi
echo ""

# ============================================
# Step 5: Delete ClusterIssuer
# ============================================

echo "======================================"
echo "Step 5: Deleting ClusterIssuer"
echo "======================================"
echo ""

if oc get clusterissuer ${KUADRANT_CLUSTER_ISSUER_NAME} &> /dev/null; then
    oc delete clusterissuer ${KUADRANT_CLUSTER_ISSUER_NAME}
    echo -e "${GREEN}✓ ClusterIssuer deleted${NC}"
else
    echo -e "${YELLOW}⚠ ClusterIssuer not found. Skipping.${NC}"
fi
echo ""

# ============================================
# Step 6: Delete Secrets
# ============================================

echo "======================================"
echo "Step 6: Deleting Secrets"
echo "======================================"
echo ""

# API Keys Secret
if oc get secret api-keys -n kuadrant-system &> /dev/null; then
    oc delete secret api-keys -n kuadrant-system
    echo -e "${GREEN}✓ API Keys secret deleted from 'kuadrant-system'${NC}"
fi

# AWS credentials - Gateway namespace
if oc get secret aws-credentials -n ${KUADRANT_GATEWAY_NS} &> /dev/null; then
    oc delete secret aws-credentials -n ${KUADRANT_GATEWAY_NS}
    echo -e "${GREEN}✓ AWS credentials secret deleted from '${KUADRANT_GATEWAY_NS}'${NC}"
fi

# AWS credentials - cert-manager namespace
if oc get secret aws-credentials -n cert-manager &> /dev/null; then
    oc delete secret aws-credentials -n cert-manager
    echo -e "${GREEN}✓ AWS credentials secret deleted from 'cert-manager'${NC}"
fi
echo ""

# ============================================
# Step 7: Delete News API Application
# ============================================

echo "======================================"
echo "Step 7: Deleting News API Application"
echo "======================================"
echo ""

if oc get namespace ${KUADRANT_DEVELOPER_NS} &> /dev/null; then
    if oc get deployment news-api -n ${KUADRANT_DEVELOPER_NS} &> /dev/null; then
        oc delete deployment news-api -n ${KUADRANT_DEVELOPER_NS}
        echo -e "${GREEN}✓ News API Deployment deleted${NC}"
    fi

    if oc get service news-api -n ${KUADRANT_DEVELOPER_NS} &> /dev/null; then
        oc delete service news-api -n ${KUADRANT_DEVELOPER_NS}
        echo -e "${GREEN}✓ News API Service deleted${NC}"
    fi
fi
echo ""

# ============================================
# Step 8: Delete Namespaces
# ============================================

echo "======================================"
echo "Step 8: Deleting Namespaces"
echo "======================================"
echo ""

# Developer namespace
if oc get namespace ${KUADRANT_DEVELOPER_NS} &> /dev/null; then
    oc delete namespace ${KUADRANT_DEVELOPER_NS}
    echo -e "${GREEN}✓ Namespace '${KUADRANT_DEVELOPER_NS}' deleted${NC}"
else
    echo -e "${YELLOW}⚠ Namespace '${KUADRANT_DEVELOPER_NS}' not found. Skipping.${NC}"
fi

# Gateway namespace
if oc get namespace ${KUADRANT_GATEWAY_NS} &> /dev/null; then
    oc delete namespace ${KUADRANT_GATEWAY_NS}
    echo -e "${GREEN}✓ Namespace '${KUADRANT_GATEWAY_NS}' deleted${NC}"
else
    echo -e "${YELLOW}⚠ Namespace '${KUADRANT_GATEWAY_NS}' not found. Skipping.${NC}"
fi
echo ""

echo "======================================"
echo "Cleanup Complete!"
echo "======================================"
echo ""
echo "All Gateway and Policy resources have been removed."
echo ""
echo "Note: DNS records in AWS Route 53 may take a few minutes to be removed."
echo ""
echo "To recreate the setup, run: ./setup-gateway-and-policy.sh"
echo ""
