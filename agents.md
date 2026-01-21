# Minecraft Server on AWS - プロジェクト仕様書

## 1. プロジェクト概要

個人用のMinecraftマルチプレイサーバーをAWS上に構築する。
最大6人程度でのプレイを想定し、コストを抑えながらも安定した運用を目指す。

### 目標
- 月額500円程度に収める
- AWSの知識がない人でも簡単に起動/停止できる（Discord経由）
- ワールドデータは永続化し、前回の状態から再開できる

---

## 2. アーキテクチャ

### 全体構成図

```
┌─────────────────────────────────────────────────────────────────┐
│                         全体アーキテクチャ                        │
└─────────────────────────────────────────────────────────────────┘

[Discord]
    │
    │ /mc start, /mc stop, /mc status コマンド
    ↓
[API Gateway] ←── Discord Interactions Webhook
    │
    ↓
[Lambda: discord_bot]
    │
    ├──→ EC2 起動/停止 (boto3)
    └──→ ステータス確認

[CloudWatch Events] ──(5分毎)──→ [Lambda: monitor]
                                      │
                                      ↓
                                 [RCON で Minecraft に問い合わせ]
                                      │
                                      ↓
                                 [0人が1時間続いたら EC2 停止]

[EC2: Minecraft Server (t4g.medium)]
    │
    ├── EBS (30GB gp3): ワールドデータ永続化
    ├── Security Group: 25565(MC), 25575(RCON), 22(SSH)
    └── User Data: 初回起動時に自動セットアップ

[S3]
    └── tfstate 保存用（※Terraform管理外、手動作成）

[DynamoDB]
    └── tfstate ロック用（※Terraform管理外、手動作成）

[SSM Parameter Store]
    └── 0人カウンター保存
```

### AWSリソース一覧

| リソース | 用途 | Terraform管理 |
|----------|------|---------------|
| EC2 (t4g.medium) | Minecraftサーバー | ✅ |
| EBS (30GB, gp3) | ワールドデータ永続化 | ✅ |
| Lambda (discord_bot) | Discord連携・起動/停止 | ✅ |
| Lambda (monitor) | プレイヤー監視・自動停止 | ✅ |
| API Gateway (HTTP API) | Discord Webhook受信 | ✅ |
| CloudWatch Events | 5分毎の監視トリガー | ✅ |
| SSM Parameter Store | 0人カウンター保存 | ✅ |
| Security Group | ネットワークアクセス制御 | ✅ |
| IAM Role/Policy | Lambda/EC2実行権限 | ✅ |
| VPC | ネットワーク（デフォルトVPC使用） | ❌ 既存利用 |
| S3 (tfstate用) | Terraform状態管理 | ❌ 手動作成 |
| DynamoDB (tfstate lock用) | 同時実行防止 | ❌ 手動作成 |

---

## 3. 技術仕様

### 3.1 EC2インスタンス

- **インスタンスタイプ**: t4g.medium（2vCPU, 4GB RAM, ARM64）
- **AMI**: Amazon Linux 2023（ARM64）
- **ストレージ**: EBS gp3 30GB（ルートボリューム兼データ用）
- **購入オプション**: オンデマンド（スポットインスタンスは使用しない）
- **キーペア**: 新規作成（SSH接続用、トラブルシューティング用途）

### 3.2 Minecraftサーバー

- **エディション**: Java版
- **バージョン**: 最新安定版（セットアップ時に自動取得）
- **ポート**: 
  - 25565（ゲーム接続用）
  - 25575（RCON、内部監視用）
- **RCON**: 有効化（プレイヤー数監視のため）
- **メモリ割当**: 3GB（-Xmx3G -Xms3G）
- **セットアップ方式**: EC2 User Dataスクリプトで自動構築

### 3.3 Discord Bot

- **方式**: Interactions（Webhook）方式 ※常時接続ではない
- **実行環境**: Lambda + API Gateway (HTTP API)
- **ランタイム**: Python 3.12
- **コマンド一覧**:

| コマンド | 説明 | 処理内容 |
|----------|------|----------|
| `/mc start` | サーバー起動 | EC2インスタンスを起動 |
| `/mc stop` | サーバー停止 | EC2インスタンスを停止 |
| `/mc status` | 状態確認 | 起動状態・IPアドレス・プレイヤー数を表示 |

