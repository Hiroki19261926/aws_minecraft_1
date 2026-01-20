import os
import boto3
from mcrcon import MCRcon
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Environment variables
INSTANCE_ID = os.environ.get('INSTANCE_ID')
RCON_PORT = int(os.environ.get('RCON_PORT', 25575))
RCON_PASSWORD = os.environ.get('RCON_PASSWORD')
SSM_PARAM_NAME = '/minecraft/player_zero_count'
STOP_THRESHOLD = 12  # 12 checks * 5 mins = 60 mins

ec2 = boto3.client('ec2')
ssm = boto3.client('ssm')

def get_instance_public_ip(instance_id):
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
    try:
        with MCRcon(host, password, port=port) as mcr:
            response = mcr.command("list")
            logger.info(f"RCON response: {response}")
            # Expected format: "There are X of a max of Y players online: ..."
            # Or "There are 0 of a max of 20 players online: "

            parts = response.split(" ")
            # Basic parsing logic. Adjust if Minecraft output format changes.
            # "There are 0 of a max of 20 players online:"
            if len(parts) >= 3 and parts[2].isdigit():
                return int(parts[2])
            else:
                logger.warning(f"Unexpected RCON response format: {response}")
                return 0 # Fail safe? Or treat as active? Let's treat as 0 for now but log warning.
    except Exception as e:
        logger.error(f"RCON Connection failed: {e}")
        return None

def update_zero_count(count):
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
    try:
        response = ssm.get_parameter(Name=SSM_PARAM_NAME)
        return int(response['Parameter']['Value'])
    except ssm.exceptions.ParameterNotFound:
        return 0
    except Exception as e:
        logger.error(f"Failed to get SSM parameter: {e}")
        return 0

def handler(event, context):
    logger.info("Monitor function started.")

    # Check if instance is running
    try:
        response = ec2.describe_instance_status(InstanceIds=[INSTANCE_ID], IncludeAllInstances=True)
        statuses = response.get('InstanceStatuses', [])
        if not statuses:
            logger.info("Instance status not found. Assuming stopped.")
            return

        state = statuses[0].get('InstanceState', {}).get('Name')
        if state != 'running':
            logger.info(f"Instance is {state}. Skipping check.")
            # Reset counter if server is stopped? Maybe not necessary, but cleaner.
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
        # Do not increment counter on connection failure to avoid accidental shutdown during maintenance/startup
        return

    logger.info(f"Player count: {player_count}")

    if player_count == 0:
        new_count = current_zero_count + 1
        logger.info(f"Zero players. Incrementing counter to {new_count}.")
        update_zero_count(new_count)

        if new_count >= STOP_THRESHOLD:
            logger.info("Threshold reached. Stopping instance.")
            ec2.stop_instances(InstanceIds=[INSTANCE_ID])
            update_zero_count(0) # Reset after stop command
    else:
        if current_zero_count > 0:
            logger.info("Players detected. Resetting counter.")
            update_zero_count(0)
        else:
            logger.info("Players detected. Counter already 0.")

    return {"status": "ok"}
