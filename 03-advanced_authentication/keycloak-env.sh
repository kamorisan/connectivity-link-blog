#!/bin/bash
# Keycloak environment variables
export KEYCLOAK_URL="https://keycloak.apps.cluster-lw2fp.lw2fp.sandbox2972.opentlc.com"
export KEYCLOAK_REALM="news-api-realm"
export KEYCLOAK_ADMIN_USER="temp-admin"
export KEYCLOAK_ADMIN_PASSWORD="b6d9701928784e4690b7ea367145ffe4"
export KUADRANT_ZONE_ROOT_DOMAIN="apps.cluster-lw2fp.lw2fp.sandbox2972.opentlc.com"
export KUADRANT_DEVELOPER_NS="news-api"
export KUADRANT_GATEWAY_NAME="external"

# Client credentials (added by import-realm.sh)
export CLIENT_SECRET="ThqqY7nh16ACWtjrGpaXc0Asw54Lj0Vh"
