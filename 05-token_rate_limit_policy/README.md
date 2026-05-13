# Red Hat Connectivity Link - Token-based Rate Limiting for LLM APIs

このディレクトリには、Red Hat Connectivity Link 1.3のトークンベースレート制限（TokenRateLimitPolicy）を体験するための自動セットアップスクリプトが含まれています。

## 概要

OpenAI互換のモックLLM APIサービスをデプロイし、**TokenRateLimitPolicy**を使用してトークン消費量に基づくレート制限を実装します。従来のリクエスト数ベースの制限ではなく、実際のトークン使用量（`usage.total_tokens`）に基づいた精密な制限が可能です。

### セットアップされるコンポーネント

1. **Mock LLM API** - OpenAI互換のテストAPIサービス
   - Flask製のシンプルなモックサーバー
   - `/v1/chat/completions` エンドポイントを提供
   - `usage.total_tokens` フィールドを含むレスポンスを返す

2. **HTTP Gateway** - LLM API用のシンプルなGateway
   - ホスト名: `*.llm-api.local`
   - プロトコル: HTTP（テスト環境用）

3. **HTTPRoute** - モックLLM APIへのルーティング
   - パス: `/v1/chat/completions` (POST)
   - バックエンド: mock-llm-api:8080

4. **TokenRateLimitPolicy** - トークンベースのレート制限
   - 制限値: 1分あたり1,000トークン
   - カウンター: 全リクエスト共通（テスト用）

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

3. **適切な権限**:
   - Namespaceの作成権限
   - Gateway, HTTPRoute, TokenRateLimitPolicyの作成権限

### 推奨要件

- **Article 1 (Connectivity Linkインストール)** 完了済み
- `jq` コマンドがインストール済み（JSONレスポンスの確認用）

## セットアップ内容の詳細

### 1. Mock LLM API

OpenAI互換のモックサービスを提供します。実際のGPUやモデルは不要です。

- **namespace**: `llm-api`
- **エンドポイント**: `/v1/chat/completions` (POST)
- **レスポンス形式**:
  ```json
  {
    "id": "chatcmpl-1234567",
    "object": "chat.completion",
    "model": "mock-llm",
    "choices": [...],
    "usage": {
      "prompt_tokens": 12,
      "completion_tokens": 142,
      "total_tokens": 154
    }
  }
  ```
- **トークン計算**:
  - `prompt_tokens`: 入力文字数 / 4（簡易推定）
  - `completion_tokens`: max_tokensの70-90%（ランダム）

### 2. HTTP Gateway

シンプルなHTTPゲートウェイでLLM APIを公開します。

- **namespace**: `llm-gateway`
- **リスナー**:
  - ホスト名: `*.llm-api.local`
  - ポート: 80
  - プロトコル: HTTP

### 3. TokenRateLimitPolicy

トークン消費量に基づくレート制限を実装します。

- **namespace**: `llm-api`
- **API Version**: `kuadrant.io/v1alpha1`
- **制限設定**:
  - 制限値: 1,000トークン / 分
  - ウィンドウ: 1分間
  - カウンター: `expression: "1"` （全リクエスト共通）

**重要**: 本番環境では、AuthPolicyと統合して`auth.identity.userid`を使用し、ユーザーごとに制限することを推奨します。

## 使用方法

### 初回セットアップ

1. **スクリプトに実行権限を付与**:
   ```bash
   chmod +x setup-token-rate-limit.sh cleanup-token-rate-limit.sh
   ```

2. **セットアップ実行**:
   ```bash
   ./setup-token-rate-limit.sh
   ```

3. **セットアップ時間**: 約2-3分
   - Mock LLM APIポッド起動: ~1分
   - Gateway/HTTPRoute作成: ~1分
   - TokenRateLimitPolicy適用: 即時

4. **完了後の確認**:
   ```bash
   # Gateway確認
   oc get gateway llm-gateway -n llm-gateway
   
   # HTTPRoute確認
   oc get httproute llm-api -n llm-api
   
   # TokenRateLimitPolicy確認
   oc get tokenratelimitpolicy llm-api-token-limit -n llm-api
   
   # Mock LLM API確認
   oc get pods -n llm-api
   ```

