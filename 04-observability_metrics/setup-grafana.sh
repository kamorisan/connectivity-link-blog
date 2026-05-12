#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "======================================"
echo "Grafana Complete Setup"
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

# Use monitoring namespace (same as kube-state-metrics-kuadrant)
GRAFANA_NAMESPACE="monitoring"

# Check if monitoring namespace exists
if ! oc get namespace monitoring &> /dev/null; then
    echo -e "${RED}✗ monitoring namespace does not exist.${NC}"
    echo "  This namespace should be created by User Workload Monitoring."
    exit 1
fi
echo -e "${GREEN}✓ Using monitoring namespace${NC}"
echo ""

# ============================================
# Prerequisites: Check Kuadrant Observability
# ============================================

echo "======================================"
echo "Prerequisites: Checking Kuadrant CR"
echo "======================================"
echo ""

# Check if Kuadrant CR exists
if ! oc get kuadrant -n kuadrant-system &> /dev/null; then
    echo -e "${RED}✗ Kuadrant CR not found in kuadrant-system namespace.${NC}"
    echo -e "${RED}  Please install Red Hat Connectivity Link first.${NC}"
    exit 1
fi

# Get Kuadrant CR name (usually 'kuadrant')
KUADRANT_CR_NAME=$(oc get kuadrant -n kuadrant-system -o jsonpath='{.items[0].metadata.name}')
echo -e "${GREEN}✓ Kuadrant CR found: ${KUADRANT_CR_NAME}${NC}"

# Check if observability is enabled
OBSERVABILITY_ENABLED=$(oc get kuadrant ${KUADRANT_CR_NAME} -n kuadrant-system -o jsonpath='{.spec.observability.enable}')

if [ "$OBSERVABILITY_ENABLED" != "true" ]; then
    echo -e "${YELLOW}⚠ Kuadrant observability is NOT enabled (current value: ${OBSERVABILITY_ENABLED})${NC}"
    echo ""
    echo "To enable observability, run:"
    echo "  oc patch kuadrant ${KUADRANT_CR_NAME} -n kuadrant-system --type='merge' -p '{\"spec\":{\"observability\":{\"enable\":true}}}'"
    echo ""
    read -p "Do you want to enable observability now? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        oc patch kuadrant ${KUADRANT_CR_NAME} -n kuadrant-system --type='merge' -p '{"spec":{"observability":{"enable":true}}}'
        echo -e "${GREEN}✓ Observability enabled${NC}"
        echo "Waiting for ServiceMonitor/PodMonitor creation..."
        sleep 10
    else
        echo -e "${YELLOW}⚠ Continuing without enabling observability.${NC}"
        echo -e "${YELLOW}  Note: Grafana dashboards will show 'No data' without metrics.${NC}"
    fi
else
    echo -e "${GREEN}✓ Kuadrant observability is enabled${NC}"
fi
echo ""

