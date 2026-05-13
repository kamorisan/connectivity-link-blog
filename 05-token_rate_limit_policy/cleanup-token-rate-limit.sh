#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "======================================"
echo "Token-based Rate Limiting Cleanup"
echo "Red Hat Connectivity Link - Article 5"
echo "======================================"
echo ""

# Warning
echo -e "${YELLOW}⚠ WARNING: This will delete all resources created in Article 5${NC}"
echo ""
echo "Resources to be deleted:"
echo "  - TokenRateLimitPolicy: llm-api-token-limit (llm-api namespace)"
echo "  - HTTPRoute: llm-api (llm-api namespace)"
echo "  - Mock LLM API: Deployment, Service, ConfigMap (llm-api namespace)"
echo "  - Gateway: llm-gateway (llm-gateway namespace)"
echo "  - Namespaces: llm-api, llm-gateway"
echo ""
read -p "Are you sure you want to continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo ""

# Check if oc is installed
if ! command -v oc &> /dev/null; then
    echo -e "${RED}✗ OpenShift CLI (oc) is not installed${NC}"
    exit 1
fi

# Check if logged in to OpenShift
if ! oc whoami &> /dev/null; then
    echo -e "${RED}✗ Not logged in to OpenShift${NC}"
    echo "Please run: oc login"
    exit 1
fi

echo "======================================"
echo "Step 1: Deleting TokenRateLimitPolicy"
echo "======================================"
echo ""

if oc get tokenratelimitpolicy llm-api-token-limit -n llm-api &> /dev/null; then
    oc delete tokenratelimitpolicy llm-api-token-limit -n llm-api
    echo -e "${GREEN}✓ TokenRateLimitPolicy deleted${NC}"
else
    echo -e "${YELLOW}⚠ TokenRateLimitPolicy not found${NC}"
fi

echo ""

echo "======================================"
echo "Step 2: Deleting HTTPRoute"
echo "======================================"
echo ""

if oc get httproute llm-api -n llm-api &> /dev/null; then
    oc delete httproute llm-api -n llm-api
    echo -e "${GREEN}✓ HTTPRoute deleted${NC}"
else
    echo -e "${YELLOW}⚠ HTTPRoute not found${NC}"
fi

echo ""

echo "======================================"
echo "Step 3: Deleting Mock LLM API"
echo "======================================"
echo ""

if oc get namespace llm-api &> /dev/null; then
    if oc get deployment mock-llm-api -n llm-api &> /dev/null; then
        oc delete deployment mock-llm-api -n llm-api
        echo -e "${GREEN}✓ Deployment deleted${NC}"
    fi

    if oc get service mock-llm-api -n llm-api &> /dev/null; then
        oc delete service mock-llm-api -n llm-api
        echo -e "${GREEN}✓ Service deleted${NC}"
    fi

    if oc get configmap mock-llm-api -n llm-api &> /dev/null; then
        oc delete configmap mock-llm-api -n llm-api
        echo -e "${GREEN}✓ ConfigMap deleted${NC}"
    fi
else
    echo -e "${YELLOW}⚠ llm-api namespace not found${NC}"
fi

echo ""

echo "======================================"
echo "Step 4: Deleting Gateway"
echo "======================================"
echo ""

if oc get gateway llm-gateway -n llm-gateway &> /dev/null; then
    oc delete gateway llm-gateway -n llm-gateway
    echo -e "${GREEN}✓ Gateway deleted${NC}"
else
    echo -e "${YELLOW}⚠ Gateway not found${NC}"
fi

echo ""

echo "======================================"
echo "Step 5: Deleting Namespaces"
echo "======================================"
echo ""

if oc get namespace llm-api &> /dev/null; then
    oc delete namespace llm-api
    echo -e "${GREEN}✓ Namespace llm-api deleted${NC}"
else
    echo -e "${YELLOW}⚠ Namespace llm-api not found${NC}"
fi

if oc get namespace llm-gateway &> /dev/null; then
    oc delete namespace llm-gateway
    echo -e "${GREEN}✓ Namespace llm-gateway deleted${NC}"
else
    echo -e "${YELLOW}⚠ Namespace llm-gateway not found${NC}"
fi

echo ""

# Wait for namespaces to be fully deleted
echo "Waiting for namespaces to be fully deleted..."
while oc get namespace llm-api &> /dev/null || oc get namespace llm-gateway &> /dev/null; do
    echo -n "."
    sleep 2
done
echo ""

echo ""
echo "======================================"
echo "Cleanup Complete!"
echo "======================================"
echo ""

echo "All resources have been deleted."
echo ""
echo "Note: Red Hat Connectivity Link (Kuadrant) is still installed."
echo "To reinstall the Article 5 environment, run:"
echo "  ./setup-token-rate-limit.sh"
echo ""
