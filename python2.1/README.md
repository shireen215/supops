# Auto-tag AWS Resources with Creator ARN

This guide shows how to automatically tag every newly created AWS resource with the creator's ARN:
Tag key: `CreatedBy`  

High-level flow:
CloudTrail → EventBridge Rule(s) → Lambda → ResourceGroupsTaggingAPI (fallback to service APIs) → Tag resource with `CreatedBy=<user_arn>`

---

## Quick architecture

CloudTrail records API calls, EventBridge detects "resource created" events and invokes a Lambda which extracts the user ARN and applies the `CreatedBy=<user_arn>` tag using the Resource Groups Tagging API (and service-specific APIs if needed).

---

## 1 — Prerequisites

- AWS account and an IAM user with privileges to create:
  - Lambda functions
  - IAM roles and policies
  - EventBridge rules
  - CloudTrail (or access to confirm it exists)
- Basic familiarity with the AWS Console (or AWS CLI if you prefer CLI steps).
- AWS CLI configured locally for testing.(Optional)

---

## 2 — Enable or confirm CloudTrail

1. Open AWS Console → CloudTrail.
2. If you do not have a trail, choose **Create trail**.
   - Single-region or multi-region is fine for this project (multi-region recommended for global coverage).
   - Ensure **Management events** are being logged (read/write events) so EventBridge receives API call events.
3. Save the trail.

CloudTrail must be enabled so EventBridge can match CloudTrail events (the Event pattern below uses “AWS API Call via CloudTrail”).

---

## 3 — Create the Lambda function (Python)

1. Open Console → Lambda → Create function → Author from scratch.
2. Name: `auto-tag-created-resources`
3. Runtime: Python 3.10 (or newer)
4. Permissions: Create a new role from AWS policy templates (we will update it).
5. Create the function.

### 3.1 — Paste the Lambda handler code

Open the function code editor and replace the default handler with this exact code. This simple version handles events that include ARNs, EC2 `RunInstances`, and S3 `CreateBucket`. Extend it later for more services.

```python
import json
import boto3

def lambda_handler(event, context):
    try:
        detail = event["detail"]
        user_arn = detail["userIdentity"]["arn"]

        # Extract resource ARNs (many AWS services use different event structures)
        resource_arns = []

        #  Case 1: Resources listed in the event
        if "resources" in event:
            for r in event["resources"]:
                resource_arns.append(r["ARN"])

        #  Case 2: EC2 -> instance creation
        if detail.get("eventName") == "RunInstances":
            instances = detail["responseElements"]["instancesSet"]["items"]
            for instance in instances:
                instance_id = instance["instanceId"]
                region = event["region"]
                account = event["account"]
                resource_arns.append(f"arn:aws:ec2:{region}:{account}:instance/{instance_id}")

        #  Case 3: S3 -> bucket creation
        if detail.get("eventName") == "CreateBucket":
            bucket_name = detail["requestParameters"]["bucketName"]
            region = event["region"]
            resource_arns.append(f"arn:aws:s3:::{bucket_name}")

        # Tag the collected ARNs
        if resource_arns:
            tagging = boto3.client("resourcegroupstaggingapi")
            tagging.tag_resources(
                ResourceARNList=resource_arns,
                Tags={"CreatedBy": user_arn}
            )
            print(f" Tagged: {resource_arns} with CreatedBy={user_arn}")
        else:
            print(" No taggable resource ARNs detected in event.")

        return {"status": "success"}

    except Exception as e:
        print(" Error:", e)
        return {"status": "error", "details": str(e)}
```

Click **Deploy**.

Notes:
- This handler covers many common cases and demonstrates the pattern. For full service coverage you’ll extend the handler to parse different event shapes and call service-specific APIs when ResourceGroupsTaggingAPI cannot tag them.
- Ensure your Lambda uses a modern boto3 (AWS-managed runtimes have a recent boto3).

---

## 4 — Add required permissions to Lambda role.

1. Open the Lambda function
2. Go to Configuration → Permissions
3. Click the Role name
4. Click Add permissions → Attach policies
5. Search and attach:

- ResourceGroupsTaggingAPI	- Allows tagging resources
- AmazonEC2FullAccess	 - Allows applying tag to EC2 instances
- AmazonS3FullAccess - (optional for S3 tagging)	Allows tagging S3 buckets
  
        

---

## 5 — Create EventBridge rules

To catch creation API calls broadly, create EventBridge rules that match CloudTrail API events.

> Important: Event pattern type is "AWS API Call via CloudTrail" (CloudTrail must be enabled).

### 5.1 — Rule — Generic create/run/put/launch/register prefix (broad coverage)

Name: `AutoTag-All-Create-Actions`

Event pattern: Custom Pattern

```json
{
  "detail-type": ["AWS API Call via CloudTrail"],
  "detail": {
    "eventName": [
      { "prefix": "Create" },
      { "prefix": "Run" },
      { "prefix": "Put" },
      { "prefix": "Launch" },
      { "prefix": "Register" }
    ]
  }
}
```

Target: Lambda function → `auto-tag-created-resources`  
Create the rule.

This rule triggers the Lambda for many resource-creation API calls. The Lambda then inspects the event and attempts to extract resource ARNs and tag them.

---

## 6 — How the Lambda extracts ARNs (concept)

- Many CloudTrail events include a `resources` array containing ARNs — those are easy to tag.
- Some service APIs only return identifiers (e.g., EC2 instanceId). The Lambda can construct ARNs from the event's `region`, `account`, and the resource ID using known ARN formats.
- For services where the Resource Groups Tagging API cannot tag (or ARN not available), the Lambda can fall back to service-specific tag APIs (e.g., `ec2.create_tags`, `s3.put_bucket_tagging`, `elasticloadbalancing.add_tags`, `rds.add_tags_to_resource`, etc.).

---

## 7 — Test the solution

- EC2 test:
  1. Launch an EC2 instance (RunInstances) as an IAM user.
  2. After instance is created, check the instance Tags in the EC2 console — you should see:
     - Key: `CreatedBy`
     - Value: `arn:aws:iam::<account-id>:user/<creator>`

- S3 test:
  1. Create an S3 bucket.
  2. After creation, open the bucket’s **Properties** → **Tags** or the S3 **Tags** tab; `CreatedBy` should be present.

---
![image alt](https://github.com/mohamedfaseeh/Superops-Img/blob/ff87f04ca2a2848a8d1f0fea34978b1f3dbdd97f/EC2tag.png)
![image alt](https://github.com/mohamedfaseeh/Superops-Img/blob/ff87f04ca2a2848a8d1f0fea34978b1f3dbdd97f/S3tag.png)

---
**What I Liked About My Solution**
- Automatically tagging resources with the creator’s ARN makes it easy to identify who created which resource, improving transparency and ownership tracking.
- Tags can be used to track and allocate costs to teams or users, simplifying cost optimization and chargeback reporting.
- Eliminates the need for developers or admins to manually tag resources, preventing human error and inconsistent tagging.

**What I Disliked About My Solution**
- Requires setting up CloudTrail, EventBridge, and Lambda correctly. A small misconfiguration can cause tags to fail or miss some resources.
- Continuous tagging through EventBridge and Lambda can incur minor costs and may hit service limits in high-volume environments.