### 3.4 自動停止機能

- **監視間隔**: 5分（CloudWatch Events）
- **停止条件**: プレイヤー0人が連続12回（= 約1時間）検知された場合
- **カウンター管理**: SSM Parameter Store に保存
- **処理フロー**:
  1. CloudWatch Events が5分ごとにLambda (monitor) を起動
  2. Lambda が RCON 経由で `list` コマンドを実行
  3. プレイヤー数を取得し、0人ならカウンターをインクリメント
  4. 1人以上ならカウンターをリセット
  5. カウンターが12に達したらEC2を停止

### 3.5 ネットワーク・セキュリティ

#### Security Group (Minecraftサーバー用)

| ルール | ポート | プロトコル | ソース | 用途 |
|--------|--------|------------|--------|------|
| インバウンド | 25565 | TCP | 0.0.0.0/0 | Minecraft接続 |
| インバウンド | 25575 | TCP | Lambda SG | RCON（Lambda専用） |
| インバウンド | 22 | TCP | 管理者IP (変数指定) | SSH接続 |
| アウトバウンド | 全て | 全て | 0.0.0.0/0 | インターネットアクセス |

#### Security Group (Lambda用)

| ルール | ポート | プロトコル | ソース | 用途 |
|--------|--------|------------|--------|------|
| アウトバウンド | 25575 | TCP | MC SG | RCON接続 |
| アウトバウンド | 443 | TCP | 0.0.0.0/0 | AWS API呼び出し |

---

## 4. ディレクトリ構成

```
/
├── terraform/
│   ├── main.tf              # プロバイダー設定、バックエンド設定
│   ├── variables.tf         # 変数定義
│   ├── outputs.tf           # 出力値定義
│   ├── versions.tf          # Terraformバージョン制約
│   ├── ec2.tf               # EC2、EBS、キーペア
│   ├── lambda.tf            # Lambda関数定義
│   ├── api_gateway.tf       # API Gateway設定
│   ├── cloudwatch.tf        # CloudWatch Events
│   ├── iam.tf               # IAMロール・ポリシー
│   ├── security_groups.tf   # セキュリティグループ
│   └── ssm.tf               # SSM Parameter Store
│
├── lambda/
│   ├── discord_bot/
│   │   ├── index.py         # Discord Botハンドラー
│   │   └── requirements.txt # 依存ライブラリ（nacl等）
│   │
│   └── monitor/
│       ├── index.py         # プレイヤー監視処理
│       └── requirements.txt # 依存ライブラリ（mcrcon等）
│
├── scripts/
│   └── user_data.sh         # EC2初期化スクリプト（Minecraftセットアップ）
│
├── .github/
│   └── workflows/
│       └── terraform.yml    # CI/CDパイプライン
│
└── agents.md                # この仕様書
```

---

## 5. Terraform設計方針

### 5.1 Backend設定 (main.tf)

```hcl
terraform {
  backend "s3" {
    bucket         = "＜S3バケット名：後で指定＞"
    key            = "minecraft/terraform.tfstate"
    region         = "ap-northeast-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}
```

### 5.2 変数定義 (variables.tf)

| 変数名 | 型 | 説明 | デフォルト値 |
|--------|-----|------|--------------|
| `aws_region` | string | AWSリージョン | `ap-northeast-1` |
| `instance_type` | string | EC2インスタンスタイプ | `t4g.medium` |
| `volume_size` | number | EBSボリュームサイズ(GB) | `30` |
| `discord_app_id` | string | Discord Application ID | （必須・Secret経由） |
| `discord_public_key` | string | Discord Public Key | （必須・Secret経由） |
| `admin_ip` | string | SSH許可IPアドレス | `null`（指定時のみSSH許可） |
| `rcon_password` | string | RCON認証パスワード | （必須・Secret経由） |
| `minecraft_port` | number | Minecraftポート | `25565` |
| `rcon_port` | number | RCONポート | `25575` |

### 5.3 出力定義 (outputs.tf)

