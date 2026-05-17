"""
AWS WAF v2 Collector

Collects WAFv2 Web ACLs for both REGIONAL scope (all configured regions) and
CLOUDFRONT scope (global; only retrievable from us-east-1).

The logical service name is 'waf'; the boto3 client alias maps it to 'wafv2'.

Python 3.12+ compatible, forward-compatible with Python 3.14+
"""

from __future__ import annotations  # PEP 563 - Deferred evaluation of annotations

from typing import List, Dict, Any, Optional
from .base import BaseCollector


class WAFCollector(BaseCollector):
    """Collects WAFv2 Web ACLs (REGIONAL + CLOUDFRONT scopes)"""

    def __init__(self):
        super().__init__('waf')

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _collect_scope(
        self,
        client: Any,
        scope: str,
        region: str,
    ) -> List[Dict[str, Any]]:
        """Collect Web ACLs for a given scope (REGIONAL or CLOUDFRONT)."""
        results: List[Dict[str, Any]] = []
        try:
            paginator = client.get_paginator('list_web_acls')
            for page in paginator.paginate(Scope=scope):
                for acl_summary in page.get('WebACLs', []):
                    name = acl_summary.get('Name', '')
                    acl_id = acl_summary.get('Id', '')
                    arn = acl_summary.get('ARN', '')

                    # Full WebACL details (best-effort)
                    details: Dict[str, Any] = {}
                    try:
                        detail_resp = client.get_web_acl(
                            Name=name, Scope=scope, Id=acl_id
                        )
                        details = detail_resp.get('WebACL', {})
                    except Exception:
                        pass

                    rules = details.get('Rules', [])
                    default_action = details.get('DefaultAction', {})
                    # DefaultAction is either {'Allow': {}} or {'Block': {}}
                    default_action_str = (
                        'Allow' if 'Allow' in default_action else
                        'Block' if 'Block' in default_action else
                        ''
                    )

                    # Capacity units consumed (best-effort)
                    capacity = details.get('Capacity', 0)

                    # Associated resources (best-effort)
                    associated_resources: List[str] = []
                    try:
                        assoc_resp = client.list_resources_for_web_acl(
                            WebACLArn=arn,
                            ResourceType='APPLICATION_LOAD_BALANCER'
                            if scope == 'REGIONAL' else 'CLOUDFRONT',
                        )
                        associated_resources = assoc_resp.get('ResourceArns', [])
                    except Exception:
                        pass

                    # Tags (best-effort)
                    tags: Dict[str, str] = {}
                    try:
                        tags_resp = client.list_tags_for_resource(ResourceARN=arn)
                        for tag in tags_resp.get('TagInfoForResource', {}).get('TagList', []):
                            tags[tag['Key']] = tag['Value']
                    except Exception:
                        pass

                    stored_region = 'global' if scope == 'CLOUDFRONT' else region

                    results.append({
                        'id': acl_id,
                        'web_acl_id': acl_id,
                        'name': name,
                        'arn': arn,
                        'scope': scope,
                        'description': details.get('Description', acl_summary.get('Description', '')),
                        'metric_name': details.get('VisibilityConfig', {}).get('MetricName', ''),
                        'sampled_requests_enabled': details.get('VisibilityConfig', {}).get('SampledRequestsEnabled', False),
                        'cloudwatch_metrics_enabled': details.get('VisibilityConfig', {}).get('CloudWatchMetricsEnabled', False),
                        'default_action': default_action_str,
                        'rule_count': len(rules),
                        'capacity': capacity,
                        'associated_resources': associated_resources,
                        'associated_resource_count': len(associated_resources),
                        'tags': tags,
                        'region': stored_region,
                    })
        except Exception as e:
            print(f"Error collecting WAF Web ACLs (scope={scope}, region={region}): {str(e)}")
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
        """
        Collect WAFv2 Web ACLs.

        REGIONAL scope is collected for every region.
        CLOUDFRONT scope is collected only when region == 'us-east-1' because
        the WAFv2 API enforces that CLOUDFRONT WebACLs are managed via
        us-east-1 endpoints.
        """
        items: List[Dict[str, Any]] = []

        # Regional Web ACLs
        items.extend(self._collect_scope(client, 'REGIONAL', region))

        # CloudFront-scoped Web ACLs — only available from us-east-1
        if region == 'us-east-1':
            items.extend(self._collect_scope(client, 'CLOUDFRONT', region))

        return items
