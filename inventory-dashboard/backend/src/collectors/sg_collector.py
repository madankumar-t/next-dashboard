"""
Security Group Collector

Security Groups are part of the EC2 API.  The logical service name is 'sg';
the boto3 client alias maps it to 'ec2'.

Python 3.12+ compatible, forward-compatible with Python 3.14+
"""

from __future__ import annotations  # PEP 563 - Deferred evaluation of annotations

from typing import List, Dict, Any, Optional
from .base import BaseCollector


def _format_rule(rule: Dict[str, Any]) -> Dict[str, Any]:
    """Normalise a single IP permission into a compact, serialisable dict."""
    protocol = rule.get('IpProtocol', '-1')
    from_port = rule.get('FromPort', 0)
    to_port = rule.get('ToPort', 0)

    # Human-readable port range
    if protocol == '-1':
        port_range = 'All'
    elif from_port == to_port:
        port_range = str(from_port)
    else:
        port_range = f"{from_port}-{to_port}"

    # Sources / destinations
    sources: List[str] = []
    for cidr in rule.get('IpRanges', []):
        desc = cidr.get('Description', '')
        entry = cidr.get('CidrIp', '')
        sources.append(f"{entry} ({desc})" if desc else entry)

    for cidr6 in rule.get('Ipv6Ranges', []):
        desc = cidr6.get('Description', '')
        entry = cidr6.get('CidrIpv6', '')
        sources.append(f"{entry} ({desc})" if desc else entry)

    for sg_ref in rule.get('UserIdGroupPairs', []):
        ref_id = sg_ref.get('GroupId', '')
        ref_name = sg_ref.get('GroupName', '')
        label = ref_name if ref_name else ref_id
        sources.append(label)

    for pl in rule.get('PrefixListIds', []):
        sources.append(pl.get('PrefixListId', ''))

    return {
        'protocol': protocol,
        'port_range': port_range,
        'sources': sources,
    }


class SecurityGroupCollector(BaseCollector):
    """Collects EC2 Security Groups"""

    def __init__(self):
        super().__init__('sg')

    def collect_single_region(
        self,
        client: Any,
        region: str,
        account_id: Optional[str] = None
    ) -> List[Dict[str, Any]]:
        """Collect Security Groups from a region"""
        items: List[Dict[str, Any]] = []

        try:
            paginator = client.get_paginator('describe_security_groups')

            for page in paginator.paginate():
                for sg in page.get('SecurityGroups', []):
                    tags = {t['Key']: t['Value'] for t in sg.get('Tags', [])}
                    group_id = sg.get('GroupId', '')

                    inbound_rules = [_format_rule(r) for r in sg.get('IpPermissions', [])]
                    outbound_rules = [_format_rule(r) for r in sg.get('IpPermissionsEgress', [])]

                    items.append({
                        'id': group_id,
                        'group_id': group_id,
                        'name': sg.get('GroupName', ''),
                        'description': sg.get('Description', ''),
                        'vpc_id': sg.get('VpcId', ''),
                        'owner_id': sg.get('OwnerId', ''),
                        'inbound_rule_count': len(inbound_rules),
                        'outbound_rule_count': len(outbound_rules),
                        'inbound_rules': inbound_rules,
                        'outbound_rules': outbound_rules,
                        'tags': tags,
                        'region': region,
                    })

        except Exception as e:
            print(f"Error collecting Security Groups from {region}: {str(e)}")

        return items