| 出力名 | 説明 |
|--------|------|
| `ec2_instance_id` | MinecraftサーバーのインスタンスID |
| `api_gateway_url` | Discord Webhook用エンドポイントURL |
| `minecraft_server_ip` | 接続用Elastic IP（または動的IP取得方法） |

---

## 6. GitHub Actions設計方針

### 6.1 ワークフロー (.github/workflows/terraform.yml)

```yaml
name: Terraform CI/CD

on:
  push:
    branches:
      - main
    paths:
      - 'terraform/**'
      - 'lambda/**'
      - 'scripts/**'
  pull_request:
    branches:
      - main
    paths:
      - 'terraform/**'
      - 'lambda/**'
      - 'scripts/**'

env:
  TF_VERSION: "1.6.0"
  AWS_REGION: "ap-northeast-1"

jobs:
  terraform:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: terraform

    steps:
      - uses: actions/checkout@v4

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Terraform Format Check
        run: terraform fmt -check -recursive

      - name: Terraform Init
        run: terraform init

      - name: Terraform Validate
        run: terraform validate

      - name: Terraform Plan
        if: github.event_name == 'pull_request'
        run: terraform plan -no-color
        env:
          TF_VAR_discord_app_id: ${{ secrets.DISCORD_APP_ID }}
          TF_VAR_discord_public_key: ${{ secrets.DISCORD_PUBLIC_KEY }}
          TF_VAR_rcon_password: ${{ secrets.RCON_PASSWORD }}

      - name: Terraform Apply
        if: github.ref == 'refs/heads/main' && github.event_name == 'push'
        run: terraform apply -auto-approve
        env:
          TF_VAR_discord_app_id: ${{ secrets.DISCORD_APP_ID }}
          TF_VAR_discord_public_key: ${{ secrets.DISCORD_PUBLIC_KEY }}
          TF_VAR_rcon_password: ${{ secrets.RCON_PASSWORD }}
```

### 6.2 必要なGitHub Secrets

| Secret名 | 説明 | 取得方法 |
|----------|------|----------|
| `AWS_ACCESS_KEY_ID` | AWSアクセスキーID | IAMユーザー作成時 |
| `AWS_SECRET_ACCESS_KEY` | AWSシークレットアクセスキー | IAMユーザー作成時 |
| `DISCORD_APP_ID` | Discord Application ID | Discord Developer Portal |
| `DISCORD_PUBLIC_KEY` | Discord Public Key | Discord Developer Portal |
| `RCON_PASSWORD` | RCON認証用パスワード | 任意の文字列を設定 |

---

## 7. 前提条件（手動で事前準備が必要なもの）

### 7.1 AWS側の準備

以下は「鶏と卵」問題を避けるため、Terraform実行前に手動で作成する：

1. **S3バケット** (tfstate保存用)
   - バケット名: `＜任意の一意な名前＞`
   - リージョン: ap-northeast-1
   - バージョニング: 有効推奨
   - パブリックアクセス: 全てブロック

2. **DynamoDBテーブル** (tfstateロック用)
   - テーブル名: `terraform-locks`
   - パーティションキー: `LockID` (String)
   - 課金モード: オンデマンド

3. **IAMユーザー** (GitHub Actions用)
   - ユーザー名: `github-actions-terraform`
   - 必要なポリシー: EC2, Lambda, API Gateway, IAM, SSM, CloudWatch等への権限

### 7.2 Discord側の準備

1. **Discordサーバー作成**
   - 任意の名前でサーバーを作成

2. **Discord Developer PortalでApplication作成**
   - https://discord.com/developers/applications
   - 「New Application」からアプリケーション作成
   - Application ID と Public Key をメモ

3. **Botの有効化**
   - Applicationの「Bot」タブでBotを作成
   - 必要な権限を設定

4. **Interactions Endpoint URL設定**
   - Terraform apply後に出力されるAPI Gateway URLを設定

---

## 8. 実装上の注意点

### 8.1 Discord Interactions の署名検証

Discord からのリクエストは署名検証が必須。Lambda内で `nacl` ライブラリを使用して検証すること。

```python
from nacl.signing import VerifyKey
from nacl.exceptions import BadSignatureError

def verify_signature(event, public_key):
    signature = event['headers'].get('x-signature-ed25519')
    timestamp = event['headers'].get('x-signature-timestamp')
    body = event['body']
    
    verify_key = VerifyKey(bytes.fromhex(public_key))
    try:
        verify_key.verify(f'{timestamp}{body}'.encode(), bytes.fromhex(signature))
        return True
    except BadSignatureError:
        return False
```