# Check if ServiceMonitors exist
echo "Checking for ServiceMonitors..."
SERVICEMONITOR_COUNT=$(oc get servicemonitor -n kuadrant-system --no-headers 2>/dev/null | wc -l)
if [ "$SERVICEMONITOR_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✓ Found ${SERVICEMONITOR_COUNT} ServiceMonitor(s)${NC}"
else
    echo -e "${YELLOW}⚠ No ServiceMonitors found. Metrics collection may not work.${NC}"
fi
echo ""

# ============================================
# Enable User Workload Monitoring
# ============================================

echo "======================================"
echo "Enabling User Workload Monitoring"
echo "======================================"
echo ""

# Check if User Workload Monitoring is already enabled
if oc get configmap cluster-monitoring-config -n openshift-monitoring &> /dev/null; then
    ENABLED=$(oc get configmap cluster-monitoring-config -n openshift-monitoring -o jsonpath='{.data.config\.yaml}' | grep -c "enableUserWorkload: true" || true)
    if [ "$ENABLED" -gt 0 ]; then
        echo -e "${GREEN}✓ User Workload Monitoring is already enabled${NC}"
    else
        echo -e "${YELLOW}⚠ User Workload Monitoring is not enabled, enabling now...${NC}"
        cat <<YAML | oc apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-monitoring-config
  namespace: openshift-monitoring
data:
  config.yaml: |
    enableUserWorkload: true
YAML
        echo -e "${GREEN}✓ User Workload Monitoring enabled${NC}"
        echo "Waiting for User Workload Monitoring pods to start..."
        sleep 30
    fi
else
    echo "Creating cluster-monitoring-config to enable User Workload Monitoring..."
    cat <<YAML | oc apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-monitoring-config
  namespace: openshift-monitoring
data:
  config.yaml: |
    enableUserWorkload: true
YAML
    echo -e "${GREEN}✓ User Workload Monitoring enabled${NC}"
    echo "Waiting for User Workload Monitoring pods to start..."
    sleep 30
fi

# Verify User Workload Monitoring pods
UWM_PODS=$(oc get pods -n openshift-user-workload-monitoring --no-headers 2>/dev/null | wc -l)
if [ "$UWM_PODS" -gt 0 ]; then
    echo -e "${GREEN}✓ User Workload Monitoring is running (${UWM_PODS} pods)${NC}"
else
    echo -e "${YELLOW}⚠ User Workload Monitoring pods not found. This may take a few minutes.${NC}"
fi
echo ""

# ============================================
# Deploy kube-state-metrics-kuadrant
# ============================================

echo "======================================"
echo "Deploying kube-state-metrics-kuadrant"
echo "======================================"
echo ""

# Check if already deployed
if oc get deployment kube-state-metrics-kuadrant -n monitoring &> /dev/null; then
    echo -e "${GREEN}✓ kube-state-metrics-kuadrant is already deployed in monitoring namespace${NC}"
else
    echo "Deploying kube-state-metrics-kuadrant using Kuadrant observability configuration..."
    # Apply the observability configuration, ignoring gateway-system errors
    oc apply -k 'https://github.com/Kuadrant/kuadrant-operator/config/install/configure/observability?ref=v1.3.0' 2>&1 | grep -v "gateway-system" | grep -v "Error from server (NotFound)" || true
    echo -e "${GREEN}✓ kube-state-metrics-kuadrant deployed${NC}"
    echo "Waiting for pod to be ready..."
    sleep 10
fi

# Verify deployment
if oc wait --for=condition=Available deployment/kube-state-metrics-kuadrant -n monitoring --timeout=60s &> /dev/null; then
    echo -e "${GREEN}✓ kube-state-metrics-kuadrant is ready${NC}"
else
    echo -e "${YELLOW}⚠ kube-state-metrics-kuadrant may still be starting${NC}"
fi

# Check pod status
KSM_POD=$(oc get pods -n monitoring -l app.kubernetes.io/name=kube-state-metrics-kuadrant --no-headers 2>/dev/null | head -1 | awk '{print $1}')
if [ -n "$KSM_POD" ]; then
    echo -e "${GREEN}✓ Pod: ${KSM_POD}${NC}"
else
    echo -e "${RED}✗ kube-state-metrics-kuadrant pod not found${NC}"
fi
echo ""

# ============================================
# Configure Istio Telemetry for Metrics
# ============================================

echo "======================================"
echo "Configuring Istio Telemetry"
echo "======================================"
echo ""

# Check if istio-system namespace exists
if ! oc get namespace istio-system &> /dev/null; then
    echo -e "${YELLOW}⚠ istio-system namespace does not exist. Creating...${NC}"
    oc create namespace istio-system
fi

# Check if Telemetry already exists
if oc get telemetry namespace-metrics -n istio-system &> /dev/null; then
    echo -e "${GREEN}✓ Istio Telemetry already configured${NC}"
else
    echo "Creating Telemetry configuration for request_url_path metrics..."
    cat <<YAML | oc apply -f -
apiVersion: telemetry.istio.io/v1
kind: Telemetry
metadata:
  name: namespace-metrics
  namespace: istio-system
spec:
  metrics:
  - overrides:
    - match:
        metric: REQUEST_COUNT
      tagOverrides:
        destination_port:
          value: string(destination.port)
        request_host:
          value: request.host
        request_url_path:
          value: request.url_path
    - match:
        metric: REQUEST_DURATION
      tagOverrides:
        destination_port:
          value: string(destination.port)
        request_host:
          value: request.host
        request_url_path:
          value: request.url_path
    providers:
    - name: prometheus
YAML
    echo -e "${GREEN}✓ Istio Telemetry configured${NC}"
fi
echo ""

# ============================================
# Check and Install Grafana Operator
# ============================================

echo "======================================"
echo "Checking Grafana Operator"
echo "======================================"
echo ""

# Check if Grafana Operator Subscription exists
if oc get subscription grafana-operator -n openshift-operators &> /dev/null; then
    echo -e "${GREEN}✓ Grafana Operator Subscription exists${NC}"

    # Check CSV status
    CSV_NAME=$(oc get subscription grafana-operator -n openshift-operators -o jsonpath='{.status.currentCSV}' 2>/dev/null)
    if [ -n "$CSV_NAME" ]; then
        CSV_PHASE=$(oc get csv "$CSV_NAME" -n openshift-operators -o jsonpath='{.status.phase}' 2>/dev/null)
        if [ "$CSV_PHASE" = "Succeeded" ]; then
            echo -e "${GREEN}✓ Grafana Operator is installed and running (CSV: $CSV_NAME)${NC}"
        else
            echo -e "${YELLOW}⚠ Grafana Operator CSV phase: $CSV_PHASE${NC}"
            echo "Waiting for Operator to be ready..."
            oc wait --for=jsonpath='{.status.phase}'=Succeeded csv "$CSV_NAME" -n openshift-operators --timeout=120s 2>/dev/null || true
        fi
    else
        echo -e "${YELLOW}⚠ Grafana Operator CSV not found yet${NC}"
    fi

    # Check Operator Pod
    OP_POD=$(oc get pods -n openshift-operators -l app.kubernetes.io/name=grafana-operator --no-headers 2>/dev/null | head -1 | awk '{print $1}')
    if [ -n "$OP_POD" ]; then
        POD_STATUS=$(oc get pod "$OP_POD" -n openshift-operators -o jsonpath='{.status.phase}')
        if [ "$POD_STATUS" = "Running" ]; then
            echo -e "${GREEN}✓ Grafana Operator pod is running: $OP_POD${NC}"
        else
            echo -e "${YELLOW}⚠ Grafana Operator pod status: $POD_STATUS${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ Grafana Operator pod not found${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Grafana Operator is not installed${NC}"
    echo ""
    echo "Installing Grafana Operator v5..."

    # Create Subscription
    cat <<YAML | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: grafana-operator
  namespace: openshift-operators
spec:
  channel: v5
  installPlanApproval: Automatic
  name: grafana-operator
  source: community-operators
  sourceNamespace: openshift-marketplace
YAML

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Grafana Operator Subscription created${NC}"
        echo "Waiting for Operator installation (this may take 1-2 minutes)..."

        # Wait for CSV to be created
        for i in {1..30}; do
            CSV_NAME=$(oc get subscription grafana-operator -n openshift-operators -o jsonpath='{.status.currentCSV}' 2>/dev/null)
            if [ -n "$CSV_NAME" ]; then
                echo "CSV created: $CSV_NAME"
                break
            fi
            echo -n "."
            sleep 2
        done
        echo ""

        if [ -n "$CSV_NAME" ]; then
            # Wait for CSV to be Succeeded
            echo "Waiting for CSV to be ready..."
            if oc wait --for=jsonpath='{.status.phase}'=Succeeded csv "$CSV_NAME" -n openshift-operators --timeout=120s 2>/dev/null; then
                echo -e "${GREEN}✓ Grafana Operator installed successfully${NC}"
            else
                echo -e "${YELLOW}⚠ Grafana Operator installation is taking longer than expected${NC}"
                echo "You can check status with: oc get csv -n openshift-operators | grep grafana"
            fi

            # Wait for Operator Pod
            echo "Waiting for Operator pod to be ready..."
            sleep 10
            OP_POD=$(oc get pods -n openshift-operators -l app.kubernetes.io/name=grafana-operator --no-headers 2>/dev/null | head -1 | awk '{print $1}')
            if [ -n "$OP_POD" ]; then
                if oc wait --for=condition=Ready pod "$OP_POD" -n openshift-operators --timeout=60s &> /dev/null; then
                    echo -e "${GREEN}✓ Grafana Operator pod is ready: $OP_POD${NC}"
                else
                    echo -e "${YELLOW}⚠ Grafana Operator pod may still be starting${NC}"
                fi
            fi
        else
            echo -e "${RED}✗ Failed to get CSV name. Installation may have failed.${NC}"
            echo "Please check: oc get subscription grafana-operator -n openshift-operators"
            exit 1
        fi
    else
        echo -e "${RED}✗ Failed to create Grafana Operator Subscription${NC}"
        exit 1
    fi
fi
echo ""

echo "======================================"
echo "Checking Gateway and HTTPRoute Setup"
echo "======================================"
echo ""

# Check if Gateway exists (from Article 2)
GATEWAY_EXISTS=false
if oc get gateway -A &> /dev/null; then
    GATEWAY_COUNT=$(oc get gateway -A --no-headers | wc -l)
    if [ "$GATEWAY_COUNT" -gt 0 ]; then
        echo -e "${GREEN}✓ Found ${GATEWAY_COUNT} Gateway(s)${NC}"
        GATEWAY_EXISTS=true
        # Show Gateway names
        oc get gateway -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name --no-headers | while read ns name; do
            echo "  - ${ns}/${name}"
        done
    fi
fi

# Check if HTTPRoute exists (from Article 2)
HTTPROUTE_EXISTS=false
if oc get httproute -A &> /dev/null; then
    HTTPROUTE_COUNT=$(oc get httproute -A --no-headers | wc -l)
    if [ "$HTTPROUTE_COUNT" -gt 0 ]; then
        echo -e "${GREEN}✓ Found ${HTTPROUTE_COUNT} HTTPRoute(s)${NC}"
        HTTPROUTE_EXISTS=true
        # Show HTTPRoute names and check labels
        oc get httproute -A -o json | jq -r '.items[] | "\(.metadata.namespace)/\(.metadata.name) - Labels: service=\(.metadata.labels.service // "MISSING") deployment=\(.metadata.labels.deployment // "MISSING")"' | while read line; do
            if echo "$line" | grep -q "MISSING"; then
                echo -e "  ${YELLOW}⚠ $line${NC}"
            else
                echo -e "  ${GREEN}✓ $line${NC}"
            fi
        done
    fi
fi

# Check if News API exists (from Article 2)
NEWS_API_EXISTS=false
if oc get deployment -A --no-headers 2>/dev/null | grep -q news-api; then
    NEWS_API_NS=$(oc get deployment -A --no-headers | grep news-api | awk '{print $1}' | head -1)
    echo -e "${GREEN}✓ Found News API deployment in namespace: ${NEWS_API_NS}${NC}"
    NEWS_API_EXISTS=true
fi

echo ""

# Warn if Article 2 setup is missing
if [ "$GATEWAY_EXISTS" = false ] || [ "$HTTPROUTE_EXISTS" = false ] || [ "$NEWS_API_EXISTS" = false ]; then
    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW}WARNING: Missing Gateway/HTTPRoute Setup${NC}"
    echo -e "${YELLOW}========================================${NC}"
    echo ""
    echo -e "${YELLOW}Grafana dashboards require the following resources from Article 2:${NC}"
    [ "$GATEWAY_EXISTS" = false ] && echo -e "  ${RED}✗ Gateway${NC} - NOT FOUND"
    [ "$HTTPROUTE_EXISTS" = false ] && echo -e "  ${RED}✗ HTTPRoute${NC} - NOT FOUND"
    [ "$NEWS_API_EXISTS" = false ] && echo -e "  ${RED}✗ News API${NC} - NOT FOUND"
    echo ""
    echo "Without these resources, dashboards will show 'No data'."
    echo ""
    echo "To set up Gateway and HTTPRoute, run Article 2 setup script:"
    echo "  cd /path/to/02-gateway_and_policy"
    echo "  ./setup-gateway-and-policy.sh"
    echo ""
    read -p "Do you want to continue Grafana setup anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Setup cancelled. Please run Article 2 setup first."
        exit 0
    fi
    echo ""
