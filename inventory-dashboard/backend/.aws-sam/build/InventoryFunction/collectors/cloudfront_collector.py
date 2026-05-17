"""
AWS CloudFront Distribution Collector

CloudFront is a global service; all distributions are returned regardless of region.
The collector stores resources with region='global'.

Python 3.12+ compatible, forward-compatible with Python 3.14+
"""

from __future__ import annotations  # PEP 563 - Deferred evaluation of annotations

from typing import List, Dict, Any, Optional
from .base import BaseCollector


class CloudFrontCollector(BaseCollector):
    """Collects CloudFront distributions (global service)"""

    def __init__(self):
        super().__init__('cloudfront')

    def collect_single_region(
        self,
        client: Any,
        region: str,
        account_id: Optional[str] = None
    ) -> List[Dict[str, Any]]:
        """Collect CloudFront distributions.

        CloudFront is global, so 'region' is always 'global' when called
        from collect_multi_region.
        """
        items = []

        try:
            paginator = client.get_paginator('list_distributions')

            for page in paginator.paginate():
                dist_list = page.get('DistributionList', {})
                for distribution in dist_list.get('Items', []):
                    dist_id = distribution.get('Id', '')

                    # Origins
                    origins = [
                        origin.get('DomainName', '')
                        for origin in distribution.get('Origins', {}).get('Items', [])
                    ]

                    # Aliases (CNAMEs)
                    aliases = distribution.get('Aliases', {}).get('Items', [])

                    # Viewer certificate
                    cert = distribution.get('ViewerCertificate', {})
                    if cert.get('ACMCertificateArn'):
                        ssl_certificate = cert['ACMCertificateArn']
                    elif cert.get('IAMCertificateId'):
                        ssl_certificate = cert['IAMCertificateId']
                    elif cert.get('CloudFrontDefaultCertificate'):
                        ssl_certificate = 'CloudFront Default'
                    else:
                        ssl_certificate = 'None'

                    # Last modified
                    last_modified = distribution.get('LastModifiedTime', '')
                    if hasattr(last_modified, 'isoformat'):
                        last_modified = last_modified.isoformat()
                    else:
                        last_modified = str(last_modified)

                    # Default cache behaviour / HTTP methods
                    default_cache = distribution.get('DefaultCacheBehavior', {})
                    allowed_methods = default_cache.get(
                        'AllowedMethods', {}
                    ).get('Items', [])

                    items.append({
                        'id': dist_id,
                        'distribution_id': dist_id,
                        'name': aliases[0] if aliases else distribution.get('DomainName', dist_id),
                        'arn': distribution.get('ARN', ''),
                        'domain_name': distribution.get('DomainName', ''),
                        'status': distribution.get('Status', ''),
                        'enabled': distribution.get('Enabled', False),
                        'http_version': distribution.get('HttpVersion', ''),
                        'price_class': distribution.get('PriceClass', ''),
                        'is_ipv6_enabled': distribution.get('IsIPV6Enabled', False),
                        'aliases': aliases,
                        'origins': origins,
                        'ssl_certificate': ssl_certificate,
                        'minimum_protocol_version': cert.get('MinimumProtocolVersion', ''),
                        'web_acl_id': distribution.get('WebACLId', ''),
                        'allowed_methods': allowed_methods,
                        'last_modified': last_modified,
                        'region': 'global',
                    })

        except Exception as e:
            print(f"Error collecting CloudFront distributions: {str(e)}")

        return items
