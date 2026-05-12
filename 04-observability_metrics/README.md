# Red Hat Connectivity Link - Observability with Grafana

このディレクトリには、Red Hat Connectivity Link 1.3のメトリクス監視環境を構築するための自動セットアップスクリプトが含まれています。

## 概要

コミュニティ版Grafanaを使用して、Kuadrant（Connectivity Link）のメトリクスを可視化するための完全な監視スタックをセットアップします。

### セットアップされるコンポーネント

1. **User Workload Monitoring** - OpenShiftのユーザーワークロード監視機能を有効化
2. **kube-state-metrics-kuadrant** - Gateway APIリソース（Gateway, HTTPRoute等）のメトリクスを収集
3. **Istio Telemetry** - リクエストパス、ホスト名、ポート情報を含む拡張メトリクス設定
4. **Grafana Operator** - コミュニティ版Grafana v5の自動インストール・管理
5. **Grafana Instance** - メトリクス可視化ダッシュボード
6. **Prometheus Datasource** - Thanos Querierへの接続設定
7. **3つの公式ダッシュボード**:
   - **Platform Engineer Dashboard** - Gateway、Policy、コンポーネントヘルスの全体監視
   - **App Developer Dashboard** - HTTPRouteごとのトラフィック、レイテンシ、エラー率
   - **Business User Dashboard** - ビジネスメトリクス、リクエスト比較、パス別分析

## 前提条件

### 必須要件

1. **Red Hat Connectivity Link 1.3** がインストール済みであること
   ```bash
   oc get kuadrant -n kuadrant-system
   ```

2. **OpenShift CLI (`oc`)** がインストール済みで、クラスターにログイン済みであること
   ```bash
   oc whoami
   ```

3. **cluster-admin権限** または以下の権限:
   - User Workload Monitoringの有効化
   - Operatorのインストール（openshift-operators namespace）
   - Telemetryリソースの作成（istio-system namespace）
   - monitoring namespaceでのリソース作成

### 推奨要件

- **Article 2 (Gateway and Policy)** のセットアップ完了
  - Gateway、HTTPRoute、News APIがデプロイ済み
  - ダッシュボードはこれらのリソースのメトリクスを表示します

## セットアップ内容の詳細

### 1. User Workload Monitoring

OpenShiftの組み込みPrometheus/Thanosスタックを使用して、ユーザーアプリケーションのメトリクスを収集します。

- **namespace**: `openshift-monitoring`, `openshift-user-workload-monitoring`
- **収集対象**: ServiceMonitor/PodMonitorで定義されたメトリクス
- **保持期間**: デフォルト24時間（OpenShift設定に依存）

### 2. kube-state-metrics-kuadrant

Kuadrant公式のカスタムメトリクスエクスポーター。Gateway APIリソースの状態を収集します。

- **namespace**: `monitoring`
- **収集メトリクス**:
  - `gatewayapi_httproute_labels` - HTTPRouteのラベル情報
  - `gatewayapi_httproute_status_parent_info` - 親Gatewayとの関連
  - `gatewayapi_gateway_info` - Gateway情報
  - `gatewayapi_*_created` - リソース作成時刻
- **デプロイ方法**: Kuadrant公式observability設定を適用
  ```
  https://github.com/Kuadrant/kuadrant-operator/config/install/configure/observability?ref=v1.3.0
  ```

### 3. Istio Telemetry

IstioのPrometheusメトリクスに追加ラベルを設定し、詳細な分析を可能にします。

- **namespace**: `istio-system`
- **リソース名**: `namespace-metrics`
- **追加ラベル**:
  - `request_url_path` - リクエストパス（例: `/technology`, `/sports`）
  - `request_host` - リクエストホスト（例: `api.sandbox1518.opentlc.com`）
  - `destination_port` - 宛先ポート（例: `443`）