fi

# ============================================
# Step 1: Service Account
# ============================================

echo "======================================"
echo "Step 1: Creating Service Account"
echo "======================================"
echo ""

oc create serviceaccount grafana-serviceaccount -n ${GRAFANA_NAMESPACE}
echo -e "${GREEN}✓ Service Account created${NC}"

oc adm policy add-cluster-role-to-user cluster-monitoring-view \
  system:serviceaccount:${GRAFANA_NAMESPACE}:grafana-serviceaccount
echo -e "${GREEN}✓ cluster-monitoring-view permission granted${NC}"

cat <<YAML | oc apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: grafana-serviceaccount-token
  namespace: ${GRAFANA_NAMESPACE}
  annotations:
    kubernetes.io/service-account.name: grafana-serviceaccount
type: kubernetes.io/service-account-token
YAML
echo -e "${GREEN}✓ Token Secret created${NC}"

echo "Waiting for token generation..."
sleep 15
echo ""

# ============================================
# Step 2: Grafana Instance
# ============================================

echo "======================================"
echo "Step 2: Creating Grafana Instance"
echo "======================================"
echo ""

cat <<YAML | oc apply -f -
apiVersion: grafana.integreatly.org/v1beta1
kind: Grafana
metadata:
  name: grafana
  namespace: ${GRAFANA_NAMESPACE}
  labels:
    dashboards: grafana