### LLM APIのテスト

セットアップ完了後、port-forward経由でテストします。

**1. Port-forwardの開始**（別ターミナル）:
```bash
oc port-forward -n llm-gateway service/llm-gateway-istio 8080:80
```

**2. 正常リクエストのテスト**:
```bash
curl -X POST http://localhost:8080/v1/chat/completions \
  -H "Host: api.llm-api.local" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mock-llm",
    "messages": [
      {"role": "user", "content": "What is OpenShift?"}
    ],
    "max_tokens": 200
  }' | jq .
```

**期待されるレスポンス**:
```json
{
  "choices": [...],
  "usage": {
    "prompt_tokens": 4,
    "completion_tokens": 142,
    "total_tokens": 146
  }
}
```

**3. レート制限のテスト**:
```bash
for i in {1..10}; do
  echo "=== Request $i ==="
  response=$(curl -s -X POST http://localhost:8080/v1/chat/completions \
    -H "Host: api.llm-api.local" \
    -H "Content-Type: application/json" \
    -d '{
      "model": "mock-llm",
      "messages": [{"role": "user", "content": "What is OpenShift?"}],
      "max_tokens": 200
    }')
  echo "$response" | jq -r '.usage.total_tokens' 2>/dev/null || echo "$response"
  sleep 1
done
```

**期待される動作**:
- 最初の6-8リクエスト: トークン数が表示される（例: 152, 172, 151...）
- 累計が1,000トークンを超えた後: `Too Many Requests` が返される
- 1分後: カウンターがリセットされ、再びリクエスト可能

### メトリクスの確認

トークン消費状況をOpenShift Web Consoleで確認できます。

**手順**:
1. OpenShift Web Consoleにログイン
2. 左メニューから **Observe** > **Metrics** を選択
3. クエリ入力欄に以下を入力:
   ```
   authorized_hits{limitador_namespace="llm-api/llm-api"}
   ```
4. **Run queries** をクリック

**グラフの見方**:
- Y軸: 累計トークン消費量
- X軸: 時刻
- グラフは階段状に上昇し、リクエストごとのトークン消費を表示

## 作成されるリソース一覧

### llm-api Namespace
- `ConfigMap/mock-llm-api` - Flaskアプリケーションコード
- `Deployment/mock-llm-api` - モックLLM APIサーバー
- `Service/mock-llm-api` - ClusterIPサービス（8080ポート）
- `HTTPRoute/llm-api` - Gatewayへのルーティング設定
- `TokenRateLimitPolicy/llm-api-token-limit` - トークンベースレート制限

### llm-gateway Namespace
- `Gateway/llm-gateway` - HTTP Gateway（Istio）

## トークンベースレート制限の仕組み

### 従来のリクエストベース vs トークンベース

| 特徴 | リクエストベース | トークンベース |
|-----|---------------|--------------|
| **公平性** | リクエスト数のみ | 実際の使用量 |
| **コスト管理** | 困難 | 精密 |
| **悪用防止** | 脆弱 | 強固 |

### トークンカウントのフロー

1. **クライアント** → Gateway経由でリクエスト送信
2. **Gateway** → バックエンドLLM APIに転送
3. **LLM API** → レスポンスに`usage.total_tokens`を含めて返却
4. **TokenRateLimitPolicy** → レスポンスから`usage.total_tokens`を自動抽出
5. **Limitador** → トークン数をカウンターに加算、制限チェック
6. **Gateway** → 制限内なら200 OK、超過なら429 Too Many Requests

### TokenRateLimitPolicyの特徴

- **自動トークン抽出**: レスポンスの`usage.total_tokens`を自動的に抽出
- **累積カウント**: 1分間のウィンドウ内でトークン数を累積
- **OpenAI互換**: OpenAI API互換のレスポンス形式に対応
- **柔軟な制限**: ユーザー、ティア、モデルごとに異なる制限が可能

## トラブルシューティング

### Mock LLM APIが起動しない

