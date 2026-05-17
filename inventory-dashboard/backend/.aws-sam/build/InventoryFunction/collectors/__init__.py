"""
AWS Service Collectors

Python 3.12+ compatible, forward-compatible with Python 3.14+
"""

from __future__ import annotations  # PEP 563 - Deferred evaluation of annotations

from .ec2_collector import EC2Collector
from .vpc_collector import VPCCollector
from .eks_collector import EKSCollector
from .ecs_collector import ECSCollector
from .s3_collector import S3Collector
from .rds_collector import RDSCollector
from .dynamodb_collector import DynamoDBCollector
from .iam_collector import IAMCollector
from .lambda_collector import LambdaCollector
from .cloudfront_collector import CloudFrontCollector
from .acm_collector import ACMCollector
from .elb_collector import ELBCollector
from .nat_collector import NATCollector
from .eip_collector import EIPCollector
from .apigw_collector import APIGatewayCollector
from .route53_collector import Route53Collector
from .sg_collector import SecurityGroupCollector
from .cognito_collector import CognitoCollector
from .waf_collector import WAFCollector

# Collector registry
COLLECTORS = {
    'ec2': EC2Collector,
    'vpc': VPCCollector,
    'eks': EKSCollector,
    'ecs': ECSCollector,
    's3': S3Collector,
    'rds': RDSCollector,
    'dynamodb': DynamoDBCollector,
    'iam': IAMCollector,
    'lambda': LambdaCollector,
    'cloudfront': CloudFrontCollector,
    'acm': ACMCollector,
    'elb': ELBCollector,
    'nat': NATCollector,
    'eip': EIPCollector,
    'apigw': APIGatewayCollector,
    'route53': Route53Collector,
    'sg': SecurityGroupCollector,
    'cognito': CognitoCollector,
    'waf': WAFCollector,
}

