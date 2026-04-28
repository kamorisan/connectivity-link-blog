# Red Hat Connectivity Link - Gateway and Policy セットアップツール

このディレクトリには、Red Hat Connectivity Link第2回記事「GatewayとPolicyの基本設定」で扱う全リソースを自動的にセットアップするためのスクリプトが含まれています。

## 📋 目次

- [前提条件](#前提条件)
- [ファイル構成](#ファイル構成)
- [クイックスタート](#クイックスタート)
- [セットアップ内容](#セットアップ内容)
- [トラブルシューティング](#トラブルシューティング)

## 前提条件

### 必須

| 項目 | 要件 |
|------|------|
| **Red Hat Connectivity Link** | インストール済み（第1回記事参照） |
| **OpenShift Container Platform** | 4.19以降 |
| **OpenShift Service Mesh 3** | インストール済み |
| **cert-manager** | Connectivity Linkで自動インストール済み |
| **AWS アカウント** | Route 53のHosted Zone設定済み |
| **oc CLI** | インストール済み |

### AWS Route 53 要件

- **Hosted Zone**: セットアップ済みのドメイン
- **AWS Access Key ID**: Route 53への書き込み権限
- **AWS Secret Access Key**: Route 53への書き込み権限

> **注**: Google Cloud DNS、Azure DNS、またはオンプレミスCoreDNSを使用する場合は、環境変数とYAML設定を適宜調整してください。

## ファイル構成

```
02-gateway_and_policy/
├── setup-gateway-and-policy.sh      # セットアップスクリプト
├── cleanup-gateway-and-policy.sh    # クリーンアップスクリプト
└── README.md                        # このファイル
```

## クイックスタート

### 1. 環境変数の設定

```bash
# 必須環境変数
export KUADRANT_GATEWAY_NS=api-gateway
export KUADRANT_GATEWAY_NAME=external
export KUADRANT_DEVELOPER_NS=news-api
export KUADRANT_AWS_ACCESS_KEY_ID=<your-aws-access-key>
export KUADRANT_AWS_SECRET_ACCESS_KEY=<your-aws-secret-key>
export KUADRANT_ZONE_ROOT_DOMAIN=<your-route53-domain>  # 例: sandbox1479.opentlc.com
export KUADRANT_CLUSTER_ISSUER_NAME=letsencrypt-prod
export KUADRANT_AWS_REGION=<your-aws-region>  # 例: us-east-2
export KUADRANT_LETSENCRYPT_EMAIL=<your-email>
```

**環境変数の説明**:

| 変数名 | 説明 | 例 |
|--------|------|-----|
| `KUADRANT_GATEWAY_NS` | Gatewayを配置するネームスペース | `api-gateway` |
| `KUADRANT_GATEWAY_NAME` | Gateway名 | `external` |
| `KUADRANT_DEVELOPER_NS` | アプリケーションを配置するネームスペース | `news-api` |
| `KUADRANT_AWS_ACCESS_KEY_ID` | AWS Access Key ID | `AKIA...` |
| `KUADRANT_AWS_SECRET_ACCESS_KEY` | AWS Secret Access Key | `wJalr...` |
| `KUADRANT_ZONE_ROOT_DOMAIN` | Route 53のHosted Zone | `sandbox1479.opentlc.com` |
| `KUADRANT_CLUSTER_ISSUER_NAME` | ClusterIssuer名 | `letsencrypt-prod` |
| `KUADRANT_AWS_REGION` | AWSリージョン | `us-east-2` |
| `KUADRANT_LETSENCRYPT_EMAIL` | Let's Encrypt通知用メール | `admin@example.com` |

### 2. セットアップの実行

```bash
./setup-gateway-and-policy.sh
```

**所要時間**: 約3〜5分（DNS伝播とTLS証明書発行を除く）

**完了後の出力例**:
```
======================================
Setup Complete!
======================================

Gateway and Policy resources have been successfully created.

Created resources:
  1. Namespaces:
     - api-gateway (Gateway)
     - news-api (Application)

  2. Application:
     - News API Deployment and Service

  3. DNS and TLS:
     - AWS Credentials Secrets
     - ClusterIssuer: letsencrypt-prod

  4. Gateway API:
     - Gateway: external
     - HTTPRoute: news-api

  5. Gateway-level Policies:
     - TLSPolicy: external-tls
     - DNSPolicy: external-dnspolicy (health checks disabled for initial setup)
     - AuthPolicy: external-auth (deny-all by default)
     - RateLimitPolicy: external-rlp (5 req/10s)
  
  6. HTTPRoute-level Policies (overrides):
     - API Keys Secret: api-keys
     - AuthPolicy: news-api-auth (API key authentication)
     - RateLimitPolicy: news-api-ratelimit (10 req/min per user)

API Endpoint:
  https://api.sandbox1479.opentlc.com/
```

### 3. 動作確認

#### DNS解決の確認

```bash
nslookup api.${KUADRANT_ZONE_ROOT_DOMAIN}
```

**期待される出力**:
```
Server:         192.168.1.1
Address:        192.168.1.1#53

Non-authoritative answer:
api.sandbox1479.opentlc.com     canonical name = klb.api.sandbox1479.opentlc.com.
klb.api.sandbox1479.opentlc.com canonical name = geo-na.klb.api.sandbox1479.opentlc.com.
...
```

#### APIアクセステスト

HTTPRouteレベルのAuthPolicyでAPI Key認証が設定されているため、認証が必要です。

**API Keyなしでアクセス（401エラー）**:

```bash
curl -k https://api.${KUADRANT_ZONE_ROOT_DOMAIN}/technology
```

**期待される出力**:
```json
{
  "error": "Unauthenticated",
  "message": "Valid API key is required. Use header: Authorization: APIKEY <your-key>"
}
```

**API Keyありでアクセス（成功）**:

```bash
curl -k -H "Authorization: APIKEY secret-key-12345" \
  https://api.${KUADRANT_ZONE_ROOT_DOMAIN}/technology
```

**期待される出力**:
```json
[]
```

空の配列が返されます。まだ記事が投稿されていないためです。

**記事の投稿テスト**:

```bash
curl -k -X POST \
  -H "Authorization: APIKEY secret-key-12345" \
  -H "Content-Type: application/json" \
  -d '{"title":"Test Article","content":"This is a test"}' \
  https://api.${KUADRANT_ZONE_ROOT_DOMAIN}/technology
```

**レート制限のテスト**:

HTTPRouteレベルのRateLimitPolicyにより、1分あたり10リクエストの制限があります:

```bash
for i in {1..15}; do 
  curl -k -H "Authorization: APIKEY secret-key-12345" \
    --write-out " - Response: %{http_code}\n" --silent --output /dev/null \
    "https://api.$KUADRANT_ZONE_ROOT_DOMAIN/technology"
  sleep 0.5
done
```

最初の10リクエストは200で成功し、11回目以降は429 (Too Many Requests) が返されます。

### 4. クリーンアップ（必要に応じて）

```bash
./cleanup-gateway-and-policy.sh
```

**警告**: このスクリプトは以下をすべて削除します:
- ⚠️ HTTPRouteレベルのPolicies（AuthPolicy、RateLimitPolicy）
- ⚠️ GatewayレベルのPolicies（TLSPolicy、DNSPolicy、AuthPolicy、RateLimitPolicy）
- ⚠️ Gateway と HTTPRoute
- ⚠️ News API アプリケーション
- ⚠️ ネームスペース（`api-gateway`, `news-api`）
- ⚠️ Secrets（API Keys、AWS Credentials）
- ⚠️ ClusterIssuer

## セットアップ内容

### ステップ1: ネームスペースの作成

- **Gateway namespace** (`api-gateway`): Gatewayと各種Policyを配置
- **Developer namespace** (`news-api`): アプリケーションとHTTPRouteを配置

### ステップ2: News APIアプリケーションのデプロイ

News APIは、Kuadrantコミュニティが提供するサンプルRESTful APIです。

**提供されるエンドポイント**:
- `POST /{category}` - 記事の作成
- `GET /{category}` - 記事一覧の取得
- `GET /{category}/{id}` - 特定の記事の取得
- `DELETE /{category}/{id}` - 記事の削除

**イメージ**: `quay.io/kuadrant/authorino-examples:news-api`

### ステップ3: AWS Credentials Secretsの作成

以下の2つのSecretを作成します:

1. **Gateway namespace用** (`api-gateway`): DNSPolicyで使用
2. **cert-manager namespace用**: TLS証明書のDNS-01チャレンジで使用

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: aws-credentials
type: kuadrant.io/aws
data:
  AWS_ACCESS_KEY_ID: <base64-encoded>
  AWS_SECRET_ACCESS_KEY: <base64-encoded>
```

### ステップ4: ClusterIssuerの作成

Let's EncryptでTLS証明書を発行するためのClusterIssuerを作成します。

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: <your-email>
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - dns01:
        route53:
          region: <your-aws-region>
          accessKeyIDSecretRef:
            name: aws-credentials
            key: AWS_ACCESS_KEY_ID
          secretAccessKeySecretRef:
            name: aws-credentials
            key: AWS_SECRET_ACCESS_KEY
```

**DNS-01チャレンジ**: AWS Route 53を使用してドメイン所有権を検証します。

### ステップ5: Gatewayの作成

Kubernetes Gateway APIを使用して、外部トラフィックの入口を定義します。

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: external
  namespace: api-gateway
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
      - name: api-external-tls
        kind: Secret
```

**重要な設定**:
- `gatewayClassName: istio` - OpenShift Service Mesh 3を使用
- `allowedRoutes.namespaces.from: All` - すべてのnamespaceからのHTTPRouteを許可
- `tls.mode: Terminate` - GatewayでTLSを終端

### ステップ6: TLSPolicyの適用

GatewayのHTTPSリスナーに自動的にTLS証明書を発行・更新します。

```yaml
apiVersion: kuadrant.io/v1
kind: TLSPolicy
metadata:
  name: external-tls
  namespace: api-gateway
spec:
  targetRef:
    name: external
    group: gateway.networking.k8s.io
    kind: Gateway
  issuerRef:
    group: cert-manager.io
    kind: ClusterIssuer
    name: letsencrypt-prod
```

**動作**:
- Gatewayのリスナーからホスト名を検出
- cert-managerを使用してTLS証明書を自動発行
- 証明書の自動更新（Let's Encryptは90日間有効）

> **注**: 初回の証明書発行には数分かかる場合があります。

### ステップ7: HTTPRouteの作成

Gatewayを通じてNews APIへトラフィックをルーティングします。

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: news-api
  namespace: news-api
spec:
  parentRefs:
  - name: external
    namespace: api-gateway
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
```

**クロスネームスペース参照**: HTTPRouteは`news-api`ネームスペースにありながら、`api-gateway`ネームスペースのGatewayを参照できます。

### ステップ8: DNSPolicyの適用

AWS Route 53にDNSレコードを自動的に作成し、地理的ロードバランシングを設定します。

```yaml
apiVersion: kuadrant.io/v1
kind: DNSPolicy
metadata:
  name: external-dnspolicy
  namespace: api-gateway
spec:
  targetRef:
    name: external
    group: gateway.networking.k8s.io
    kind: Gateway
  loadBalancing:
    defaultGeo: true
    geo: GEO-NA
    weight: 120
  providerRefs:
  - name: aws-credentials
```

> **注**: ヘルスチェックは初期セットアップでは無効化されています。ヘルスチェックを有効にするとDNSレコードが未作成の状態でヘルスチェックが失敗し、レコードが作成されない循環依存が発生するためです。本番環境では、DNS伝播後にヘルスチェックを追加することを推奨します。

**作成されるDNSレコード**:
- `api.${KUADRANT_ZONE_ROOT_DOMAIN}` → CNAME → `klb.api.${KUADRANT_ZONE_ROOT_DOMAIN}`
- `klb.api.${KUADRANT_ZONE_ROOT_DOMAIN}` → CNAME → `geo-na.klb.api.${KUADRANT_ZONE_ROOT_DOMAIN}`
- `geo-na.klb.api.${KUADRANT_ZONE_ROOT_DOMAIN}` → CNAME → AWS ELB

**地理的ロードバランシング**:
- `GEO-NA` (北米): `us-east-*`, `us-west-*`, `ca-central-*`
- `GEO-EU` (ヨーロッパ): `eu-west-*`, `eu-central-*`, `eu-north-*`
- `GEO-AP` (アジア太平洋): `ap-northeast-*`, `ap-southeast-*`, `ap-south-*`

**ヘルスチェックについて**:
初期セットアップではヘルスチェックを無効化しています。ヘルスチェックを有効にすると、DNS未作成時にヘルスチェックが失敗してレコードが作成されない循環依存が発生するためです。本番環境では、DNSレコード作成後に以下のようにヘルスチェックを追加できます:

```bash
oc patch dnspolicy external-dnspolicy -n api-gateway --type='merge' -p '
spec:
  healthCheck:
    failureThreshold: 3
    interval: 1m
    path: /health
'
```

> **注**: DNSレコードの作成には数分かかる場合があります。

### ステップ9: AuthPolicyの適用（Gateway level）

Gatewayレベルでデフォルトの認証・認可ポリシーを設定します。

```yaml
apiVersion: kuadrant.io/v1
kind: AuthPolicy
metadata:
  name: external-auth
  namespace: api-gateway
spec:
  targetRef:
    group: gateway.networking.k8s.io
    kind: Gateway
    name: external
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
```

**動作**:
- すべてのリクエストをデフォルトで拒否
- HTTPRouteレベルのAuthPolicyで個別に上書き可能（`defaults`を使用）
- カスタムエラーメッセージを返す

### ステップ10: RateLimitPolicyの適用（Gateway level）

Gatewayレベルでデフォルトのレート制限を設定します。

```yaml
apiVersion: kuadrant.io/v1
kind: RateLimitPolicy
metadata:
  name: external-rlp
  namespace: api-gateway
spec:
  targetRef:
    group: gateway.networking.k8s.io
    kind: Gateway
    name: external
  defaults:
    limits:
      "low-limit":
        rates:
        - limit: 5
          window: 10s
```

**設定内容**:
- **10秒あたり5リクエスト**の制限（テスト用の厳しい設定）
- HTTPRouteレベルで上書き可能（`defaults`を使用）

> **注**: 本番環境では、想定されるトラフィックに応じた適切な値（例: 100リクエスト/分、1000リクエスト/時間）を設定してください。

### ステップ11: API Keys Secretの作成

HTTPRouteレベルのAuthPolicyで使用するAPI Keyを含むSecretを作成します。

```yaml
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
```

**重要**: Secretは、Kuadrant CRが配置されているネームスペース（`kuadrant-system`）に作成する必要があります。

### ステップ12: AuthPolicyの適用（HTTPRoute level）

HTTPRouteレベルでAPI Key認証を設定し、GatewayレベルのデフォルトのAuthPolicy（deny-all）を上書きします。

```yaml
apiVersion: kuadrant.io/v1
kind: AuthPolicy
metadata:
  name: news-api-auth
  namespace: news-api
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
```

**動作**:
- API Keyヘッダー（`Authorization: APIKEY <key>`）による認証
- GatewayレベルのAuthPolicy（deny-all）を上書き
- 認証失敗時のカスタムエラーメッセージ

### ステップ13: RateLimitPolicyの適用（HTTPRoute level）

HTTPRouteレベルでユーザー別のレート制限を設定し、GatewayレベルのデフォルトのRateLimitPolicyを上書きします。

```yaml
apiVersion: kuadrant.io/v1
kind: RateLimitPolicy
metadata:
  name: news-api-ratelimit
  namespace: news-api
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
```

**設定内容**:
- **各API Keyごとに1分あたり10リクエスト**の制限
- GatewayレベルのRateLimitPolicy（10秒5リクエスト）を上書き
- `counters`で認証されたユーザー（API Key）ごとにカウント

## トラブルシューティング

### 1. DNS解決が失敗する

**症状**: `nslookup api.${KUADRANT_ZONE_ROOT_DOMAIN}` がタイムアウトまたは見つからない

**原因**:
- DNSPolicyがまだDNSレコードを作成していない
- AWS Route 53の権限不足
- AWS Credentials Secretが正しく設定されていない

**解決策**:

```bash
# DNSPolicyのステータスを確認
oc get dnspolicy external-dnspolicy -n api-gateway -o yaml

# DNSRecordリソースを確認
oc get dnsrecord -n api-gateway

# AWS Route 53のレコードを確認（AWS CLIがある場合）
aws route53 list-resource-record-sets --hosted-zone-id <zone-id>

# DNSPolicyを再作成
oc delete dnspolicy external-dnspolicy -n api-gateway
./setup-gateway-and-policy.sh  # DNSPolicyのみ再作成される
```

### 2. TLS証明書が発行されない

**症状**: `curl` で `certificate verify failed` エラーが発生

**原因**:
- Let's EncryptのDNS-01チャレンジが完了していない
- ClusterIssuerの設定が間違っている
- AWS Route 53への書き込み権限がない

**解決策**:

```bash
# Certificateリソースを確認
oc get certificate -n api-gateway

# Certificate詳細を確認
oc describe certificate api-external-tls -n api-gateway

# CertificateRequestを確認
oc get certificaterequest -n api-gateway

# cert-manager Podのログを確認
oc logs -n cert-manager deployment/cert-manager-controller

# ClusterIssuerを再作成
oc delete clusterissuer letsencrypt-prod
./setup-gateway-and-policy.sh  # ClusterIssuerのみ再作成される
```

### 3. Gatewayが Ready にならない

**症状**: Gateway ステータスが `Programmed: False`

**原因**:
- OpenShift Service Mesh 3が正しくインストールされていない
- GatewayClassが存在しない
- Istio Operatorの問題

**解決策**:

```bash
# GatewayClassを確認
oc get gatewayclass istio

# Gatewayの詳細を確認
oc describe gateway external -n api-gateway

# istio-system namespaceのPodを確認
oc get pods -n istio-system

# Gatewayを再作成
oc delete gateway external -n api-gateway
./setup-gateway-and-policy.sh  # Gatewayのみ再作成される
```

### 4. News APIにアクセスできない

**症状**: `curl https://api.${KUADRANT_ZONE_ROOT_DOMAIN}/health` が応答しない

**原因**:
- News API Podが起動していない
- HTTPRouteが正しく設定されていない
- Gatewayとの接続に問題がある

**解決策**:

```bash
# News API Podを確認
oc get pods -n news-api

# Podのログを確認
oc logs -n news-api deployment/news-api

# HTTPRouteを確認
oc get httproute news-api -n news-api -o yaml

# HTTPRouteのステータスを確認
oc describe httproute news-api -n news-api

# News APIを再デプロイ
oc delete deployment news-api -n news-api
oc delete service news-api -n news-api
./setup-gateway-and-policy.sh  # News APIのみ再作成される
```

### 5. API Keyが認識されない

**症状**: API Keyを指定してもアクセスが拒否される（401エラー）

**原因**:
- API Keys SecretがKuadrant CRと同じネームスペース（`kuadrant-system`）に作成されていない
- Secretのラベル（`authorino.kuadrant.io/managed-by: authorino`、`app: news-api`）が正しくない
- HTTPRouteレベルのAuthPolicyが正しく適用されていない

**解決策**:

```bash
# API Keys Secretを確認
oc get secret api-keys -n kuadrant-system -o yaml

# Secretのラベルを確認
oc get secret api-keys -n kuadrant-system -o jsonpath='{.metadata.labels}'

# HTTPRouteレベルのAuthPolicyを確認
oc get authpolicy news-api-auth -n news-api -o yaml

# AuthConfigが作成されているか確認（kuadrant-systemネームスペース）
oc get authconfig -n kuadrant-system

# AuthConfigの詳細を確認
oc describe authconfig -n kuadrant-system

# AuthPolicyを再作成
oc delete authpolicy news-api-auth -n news-api
./setup-gateway-and-policy.sh  # HTTPRouteレベルのAuthPolicyのみ再作成される
```

### 6. RateLimitPolicyでリクエストが制限される

**症状**: HTTPRouteレベルのRateLimitPolicyでは11回目以降のリクエストで `429 Too Many Requests` が返される

**原因**: これは**正常な動作**です。HTTPRouteレベルのRateLimitPolicyが1分あたり10リクエストに制限しています。

**解決策**: 

一時的に制限を緩和する場合:

```bash
# HTTPRouteレベルのRateLimitPolicyを編集
oc edit ratelimitpolicy news-api-ratelimit -n news-api

# limits.authenticated-user-limit.rates[0].limit を 100 に変更
# または window を 1h に変更
```

または削除して、GatewayレベルのRateLimitPolicyを使用:

```bash
# HTTPRouteレベルのRateLimitPolicyを削除
oc delete ratelimitpolicy news-api-ratelimit -n news-api

# この場合、GatewayレベルのRateLimitPolicy（10秒5リクエスト）が適用されます
```

## 次のステップ

第2回記事のセットアップが完了しました。次は第3回記事「高度な認証設定」で、以下を扱います:

- Keycloakとの統合
- JWT認証の実装
- ロールベースアクセス制御（RBAC）
- ユーザーロール別のレート制限

## 参考リンク

- [Red Hat Connectivity Link公式ドキュメント](https://access.redhat.com/documentation/ja-jp/red_hat_connectivity_link/)
- [Kubernetes Gateway API](https://gateway-api.sigs.k8s.io/)
- [Kuadrantコミュニティ](https://kuadrant.io/)
- [cert-manager Documentation](https://cert-manager.io/docs/)
- [AWS Route 53 Documentation](https://docs.aws.amazon.com/route53/)

---

**作成日**: 2026年4月28日  
**対象バージョン**: Red Hat Connectivity Link 1.3.2  
**動作確認環境**: OpenShift Container Platform 4.19
