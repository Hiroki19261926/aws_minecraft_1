# Minecraft Server on AWS with Terraform

このリポジトリは、AWS上にMinecraftサーバーを構築・運用するためのTerraformコードとLambda関数を含んでいます。
コストを抑えつつ（月額500円程度）、Discordからサーバーの起動・停止を行えるように設計されています。

## ⚠️ セキュリティに関する重要な注意

本リポジトリのコードを公開・使用する際は、以下の点に十分注意してください。

### 1. RCONポートの公開について
コスト削減のため、監視用Lambda関数（Monitor Lambda）はVPC外で実行され、MinecraftサーバーのRCONポート（デフォルト: 57000）に対してパブリックIP経由で接続します。
そのため、**RCONポートはインターネット全体（0.0.0.0/0）に対して開放されています。**

*   **強力なRCONパスワードを設定してください。** 推測されやすいパスワードを使用すると、外部からサーバーを操作される危険性があります。
*   可能であれば、自宅のIPアドレスや特定のIP範囲のみに制限することを検討してください（ただし、LambdaのIP範囲は不定なため、Lambdaからの接続を維持しつつ制限するのは難しい場合があります）。

### 2. SSH接続の制限
SSHポート（22）は、`terraform/variables.tf` の `admin_ip` 変数で指定したIPアドレス（管理者）からのみ許可するように設定されています。
意図せず `0.0.0.0/0` に設定しないよう注意してください。

## セットアップ手順

### 1. 前提条件
以下のAWSリソースはTerraform管理外のため、手動で作成する必要があります。

*   **S3バケット**: Terraformのstateファイル保存用
*   **DynamoDBテーブル**: Terraformのstateロック用（パーティションキー: `LockID`）
*   **EC2キーペア**: インスタンス接続用（名称例: `minecraft-key`）

### 2. コンフィグレーション
`terraform/main.tf` を編集し、ご自身の環境に合わせてバックエンド設定を更新してください。

```hcl
terraform {
  backend "s3" {
    bucket         = "YOUR_BUCKET_NAME"   # 作成したS3バケット名
    key            = "minecraft/prod/terraform.tfstate"
    region         = "ap-northeast-1"
    dynamodb_table = "YOUR_DYNAMODB_TABLE" # 作成したDynamoDBテーブル名
    encrypt        = true
  }
}
```

### 3. 変数の設定
`terraform/variables.tf` または `terraform.tfvars` (作成する場合) で必要な変数を設定してください。
GitHub Actionsを使用する場合は、Secretsに以下の値を設定する必要があります。

*   `AWS_ACCESS_KEY_ID`
*   `AWS_SECRET_ACCESS_KEY`
*   `DISCORD_APP_ID`
*   `DISCORD_PUBLIC_KEY`
*   `RCON_PASSWORD`

## アーキテクチャ概要
詳細は `agents.md` を参照してください。

*   **EC2**: Minecraftサーバー (t4g.medium)
*   **Lambda (discord_bot)**: Discordからのコマンド (start/stop) を処理
*   **Lambda (monitor)**: プレイヤー数を監視し、無人状態が続くと自動停止
*   **API Gateway**: Discord Interactionsのエンドポイント
