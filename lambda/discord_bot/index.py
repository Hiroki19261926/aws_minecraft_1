import json
import os
import boto3
from nacl.signing import VerifyKey
from nacl.exceptions import BadSignatureError

# Environment variables
DISCORD_PUBLIC_KEY = os.environ.get('DISCORD_PUBLIC_KEY')
INSTANCE_ID = os.environ.get('INSTANCE_ID')

ec2 = boto3.client('ec2')

def verify_signature(event):
    if not DISCORD_PUBLIC_KEY:
        return False

    try:
        signature = event['headers'].get('x-signature-ed25519')
        timestamp = event['headers'].get('x-signature-timestamp')
        body = event.get('body', '')

        if not signature or not timestamp:
            return False

        verify_key = VerifyKey(bytes.fromhex(DISCORD_PUBLIC_KEY))
        verify_key.verify(f'{timestamp}{body}'.encode(), bytes.fromhex(signature))
        return True
    except (BadSignatureError, Exception):
        return False

def handle_command(command_name):
    if command_name == 'start':
        ec2.start_instances(InstanceIds=[INSTANCE_ID])
        return "Minecraftサーバーを起動しました。数分お待ちください。"

    elif command_name == 'stop':
        ec2.stop_instances(InstanceIds=[INSTANCE_ID])
        return "Minecraftサーバーを停止しました。"

    elif command_name == 'status':
        try:
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
    print(json.dumps(event))

    # Verify Signature
    if not verify_signature(event):
        return {
            'statusCode': 401,
            'body': json.dumps({'error': 'invalid request signature'})
        }

    # Handle Ping (required by Discord)
    body = json.loads(event.get('body', '{}'))
    if body.get('type') == 1:
        return {
            'statusCode': 200,
            'body': json.dumps({'type': 1})
        }

    # Handle Application Commands
    if body.get('type') == 2:
        command_name = body['data']['name']
        # subcommands handling (/mc start)
        # Structure: /mc [subcommand]
        # Check if it is a subcommand structure or direct command
        # Assuming the command is registered as "mc" with options/subcommands
        # But for simplicity, let's assume flattened commands or handle "mc" options

        # AGENTS.md says "/mc start", so "mc" is the root command, "start" is the subcommand (option type 1)
        # Inspecting payload structure for subcommands

        # If the command is registered as "start", "stop", "status" directly:
        # response_text = handle_command(command_name)

        # If the command is "mc" with subcommands:
        response_text = "コマンドエラー"
        if command_name == 'mc':
            options = body['data'].get('options', [])
            if options:
                subcommand = options[0]['name']
                response_text = handle_command(subcommand)
            else:
                response_text = "/mc [start|stop|status] を指定してください"
        else:
             # Fallback if commands are registered as "start" etc directly (less likely for "/mc start")
             # But let's support direct commands just in case user registered them that way
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
