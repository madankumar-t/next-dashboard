"""
Elastic IP Address Collector

Elastic IPs are part of the EC2 API.  The logical service name is 'eip';
the boto3 client alias maps it to 'ec2'.

Python 3.12+ compatible, forward-compatible with Python 3.14+
"""

from __future__ import annotations  # PEP 563 - Deferred evaluation of annotations

from typing import List, Dict, Any, Optional
from .base import BaseCollector


class EIPCollector(BaseCollector):
    """Collects Elastic IP addresses"""

    def __init__(self):
        super().__init__('eip')

    def collect_single_region(
        self,
        client: Any,
        region: str,
        account_id: Optional[str] = None
    ) -> List[Dict[str, Any]]:
        """Collect Elastic IPs from a region"""
        items = []

        try:
            response = client.describe_addresses()

            for address in response.get('Addresses', []):
                tags = {t['Key']: t['Value'] for t in address.get('Tags', [])}

                allocation_id = address.get('AllocationId', '')
                public_ip = address.get('PublicIp', '')

                # Use AllocationId as id for VPC EIPs, else PublicIp
                resource_id = allocation_id if allocation_id else public_ip

                # Determine association status
                association_id = address.get('AssociationId', '')
                associated = bool(association_id)

                items.append({
                    'id': resource_id,
                    'name': tags.get('Name', public_ip),
                    'public_ip': public_ip,
                    'allocation_id': allocation_id,
                    'association_id': association_id,
                    'associated': associated,
                    'domain': address.get('Domain', ''),
                    'instance_id': address.get('InstanceId', ''),
                    'network_interface_id': address.get('NetworkInterfaceId', ''),
                    'private_ip_address': address.get('PrivateIpAddress', ''),
                    'public_ipv4_pool': address.get('PublicIpv4Pool', ''),
                    'network_border_group': address.get('NetworkBorderGroup', ''),
                    'carrier_ip': address.get('CarrierIp', ''),
                    'tags': tags,
                    'region': region,
                })

        except Exception as e:
            print(f"Error collecting Elastic IPs from {region}: {str(e)}")

        return items