- **対象メトリクス**:
  - `REQUEST_COUNT` - リクエスト数（`istio_requests_total`）
  - `REQUEST_DURATION` - レイテンシ（`istio_request_duration_milliseconds_bucket`）

**重要**: この設定により、Business User Dashboardの「Total requests for selected range」パネルが正常動作します。

### 4. Grafana Instance

コミュニティ版Grafana 12.4.1をデプロイします。

- **namespace**: `monitoring`
- **認証情報**:
  - Username: `admin`
  - Password: `grafana123`（テスト環境用）
- **アクセス**: OpenShift Route経由（TLS/HTTPS）
- **セキュリティ設定**:
  - パスワード変更強制: 無効
  - Gravatar: 無効
  - サインアップ: 無効

### 5. Prometheus Datasource

Grafanaから OpenShift Monitoring の Thanos Querier に接続します。

- **接続先**: `thanos-querier-openshift-monitoring.<cluster-domain>`
- **認証方式**: Bearer Token（ServiceAccountトークン）
- **権限**: `cluster-monitoring-view` ClusterRole

### 6. Grafana Dashboards

Kuadrant公式ダッシュボードをURLから取得して自動インポートします。

- **取得元**: GitHub - Kuadrant operator repository (v1.3.0)
- **インポート方法**: `spec.url` による自動ダウンロード
- **ダッシュボード詳細**:

#### Platform Engineer Dashboard
- **用途**: クラスター全体のGateway API監視
- **主要パネル**:
  - Gateway/HTTPRoute数とステータス
  - Policy（Auth, RateLimit, TLS, DNS）適用状況
  - Kuadrantコンポーネント（Authorino, Limitador等）のヘルス
  - CPU/メモリ使用量
  - アラート状態

#### App Developer Dashboard
- **用途**: HTTPRouteごとのアプリケーション監視
- **主要パネル**:
  - リクエストレート（req/sec）
  - HTTPステータスコード分布
  - レイテンシ（p95, p90, p99）
  - エラー率
  - マルチクラスター比較

#### Business User Dashboard
- **用途**: ビジネスメトリクスとトレンド分析
- **主要パネル**:
  - トータルリクエスト数（期間比較）
  - パス別トラフィック
  - 成功率/失敗率
  - リクエスト数の増減トレンド

## 使用方法

### 初回セットアップ

1. **スクリプトに実行権限を付与**:
   ```bash
   chmod +x setup-grafana.sh cleanup-grafana.sh
   ```

2. **セットアップ実行**:
   ```bash
   ./setup-grafana.sh
   ```

3. **セットアップ時間**: 約3-5分
   - Grafana Operatorのインストール（初回のみ）: ~2分
   - Grafanaポッド起動: ~1分
   - メトリクス収集開始: ~1-2分

4. **完了後の確認**:
   ```bash
   # Grafana URL確認
   oc get route grafana-route -n monitoring
   
   # ダッシュボード確認
   oc get grafanadashboard -n monitoring
   
   # Telemetry確認
   oc get telemetry namespace-metrics -n istio-system
   ```

### Grafanaへのアクセス

セットアップ完了後、出力されたURLにアクセスします:

```
URL: https://grafana-route-monitoring.apps.<cluster-domain>
Username: admin
Password: grafana123
```

**ダッシュボードの確認手順**:
1. 左メニュー > Dashboards
2. 以下の3つのダッシュボードが表示されます:
   - Platform Engineer Dashboard
   - App Developer Dashboard
   - Business User Dashboard

### メトリクスの確認

ダッシュボードでデータを表示するには、トラフィックが必要です:

```bash
# APIキー取得
API_KEY=$(oc get secret api-keys -n kuadrant-system -o jsonpath='{.data.api_key}' | base64 -d)

# テストリクエスト送信
curl -k -H "Authorization: APIKEY ${API_KEY}" https://api.<your-domain>/technology
curl -k -H "Authorization: APIKEY ${API_KEY}" https://api.<your-domain>/sports
```

