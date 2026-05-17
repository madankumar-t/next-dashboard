"""
API Gateway Collector

Collects both REST APIs (V1) and HTTP/WebSocket APIs (V2) from all configured
regions.  The logical service name is 'apigw'; the boto3 client alias maps it
to 'apigateway' (V1).  V2 APIs are collected by creating a sibling
'apigatewayv2' client for the same region using the default credential chain
(the Lambda execution role).  For cross-account collection V2 APIs from member
accounts will be skipped gracefully — V1 REST APIs are always collected via the
assumed-role client that is passed in.

Python 3.12+ compatible, forward-compatible with Python 3.14+
"""

from __future__ import annotations  # PEP 563 - Deferred evaluation of annotations

from typing import List, Dict, Any, Optional
import boto3

from .base import BaseCollector


class APIGatewayCollector(BaseCollector):
    """Collects API Gateway REST APIs (V1) and HTTP/WebSocket APIs (V2)"""

    def __init__(self):
        super().__init__('apigw')

    # ------------------------------------------------------------------
    # V1 helpers
    # ------------------------------------------------------------------

    def _collect_rest_apis(self, client: Any) -> List[Dict[str, Any]]:
        """Collect REST APIs (V1) using the passed-in apigateway client."""
        results: List[Dict[str, Any]] = []
        try:
            paginator = client.get_paginator('get_rest_apis')
            for page in paginator.paginate():
                for api in page.get('items', []):
                    api_id = api.get('id', '')

                    # Stages (best-effort)
                    stages: List[str] = []
                    try:
                        stages_resp = client.get_stages(restApiId=api_id)
                        stages = [s.get('stageName', '') for s in stages_resp.get('item', [])]
                    except Exception:
                        pass

                    endpoint_config = api.get('endpointConfiguration', {})
                    endpoint_types = endpoint_config.get('types', [])
                    endpoint_type = endpoint_types[0] if endpoint_types else ''

                    created_date = api.get('createdDate', '')
                    if hasattr(created_date, 'isoformat'):
                        created_date = created_date.isoformat()
                    else:
                        created_date = str(created_date)

                    results.append({
                        'id': api_id,
                        'api_id': api_id,
                        'name': api.get('name', ''),
                        'api_version': 'v1',
                        'protocol_type': 'REST',
                        'description': api.get('description', ''),
                        'endpoint_type': endpoint_type,
                        'stage_count': len(stages),
                        'stages': stages,
                        'created_date': created_date,
                        'tags': api.get('tags', {}),
                    })
        except Exception as e:
            print(f"Error collecting API Gateway V1 REST APIs: {str(e)}")
        return results

    # ------------------------------------------------------------------
    # V2 helpers
    # ------------------------------------------------------------------

    def _collect_http_apis(self, region: str, v2_client: Any) -> List[Dict[str, Any]]:
        """Collect HTTP and WebSocket APIs (V2) using an apigatewayv2 client."""
        results: List[Dict[str, Any]] = []
        try:
            paginator = v2_client.get_paginator('get_apis')
            for page in paginator.paginate():
                for api in page.get('Items', []):
                    api_id = api.get('ApiId', '')

                    # Stages (best-effort)
                    stages: List[str] = []
                    try:
                        stages_resp = v2_client.get_stages(ApiId=api_id)
                        stages = [s.get('StageName', '') for s in stages_resp.get('Items', [])]
                    except Exception:
                        pass

                    created_date = api.get('CreatedDate', '')
                    if hasattr(created_date, 'isoformat'):
                        created_date = created_date.isoformat()
                    else:
                        created_date = str(created_date)

                    results.append({
                        'id': api_id,
                        'api_id': api_id,
                        'name': api.get('Name', ''),
                        'api_version': 'v2',
                        'protocol_type': api.get('ProtocolType', ''),  # HTTP | WEBSOCKET
                        'description': api.get('Description', ''),
                        'endpoint_type': 'REGIONAL',
                        'api_endpoint': api.get('ApiEndpoint', ''),
                        'stage_count': len(stages),
                        'stages': stages,
                        'cors_enabled': bool(api.get('CorsConfiguration')),
                        'created_date': created_date,
                        'tags': api.get('Tags', {}),
                    })
        except Exception as e:
            print(f"Error collecting API Gateway V2 APIs from {region}: {str(e)}")
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
        """Collect REST (V1) and HTTP/WebSocket (V2) APIs from a region."""
        items: List[Dict[str, Any]] = []

        # --- V1 REST APIs (uses the assumed-role client passed in) ---
        items.extend(self._collect_rest_apis(client))

        # --- V2 HTTP / WebSocket APIs ---
        # Build a V2 client.  If the V1 client was created with assumed-role
        # credentials, those credentials live in the client's signer.  We
        # attempt to reuse them; on failure we fall back to the default
        # credential chain (Lambda execution role).
        try:
            creds = client._request_signer._credentials
            v2_client = boto3.client(
                'apigatewayv2',
                region_name=region,
                aws_access_key_id=creds.access_key,
                aws_secret_access_key=creds.secret_key,
                aws_session_token=getattr(creds, 'token', None),
            )
        except Exception:
            # Fall back to Lambda's own execution role
            v2_client = boto3.client('apigatewayv2', region_name=region)

        items.extend(self._collect_http_apis(region, v2_client))

        return items
