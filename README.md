# Red Hat Connectivity Link 赤帽エンジニアブログ - サンプルコード

このリポジトリは、Red Hat Connectivity Linkに関するブログ記事シリーズのサンプルコード、設定ファイル、自動化スクリプトを提供します。

## Red Hat Connectivity Link とは

Red Hat Connectivity Linkは、Kuadrantプロジェクトをベースにした、API管理とマイクロサービス間通信のためのエンタープライズグレードのソリューションです。Gateway API、認証・認可、レート制限、DNSルーティング、TLS管理などの機能を提供します。

## ブログ記事シリーズ

| 記事 | タイトル | 内容 | ディレクトリ |
|------|---------|------|------------|
| **第1回** | 導入とインストール | Connectivity Linkの概要とOpenShift環境へのインストール | [`01-introduction_and_install`](01-introduction_and_install/) |
| **第2回** | Gateway APIとPolicy | Gateway、HTTPRoute、AuthPolicy、RateLimitPolicyの基本 | [`02-gateway_and_policy`](02-gateway_and_policy/) |
| **第3回** | 高度な認証設定 | Keycloak統合とJWT認証、ロールベースアクセス制御（RBAC） | [`03-advanced_authentication`](03-advanced_authentication/) |

## 前提条件

| 項目 | 要件 |
|------|------|
| **OpenShift Container Platform** | 4.19以降 |
| **クラスター管理者権限** | 必要 |
| **oc CLI** | インストール済み |
| **Red Hat Connectivity Link** | 1.3.2以降 |

詳細は各ディレクトリのREADME.mdを参照してください。