**継続的なトラフィック生成（テスト用）**:
```bash
while true; do
  curl -sk -H "Authorization: APIKEY ${API_KEY}" https://api.<your-domain>/technology
  sleep 2
done
```

## 作成されるリソース一覧

### OpenShift Monitoring Namespace
- `ConfigMap/cluster-monitoring-config` - User Workload Monitoring有効化

### monitoring Namespace
- `ServiceAccount/grafana-serviceaccount`
- `Secret/grafana-serviceaccount-token`
- `Secret/prometheus-bearer-token`
- `Deployment/kube-state-metrics-kuadrant`
- `Service/kube-state-metrics-kuadrant`
- `ServiceMonitor/kube-state-metrics-kuadrant`
- `Grafana/grafana`
- `Route/grafana-route`
- `GrafanaDatasource/prometheus-datasource`
- `GrafanaDashboard/platform-engineer-dashboard`
- `GrafanaDashboard/app-developer-dashboard`
- `GrafanaDashboard/business-user-dashboard`

### istio-system Namespace
- `Telemetry/namespace-metrics`

### openshift-operators Namespace
- `Subscription/grafana-operator` (初回のみ)
- `CSV/grafana-operator.v5.x.x` (初回のみ)

### Cluster-wide
- `ClusterRoleBinding` - grafana-serviceaccount に cluster-monitoring-view 権限

## トラブルシューティング

### ダッシュボードに "No data" が表示される

**原因1: メトリクス収集が開始されていない**
```bash
# kube-state-metrics-kuadrant の確認
oc get pods -n monitoring -l app.kubernetes.io/name=kube-state-metrics-kuadrant
oc logs -n monitoring deployment/kube-state-metrics-kuadrant

# メトリクスが取得できているか確認
oc exec -n openshift-user-workload-monitoring prometheus-user-workload-0 -c prometheus -- \
  promtool query instant http://localhost:9090 'gatewayapi_httproute_labels'
```

**原因2: HTTPRouteにラベルがない**
```bash
# HTTPRouteのラベル確認
oc get httproute -A -o yaml | grep -A5 "labels:"

# 必要なラベル: service=<service-name>, deployment=<deployment-name>
```

**原因3: トラフィックが発生していない**
- テストリクエストを送信してメトリクスを生成

### Grafanaポッドが起動しない

```bash
# Grafana CR の状態確認
oc get grafana grafana -n monitoring -o yaml

# ポッドのイベント確認
oc describe pod -n monitoring -l app=grafana

# Grafana Operator ログ確認
oc logs -n openshift-operators deployment/grafana-operator-controller-manager-v5
```

### "Total requests for selected range" が No Data

**原因: request_url_path ラベルがない**

Telemetry設定を確認:
```bash
# Telemetry確認
oc get telemetry namespace-metrics -n istio-system -o yaml

# メトリクスにラベルがあるか確認
oc exec -n openshift-user-workload-monitoring prometheus-user-workload-0 -c prometheus -- \
  promtool query instant http://localhost:9090 \
  'istio_requests_total{destination_service_name="news-api"}' | grep request_url_path
```

**解決方法**: セットアップスクリプトを再実行してTelemetryを作成

### Prometheus Datasourceが接続できない

```bash
# ServiceAccount トークン確認
oc get secret grafana-serviceaccount-token -n monitoring -o jsonpath='{.data.token}' | base64 -d | wc -c

# Thanos Querier URL確認
oc get route thanos-querier -n openshift-monitoring

# Grafana から Thanos への接続テスト
oc exec -n monitoring deployment/grafana-deployment -- \
  curl -k -H "Authorization: Bearer $(oc get secret prometheus-bearer-token -n monitoring -o jsonpath='{.data.token}' | base64 -d)" \
  https://thanos-querier-openshift-monitoring.<cluster-domain>/api/v1/query?query=up
```