### 8.2 RCON接続

mcrcon ライブラリまたはソケット直接接続でRCON通信を行う。

```python
from mcrcon import MCRcon

def get_player_count(host, password, port=25575):
    with MCRcon(host, password, port) as mcr:
        response = mcr.command("list")
        # "There are X of a max of Y players online: ..." をパース
        # 例: "There are 0 of a max of 20 players online:"
```

### 8.3 EC2の状態遷移待機

起動/停止コマンド後、Discord には即座に応答を返し、バックグラウンドで状態確認を行うか、「起動を開始しました」のような応答にする。（Discordは3秒以内の応答を要求）

---

## 9. コスト見積もり

| リソース | 単価 | 月間見積もり（週15時間稼働想定） |
|----------|------|----------------------------------|
| EC2 t4g.medium | ¥3.3/時間 | ¥200 (60時間) |
| EBS 30GB gp3 | ¥10/GB/月 | ¥300 |
| Lambda | 無料枠内 | ¥0 |
| API Gateway | 無料枠内 | ¥0 |
| CloudWatch | 無料枠内 | ¥0 |
| データ転送 | 微量 | ¥0〜50 |
| **合計** | | **¥500〜550/月** |

※ 稼働時間によって変動。週15時間（月60時間）を超える場合は増加。

---

## 10. 未決定事項・TODO

- [ ] S3バケット名の決定・作成
- [ ] DynamoDBテーブルの作成
- [ ] Discord Application作成・各種IDの取得
- [ ] GitHub SecretsへのAWS認証情報登録
- [ ] SSH用キーペアの命名規則
- [ ] 将来的な追加機能の検討
  - [ ] S3へのワールドデータ定期バックアップ
  - [ ] Minecraftバージョン更新の自動化

## 11. 開発ルール（Julesへの指示）

### 11.1 基本方針

- 作業依頼時は一度作業が完了した後、もう一度自身で振り返りを行い品質を担保した上で、プルリクエストまで実施する
- コード内のコメントは厚めにつける
- コード内のコメントやプルリクエスト作成時の文言など、コード本体以外の部分は日本語で作成する

### 11.2 ブランチ戦略

- 作業ごとにブランチを作成する（直接mainにコミットしない）
- **ブランチ命名規則**: `jules-＜作業内容＞`
  - 例: `jules-terraform-ec2`
  - 例: `jules-lambda-discord-bot`
  - 例: `jules-github-actions`
  - 例: `jules-bugfix-security-group`
- 作業完了後は `main` ブランチへプルリクエストを作成する

### 11.3 コミットルール

- **1リソース or 1機能の修正ごとにコミット**する（まとめてコミットしない）
- 作業履歴が見返しやすいように、細かくコミットを分ける
- コミットメッセージは**日本語**で記述する
- コミットメッセージには修正内容を明確に記載する
- コミットメッセージのフォーマット例:
  ```
  [追加] EC2インスタンスの定義を作成
  [追加] Minecraftサーバー用セキュリティグループを作成
  [修正] セキュリティグループのポート設定を変更
  [修正] Lambda関数のタイムアウト値を調整
  [削除] 不要な変数定義を削除
  [修正] typoの修正
  ```

### 11.4 プルリクエスト（PR）ルール

- PRのタイトル・説明は**日本語**で記述する
- PRの説明には以下を含める:
  - 変更の概要
  - 変更したファイル一覧
  - 動作確認の有無（該当する場合）
  - 関連するセクション番号（例: 「3.1 EC2インスタンス」に対応）
- レビュー依頼時は変更点がわかりやすいように記載する

### 11.5 言語ルールまとめ

| 対象 | 言語 |
|------|------|
| コミットメッセージ | 日本語 |
| PRタイトル・説明 | 日本語 |
| コード内コメント | 日本語 |
| ファイル名 | 英語（スネークケース推奨） |
| 変数名・関数名 | 英語（スネークケース推奨） |
| Terraformリソース名 | 英語（スネークケース） |
