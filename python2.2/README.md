# AWS IAM User Provisioning with Python

This guide shows how to automate IAM user onboarding on AWS using a simple Python (boto3) script. It's beginner-friendly and walks through prerequisites, required IAM permissions, the provisioning script, how to run it, and how to verify the created user.

What you'll build
- A Python script that, given inputs:
  - username
  - whether console login is enabled (yes/no)
  - temporary password (if console login enabled)
  - group name (created if missing)
  - AWS managed policy names (comma separated)
- Will:
  - Create the IAM user (if not exists)
  - Optionally create a console login profile with a temporary password
  - Create the group (if missing) and attach specified AWS managed policies to the group
  - Add the user to the group
  - Create programmatic access keys and print/save them

---

## Prerequisites

- An AWS account and an IAM admin user (not root) with permissions to create users, groups, attach policies and create access keys.
- Python 3.8+ installed (on macOS use `python3`, on Windows `python` that maps to Python 3).
- pip available to install boto3.
- AWS CLI v2 installed and configured (useful for verification).
- Basic familiarity with CLI and AWS Console.

---

## Required IAM permissions (for the admin user used to run the script)

The admin user running the script must have IAM permissions such as:
- iam:CreateUser, iam:GetUser, iam:CreateLoginProfile, iam:CreateAccessKey
- iam:CreateGroup, iam:GetGroup, iam:AddUserToGroup
- iam:AttachGroupPolicy, iam:AttachUserPolicy
- iam:ListGroups, iam:ListPolicies, iam:ListUsers

For testing you can use AdministratorAccess, but in production use least privilege.

---

## Local setup

On Windows (PowerShell) or macOS/Linux:

1. Install boto3:
```bash
pip install boto3
```

2. Check versions:
```bash
python --version
aws --version
```

3. Configure AWS CLI (so boto3 uses the same credentials):
```bash
aws configure
```
Enter the admin user's Access Key ID and Secret Access Key, default region, and output format (`json`).

Verify credentials:
```bash
aws sts get-caller-identity
```
You should see the ARN and account of the admin user.

---

## The Python script

Save the following as `create_user.py` in your working directory.

```python
import boto3
from botocore.exceptions import ClientError
from getpass import getpass

iam = boto3.client('iam')

def create_group_if_not_exists(group_name):
    try:
        iam.get_group(GroupName=group_name)
        print(f"[INFO] Group '{group_name}' already exists.")
    except ClientError as e:
        if e.response['Error']['Code'] == 'NoSuchEntity':
            iam.create_group(GroupName=group_name)
            print(f"[OK] Group '{group_name}' created successfully.")
        else:
            raise e

def attach_policies_to_group(group_name, policy_names):
    for policy_name in policy_names:
        policy_arn = f"arn:aws:iam::aws:policy/{policy_name}"
        try:
            iam.attach_group_policy(GroupName=group_name, PolicyArn=policy_arn)
            print(f"[OK] Attached policy '{policy_name}' to group '{group_name}'.")
        except Exception as e:
            print(f"[ERROR] Couldn't attach policy '{policy_name}': {e}")

def create_iam_user(username, enable_console_login, password, group_name):
    try:
        iam.create_user(UserName=username)
        print(f"[OK] User '{username}' created successfully.")
    except ClientError as e:
        if e.response['Error']['Code'] != 'EntityAlreadyExists':
            raise e
        print(f"[INFO] User '{username}' already exists. Continuing...")

    # Console login optional
    if enable_console_login.lower() == "yes":
        try:
            iam.create_login_profile(
                UserName=username,
                Password=password,
                PasswordResetRequired=True
            )
            print(f"[OK] Console login enabled for '{username}'.")
        except ClientError as e:
            if e.response['Error']['Code'] != 'EntityAlreadyExists':
                raise e
            print("[INFO] Console login already exists. Continuing...")
    else:
        print("[INFO] Console login disabled. (CLI/Programmatic access only)")

    # Add to group
    iam.add_user_to_group(GroupName=group_name, UserName=username)
    print(f"[OK] Added '{username}' to group '{group_name}'.")

    # Create access key (always created)
    response = iam.create_access_key(UserName=username)
    key = response['AccessKey']
    print("\n[OK] Access Key Created (Copy and Store Securely):")
    print(f"Access Key ID: {key['AccessKeyId']}")
    print(f"Secret Access Key: {key['SecretAccessKey']}")

# ---------------------------
# Input Section
# ---------------------------

username = input("Enter new IAM username: ")

enable_console_login = input("Enable console login? (yes/no): ").strip().lower()
password = None
if enable_console_login == "yes":
    password = getpass("Enter temporary password (must follow AWS password policy): ")

group_name = input("Enter group name to assign user to: ")

policy_input = input("Enter AWS policy names (comma separated): ")
policy_names = [p.strip() for p in policy_input.split(",")]

create_group_if_not_exists(group_name)
attach_policies_to_group(group_name, policy_names)
create_iam_user(username, enable_console_login, password, group_name)

```

Important: The script prints the SecretAccessKey only once. Save it securely.
---

## Run the script

In a terminal where AWS credentials are configured:

Windows (PowerShell):
```powershell
python create_user.py
```

Follow the prompts, for example:
- Enter new IAM username: alice.dev
- Enable console login? (yes/no): yes
- Enter temporary password... (must meet AWS policy)
- Enter group name...: Developers
- Enter AWS managed policy names: ReadOnlyAccess, AmazonS3FullAccess

Expected example output:
```
[OK] Group 'dev' created successfully.
[OK] Attached policy 'ReadOnlyAccess' to group 'Developers'.
[OK] User 'Jhon' created successfully.
[OK] Console login enabled for 'alice.dev'.
[OK] Added 'Jhon' to group 'Developers'.

[OK] Access Key Created (Copy and Store Securely):
Access Key ID: AKIA...
SecretAccessKey: ...
```

---
<img width="505" height="255" alt="image" src="https://github.com/user-attachments/assets/78d74d51-4dc4-46d3-a35b-1da2dc4b3094" />

---

## Verify the new user

Console access
1. Sign out of the admin console.
2. Sign in as the new IAM user using the account sign-in URL or account ID + username.
3. Use the temporary password; the user will be prompted to set a new password.

Programmatic access (test using a named profile):
```bash
aws configure --profile alice.dev
# paste Access Key ID and SecretAccessKey from the script output
# region: same as before
# output: json

aws sts get-caller-identity --profile alice.dev
```
The returned ARN should correspond to the new user.
