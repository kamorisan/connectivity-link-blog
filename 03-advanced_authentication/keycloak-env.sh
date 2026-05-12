#!/bin/bash
# Keycloak environment variables
export KEYCLOAK_URL="https://keycloak.apps.cluster-7kc8k.7kc8k.sandbox1106.opentlc.com"
export KEYCLOAK_REALM="news-api-realm"
export KEYCLOAK_ADMIN_USER="temp-admin"
export KEYCLOAK_ADMIN_PASSWORD="b964ee10f46a486394a1a2781c556b98"
export KUADRANT_ZONE_ROOT_DOMAIN="apps.cluster-7kc8k.7kc8k.sandbox1106.opentlc.com"
export KUADRANT_DEVELOPER_NS="news-api"
export KUADRANT_GATEWAY_NAME="external"

# Client credentials (added by import-realm.sh)
export CLIENT_SECRET="ThqqY7nh16ACWtjrGpaXc0Asw54Lj0Vh"
