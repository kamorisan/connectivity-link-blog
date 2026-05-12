#!/bin/bash

set -e

echo "======================================"
echo "Grafana Complete Cleanup"
echo "Red Hat Connectivity Link - Article 4"
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

# Use monitoring namespace (same as setup script)
GRAFANA_NAMESPACE="monitoring"

echo -e "${YELLOW}WARNING: This will delete ALL Grafana resources from ${GRAFANA_NAMESPACE} namespace:${NC}"
echo "  - All GrafanaDashboard CRs"
echo "  - All GrafanaDatasource CRs"
echo "  - Grafana instance"
echo "  - All Secrets (tokens, credentials)"
echo "  - Service Account"
echo ""
echo -e "${RED}NOTE: kube-state-metrics-kuadrant in ${GRAFANA_NAMESPACE} will also be deleted${NC}"
echo ""
read -p "Are you sure you want to continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cleanup cancelled."
    exit 0
fi
echo ""

# Ask about Grafana Operator
REMOVE_OPERATOR=false
if oc get subscription grafana-operator -n openshift-operators &> /dev/null; then
    echo -e "${YELLOW}Grafana Operator is currently installed.${NC}"
    echo "Do you also want to remove the Grafana Operator?"
    echo -e "  ${RED}WARNING: This will affect ALL Grafana instances in the cluster!${NC}"
    echo ""
    read -p "Remove Grafana Operator? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        REMOVE_OPERATOR=true
    fi
    echo ""
fi

echo "======================================"
echo "Step 1: Deleting GrafanaDashboard CRs"
echo "======================================"
oc delete grafanadashboard --all -n ${GRAFANA_NAMESPACE} --ignore-not-found --wait=false
echo -e "${GREEN}✓ GrafanaDashboard CRs deletion initiated${NC}"
echo ""

echo "======================================"
echo "Step 2: Deleting GrafanaDatasource CRs"
echo "======================================"
oc delete grafanadatasource --all -n ${GRAFANA_NAMESPACE} --ignore-not-found --wait=false
echo -e "${GREEN}✓ GrafanaDatasource CRs deletion initiated${NC}"
echo ""

echo "======================================"
echo "Step 3: Deleting Grafana instance"
echo "======================================"
oc delete grafana grafana -n ${GRAFANA_NAMESPACE} --ignore-not-found --wait=false
echo -e "${GREEN}✓ Grafana instance deletion initiated${NC}"
echo ""

echo "======================================"
echo "Step 4: Deleting Secrets"
echo "======================================"
oc delete secret prometheus-bearer-token -n ${GRAFANA_NAMESPACE} --ignore-not-found --wait=false
oc delete secret grafana-serviceaccount-token -n ${GRAFANA_NAMESPACE} --ignore-not-found --wait=false
echo -e "${GREEN}✓ Secrets deletion initiated${NC}"
echo ""

echo "======================================"
echo "Step 5: Deleting Service Account"
echo "======================================"
oc delete sa grafana-serviceaccount -n ${GRAFANA_NAMESPACE} --ignore-not-found --wait=false
echo -e "${GREEN}✓ Service Account deletion initiated${NC}"
echo ""

echo "======================================"
echo "Step 6: Deleting kube-state-metrics-kuadrant"
echo "======================================"
echo "Removing kube-state-metrics-kuadrant from monitoring namespace..."
oc delete deployment kube-state-metrics-kuadrant -n monitoring --ignore-not-found --wait=false
oc delete service kube-state-metrics-kuadrant -n monitoring --ignore-not-found --wait=false
oc delete servicemonitor kube-state-metrics-kuadrant -n monitoring --ignore-not-found --wait=false
oc delete serviceaccount kube-state-metrics-kuadrant -n monitoring --ignore-not-found --wait=false
oc delete configmap custom-resource-state -n monitoring --ignore-not-found --wait=false
echo -e "${GREEN}✓ kube-state-metrics-kuadrant resources deletion initiated${NC}"
echo ""