### レイテンシグラフが歯抜けになる

**これは正常な動作です**

- レイテンシメトリクス（ヒストグラム）はリクエストが発生した時のみデータポイントを持ちます
- テスト環境で断続的なトラフィックの場合、グラフは歯抜けになります
- 本番環境で継続的なトラフィックがあれば、連続したグラフになります

## クリーンアップ

### 全リソース削除（Grafana Operatorは保持）

```bash
./cleanup-grafana.sh
# プロンプトで 'y' を入力
# Grafana Operator削除のプロンプトでは 'n' を入力（保持する場合）
```

### Grafana Operatorも含めて完全削除

```bash
./cleanup-grafana.sh
# 両方のプロンプトで 'y' を入力
```

**注意**: Grafana Operatorを削除すると、クラスター内の**すべてのGrafanaインスタンス**に影響します。

### 削除されるリソース

- monitoring namespace内のGrafana関連リソース
- kube-state-metrics-kuadrant
- Istio Telemetry設定
- ServiceAccount と ClusterRoleBinding

### 削除されないリソース（デフォルト）

- User Workload Monitoring設定（他のアプリケーションが使用している可能性があるため）
- Grafana Operator（他のプロジェクトで使用している可能性があるため）
- monitoring namespace（共有リソース）

## 注意事項

### セキュリティ

1. **デフォルトパスワード**: `grafana123` はテスト環境用です。本番環境では強力なパスワードに変更してください
   - スクリプト内の `admin_password` を修正

2. **API Key Secret**: Article 2で作成されたAPIキーは `kuadrant-system` namespaceに配置されています
   - Authorino（認証コンポーネント）と同じnamespaceに配置するのが正しい構成です

3. **権限**: Grafana ServiceAccountには `cluster-monitoring-view` 権限が付与されます
   - クラスター全体のメトリクスを参照可能（書き込み不可）

### パフォーマンス

1. **メトリクス保持期間**: User Workload Monitoringのデフォルトは24時間
   - 長期保存が必要な場合は、別途設定が必要

2. **Telemetry設定の影響**:
   - `request_url_path` 等の追加ラベルはカーディナリティを増加させます
   - 多数の異なるパスがある場合、Prometheusのメモリ使用量が増加する可能性があります

3. **ダッシュボードのリフレッシュ間隔**:
   - デフォルトは自動リフレッシュなし
   - 手動でリフレッシュするか、ダッシュボード設定で間隔を設定してください

### 互換性

- **Connectivity Link**: 1.3.x で動作確認済み
- **OpenShift**: 4.x
- **Grafana Operator**: v5.x（コミュニティ版）
- **ダッシュボード**: Kuadrant operator v1.3.0の公式ダッシュボード

### 既知の制限事項

1. **CPU/Memory Usageパネル（Platform Engineer Dashboard）**:
   - Recording rulesがUser Workload Monitoringに存在しないため、簡略化されたクエリを使用
   - 本家のopenshift-monitoringとは若干異なる可能性があります

2. **マルチクラスター表示**:
   - ダッシュボードはマルチクラスター対応ですが、シングルクラスター環境では一部パネルが空になる場合があります

## 参考リンク

- [Red Hat Connectivity Link Documentation](https://docs.redhat.com/en/documentation/red_hat_connectivity_link/)
- [Kuadrant Operator - Observability](https://github.com/Kuadrant/kuadrant-operator/tree/main/examples/dashboards)
- [OpenShift User Workload Monitoring](https://docs.openshift.com/container-platform/latest/monitoring/enabling-monitoring-for-user-defined-projects.html)
- [Grafana Operator Documentation](https://grafana.github.io/grafana-operator/)
- [Istio Telemetry API](https://istio.io/latest/docs/reference/config/telemetry/)

## ライセンス

これらのスクリプトはRed Hat Connectivity Link公式ドキュメントの補完として提供されています。
