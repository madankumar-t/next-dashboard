"""
Elastic Load Balancer Collector (Application, Network, Gateway)

Uses the elbv2 API to collect ALBs and NLBs.  The logical service name
is 'elb'; the boto3 client alias maps it to 'elbv2'.

Python 3.12+ compatible, forward-compatible with Python 3.14+
"""

from __future__ import annotations  # PEP 563 - Deferred evaluation of annotations

from typing import List, Dict, Any, Optional
from .base import BaseCollector


class ELBCollector(BaseCollector):
    """Collects Application, Network, and Gateway Load Balancers"""

    def __init__(self):
        super().__init__('elb')

    def collect_single_region(
        self,
        client: Any,
        region: str,
        account_id: Optional[str] = None
    ) -> List[Dict[str, Any]]:
        """Collect load balancers from a region using the elbv2 API"""
        items = []

        try:
            paginator = client.get_paginator('describe_load_balancers')

            for page in paginator.paginate():
                for lb in page.get('LoadBalancers', []):
                    lb_arn = lb.get('LoadBalancerArn', '')

                    # State is a nested dict: {'Code': 'active', 'Reason': ''}
                    state_obj = lb.get('State', {})
                    state = state_obj.get('Code', '') if isinstance(state_obj, dict) else str(state_obj)

                    # Availability zones and their subnets
                    az_list = lb.get('AvailabilityZones', [])
                    availability_zones = [az.get('ZoneName', '') for az in az_list]
                    subnet_ids = [az.get('SubnetId', '') for az in az_list]

                    # Tags (best-effort)
                    tags: Dict[str, str] = {}
                    try:
                        tags_response = client.describe_tags(ResourceArns=[lb_arn])
                        for td in tags_response.get('TagDescriptions', []):
                            tags = {t['Key']: t['Value'] for t in td.get('Tags', [])}
                    except Exception:
                        pass

                    # Creation time
                    created_time = lb.get('CreatedTime', '')
                    if hasattr(created_time, 'isoformat'):
                        created_time = created_time.isoformat()
                    else:
                        created_time = str(created_time)

                    items.append({
                        'id': lb_arn,
                        'name': lb.get('LoadBalancerName', ''),
                        'arn': lb_arn,
                        'dns_name': lb.get('DNSName', ''),
                        'type': lb.get('Type', ''),
                        'scheme': lb.get('Scheme', ''),
                        'state': state,
                        'vpc_id': lb.get('VpcId', ''),
                        'ip_address_type': lb.get('IpAddressType', ''),
                        'availability_zones': availability_zones,
                        'subnet_ids': subnet_ids,
                        'security_groups': lb.get('SecurityGroups', []),
                        'canonical_hosted_zone_id': lb.get('CanonicalHostedZoneId', ''),
                        'created_time': created_time,
                        'tags': tags,
                        'region': region,
                    })

        except Exception as e:
            print(f"Error collecting ELBs from {region}: {str(e)}")

        return items
