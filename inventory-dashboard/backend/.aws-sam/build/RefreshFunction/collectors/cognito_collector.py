"""
Amazon Cognito Collector

Collects both User Pools (cognito-idp) and Identity Pools (cognito-identity)
from all configured regions.

The logical service name is 'cognito'; the boto3 client alias maps it to
'cognito-idp'.  Identity Pools are collected by creating a sibling
'cognito-identity' client, reusing the assumed-role credentials from the
passed-in client where possible.

Python 3.12+ compatible, forward-compatible with Python 3.14+
"""

from __future__ import annotations  # PEP 563 - Deferred evaluation of annotations

from typing import List, Dict, Any, Optional
import boto3

from .base import BaseCollector


def _iso(val: Any) -> str:
    if val is None:
        return ''
    return val.isoformat() if hasattr(val, 'isoformat') else str(val)


class CognitoCollector(BaseCollector):
    """Collects Cognito User Pools and Identity Pools"""

    def __init__(self):
        super().__init__('cognito')

    # ------------------------------------------------------------------
    # User Pools (cognito-idp)
    # ------------------------------------------------------------------

    def _collect_user_pools(self, client: Any, region: str) -> List[Dict[str, Any]]:
        results: List[Dict[str, Any]] = []
        try:
            paginator = client.get_paginator('list_user_pools')
            for page in paginator.paginate(MaxResults=60):
                for pool_summary in page.get('UserPools', []):
                    pool_id = pool_summary.get('Id', '')

                    # Detailed description (best-effort)
                    details: Dict[str, Any] = {}
                    try:
                        resp = client.describe_user_pool(UserPoolId=pool_id)
                        details = resp.get('UserPool', {})
                    except Exception:
                        pass

                    # App client count (best-effort)
                    app_client_count = 0
                    try:
                        clients_resp = client.list_user_pool_clients(
                            UserPoolId=pool_id, MaxResults=60
                        )
                        app_client_count = len(clients_resp.get('UserPoolClients', []))
                    except Exception:
                        pass

                    # Lambda triggers
                    lambda_config = details.get('LambdaConfig', {})
                    triggers = [k for k, v in lambda_config.items() if v]

                    # MFA configuration
                    mfa_config = details.get('MfaConfiguration', 'OFF')

                    # Password policy
                    policies = details.get('Policies', {})
                    pwd_policy = policies.get('PasswordPolicy', {})

                    # Domain (hosted UI)
                    domain = details.get('Domain', '') or details.get('CustomDomain', '')

                    results.append({
                        'id': pool_id,
                        'pool_id': pool_id,
                        'name': pool_summary.get('Name', ''),
                        'resource_type': 'UserPool',
                        'status': details.get('Status', ''),
                        'estimated_user_count': details.get('EstimatedNumberOfUsers', 0),
                        'mfa_config': mfa_config,
                        'domain': domain,
                        'app_client_count': app_client_count,
                        'lambda_triggers': triggers,
                        'password_min_length': pwd_policy.get('MinimumLength', 0),
                        'deletion_protection': details.get('DeletionProtection', ''),
                        'created_date': _iso(
                            details.get('CreationDate') or pool_summary.get('CreationDate')
                        ),
                        'last_modified_date': _iso(details.get('LastModifiedDate')),
                        'region': region,
                    })
        except Exception as e:
            print(f"Error collecting Cognito User Pools from {region}: {str(e)}")
        return results

    # ------------------------------------------------------------------
    # Identity Pools (cognito-identity)
    # ------------------------------------------------------------------

    def _collect_identity_pools(
        self, identity_client: Any, region: str
    ) -> List[Dict[str, Any]]:
        results: List[Dict[str, Any]] = []
        try:
            paginator = identity_client.get_paginator('list_identity_pools')
            for page in paginator.paginate(MaxResults=60):
                for pool in page.get('IdentityPools', []):
                    pool_id = pool.get('IdentityPoolId', '')

                    # Detailed description (best-effort)
                    details: Dict[str, Any] = {}
                    try:
                        details = identity_client.describe_identity_pool(
                            IdentityPoolId=pool_id
                        )
                    except Exception:
                        pass

                    # Collect identity providers
                    providers = list(
                        details.get('CognitoIdentityProviders', [{}])
                    )
                    provider_names = [
                        p.get('ProviderName', '') for p in providers if p.get('ProviderName')
                    ]

                    results.append({
                        'id': pool_id,
                        'pool_id': pool_id,
                        'name': pool.get('IdentityPoolName', ''),
                        'resource_type': 'IdentityPool',
                        'status': 'active',
                        'allow_unauthenticated': details.get(
                            'AllowUnauthenticatedIdentities', False
                        ),
                        'allow_classic_flow': details.get(
                            'AllowClassicFlow', False
                        ),
                        'identity_providers': provider_names,
                        'saml_provider_arns': details.get('SamlProviderARNs', []),
                        'supported_login_providers': list(
                            details.get('SupportedLoginProviders', {}).keys()
                        ),
                        'region': region,
                    })
        except Exception as e:
            print(f"Error collecting Cognito Identity Pools from {region}: {str(e)}")
        return results

    # ------------------------------------------------------------------
    # BaseCollector interface
    # ------------------------------------------------------------------

    def collect_single_region(
        self,
        client: Any,
        region: str,
        account_id: Optional[str] = None
    ) -> List[Dict[str, Any]]:
        """Collect Cognito User Pools and Identity Pools from a region."""
        items: List[Dict[str, Any]] = []

        # --- User Pools (uses assumed-role client passed in) ---
        items.extend(self._collect_user_pools(client, region))

        # --- Identity Pools via sibling cognito-identity client ---
        try:
            creds = client._request_signer._credentials
            identity_client = boto3.client(
                'cognito-identity',
                region_name=region,
                aws_access_key_id=creds.access_key,
                aws_secret_access_key=creds.secret_key,
                aws_session_token=getattr(creds, 'token', None),
            )
        except Exception:
            identity_client = boto3.client('cognito-identity', region_name=region)

        items.extend(self._collect_identity_pools(identity_client, region))

        return items
