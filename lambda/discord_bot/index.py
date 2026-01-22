import json
import os
import boto3
from nacl.signing import VerifyKey
from nacl.exceptions import BadSignatureError

# 環境変数から Discord の公開鍵と EC2 インスタンス ID を取得
DISCORD_PUBLIC_KEY = os.environ.get('DISCORD_PUBLIC_KEY')
INSTANCE_ID = os.environ.get('INSTANCE_ID')

# EC2 クライアントの初期化
ec2 = boto3.client('ec2')

def verify_signature(event):
    """
    Discord からのリクエスト署名を検証します。

    Args:
        event (dict): Lambda イベントオブジェクト

    Returns:
        bool: 署名が有効な場合は True、それ以外は False
    """
    if not DISCORD_PUBLIC_KEY:
        return False

    try:
        # ヘッダーから署名とタイムスタンプを取得
        signature = event['headers'].get('x-signature-ed25519')
        timestamp = event['headers'].get('x-signature-timestamp')
        body = event.get('body', '')

        if not signature or not timestamp:
            return False

        # 公開鍵を使って署名を検証
        verify_key = VerifyKey(bytes.fromhex(DISCORD_PUBLIC_KEY))
        verify_key.verify(f'{timestamp}{body}'.encode(), bytes.fromhex(signature))
        return True
    except (BadSignatureError, Exception):
        return False

def handle_command(command_name):
    """
    指定されたコマンドに基づいて EC2 インスタンスの操作や状態確認を行います。

    Args:
        command_name (str): 実行するコマンド名 ('start', 'stop', 'status')

    Returns:
        str: 実行結果のメッセージ
    """
    if command_name == 'start':
        # インスタンスを起動
        ec2.start_instances(InstanceIds=[INSTANCE_ID])
        return "Minecraftサーバーを起動しました。数分お待ちください。"

    elif command_name == 'stop':
        # インスタンスを停止
        ec2.stop_instances(InstanceIds=[INSTANCE_ID])
        return "Minecraftサーバーを停止しました。"

    elif command_name == 'status':
        try:
            # インスタンスの状態を取得
            response = ec2.describe_instances(InstanceIds=[INSTANCE_ID])
            state = response['Reservations'][0]['Instances'][0]['State']['Name']
            public_ip = response['Reservations'][0]['Instances'][0].get('PublicIpAddress', 'None')

            msg = f"ステータス: {state}"
            if state == 'running':
                msg += f"\nIPアドレス: {public_ip}"
            return msg
        except Exception as e:
            return f"ステータス取得エラー: {str(e)}"

    return "不明なコマンドです。"

def handler(event, context):
    """
    Lambda 関数のメインハンドラー。
    Discord からのリクエストを受け取り、適切な処理を行います。

    Args:
        event (dict): Lambda イベントデータ
        context (object): Lambda コンテキストオブジェクト

    Returns:
        dict: API Gateway へのレスポンス
    """
    print(json.dumps(event))

    # 署名の検証
    if not verify_signature(event):
        return {
            'statusCode': 401,
            'body': json.dumps({'error': 'invalid request signature'})
        }

    # Ping リクエストの処理 (Discord の仕様で必須)
    body = json.loads(event.get('body', '{}'))
    if body.get('type') == 1:
        return {
            'statusCode': 200,
            'body': json.dumps({'type': 1})
        }

    # アプリケーションコマンドの処理
    if body.get('type') == 2:
        command_name = body['data']['name']

        # サブコマンドの処理 (/mc start 等)
        # 構造: /mc [subcommand]

        response_text = "コマンドエラー"
        if command_name == 'mc':
            options = body['data'].get('options', [])
            if options:
                # 最初のオプションをサブコマンドとして扱う
                subcommand = options[0]['name']
                response_text = handle_command(subcommand)
            else:
                response_text = "/mc [start|stop|status] を指定してください"
        else:
             # コマンドが直接 'start' などで登録されている場合のフォールバック
             response_text = handle_command(command_name)

        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'type': 4,
                'data': {
                    'content': response_text
                }
            })
        }

    return {
        'statusCode': 404,
        'body': json.dumps({'error': 'not found'})
    }
