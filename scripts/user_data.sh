#!/bin/bash
# user_data.sh

# ログ出力設定
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "Starting Minecraft Server Setup..."

# システムアップデート
dnf update -y

# Javaのインストール (Java 21 Amazon Corretto)
# Amazon Linux 2023 では java-21-amazon-corretto が利用可能か確認
# 利用できない場合は java-17 をフォールバックとして検討するが、
# AL2023では `dnf search java` で確認可能。通常は最新が提供されている。
dnf install -y java-21-amazon-corretto-headless

if [ $? -ne 0 ]; then
    echo "Java 21 install failed, trying Java 17..."
    dnf install -y java-17-amazon-corretto-headless
fi

# ユーザー作成
if ! id "minecraft" &>/dev/null; then
    useradd -r -m -d /opt/minecraft minecraft
fi

# ディレクトリ作成
mkdir -p /opt/minecraft/server
cd /opt/minecraft/server

# Minecraft Server JARのダウンロード
# バージョン取得ロジックを入れるのが理想だが、ここでは固定URL例、あるいは最新版取得スクリプトを実装
# ここでは簡易的に 1.20.4 (Java 17 compatible) または 最新を取得
# https://piston-meta.mojang.com/mc/game/version_manifest_v2.json から取得可能だが
# jqが必要
dnf install -y jq

# 最新のリリースバージョンURLを取得
MANIFEST_URL="https://piston-meta.mojang.com/mc/game/version_manifest_v2.json"
LATEST_VERSION=$(curl -s $MANIFEST_URL | jq -r '.latest.release')
VERSION_URL=$(curl -s $MANIFEST_URL | jq -r --arg VER "$LATEST_VERSION" '.versions[] | select(.id == $VER) | .url')
SERVER_JAR_URL=$(curl -s $VERSION_URL | jq -r '.downloads.server.url')

echo "Downloading Minecraft Server version $LATEST_VERSION from $SERVER_JAR_URL"
curl -o server.jar "$SERVER_JAR_URL"

# EULA同意
echo "eula=true" > eula.txt

# server.properties の生成
cat <<EOF > server.properties
server-port=25565
enable-rcon=true
rcon.port=25575
rcon.password=${rcon_password}
broadcast-rcon-to-ops=true
difficulty=normal
gamemode=survival
max-players=20
motd=Minecraft Server on AWS
EOF

# 所有権変更
chown -R minecraft:minecraft /opt/minecraft

# Systemd サービス作成
cat <<EOF > /etc/systemd/system/minecraft.service
[Unit]
Description=Minecraft Server
After=network.target

[Service]
User=minecraft
Group=minecraft
WorkingDirectory=/opt/minecraft/server
# メモリ設定はAGENTS.mdより3GB
ExecStart=/usr/bin/java -Xmx3G -Xms3G -jar server.jar nogui
Restart=on-failure
RestartSec=20 5

[Install]
WantedBy=multi-user.target
EOF

# サービス有効化と起動
systemctl daemon-reload
systemctl enable minecraft
systemctl start minecraft

echo "Minecraft Server Setup Completed."