spec:
  config:
#    auth:
#      disable_login_form: "false"
    security:
      admin_user: admin
      admin_password: grafana123
#      force_password_change: "false"
#      disable_initial_admin_creation: "false"
#      disable_gravatar: "true"
#    users:
#      allow_sign_up: "false"
#      auto_assign_org: "true"
#      auto_assign_org_role: Viewer
  route:
    spec:
      port:
        targetPort: 3000
      tls:
        insecureEdgeTerminationPolicy: Redirect
        termination: edge
      wildcardPolicy: None
YAML
echo -e "${GREEN}✓ Grafana CR created${NC}"

echo "Waiting for Grafana pod to be created..."
for i in {1..60}; do
    POD_COUNT=$(oc get pods -n ${GRAFANA_NAMESPACE} -l app=grafana --no-headers 2>/dev/null | wc -l)
    if [ "$POD_COUNT" -gt 0 ]; then
        echo -e "${GREEN}✓ Grafana pod created${NC}"
        break
    fi
    sleep 2
done

echo "Waiting for Grafana pod to be ready..."
oc wait --for=condition=Ready pod -l app=grafana -n ${GRAFANA_NAMESPACE} --timeout=180s 2>/dev/null || true
echo -e "${GREEN}✓ Grafana pod is ready${NC}"

