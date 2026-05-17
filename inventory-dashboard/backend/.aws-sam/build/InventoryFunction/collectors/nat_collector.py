"""
NAT Gateway Collector

NAT Gateways are part of the EC2 API.  The logical service name is 'nat';
the boto3 client alias maps it to 'ec2'.

Python 3.12+ compatible, forward-compatible with Python 3.14+
"""

from __future__ import annotations  # PEP 563 - Deferred evaluation of annotations

from typing import List, Dict, Any, Optional
from .base import BaseCollector


class NATCollector(BaseCollector):
    """Collects NAT Gateways"""

    def __init__(self):
        super().__init__('nat')

    def collect_single_region(
        self,
        client: Any,
        region: str,
        account_id: Optional[str] = None
    ) -> List[Dict[str, Any]]:
        """Collect NAT Gateways from a region"""
        items = []

        try:
            paginator = client.get_paginator('describe_nat_gateways')

            for page in paginator.paginate():
                for nat in page.get('NatGateways', []):
                    nat_id = nat.get('NatGatewayId', '')
                    tags = {t['Key']: t['Value'] for t in nat.get('Tags', [])}

                    # Primary address details
                    addresses = nat.get('NatGatewayAddresses', [])
                    primary = next(
                        (a for a in addresses if a.get('IsPrimary', False)),
                        addresses[0] if addresses else {}
                    )
                    public_ip = primary.get('PublicIp', '')
                    private_ip = primary.get('PrivateIp', '')
                    allocation_id = primary.get('AllocationId', '')

                    # All public IPs (multi-IP NAT gateways)
                    public_ips = [a.get('PublicIp', '') for a in addresses if a.get('PublicIp')]

                    # Timestamps
                    def _iso(val: Any) -> str:
                        if val is None:
                            return ''
                        return val.isoformat() if hasattr(val, 'isoformat') else str(val)

                    items.append({
                        'id': nat_id,
                        'nat_gateway_id': nat_id,
                        'name': tags.get('Name', nat_id),
                        'state': nat.get('State', ''),
                        'connectivity_type': nat.get('ConnectivityType', ''),
                        'subnet_id': nat.get('SubnetId', ''),
                        'vpc_id': nat.get('VpcId', ''),
                        'public_ip': public_ip,
                        'private_ip': private_ip,
                        'public_ips': public_ips,
                        'allocation_id': allocation_id,
                        'failure_code': nat.get('FailureCode', ''),
                        'failure_message': nat.get('FailureMessage', ''),
                        'created_time': _iso(nat.get('CreateTime')),
                        'deleted_time': _iso(nat.get('DeleteTime')),
                        'tags': tags,
                        'region': region,
                    })

        except Exception as e:
            print(f"Error collecting NAT Gateways from {region}: {str(e)}")

        return items
