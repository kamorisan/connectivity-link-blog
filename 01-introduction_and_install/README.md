# Red Hat Connectivity Link インストールツール

このディレクトリには、OpenShift Container Platform上にRed Hat Connectivity Linkを自動的にインストールするためのスクリプトが含まれています。

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
| **oc CLI** | インストール済み |
| **Red Hat Connectivity Link Subscription** | 必要（営業までお問い合わせください） |

### 事前にログイン

```bash
# OpenShiftクラスタにログイン
oc login --server=https://api.your-cluster.example.com:6443
```

## ファイル構成

```
01-introduction_and_install/
├── install-prerequisites.sh        # 前提条件インストールスクリプト
├── install-connectivity-link.sh    # Connectivity Linkインストールスクリプト
├── cleanup-prerequisites.sh        # 前提条件クリーンアップスクリプト
├── cleanup-connectivity-link.sh    # Connectivity Linkクリーンアップスクリプト
└── README.md                       # このファイル
```

## クイックスタート

### 1. 前提条件のインストール

まず、OpenShift Service Mesh 3をインストールします。

```bash
./install-prerequisites.sh
```

**所要時間**: 約5〜10分

**処理内容**:
- ✅ OpenShift Service Mesh 3のインストール (v3.2+)
- ✅ Istio CRの作成
- ✅ インストール確認

**完了後の出力例**:
```
======================================
Installation Complete!
======================================

Prerequisites have been successfully installed.

Installed components:
  1. OpenShift Service Mesh 3

Next step:
  Install Red Hat Connectivity Link:
    ./install-connectivity-link.sh
```

### 2. Red Hat Connectivity Linkのインストール

前提条件のインストール完了後、Connectivity Linkをインストールします。

```bash
./install-connectivity-link.sh
```

**所要時間**: 約5〜10分

**処理内容**:
- ✅ `kuadrant-system` namespaceの作成
- ✅ Red Hat Connectivity Link Operatorのインストール
- ✅ GatewayClassの作成（Istio Gateway Controller用）
- ✅ Kuadrant CRの作成
- ✅ Authorino Operatorのインストール（自動）
- ✅ DNS Operatorのインストール（自動）
- ✅ Limitador Operatorのインストール（自動）
- ✅ インストール確認

**完了後の出力例**:
```
======================================
Installation Complete!
======================================

Red Hat Connectivity Link has been successfully installed.

Key resources created:
  - Namespace: kuadrant-system
  - Kuadrant CR: kuadrant

Installed Operators:
  - Red Hat Connectivity Link Operator
  - Authorino Operator
  - DNS Operator
  - Limitador Operator

Next steps:
  1. Enable Console Plugin (optional)
  2. Create a Gateway
```

### 3. Console Plugin の有効化（オプション）

Connectivity LinkはOpenShift Web ConsoleにカスタムUIを提供するConsole Pluginを含んでいます。

**手順**:

1. OpenShift Web Consoleにログイン
2. **Home > Overview** を選択
3. **Dynamic Plugin status** セクションで **kuadrant-console-plugin** を探す
4. **Disabled** の場合、クリックして **Enable** を選択
5. **Save** をクリック
6. ブラウザをリフレッシュ

**Console Plugin有効化後の機能**:
- 左側のナビゲーションに **Connectivity Link** セクションが追加
- **Connectivity Link Overview**: Gatewayの統計情報
- **Policies**: 各種Policyの一覧と管理
- **Policy Topology**: ポリシー関係の視覚化
- **Networking** メニューに **Gateways**、**HTTPRoutes** が追加

### 4. インストール確認

```bash
# Operatorの確認
oc get csv -n kuadrant-system

# Podの確認
oc get pods -n kuadrant-system

# Kuadrant CRの確認
oc get kuadrant -n kuadrant-system
```

**期待される出力**:

```
NAME                                  PHASE
rhcl-operator.v1.3.2                  Succeeded
authorino-operator.vX.X.X             Succeeded
dns-operator.vX.X.X                   Succeeded
limitador-operator.vX.X.X             Succeeded

NAME                                  READY   STATUS
authorino-operator-xxxxx              1/1     Running
dns-operator-xxxxx                    1/1     Running
limitador-operator-xxxxx              1/1     Running
kuadrant-operator-xxxxx               1/1     Running

NAME        READY
kuadrant    True
```