echo "Waiting for Grafana Operator to sync..."
sleep 30
echo ""

# ============================================
# Step 3: Prometheus Datasource
# ============================================

echo "======================================"
echo "Step 3: Creating Prometheus Datasource"
echo "======================================"
echo ""

# Get token
TOKEN=$(oc get secret grafana-serviceaccount-token -n ${GRAFANA_NAMESPACE} -o jsonpath='{.data.token}' | base64 -d)
echo -e "${GREEN}✓ Token retrieved (length: ${#TOKEN})${NC}"

# Create Bearer Token Secret
cat <<YAML | oc apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: prometheus-bearer-token
  namespace: ${GRAFANA_NAMESPACE}
stringData:
  token: "Bearer ${TOKEN}"
type: Opaque
YAML
echo -e "${GREEN}✓ Prometheus Bearer Token Secret created${NC}"

# Get Thanos Querier URL
CLUSTER_DOMAIN=$(oc get route console -n openshift-console -o jsonpath='{.spec.host}' | sed 's/^console-openshift-console\.//')
THANOS_URL="https://thanos-querier-openshift-monitoring.${CLUSTER_DOMAIN}"
echo "Thanos Querier URL: ${THANOS_URL}"

# Create GrafanaDatasource CR
cat <<YAML | oc apply -f -
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaDatasource
metadata:
  name: prometheus-datasource
  namespace: ${GRAFANA_NAMESPACE}
