# Red Hat build of Keycloak セットアップツール

このディレクトリには、OpenShift Container Platform上にRed Hat build of Keycloak (RHBK)を自動的にデプロイするためのスクリプトとYAMLファイルが含まれています。

## 📋 目次

- [前提条件](#前提条件)
- [ファイル構成](#ファイル構成)
- [クイックスタート](#クイックスタート)
- [詳細な使用方法](#詳細な使用方法)
- [トラブルシューティング](#トラブルシューティング)

## 前提条件

### 必須

| 項目 | 要件 |
|------|------|
| **OpenShift Container Platform** | 4.19以降 |
| **クラスター管理者権限** | 必要 |
| **永続ストレージ** | PostgreSQL用に20GB以上推奨 |
| **oc CLI** | インストール済み |

### 事前にログイン

```bash
# OpenShiftクラスタにログイン
oc login --server=https://api.your-cluster.example.com:6443
```

## ファイル構成

```
03-advanced_authentication/
├── install-rhbk.sh          # RHBKインストールスクリプト
├── import-realm.sh          # Realmインポートスクリプト
├── cleanup-rhbk.sh          # クリーンアップスクリプト
├── keycloak-env.sh          # 環境変数（自動生成）
├── README.md                # このファイル
└── openshift/
    ├── postgres-credentials-secret.yaml  # PostgreSQL認証情報
    ├── postgres-deployment.yaml          # PostgreSQLデプロイメント
    ├── keycloak-cr.yaml                  # Keycloak CR
    ├── keycloak-route.yaml               # Keycloak Route
    └── realm-export.json                 # サンプルRealm設定
```

## クイックスタート

### 1. RHBKのインストール

```bash
./install-rhbk.sh
```

**所要時間**: 約5〜10分

**処理内容**:
- ✅ `rhbk` namespaceの作成
- ✅ RHBK Operatorのインストール
- ✅ PostgreSQLのデプロイ
- ✅ Keycloakインスタンスのデプロイ
- ✅ OpenShift Routeの作成
- ✅ 管理者認証情報の取得

**完了後の出力例**:
```
======================================
Installation Complete!
======================================

Keycloak URL: https://keycloak.apps.cluster-xxx.xxx.opentlc.com
Admin Username: admin
Admin Password: <自動生成されたパスワード>

To import the sample realm, run:
  ./import-realm.sh

Environment variables saved to: keycloak-env.sh
Source it with: source keycloak-env.sh
```

### 2. サンプルRealmのインポート

```bash
./import-realm.sh
```

**所要時間**: 約1〜2分

**インポート内容**:
- ✅ Realm: `news-api-realm`
- ✅ Client: `news-api-client`
- ✅ Roles: `admin`, `user`, `premium`
- ✅ Users:
  - `john.doe` (user + premium roles) - password: `password123`
  - `admin.user` (admin role) - password: `admin123`
  - `guest` (no roles) - password: `guest123`

**完了後の出力例**:
```
======================================
Realm Import Complete!
======================================

Realm Details:
  Realm Name: news-api-realm
  Client ID: news-api-client
  Client Secret: <自動生成されたSecret>

Test Users:
  1. john.doe (user + premium roles)
     - Email: john.doe@example.com
     - Password: password123

  2. admin.user (admin role)
     - Email: admin@example.com
     - Password: admin123

  3. guest (no roles)
     - Email: guest@example.com
     - Password: guest123
```

### 3. 環境変数の読み込み

```bash
source keycloak-env.sh
```

これにより、以下の環境変数が設定されます:
- `KEYCLOAK_URL`
- `KEYCLOAK_REALM`
- `KEYCLOAK_ADMIN_USER`
- `KEYCLOAK_ADMIN_PASSWORD`
- `CLIENT_SECRET`
- `KUADRANT_ZONE_ROOT_DOMAIN`

### 4. 動作確認

```bash
# アクセストークンを取得
export ACCESS_TOKEN=$(curl -s -X POST \
  "${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password" \
  -d "client_id=news-api-client" \
  -d "client_secret=${CLIENT_SECRET}" \
  -d "username=john.doe" \
  -d "password=password123" \
  | jq -r '.access_token')

# トークンの内容を確認
echo $ACCESS_TOKEN | jq -R 'split(".") | .[1] | @base64d | fromjson'
```

**期待される出力（抜粋）**:
```json
{
  "preferred_username": "john.doe",
  "email": "john.doe@example.com",
  "realm_access": {
    "roles": ["premium", "user", ...]
  }
}
```

### 5. クリーンアップ（必要に応じて）

```bash
./cleanup-rhbk.sh
```

**警告**: このスクリプトは以下をすべて削除します:
- ⚠️ Keycloakインスタンスと全Realm
- ⚠️ PostgreSQLデータベース（全データ）
- ⚠️ RHBK Operator
- ⚠️ `rhbk` namespace

## 詳細な使用方法

### install-rhbk.sh の詳細

このスクリプトは、以下の処理を自動的に実行します:

#### ステップ1: Namespaceの作成
```bash
oc create namespace rhbk
```

#### ステップ2: RHBK Operatorのインストール
- OperatorGroupの作成
- Subscriptionの作成（チャネル: `stable-v26.4`）
- Operatorが`Succeeded`状態になるまで待機

#### ステップ3: PostgreSQLのデプロイ
- ランダムパスワードの生成（OpenSSL使用）
- PostgreSQL credentials secretの作成
- PersistentVolumeClaim（20GB）の作成
- PostgreSQL Deploymentの作成
- PostgreSQL Serviceの作成

#### ステップ4: Keycloakのデプロイ
- Keycloak CRの作成
- Keycloakが`Ready`状態になるまで待機（最大10分）

#### ステップ5: Routeの作成
- OpenShiftデフォルトルート（`*.apps.cluster-xxx`）を使用
- TLS terminationモード: `reencrypt`

#### ステップ6: 認証情報の取得
- 管理者パスワードを`keycloak-initial-admin` Secretから取得
- 環境変数ファイル（`keycloak-env.sh`）を生成

### import-realm.sh の詳細

このスクリプトは、`openshift/realm-export.json`をインポートします:

#### ステップ1: ファイルのコピー
```bash
oc cp realm-export.json rhbk/keycloak-0:/tmp/realm-export.json
```

#### ステップ2: kcadm.shの設定
- Keycloak管理者でログイン
- 設定ファイルを`/tmp/kcadm.config`に保存

#### ステップ3: Realmのインポート
- 既存のRealmがある場合、削除確認プロンプトを表示
- `kcadm.sh create realms`コマンドでインポート

#### ステップ4: Client Secretの取得
```bash
kcadm.sh get clients -r news-api-realm -q clientId=news-api-client --fields secret
```

#### ステップ5: ユーザーの確認
- インポートされたユーザーのリストを表示

#### ステップ6: 環境変数ファイルの更新
- `CLIENT_SECRET`を`keycloak-env.sh`に追加

### cleanup-rhbk.sh の詳細

このスクリプトは、インストールされた全リソースを削除します:

#### ステップ1〜3: Keycloak関連リソースの削除
- Keycloak CR
- Keycloak Route
- PostgreSQL（Deployment, Service, PVC, Secret）

#### ステップ4: Keycloakリソースの完全削除待機
- Finalizerが完了するまで最大1分待機

#### ステップ5〜6: Operatorの削除
- Subscription
- ClusterServiceVersion (CSV)
- OperatorGroup

#### ステップ7: Namespaceの削除
```bash
oc delete namespace rhbk
```

#### ステップ8: 環境変数ファイルの削除
```bash
rm keycloak-env.sh
```

## Realm設定の詳細

`openshift/realm-export.json`には以下が含まれています:

### トークン設定
```json
{
  "accessTokenLifespan": 300,  // 5分
  "ssoSessionIdleTimeout": 1800,  // 30分
  "ssoSessionMaxLifespan": 36000  // 10時間
}
```

### Roles
- `admin`: 管理者ロール - 全エンドポイントへのフルアクセス
- `user`: 一般ユーザーロール - 読み取り専用アクセス
- `premium`: プレミアムユーザーロール - 拡張機能へのアクセス

### Client設定
```json
{
  "clientId": "news-api-client",
  "directAccessGrantsEnabled": true,  // Resource Owner Password Credentials Grant有効
  "publicClient": false,
  "redirectUris": ["https://api.sandbox1479.opentlc.com/*"],
  "webOrigins": ["https://api.sandbox1479.opentlc.com"]
}
```

### Users
| Username | Email | Roles | Password |
|----------|-------|-------|----------|
| john.doe | john.doe@example.com | user, premium | password123 |
| admin.user | admin@example.com | admin | admin123 |
| guest | guest@example.com | (none) | guest123 |

**注**: すべてのユーザーは以下が設定されています:
- `emailVerified`: true
- `enabled`: true
- `firstName` と `lastName`: 設定済み（必須）

## トラブルシューティング

### 1. Operatorのインストールが失敗する

**症状**: `rhbk-operator` CSVが`Succeeded`にならない

**確認方法**:
```bash
oc get csv -n rhbk
oc describe csv <csv-name> -n rhbk
```

**解決策**:
- OpenShiftのバージョンが4.19以降であることを確認
- `redhat-operators` CatalogSourceが利用可能か確認:
  ```bash
  oc get catalogsource -n openshift-marketplace
  ```

### 2. PostgreSQLが起動しない

**症状**: `postgres` Podが`Running`にならない

**確認方法**:
```bash
oc get pods -n rhbk -l app=postgres
oc describe pod <postgres-pod> -n rhbk
oc logs <postgres-pod> -n rhbk
```

**解決策**:
- 永続ストレージが利用可能か確認:
  ```bash
  oc get pvc -n rhbk
  ```
- StorageClassが存在するか確認:
  ```bash
  oc get storageclass
  ```

### 3. Keycloakが`Ready`にならない

**症状**: Keycloak CRが10分経っても`Ready: True`にならない

**確認方法**:
```bash
oc get keycloak keycloak -n rhbk -o yaml
oc describe keycloak keycloak -n rhbk
oc logs -n rhbk -l app=keycloak
```

**一般的な原因**:
- PostgreSQLへの接続失敗
- TLS証明書の問題
- リソース不足

**解決策**:
```bash
# PostgreSQL接続を確認
oc get secret postgres-credentials -n rhbk -o yaml

# Keycloak Podのイベントを確認
oc get events -n rhbk --sort-by='.lastTimestamp'

# 必要に応じて再作成
oc delete keycloak keycloak -n rhbk
oc apply -f openshift/keycloak-cr.yaml
```

### 4. Realmインポートが失敗する

**症状**: `import-realm.sh`でエラーが発生

**確認方法**:
```bash
# kcadm.shのログを確認
oc exec -n rhbk keycloak-0 -- cat /tmp/kcadm.log
```

**一般的なエラー**:

#### "Account is not fully set up"
**原因**: ユーザーに`firstName`または`lastName`が設定されていない

**解決策**: `realm-export.json`を確認し、すべてのユーザーに以下が設定されていることを確認:
```json
{
  "firstName": "John",
  "lastName": "Doe"
}
```

#### "Client secret mismatch"
**原因**: Client secretが正しく設定されていない

**解決策**:
```bash
# 新しいsecretを生成
oc exec -n rhbk keycloak-0 -- /opt/keycloak/bin/kcadm.sh update clients/<client-uuid> \
  -r news-api-realm \
  -s 'secret=<new-secret>' \
  --config /tmp/kcadm.config
```

### 5. 管理コンソールにアクセスできない

**症状**: ブラウザで`https://<keycloak-hostname>`にアクセスできない

**確認方法**:
```bash
# Routeを確認
oc get route keycloak -n rhbk

# Keycloak Serviceを確認
oc get svc keycloak-service -n rhbk
```

**解決策**:
```bash
# Routeを再作成
oc delete route keycloak -n rhbk
./install-rhbk.sh  # ステップ5のみ実行される
```

### 6. トークン取得時のエラー

#### "invalid_grant: Account is not fully set up"
**原因**: ユーザーのRequired Actionsがクリアされていない

**解決策**:
```bash
# kcadm.shでRequired Actionsをクリア
oc exec -n rhbk keycloak-0 -- /opt/keycloak/bin/kcadm.sh update users/<user-id> \
  -r news-api-realm \
  -s 'requiredActions=[]' \
  --config /tmp/kcadm.config

# パスワードを再設定
oc exec -n rhbk keycloak-0 -- /opt/keycloak/bin/kcadm.sh set-password \
  -r news-api-realm \
  --username john.doe \
  --new-password password123 \
  --config /tmp/kcadm.config
```

#### "invalid_client"
**原因**: Client IDまたはClient Secretが間違っている

**解決策**:
```bash
# 環境変数を再読み込み
source keycloak-env.sh

# Client Secretを確認
echo $CLIENT_SECRET

# 必要に応じてimport-realm.shを再実行
./import-realm.sh
```

## 高度な設定

### カスタムドメインの使用

デフォルトではOpenShiftのデフォルトルート（`*.apps.cluster-xxx`）を使用しますが、カスタムドメインを使用する場合は以下を変更してください:

1. **Keycloak CR**（`openshift/keycloak-cr.yaml`）に追加:
```yaml
spec:
  hostname:
    hostname: keycloak.your-custom-domain.com
  http:
    tlsSecret: keycloak-tls
```

2. **TLS証明書の準備**:
```bash
oc apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: keycloak-tls
  namespace: rhbk
spec:
  secretName: keycloak-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
  - keycloak.your-custom-domain.com
EOF
```

3. **Route**（`openshift/keycloak-route.yaml`）を変更:
```yaml
spec:
  tls:
    termination: passthrough  # reencryptからpassthroughに変更
```

### 高可用性構成

本番環境では、Keycloakインスタンス数を増やすことを推奨します:

**`openshift/keycloak-cr.yaml`を編集**:
```yaml
spec:
  instances: 3  # 1から3に変更
```

### リソース制限の設定

**`openshift/keycloak-cr.yaml`に追加**:
```yaml
spec:
  resources:
    limits:
      cpu: "2"
      memory: 2Gi
    requests:
      cpu: "1"
      memory: 1Gi
```

## 参考リンク

- [Red Hat build of Keycloak公式ドキュメント](https://access.redhat.com/documentation/ja-jp/red_hat_build_of_keycloak/)
- [Keycloak Operator GitHub](https://github.com/keycloak/keycloak-k8s-resources)
- [OpenShift Container Platform ドキュメント](https://docs.openshift.com/)

---

**作成日**: 2026年4月28日  
**対象バージョン**: Red Hat build of Keycloak 26.4  
**動作確認環境**: OpenShift Container Platform 4.19
