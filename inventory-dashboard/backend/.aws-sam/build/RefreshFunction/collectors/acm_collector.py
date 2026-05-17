"""
AWS Certificate Manager (ACM) Collector

Collects SSL/TLS certificates from ACM across all configured regions.

Python 3.12+ compatible, forward-compatible with Python 3.14+
"""

from __future__ import annotations  # PEP 563 - Deferred evaluation of annotations

from typing import List, Dict, Any, Optional
from .base import BaseCollector


class ACMCollector(BaseCollector):
    """Collects ACM certificates"""

    def __init__(self):
        super().__init__('acm')

    def collect_single_region(
        self,
        client: Any,
        region: str,
        account_id: Optional[str] = None
    ) -> List[Dict[str, Any]]:
        """Collect ACM certificates from a region"""
        items = []

        try:
            paginator = client.get_paginator('list_certificates')

            for page in paginator.paginate():
                for cert_summary in page.get('CertificateSummaryList', []):
                    cert_arn = cert_summary.get('CertificateArn', '')

                    # Fetch full certificate details
                    try:
                        detail_response = client.describe_certificate(
                            CertificateArn=cert_arn
                        )
                        cert = detail_response.get('Certificate', {})
                    except Exception as e:
                        print(
                            f"Warning: Could not describe certificate {cert_arn}: {str(e)}"
                        )
                        cert = cert_summary

                    # Validation method from domain validation options
                    domain_options = cert.get('DomainValidationOptions', [])
                    validation_method = (
                        domain_options[0].get('ValidationMethod', '')
                        if domain_options
                        else ''
                    )

                    # Safely convert datetime fields to ISO strings
                    def _iso(val: Any) -> str:
                        if val is None:
                            return ''
                        return val.isoformat() if hasattr(val, 'isoformat') else str(val)

                    # Renewal summary
                    renewal_summary = cert.get('RenewalSummary', {})
                    renewal_status = renewal_summary.get('RenewalStatus', '')

                    items.append({
                        'id': cert_arn,
                        'certificate_arn': cert_arn,
                        'name': cert.get(
                            'DomainName',
                            cert_summary.get('DomainName', '')
                        ),
                        'domain_name': cert.get(
                            'DomainName',
                            cert_summary.get('DomainName', '')
                        ),
                        'status': cert.get(
                            'Status',
                            cert_summary.get('Status', '')
                        ),
                        'type': cert.get('Type', cert_summary.get('Type', '')),
                        'key_algorithm': cert.get(
                            'KeyAlgorithm',
                            cert_summary.get('KeyAlgorithm', '')
                        ),
                        'issuer': cert.get('Issuer', ''),
                        'subject': cert.get('Subject', ''),
                        'serial': cert.get('Serial', ''),
                        'created_at': _iso(cert.get('CreatedAt')),
                        'issued_at': _iso(cert.get('IssuedAt')),
                        'not_before': _iso(cert.get('NotBefore')),
                        'not_after': _iso(cert.get('NotAfter')),
                        'renewal_eligibility': cert.get(
                            'RenewalEligibility',
                            cert_summary.get('RenewalEligibility', '')
                        ),
                        'renewal_status': renewal_status,
                        'in_use_by': cert.get('InUseBy', []),
                        'subject_alternative_names': cert.get(
                            'SubjectAlternativeNames', []
                        ),
                        'validation_method': validation_method,
                        'region': region,
                    })

        except Exception as e:
            print(f"Error collecting ACM certificates from {region}: {str(e)}")

        return items
