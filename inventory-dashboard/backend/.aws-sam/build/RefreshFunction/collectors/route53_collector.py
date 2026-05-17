"""
Route 53 Hosted Zone Collector

Route 53 is a global service; all hosted zones are returned regardless of
region.  Resources are stored with region='global'.

Python 3.12+ compatible, forward-compatible with Python 3.14+
"""

from __future__ import annotations  # PEP 563 - Deferred evaluation of annotations

from typing import List, Dict, Any, Optional
from .base import BaseCollector


class Route53Collector(BaseCollector):
    """Collects Route 53 hosted zones (global service)"""

    def __init__(self):
        super().__init__('route53')

    def collect_single_region(
        self,
        client: Any,
        region: str,
        account_id: Optional[str] = None
    ) -> List[Dict[str, Any]]:
        """Collect Route 53 hosted zones.

        Route 53 is global, so 'region' is always 'global' when called from
        collect_multi_region.
        """
        items: List[Dict[str, Any]] = []

        try:
            paginator = client.get_paginator('list_hosted_zones')

            for page in paginator.paginate():
                for zone in page.get('HostedZones', []):
                    # Strip the /hostedzone/ prefix from the ID
                    raw_id = zone.get('Id', '')
                    zone_id = raw_id.split('/')[-1] if '/' in raw_id else raw_id

                    config = zone.get('Config', {})
                    private_zone = config.get('PrivateZone', False)
                    comment = config.get('Comment', '')

                    # Resource record set count
                    record_count = zone.get('ResourceRecordSetCount', 0)

                    # VPC associations for private zones (best-effort)
                    vpc_associations: List[str] = []
                    if private_zone:
                        try:
                            detail = client.get_hosted_zone(Id=zone_id)
                            for vpc in detail.get('VPCs', []):
                                vpc_id = vpc.get('VPCId', '')
                                vpc_region = vpc.get('VPCRegion', '')
                                if vpc_id:
                                    vpc_associations.append(
                                        f"{vpc_id} ({vpc_region})" if vpc_region else vpc_id
                                    )
                        except Exception:
                            pass

                    # Tags (best-effort – Route 53 uses a different tags API)
                    tags: Dict[str, str] = {}
                    try:
                        tags_resp = client.list_tags_for_resource(
                            ResourceType='hostedzone',
                            ResourceId=zone_id,
                        )
                        for tag in tags_resp.get('ResourceTagSet', {}).get('Tags', []):
                            tags[tag['Key']] = tag['Value']
                    except Exception:
                        pass

                    zone_name = zone.get('Name', '').rstrip('.')

                    items.append({
                        'id': zone_id,
                        'zone_id': zone_id,
                        'name': zone_name,
                        'zone_name': zone_name,
                        'private': private_zone,
                        'record_count': record_count,
                        'comment': comment,
                        'vpc_associations': vpc_associations,
                        'caller_reference': zone.get('CallerReference', ''),
                        'tags': tags,
                        'region': 'global',
                    })

        except Exception as e:
            print(f"Error collecting Route 53 hosted zones: {str(e)}")

        return items