### 5. クリーンアップ（必要に応じて）

Connectivity Linkと前提条件を完全に削除する場合は、以下の順序で実行します。

#### Connectivity Linkのクリーンアップ

```bash
./cleanup-connectivity-link.sh
```

**警告**: このスクリプトは以下をすべて削除します:
- ⚠️ Kuadrant CRと関連リソース
- ⚠️ GatewayClass `istio`
- ⚠️ Red Hat Connectivity Link Operator
- ⚠️ Authorino Operator
- ⚠️ DNS Operator
- ⚠️ Limitador Operator
- ⚠️ `kuadrant-system` namespace

#### 前提条件のクリーンアップ

Connectivity Linkのクリーンアップ後、必要に応じて前提条件も削除できます。

```bash
./cleanup-prerequisites.sh
```

**警告**: このスクリプトは以下をすべて削除します:
- ⚠️ OpenShift Service Mesh 3 (Istio CRとOperator)
- ⚠️ `istio-system` namespace

**注**: 他のnamespaceに作成されたGateway、HTTPRoute、Policy（AuthPolicy、RateLimitPolicy、DNSPolicy、TLSPolicy）は手動で削除する必要があります。

## 詳細な使用方法

### install-prerequisites.sh の詳細

このスクリプトは、Connectivity Linkに必要な前提条件（OpenShift Service Mesh 3）を自動的にインストールします。

#### OpenShift Service Mesh 3

**ステップ1: Namespaceの作成**
```bash
oc create namespace istio-system
```

**ステップ2: OpenShift Service Mesh Operatorのインストール**
- OperatorGroupの作成（AllNamespacesモード）
- Subscriptionの作成（チャネル: `stable`）
- Operatorが`Succeeded`状態になるまで待機

**OperatorGroup設定**:
```yaml
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: istio-system
  namespace: istio-system
spec: {}
```

**Subscription設定**:
```yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: servicemeshoperator3
  namespace: istio-system
spec:
  channel: stable
  installPlanApproval: Automatic
  name: servicemeshoperator3
  source: redhat-operators
  sourceNamespace: openshift-marketplace
```

**ステップ3: Istio CRの作成**
```yaml
apiVersion: sailoperator.io/v1
kind: Istio
metadata:
  name: default
  namespace: istio-system
spec:
  namespace: istio-system
  updateStrategy:
    type: InPlace
  version: v1.28-latest
```

**ステップ4: Istioの準備完了確認**
- Istio CRが`Healthy`状態になるまで最大5分待機
- Istio control planeコンポーネントのデプロイ確認

### install-connectivity-link.sh の詳細

このスクリプトは、以下の処理を自動的に実行します:

#### ステップ1: 事前確認
- `oc` CLIのインストール確認
- OpenShiftへのログイン確認
- OpenShiftバージョン確認（4.19以降）

#### ステップ2: Namespaceの作成
```bash
oc create namespace kuadrant-system
```

#### ステップ3: GatewayClassの作成
Istio Gateway ControllerのためのGatewayClassを作成します。これはKuadrant OperatorがGateway API providerを認識するために必要です。

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: istio
spec:
  controllerName: istio.io/gateway-controller
  description: The default Istio GatewayClass
```

#### ステップ4: Operatorのインストール
- OperatorGroupの作成
- Subscriptionの作成（チャネル: `stable`）
- Operatorが`Succeeded`状態になるまで待機

**Subscription設定**:
```yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: rhcl-operator
  namespace: kuadrant-system
spec:
  channel: stable
  installPlanApproval: Automatic
  name: rhcl-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
```

#### ステップ5: Kuadrant CRの作成
```yaml
apiVersion: kuadrant.io/v1beta1
kind: Kuadrant
metadata:
  name: kuadrant
  namespace: kuadrant-system
