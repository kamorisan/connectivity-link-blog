#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "======================================"
echo "Token-based Rate Limiting Setup"
echo "Red Hat Connectivity Link - Article 5"
echo "======================================"
echo ""

# Check prerequisites
echo "======================================"
echo "Checking Prerequisites"
echo "======================================"
echo ""

# Check if oc is installed
if ! command -v oc &> /dev/null; then
    echo -e "${RED}✗ OpenShift CLI (oc) is not installed${NC}"
    exit 1
fi
echo -e "${GREEN}✓ OpenShift CLI (oc) found${NC}"

# Check if logged in to OpenShift
if ! oc whoami &> /dev/null; then
    echo -e "${RED}✗ Not logged in to OpenShift${NC}"
    echo "Please run: oc login"
    exit 1
fi
echo -e "${GREEN}✓ Logged in to OpenShift as $(oc whoami)${NC}"

# Check if Kuadrant is installed
if ! oc get kuadrant -n kuadrant-system &> /dev/null; then
    echo -e "${RED}✗ Kuadrant is not installed${NC}"
    echo "Please install Red Hat Connectivity Link first (see Article 1)"
    exit 1
fi
echo -e "${GREEN}✓ Kuadrant is installed${NC}"

echo ""

# Create llm-api namespace
echo "======================================"
echo "Step 1: Creating LLM API Namespace"
echo "======================================"
echo ""

if oc get namespace llm-api &> /dev/null; then
    echo -e "${YELLOW}⚠ Namespace llm-api already exists${NC}"
    read -p "Delete and recreate? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        oc delete namespace llm-api
        echo "Waiting for namespace deletion..."
        while oc get namespace llm-api &> /dev/null; do
            sleep 2
        done
        oc create namespace llm-api
        echo -e "${GREEN}✓ Namespace llm-api recreated${NC}"
    else
        echo "Using existing namespace llm-api"
    fi
else
    oc create namespace llm-api
    echo -e "${GREEN}✓ Namespace llm-api created${NC}"
fi

echo ""

# Deploy Mock LLM API
echo "======================================"
echo "Step 2: Deploying Mock LLM API"
echo "======================================"
echo ""

cat <<EOF | oc apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: mock-llm-api
  namespace: llm-api
data:
  app.py: |
    from flask import Flask, request, jsonify
    import random
    import time

    app = Flask(__name__)

    @app.route('/v1/chat/completions', methods=['POST'])
    def chat_completions():
        data = request.get_json(silent=True) or {}
        messages = data.get('messages', [])
        max_tokens = data.get('max_tokens', 100)

        # プロンプトトークン数を推定（簡易的に文字数/4）
        prompt_text = ' '.join([m.get('content', '') for m in messages])
        prompt_tokens = len(prompt_text) // 4

        # 出力トークン数（max_tokensの70-90%をランダムに使用）
        completion_tokens = int(max_tokens * random.uniform(0.7, 0.9))

        response = {
            "id": f"chatcmpl-{random.randint(1000000, 9999999)}",
            "object": "chat.completion",
            "created": int(time.time()),
            "model": data.get('model', 'mock-llm'),
            "choices": [{
                "index": 0,
                "message": {
                    "role": "assistant",
                    "content": "This is a mock response from the LLM API."
                },
                "finish_reason": "stop"
            }],
            "usage": {
                "prompt_tokens": prompt_tokens,
                "completion_tokens": completion_tokens,
                "total_tokens": prompt_tokens + completion_tokens
            }
        }
        return jsonify(response)

    if __name__ == '__main__':
        app.run(host='0.0.0.0', port=8080)
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mock-llm-api
  namespace: llm-api
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mock-llm-api
  template:
    metadata:
      labels:
        app: mock-llm-api
    spec:
      containers:
      - name: api
        image: python:3.11-slim
        command:
        - /bin/sh
        - -c
        - |
          pip install --target=/packages flask && \
          PYTHONPATH=/packages python /app/app.py
        ports:
        - containerPort: 8080
        volumeMounts:
        - name: app
          mountPath: /app
        - name: packages
          mountPath: /packages
      volumes:
      - name: app
        configMap:
          name: mock-llm-api
      - name: packages
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: mock-llm-api
  namespace: llm-api
spec:
  selector:
    app: mock-llm-api
  ports:
  - port: 8080
    targetPort: 8080
EOF

echo -e "${GREEN}✓ Mock LLM API resources created${NC}"

# Wait for pod to be ready
echo "Waiting for Mock LLM API pod to be ready..."
oc wait --for=condition=ready pod -l app=mock-llm-api -n llm-api --timeout=120s

POD_NAME=$(oc get pods -n llm-api -l app=mock-llm-api -o jsonpath='{.items[0].metadata.name}')
echo -e "${GREEN}✓ Mock LLM API is ready${NC}"
echo -e "${GREEN}✓ Pod: $POD_NAME${NC}"

echo ""

# Create llm-gateway namespace
echo "======================================"
echo "Step 3: Creating Gateway Namespace"
echo "======================================"
echo ""

if oc get namespace llm-gateway &> /dev/null; then
    echo -e "${YELLOW}⚠ Namespace llm-gateway already exists${NC}"
    read -p "Delete and recreate? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        oc delete namespace llm-gateway
        echo "Waiting for namespace deletion..."
        while oc get namespace llm-gateway &> /dev/null; do
            sleep 2
        done
        oc create namespace llm-gateway
        echo -e "${GREEN}✓ Namespace llm-gateway recreated${NC}"
    else
        echo "Using existing namespace llm-gateway"
    fi