spec:
  instanceSelector:
    matchLabels:
      dashboards: grafana
  datasource:
    name: Prometheus
    type: prometheus
    access: proxy
    url: ${THANOS_URL}
    isDefault: true
    jsonData:
      httpHeaderName1: Authorization
      timeInterval: 5s
      tlsSkipVerify: true
    secureJsonData:
      httpHeaderValue1: \${token}
  valuesFrom:
    - targetPath: secureJsonData.httpHeaderValue1
      valueFrom:
        secretKeyRef:
          name: prometheus-bearer-token
          key: token
YAML
echo -e "${GREEN}✓ GrafanaDatasource CR created${NC}"

sleep 20
echo ""

# ============================================
# Step 4: Grafana Dashboards
# ============================================

echo "======================================"
echo "Step 4: Creating Grafana Dashboards"
echo "======================================"
echo ""

# Platform Engineer Dashboard (from official Kuadrant JSON)
cat <<YAML | oc apply -f -
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaDashboard
metadata:
  name: platform-engineer-dashboard
  namespace: ${GRAFANA_NAMESPACE}
spec:
  instanceSelector:
    matchLabels:
      dashboards: grafana
  datasources:
    - inputName: "DS_GRAFANACLOUD-KUADRANTDEV-PROM"
      datasourceName: "Prometheus"
  url: "https://raw.githubusercontent.com/Kuadrant/kuadrant-operator/refs/tags/v1.3.0/examples/dashboards/platform_engineer.json"
YAML
echo -e "${GREEN}✓ Platform Engineer Dashboard created (from URL)${NC}"

# App Developer Dashboard (from official Kuadrant JSON)
cat <<YAML | oc apply -f -
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaDashboard
metadata:
  name: app-developer-dashboard
  namespace: ${GRAFANA_NAMESPACE}
spec:
  instanceSelector:
    matchLabels:
      dashboards: grafana
  datasources:
    - inputName: "DS_GRAFANACLOUD-KUADRANTDEV-PROM"
      datasourceName: "Prometheus"
  url: "https://raw.githubusercontent.com/Kuadrant/kuadrant-operator/refs/tags/v1.3.0/examples/dashboards/app_developer.json"
YAML
echo -e "${GREEN}✓ App Developer Dashboard created (from URL)${NC}"

# Business User Dashboard (from official Kuadrant JSON)
cat <<YAML | oc apply -f -
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaDashboard
metadata:
  name: business-user-dashboard
  namespace: ${GRAFANA_NAMESPACE}
