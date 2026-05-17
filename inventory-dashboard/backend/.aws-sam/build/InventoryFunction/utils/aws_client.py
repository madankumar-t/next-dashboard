"""
AWS Client Utilities
Handles multi-account and multi-region AWS client creation

Python 3.12+ compatible, forward-compatible with Python 3.14+
"""

from __future__ import annotations  # PEP 563 - Deferred evaluation of annotations

import boto3
from typing import Optional, List, Dict, Any
from concurrent.futures import ThreadPoolExecutor, as_completed
import os


# Some logical service names used as routing/storage keys don't match
# the boto3 client name.  This mapping resolves the difference.
# The logical name is preserved everywhere else (DynamoDB keys, COLLECTORS
# dict, API responses); only the boto3.client() call uses the mapped name.
_BOTO3_SERVICE_ALIASES: Dict[str, str] = {
    'vpc': 'ec2',              # VPC resources are part of the EC2 API
    'nat': 'ec2',              # NAT Gateways are part of the EC2 API
    'eip': 'ec2',              # Elastic IPs are part of the EC2 API
    'sg':  'ec2',              # Security Groups are part of the EC2 API
    'elb': 'elbv2',            # ALB/NLB use the elbv2 API
    'apigw': 'apigateway',     # API Gateway REST APIs (V1)
    'cognito': 'cognito-idp',  # Cognito User Pools
    'waf': 'wafv2',            # WAF v2
}


# Regions to collect inventory from.
# Defaults to DCLI's five active commercial regions; override at deploy time
# by setting the INVENTORY_REGIONS environment variable (comma-separated).
# All other commercial regions are blocked by SCPs and must not be queried.
_DEFAULT_REGIONS = [
    'us-east-1', 'us-east-2', 'us-west-2',
    'ap-south-1', 'sa-east-1',
]


