import os
import boto3
from mcrcon import MCRcon
import logging

# ログ設定の構成
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# 環境変数から設定値を取得
INSTANCE_ID = os.environ.get('INSTANCE_ID')
RCON_PORT = int(os.environ.get('RCON_PORT', 25575))
RCON_PASSWORD = os.environ.get('RCON_PASSWORD')
SSM_PARAM_NAME = '/minecraft/player_zero_count'
STOP_THRESHOLD = 12  # 5分間隔×12回 = 連続60分プレイヤー0人で停止

# AWS クライアントの初期化
ec2 = boto3.client('ec2')
ssm = boto3.client('ssm')

def get_instance_public_ip(instance_id):
    """
    指定されたインスタンスIDのパブリックIPアドレスを取得します。

    Args:
        instance_id (str): EC2インスタンスID

    Returns:
        str: パブリックIPアドレス。取得できない場合は None
    """
    try:
        response = ec2.describe_instances(InstanceIds=[instance_id])
        reservations = response.get('Reservations', [])
        if not reservations:
            return None
        instances = reservations[0].get('Instances', [])
        if not instances:
            return None
        return instances[0].get('PublicIpAddress')
    except Exception as e:
        logger.error(f"Error describing instance: {e}")
        return None

def get_player_count(host, password, port):
    """
    RCONを使用してMinecraftサーバーの現在のプレイヤー数を取得します。

    Args:
        host (str): サーバーのホスト名またはIPアドレス
        password (str): RCONパスワード
        port (int): RCONポート番号

    Returns:
        int: プレイヤー数。接続エラー等は None
    """
    try:
        with MCRcon(host, password, port=port) as mcr:
            response = mcr.command("list")
            logger.info(f"RCON response: {response}")
            # 想定される応答形式: "There are X of a max of Y players online: ..."
            # 例: "There are 0 of a max of 20 players online: "

            parts = response.split(" ")
            # 簡易パースロジック。Minecraftの出力形式が変わった場合は調整が必要。
            # "There are 0 of a max of 20 players online:" -> parts[2] が人数
            if len(parts) >= 3 and parts[2].isdigit():
                return int(parts[2])
            else:
                logger.warning(f"Unexpected RCON response format: {response}")
                return 0 # 形式不明時は安全側に倒して0とするか迷うが、一旦0として扱う（要検討）
    except Exception as e:
        logger.error(f"RCON Connection failed: {e}")
        return None

def update_zero_count(count):
    """
    プレイヤー0人の連続回数をSSMパラメータストアに保存します。

    Args:
        count (int): 現在のカウント数
    """
    try:
        ssm.put_parameter(
            Name=SSM_PARAM_NAME,
            Value=str(count),
            Type='String',
            Overwrite=True
        )
    except Exception as e:
        logger.error(f"Failed to update SSM parameter: {e}")

def get_zero_count():
    """
    SSMパラメータストアから現在のプレイヤー0人連続回数を取得します。

    Returns:
        int: 現在のカウント数。取得できない場合は 0
    """
    try:
        response = ssm.get_parameter(Name=SSM_PARAM_NAME)
        return int(response['Parameter']['Value'])
    except ssm.exceptions.ParameterNotFound:
        return 0
    except Exception as e:
        logger.error(f"Failed to get SSM parameter: {e}")
        return 0

def handler(event, context):
    """
    監視Lambdaのメインハンドラー。
    EC2の状態を確認し、RCONでプレイヤー数をチェック、
    条件を満たせばサーバーを自動停止します。
    """
    logger.info("Monitor function started.")

    # インスタンスが起動しているか確認
    try:
        response = ec2.describe_instance_status(InstanceIds=[INSTANCE_ID], IncludeAllInstances=True)
        statuses = response.get('InstanceStatuses', [])
        if not statuses:
            logger.info("Instance status not found. Assuming stopped.")
            return

        state = statuses[0].get('InstanceState', {}).get('Name')
        if state != 'running':
            logger.info(f"Instance is {state}. Skipping check.")
            # サーバー停止中はカウンターをリセットしておく（次回起動時に影響しないように）
            update_zero_count(0)
            return

    except Exception as e:
        logger.error(f"Error checking instance status: {e}")
        return

    public_ip = get_instance_public_ip(INSTANCE_ID)
    if not public_ip:
        logger.error("Could not find public IP. Instance might be initializing.")
        return

    player_count = get_player_count(public_ip, RCON_PASSWORD, RCON_PORT)

    current_zero_count = get_zero_count()

    if player_count is None:
        logger.info("Could not connect to RCON. Server might be starting or down.")
        # 接続失敗時はカウントアップしない（メンテナンス中や起動処理中の誤停止を防ぐため）
        return

    logger.info(f"Player count: {player_count}")

    if player_count == 0:
        new_count = current_zero_count + 1
        logger.info(f"Zero players. Incrementing counter to {new_count}.")
        update_zero_count(new_count)

        if new_count >= STOP_THRESHOLD:
            logger.info("Threshold reached. Stopping instance.")
            ec2.stop_instances(InstanceIds=[INSTANCE_ID])
            update_zero_count(0) # 停止命令後はリセット
    else:
        if current_zero_count > 0:
            logger.info("Players detected. Resetting counter.")
            update_zero_count(0)
        else:
            logger.info("Players detected. Counter already 0.")

    return {"status": "ok"}