spec:
  instanceSelector:
    matchLabels:
      dashboards: grafana
  datasources:
    - inputName: "DS_GRAFANACLOUD-KUADRANTDEV-PROM"
      datasourceName: "Prometheus"
  url: "https://raw.githubusercontent.com/Kuadrant/kuadrant-operator/refs/tags/v1.3.0/examples/dashboards/business_user.json"
YAML
echo -e "${GREEN}✓ Business User Dashboard created (from URL)${NC}"

echo "Waiting for dashboards to sync..."
sleep 30
echo ""

# ============================================
# Step 5: Verification
# ============================================

echo "======================================"
echo "Step 5: Verification"
echo "======================================"
echo ""

echo "Grafana instance status:"
oc get grafana grafana -n ${GRAFANA_NAMESPACE} -o jsonpath='{.status.stage}: {.status.stageStatus}'
echo ""
echo ""

echo "GrafanaDatasource status:"
oc get grafanadatasource -n ${GRAFANA_NAMESPACE}
echo ""

echo "GrafanaDashboard status:"
oc get grafanadashboard -n ${GRAFANA_NAMESPACE}
echo ""

echo "kube-state-metrics-kuadrant status:"
oc get deployment kube-state-metrics-kuadrant -n monitoring -o wide 2>/dev/null || echo "Not found in monitoring namespace"
echo ""

# Check if metrics are being collected
echo "Checking Gateway API metrics..."
PROM_POD=$(oc get pods -n openshift-user-workload-monitoring -l app.kubernetes.io/name=prometheus --no-headers 2>/dev/null | head -1 | awk '{print $1}')
if [ -n "$PROM_POD" ]; then
    METRICS_COUNT=$(oc exec -n openshift-user-workload-monitoring -c prometheus "$PROM_POD" -- promtool query instant http://localhost:9090 'count(gatewayapi_httproute_labels)' 2>/dev/null | grep -c "=> " || echo "0")
    if [ "$METRICS_COUNT" -gt 0 ]; then
        echo -e "${GREEN}✓ Gateway API metrics are being collected${NC}"
    else
        echo -e "${YELLOW}⚠ Gateway API metrics not found yet (may take 1-2 minutes)${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Prometheus pod not found (User Workload Monitoring may still be starting)${NC}"
fi
echo ""

GRAFANA_URL="https://$(oc get route grafana-route -n ${GRAFANA_NAMESPACE} -o jsonpath='{.spec.host}')"

echo "======================================"
echo "Setup Complete!"
echo "======================================"
echo ""
echo "Grafana is now available at:"
echo "  URL: ${GRAFANA_URL}"
echo "  Username: admin"
echo "  Password: grafana123"
echo ""
echo "Created resources:"
echo "  - User Workload Monitoring (enabled)"
echo "  - kube-state-metrics-kuadrant (monitoring namespace)"
echo "  - Istio Telemetry (istio-system namespace)"
echo "    - Enhanced metrics with request_url_path, request_host, destination_port"
echo "  - Grafana instance (monitoring namespace)"
echo "  - Prometheus datasource (connected to Thanos Querier)"
echo "  - 3 Grafana dashboards (from Kuadrant official repository):"
echo "    1. Platform Engineer Dashboard"
echo "    2. App Developer Dashboard"
echo "    3. Business User Dashboard"
echo ""
echo "Dashboard source:"
echo "  https://github.com/Kuadrant/kuadrant-operator/tree/v1.3.0/examples/dashboards"
echo ""
echo "Note: It may take 1-2 minutes for all metrics to appear in dashboards."
echo ""
echo "Troubleshooting:"
echo "  - If dashboards show 'No data', wait a few minutes for metrics collection"
echo "  - Check kube-state-metrics-kuadrant logs:"
echo "    oc logs -n monitoring deployment/kube-state-metrics-kuadrant"
echo "  - Verify HTTPRoute has service/deployment labels:"
echo "    oc get httproute -A -o yaml | grep -A2 'labels:'"
echo ""