# Also check and remove from kuadrant-system if exists
echo "Checking for kube-state-metrics-kuadrant in kuadrant-system namespace..."
if oc get deployment kube-state-metrics-kuadrant -n kuadrant-system &> /dev/null; then
    echo "Found resources in kuadrant-system, removing..."
    oc delete deployment kube-state-metrics-kuadrant -n kuadrant-system --ignore-not-found --wait=false
    oc delete service kube-state-metrics-kuadrant -n kuadrant-system --ignore-not-found --wait=false
    oc delete servicemonitor kube-state-metrics-kuadrant -n kuadrant-system --ignore-not-found --wait=false
    oc delete serviceaccount kube-state-metrics-kuadrant -n kuadrant-system --ignore-not-found --wait=false
    oc delete configmap custom-resource-state -n kuadrant-system --ignore-not-found --wait=false
    echo -e "${GREEN}✓ kuadrant-system resources also deleted${NC}"
else
    echo -e "${GREEN}✓ No resources found in kuadrant-system${NC}"
fi
echo ""

echo "======================================"
echo "Step 7: Cleanup ClusterRoleBinding"
echo "======================================"
echo "Removing cluster-monitoring-view permission from Grafana ServiceAccount..."
oc adm policy remove-cluster-role-from-user cluster-monitoring-view \
  system:serviceaccount:${GRAFANA_NAMESPACE}:grafana-serviceaccount \
  --ignore-not-found 2>/dev/null || true
echo -e "${GREEN}✓ ClusterRoleBinding cleanup completed${NC}"
echo ""

echo "======================================"
echo "Step 8: Deleting Istio Telemetry"
echo "======================================"
echo "Removing Istio Telemetry configuration..."
oc delete telemetry namespace-metrics -n istio-system --ignore-not-found --wait=false
echo -e "${GREEN}✓ Istio Telemetry cleanup completed${NC}"
echo ""

echo -e "${YELLOW}Note: monitoring namespace is NOT deleted (shared with kube-state-metrics-kuadrant)${NC}"
echo ""

# ============================================
# Step 9: Remove Grafana Operator (optional)
# ============================================

if [ "$REMOVE_OPERATOR" = true ]; then
    echo "======================================"
    echo "Step 9: Removing Grafana Operator"
    echo "======================================"

    # Get CSV name
    CSV_NAME=$(oc get subscription grafana-operator -n openshift-operators -o jsonpath='{.status.currentCSV}' 2>/dev/null)

    # Delete Subscription
    echo "Deleting Grafana Operator Subscription..."
    oc delete subscription grafana-operator -n openshift-operators --ignore-not-found
    echo -e "${GREEN}✓ Subscription deleted${NC}"

    # Delete CSV
    if [ -n "$CSV_NAME" ]; then
        echo "Deleting CSV: $CSV_NAME..."
        oc delete csv "$CSV_NAME" -n openshift-operators --ignore-not-found
        echo -e "${GREEN}✓ CSV deleted${NC}"
    fi

    # Wait for Operator pod to be deleted
    echo "Waiting for Operator pod to be terminated..."
    for i in {1..30}; do
        OP_POD=$(oc get pods -n openshift-operators -l app.kubernetes.io/name=grafana-operator --no-headers 2>/dev/null | wc -l)
        if [ "$OP_POD" -eq 0 ]; then
            break
        fi
        sleep 2
    done
    echo -e "${GREEN}✓ Grafana Operator removed${NC}"
    echo ""
fi

echo "======================================"
echo "Cleanup Complete!"
echo "======================================"
echo ""
echo "All Grafana resources have been removed."
echo ""

# Display what was NOT deleted
NOT_DELETED=false
echo -e "${YELLOW}Note: The following resources are NOT deleted:${NC}"

if [ "$REMOVE_OPERATOR" != true ]; then
    if oc get subscription grafana-operator -n openshift-operators &> /dev/null; then
        echo "  - Grafana Operator (openshift-operators namespace)"
        echo "    Reason: May be used by other projects"
        echo "    To remove manually:"
        echo "      oc delete subscription grafana-operator -n openshift-operators"
        echo "      oc delete csv -n openshift-operators \$(oc get csv -n openshift-operators | grep grafana | awk '{print \$1}')"
        echo ""
        NOT_DELETED=true
    fi
fi

if oc get configmap cluster-monitoring-config -n openshift-monitoring &> /dev/null; then
    echo "  - User Workload Monitoring"
    echo "    Reason: May be used by other applications"
    echo "    To disable manually:"
    echo "      oc delete configmap cluster-monitoring-config -n openshift-monitoring"
    echo ""
    NOT_DELETED=true
fi

if [ "$NOT_DELETED" = false ]; then
    echo "  (All observability resources have been completely removed)"
    echo ""
fi

echo "To recreate the setup, run: ./setup-grafana.sh"
echo ""