```bash
# ポッドのステータス確認
oc get pods -n llm-api

# ログ確認
oc logs -n llm-api deployment/mock-llm-api

# よくある原因: emptyDirボリュームの問題
# 対処: デプロイメントを再作成
oc delete deployment mock-llm-api -n llm-api
./setup-token-rate-limit.sh
```

### レート制限が動作しない

**原因1: TokenRateLimitPolicyが適用されていない**
```bash
# TokenRateLimitPolicyの状態確認
oc get tokenratelimitpolicy llm-api-token-limit -n llm-api -o yaml

# HTTPRouteとの紐付け確認
oc get httproute llm-api -n llm-api -o yaml
```

**原因2: Limitadorが起動していない**
```bash
# Limitadorポッドの確認
oc get pods -n kuadrant-system -l app=limitador

# Limitadorログ確認
oc logs -n kuadrant-system -l app=limitador
```

### メトリクスが表示されない

**原因: リクエストが送信されていない**
- トラフィックを生成するまでメトリクスは表示されません
- port-forward経由でテストリクエストを送信してください

**原因: Prometheusがメトリクスを収集していない**
```bash
# Kuadrant observability設定確認
oc get kuadrant kuadrant -n kuadrant-system -o jsonpath='{.spec.observability}'
# 出力: {"enable":true}
```

### Port-forwardが接続できない

```bash
# Gatewayサービスの確認
oc get service -n llm-gateway

# 正しいサービス名でport-forward
oc port-forward -n llm-gateway service/llm-gateway-istio 8080:80
```

## クリーンアップ

### 全リソース削除

```bash
./cleanup-token-rate-limit.sh
# プロンプトで 'y' を入力
```

### 削除されるリソース

- `llm-api` namespace内の全リソース
- `llm-gateway` namespace内の全リソース
- 両namespaceも削除

### 削除されないリソース

- Red Hat Connectivity Link（Kuadrant）
- kuadrant-system namespace

## 発展的な内容

本セットアップはトークンベースレート制限の基本動作確認用です。以下の発展的な内容は含まれていません：

### AuthPolicyとの統合

現在のカウンター設定:
```yaml
counters:
- expression: "1"
```

本番環境での推奨設定:
```yaml
counters:
- expression: auth.identity.userid
```

AuthPolicyと統合することで、ユーザーごとに独立したトークンカウンターを作成できます。

### ティア別制限

Free、Pro、Enterpriseプランなど、ユーザーティアごとに異なるトークン制限を設定できます。

### HTTPS公開

TLS PolicyとDNS Policyを使用して、外部にHTTPS公開できます。

### コスト追跡

トークン単価を設定し、実際のコストを追跡・予算管理できます。

### メトリクス監視

Grafanaダッシュボードでトークン消費状況、コスト、トレンドを可視化できます。

## 参考リンク

- [Red Hat Connectivity Link Documentation](https://docs.redhat.com/en/documentation/red_hat_connectivity_link/)
- [Kuadrant TokenRateLimitPolicy](https://docs.kuadrant.io/)
- [OpenAI API Reference](https://platform.openai.com/docs/api-reference)
- [OpenShift AI Documentation](https://access.redhat.com/documentation/ja-jp/red_hat_openshift_ai/)

## 注意事項

### セキュリティ

1. **モックサービス**: 本番環境では実際のLLMサービング基盤（OpenShift AI等）を使用してください
2. **HTTP**: テスト環境用。本番環境ではHTTPSを使用してください
3. **カウンター設定**: 全ユーザー共通。本番環境ではAuthPolicyと統合してください

### パフォーマンス

1. **トークン推定**: モックAPIの推定は簡易的なものです。実際のLLMは正確なトークン数を返します
2. **レート制限値**: 1,000トークン/分はテスト用の小さい値です。本番環境では適切な値を設定してください

### 互換性

- **Connectivity Link**: 1.3.x で動作確認済み
- **OpenShift**: 4.14以降
- **TokenRateLimitPolicy**: API Version `kuadrant.io/v1alpha1`

## ライセンス

このセットアップスクリプトはRed Hat Connectivity Link公式ドキュメントの補完として提供されています。