class AWSClientManager:
    """Manages AWS client creation with multi-account and multi-region support"""

    # Built once at import time from the environment variable so that the list
    # can be changed via a Terraform variable without touching source code.
    AWS_REGIONS: List[str] = [
        r.strip()
        for r in os.environ.get(
            'INVENTORY_REGIONS', ','.join(_DEFAULT_REGIONS)
        ).split(',')
        if r.strip()
    ]

    def __init__(self):
        self.external_id = os.environ.get('EXTERNAL_ID', '')
        self.role_session_name = os.environ.get(
            'ROLE_SESSION_NAME', 'InventoryDashboard')

    def get_sts_client(self, region: str = 'us-east-1'):
        """Get STS client for assuming roles"""
        return boto3.client('sts', region_name=region)

    def assume_role(self, role_arn: str, region: str = 'us-east-1') -> Dict[str, Any]:
        """
        Assume role in target account

        Args:
            role_arn: ARN of the role to assume (e.g., arn:aws:iam::123456789012:role/InventoryReadRole)
            region: AWS region

        Returns:
            Credentials dict with AccessKeyId, SecretAccessKey, SessionToken
        """
        sts = self.get_sts_client(region)

        try:
            assume_role_kwargs = {
                'RoleArn': role_arn,
                'RoleSessionName': self.role_session_name
            }

            # Add ExternalId if configured (recommended for security)
            if self.external_id:
                assume_role_kwargs['ExternalId'] = self.external_id

            response = sts.assume_role(**assume_role_kwargs)
            return response['Credentials']
        except Exception as e:
            print(f"Failed to assume role {role_arn}: {str(e)}")
            raise

    def get_client(
        self,
        service: str,
        region: str = 'us-east-1',
        account_id: Optional[str] = None,
        role_arn: Optional[str] = None
    ):
        """
        Get AWS service client

        Args:
            service: AWS service name (e.g., 'ec2', 's3')
            region: AWS region
            account_id: Target account ID (for multi-account)
            role_arn: Role ARN to assume (if account_id is provided)

        Returns:
            Boto3 client for the service
        """
        kwargs = {'region_name': region}

        # If account_id and role_arn are provided, assume role
        if account_id and role_arn:
            try:
                credentials = self.assume_role(role_arn, region)
                kwargs['aws_access_key_id'] = credentials['AccessKeyId']
                kwargs['aws_secret_access_key'] = credentials['SecretAccessKey']
                kwargs['aws_session_token'] = credentials['SessionToken']
            except Exception as e:
                # If role assumption fails, raise to let caller handle
                print(f"Cannot assume role for account {account_id}: {str(e)}")
                raise

        return boto3.client(service, **kwargs)

    def get_clients_for_regions(
        self,
        service: str,
        regions: List[str],
        account_id: Optional[str] = None,
        role_arn: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Get clients for multiple regions

        Args:
            service: Logical service name (e.g. 'vpc', 'ec2').  If the name
                     differs from the boto3 client name, _BOTO3_SERVICE_ALIASES
                     is consulted to find the correct client name.
            regions: List of regions
            account_id: Target account ID (for multi-account)
            role_arn: Role ARN to assume

        Returns:
            Dict mapping region -> client
        """
        # Resolve logical service name to boto3 client name (e.g. 'vpc' -> 'ec2')
        boto3_service = _BOTO3_SERVICE_ALIASES.get(service.lower(), service)

        clients = {}

        # Global services only need a single client (us-east-1 for all)
        _GLOBAL_CLIENT_SERVICES = {'iam', 'cloudfront', 'route53'}
        if service.lower() in _GLOBAL_CLIENT_SERVICES:
            region = 'us-east-1'
            try:
                clients[region] = self.get_client(
                    boto3_service, region, account_id, role_arn)
            except Exception as e:
                print(
                    f"Failed to create {service} client for {region}: {str(e)}")
            return clients

        # For regional services, create clients for each region
        for region in regions:
            try:
                clients[region] = self.get_client(
                    boto3_service, region, account_id, role_arn)
            except Exception as e:
                print(
                    f"Failed to create {service} client for {region} (account: {account_id}): {str(e)}")
                # Continue with other regions even if one fails

        return clients

    def get_accounts_from_org(self) -> List[Dict[str, str]]:
        """
        Get list of accounts from AWS Organizations

        Priority:
        1. Environment variable INVENTORY_ACCOUNTS (comma-separated account IDs)
        2. AWS Organizations API (if available)
        3. Current account (fallback)

        Returns:
            List of dicts with accountId and accountName
        """
        # Check for hardcoded accounts in environment variable FIRST
        # Format: "accountId1:AccountName1,accountId2:AccountName2" or "accountId1,accountId2"
        hardcoded_accounts = os.environ.get('INVENTORY_ACCOUNTS', '')
        if hardcoded_accounts:
            accounts = []
            for account_str in hardcoded_accounts.split(','):
                account_str = account_str.strip()
                if ':' in account_str:
                    # Format: accountId:AccountName
                    account_id, account_name = account_str.split(':', 1)
                    accounts.append({
                        'accountId': account_id.strip(),
                        'accountName': account_name.strip()
                    })
                else:
                    # Format: accountId only
                    accounts.append({
                        'accountId': account_str.strip(),
                        'accountName': f"Account {account_str.strip()}"
                    })

            if accounts:
                print(
                    f"Using {len(accounts)} accounts from INVENTORY_ACCOUNTS environment variable")
                return accounts

        # Try AWS Organizations if no environment variable
        try:
            orgs = boto3.client('organizations', region_name='us-east-1')
            accounts = []

            paginator = orgs.get_paginator('list_accounts')
            for page in paginator.paginate():
                for account in page['Accounts']:
                    if account['Status'] == 'ACTIVE':
                        accounts.append({
                            'accountId': account['Id'],
                            'accountName': account['Name']
                        })

            if accounts:
                print(f"Found {len(accounts)} accounts from AWS Organizations")
                return accounts
        except Exception as e:
            print(f"Failed to list accounts from Organizations: {str(e)}")
            return accounts

        # Final fallback: Current account
        try:
            sts = boto3.client('sts', region_name='us-east-1')
            current_account = sts.get_caller_identity()
            account_id = current_account['Account']
            print(f"Using current account: {account_id}")
            return [{
                'accountId': account_id,
                'accountName': 'Current Account'
            }]
        except Exception as e:
            print(f"Failed to get current account: {str(e)}")
            return []

    def build_role_arn(self, account_id: str, role_name: str = 'InventoryReadRole') -> str:
        """Build role ARN for an account"""
        return f"arn:aws:iam::{account_id}:role/{role_name}"


# Global instance
client_manager = AWSClientManager()