```

**注**: 既存のKuadrant CRがエラー状態（GatewayClass未作成）の場合、スクリプトは自動的に再作成します。

#### ステップ6: 準備完了の確認
- Kuadrant CRが`Ready: True`になるまで最大5分待機
- 依存するOperator（Authorino、DNS、Limitador）が自動的にインストールされる

#### ステップ7: インストール結果の表示
- インストールされたOperatorの一覧
- 実行中のPodの一覧
- 次のステップの案内

### cleanup-connectivity-link.sh の詳細

このスクリプトは、インストールされた全リソースを削除します:

#### ステップ1: Kuadrant CRの削除
- Kuadrant CRを削除

#### ステップ2: GatewayClassの削除
- GatewayClass `istio`を削除

#### ステップ3: Kuadrantリソースの削除待機
- Finalizerが処理されるまで待機

#### ステップ4〜7: Operatorの削除
- Subscription
- ClusterServiceVersion (CSV)
  - rhcl-operator
  - authorino-operator
  - dns-operator
  - limitador-operator
- OperatorGroup

#### ステップ8: Namespaceの削除
```bash
oc delete namespace kuadrant-system
```

### cleanup-prerequisites.sh の詳細

このスクリプトは、前提条件としてインストールされたOpenShift Service Mesh 3を削除します:

#### OpenShift Service Mesh 3の削除

**ステップ1: Istio CRの削除**
- Istio CRを削除
- Finalizerが処理されるまで待機

**ステップ2: Istioリソースの削除待機**
- Istio関連リソースが完全に削除されるまで待機

**ステップ3: Service Mesh Operatorの削除**
- Subscription
- ClusterServiceVersion (CSV)
- OperatorGroup

**ステップ4: istio-system namespaceの削除**
```bash
oc delete namespace istio-system
```

## トラブルシューティング

### 前提条件関連

#### 1. Istio CRが`Healthy`にならない

**症状**: Istio CRが5分経っても`Healthy`状態にならない

**確認方法**:
```bash
oc get istio default -n istio-system -o yaml
oc describe istio default -n istio-system
oc get pods -n istio-system
```

**一般的な原因**:
- Service Mesh Operatorのインストール失敗
- リソース不足
- イメージのpull失敗

**解決策**:
```bash
# Operator Podのログを確認
oc logs -n istio-system deployment/sail-operator

# Istio control planeのPodを確認
oc get pods -n istio-system -l app=istiod

# イベントを確認
oc get events -n istio-system --sort-by='.lastTimestamp'

# 必要に応じて再作成
oc delete istio default -n istio-system
oc apply -f - <<EOF
apiVersion: sailoperator.io/v1
kind: Istio
metadata:
  name: default
  namespace: istio-system
spec:
  namespace: istio-system
  updateStrategy:
    type: InPlace
  version: v1.28-latest
EOF
```

### Connectivity Link関連

#### 2. Connectivity Link Operatorのインストールが失敗する

**症状**: `rhcl-operator` CSVが`Succeeded`にならない

**確認方法**:
```bash
oc get csv -n kuadrant-system
oc describe csv <csv-name> -n kuadrant-system
```

**解決策**:
- OpenShiftのバージョンが4.19以降であることを確認
- `redhat-operators` CatalogSourceが利用可能か確認:
  ```bash
  oc get catalogsource -n openshift-marketplace
  ```
- Red Hat Connectivity Link Subscriptionが有効であることを確認

#### 3. Kuadrant CRが`Ready`にならない

**症状**: Kuadrant CRが5分経っても`Ready: True`にならない

**確認方法**:
```bash
oc get kuadrant kuadrant -n kuadrant-system -o yaml
oc describe kuadrant kuadrant -n kuadrant-system
oc logs -n kuadrant-system -l app=kuadrant-operator
```

**一般的な原因**:
- **GatewayClassが作成されていない** (最も一般的)
  - エラーメッセージ: `Gateway API provider (istio / envoy gateway) is not installed`
- 依存Operatorのインストール失敗
- リソース不足
- ネットワーク問題

**解決策**:

**1. GatewayClassの確認と作成**:
```bash
# GatewayClassが存在するか確認
oc get gatewayclass istio

# 存在しない場合、作成
oc apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: istio
spec:
  controllerName: istio.io/gateway-controller
  description: The default Istio GatewayClass