else
    oc create namespace llm-gateway
    echo -e "${GREEN}✓ Namespace llm-gateway created${NC}"
fi

echo ""

# Create Gateway
echo "======================================"
echo "Step 4: Creating Gateway"
echo "======================================"
echo ""

cat <<EOF | oc apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: llm-gateway
  namespace: llm-gateway
spec:
  gatewayClassName: istio
  listeners:
  - name: http
    hostname: "*.llm-api.local"
    port: 80
    protocol: HTTP
    allowedRoutes:
      namespaces:
        from: All
EOF

echo -e "${GREEN}✓ Gateway created${NC}"

# Wait for Gateway to be ready
echo "Waiting for Gateway to be ready..."
sleep 5
GATEWAY_STATUS=$(oc get gateway llm-gateway -n llm-gateway -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}')
if [ "$GATEWAY_STATUS" == "True" ]; then
    echo -e "${GREEN}✓ Gateway is ready${NC}"
else
    echo -e "${YELLOW}⚠ Gateway may not be fully ready yet (this is normal)${NC}"
fi

echo ""

# Create HTTPRoute
echo "======================================"
echo "Step 5: Creating HTTPRoute"
echo "======================================"
echo ""

cat <<EOF | oc apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: llm-api
  namespace: llm-api
  labels:
    service: mock-llm-api
    deployment: mock-llm-api
spec:
  parentRefs:
  - name: llm-gateway
    namespace: llm-gateway
  hostnames:
  - "api.llm-api.local"
  rules:
  - matches:
    - method: POST
      path:
        type: PathPrefix
        value: "/v1/chat/completions"
    backendRefs:
    - name: mock-llm-api
      port: 8080
EOF

echo -e "${GREEN}✓ HTTPRoute created${NC}"

# Wait for HTTPRoute to be accepted
echo "Waiting for HTTPRoute to be accepted..."
sleep 5
ROUTE_STATUS=$(oc get httproute llm-api -n llm-api -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].status}')
if [ "$ROUTE_STATUS" == "True" ]; then
    echo -e "${GREEN}✓ HTTPRoute is accepted${NC}"
else
    echo -e "${YELLOW}⚠ HTTPRoute may not be fully ready yet${NC}"
fi

echo ""

# Create TokenRateLimitPolicy
echo "======================================"
echo "Step 6: Creating TokenRateLimitPolicy"
echo "======================================"
echo ""

cat <<EOF | oc apply -f -
apiVersion: kuadrant.io/v1alpha1
kind: TokenRateLimitPolicy
metadata:
  name: llm-api-token-limit
  namespace: llm-api
spec:
  targetRef:
    group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: llm-api
  limits:
    token-limit:
      rates:
      - limit: 1000
        window: 1m
      counters:
      - expression: "1"
EOF

echo -e "${GREEN}✓ TokenRateLimitPolicy created${NC}"

echo ""

# Verification
echo "======================================"
echo "Step 7: Verification"
echo "======================================"
echo ""

echo "Resources created:"
echo ""

echo "Gateway:"
oc get gateway llm-gateway -n llm-gateway

echo ""
echo "HTTPRoute:"
oc get httproute llm-api -n llm-api

echo ""
echo "TokenRateLimitPolicy:"
oc get tokenratelimitpolicy llm-api-token-limit -n llm-api

echo ""
echo "Mock LLM API Deployment:"
oc get deployment mock-llm-api -n llm-api

echo ""

# Display next steps
echo "======================================"
echo "Setup Complete!"
echo "======================================"
echo ""

echo "Next steps:"
echo ""
echo "1. Test the Mock LLM API with port-forward:"
echo "   oc port-forward -n llm-gateway service/llm-gateway-istio 8080:80"
echo ""
echo "2. In another terminal, send a test request:"
echo "   curl -X POST http://localhost:8080/v1/chat/completions \\"
echo "     -H \"Host: api.llm-api.local\" \\"
echo "     -H \"Content-Type: application/json\" \\"
echo "     -d '{"
echo "       \"model\": \"mock-llm\","
echo "       \"messages\": ["
echo "         {\"role\": \"user\", \"content\": \"What is OpenShift?\"}"
echo "       ],"
echo "       \"max_tokens\": 200"
echo "     }' | jq ."
echo ""
echo "3. Test rate limiting by sending multiple requests:"
echo "   for i in {1..10}; do"
echo "     echo \"=== Request \$i ===\";"
echo "     response=\$(curl -s -X POST http://localhost:8080/v1/chat/completions \\"
echo "       -H \"Host: api.llm-api.local\" \\"
echo "       -H \"Content-Type: application/json\" \\"
echo "       -d '{\"model\": \"mock-llm\", \"messages\": [{\"role\": \"user\", \"content\": \"What is OpenShift?\"}], \"max_tokens\": 200}');"
echo "     echo \"\$response\" | jq -r '.usage.total_tokens' 2>/dev/null || echo \"\$response\";"
echo "     sleep 1;"
echo "   done"
echo ""
echo "4. Check token consumption metrics in OpenShift Web Console:"
echo "   Observe > Metrics > Query:"
echo "   authorized_hits{limitador_namespace=\"llm-api/llm-api\"}"
echo ""
echo "Rate limiting settings:"
echo "  - Token limit: 1000 tokens per minute"
echo "  - Counter: All requests share the same counter (expression: \"1\")"
echo ""
echo "Note: For production use, integrate with AuthPolicy to use per-user counters."
echo ""