EOF

# Kuadrant CRを再作成
oc delete kuadrant kuadrant -n kuadrant-system
oc apply -f - <<EOF
apiVersion: kuadrant.io/v1beta1
kind: Kuadrant
metadata:
  name: kuadrant
  namespace: kuadrant-system
EOF
```

**2. その他の確認**:
```bash
# 依存Operatorの状態を確認
oc get csv -n kuadrant-system

# Kuadrant Operator Podのログを確認
oc logs -n kuadrant-system deployment/kuadrant-operator-controller-manager

# イベントを確認
oc get events -n kuadrant-system --sort-by='.lastTimestamp'
```

#### 4. Console Pluginが表示されない

**症状**: ブラウザをリフレッシュしても、Connectivity Linkメニューが表示されない

**確認方法**:
```bash
# Console Pluginの確認
oc get consoleplugin kuadrant-console-plugin

# Console Pluginのステータス確認
oc get console.operator cluster -o yaml
```

**解決策**:
1. Console Pluginが有効化されているか確認:
   ```bash
   oc patch console.operator cluster --type=json \
     -p '[{"op": "add", "path": "/spec/plugins/-", "value": "kuadrant-console-plugin"}]'
   ```

2. ブラウザのキャッシュをクリア（Ctrl+Shift+R または Cmd+Shift+R）

3. プライベートモード/シークレットモードで開く

#### 5. 権限エラーが発生する

**症状**: `Forbidden` や `User cannot create resource` エラーが発生

**原因**: クラスター管理者権限がない

**解決策**:
```bash
# 現在の権限を確認
oc auth can-i create subscription -n kuadrant-system
oc auth can-i create operatorgroup -n kuadrant-system

# クラスター管理者でログインし直す
oc login --server=<cluster-url> -u <admin-user>
```

#### 6. 既存リソースとの競合

**症状**: `AlreadyExists` エラーが発生

**確認方法**:
```bash
# 既存のリソースを確認
oc get subscription,operatorgroup,kuadrant -n kuadrant-system
```

**解決策**:
- スクリプトは既存リソースをスキップするため、通常は問題ありません
- 完全にクリーンインストールしたい場合:
  ```bash
  ./cleanup-connectivity-link.sh
  ./install-connectivity-link.sh
  ```

## 次のステップ

インストールが完了したら、以下を試してください:

### 1. Gatewayの作成

```bash
oc apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: external
  namespace: <your-namespace>
spec:
  gatewayClassName: istio
  listeners:
  - name: http
    port: 80
    protocol: HTTP
    allowedRoutes:
      namespaces:
        from: Same
EOF
```

### 2. HTTPRouteの作成

```bash
oc apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: my-route
  namespace: <your-namespace>
spec:
  parentRefs:
  - name: external
  hostnames:
  - "api.example.com"
  rules:
  - backendRefs:
    - name: my-service
      port: 8080
EOF
```

### 3. AuthPolicyの適用

```bash
oc apply -f - <<EOF
apiVersion: kuadrant.io/v1
kind: AuthPolicy
metadata:
  name: my-auth
  namespace: <your-namespace>
spec:
  targetRef:
    group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: my-route
  rules:
    authentication:
      "api-key":
        apiKey:
          selector:
            matchLabels:
              app: my-app
        credentials:
          authorizationHeader:
            prefix: Bearer
EOF
```

詳細は次回のブログ記事で解説します。

## 参考リンク

- [Red Hat Connectivity Link公式ドキュメント](https://access.redhat.com/documentation/ja-jp/red_hat_connectivity_link/)
- [Kuadrantコミュニティプロジェクト](https://kuadrant.io/)
- [Kubernetes Gateway API仕様](https://gateway-api.sigs.k8s.io/)
- [OpenShift Service Meshドキュメント](https://docs.openshift.com/container-platform/latest/service_mesh/v3x/ossm-about.html)

---

**作成日**: 2026年4月28日  
**対象バージョン**: Red Hat Connectivity Link 1.3.2  
**動作確認環境**: OpenShift Container Platform 4.19
