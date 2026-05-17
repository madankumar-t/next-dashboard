"""
AWS Lambda Function Collector

Python 3.12+ compatible, forward-compatible with Python 3.14+
"""

from __future__ import annotations  # PEP 563 - Deferred evaluation of annotations

from typing import List, Dict, Any, Optional
from .base import BaseCollector


class LambdaCollector(BaseCollector):
    """Collects AWS Lambda functions"""
    
    def __init__(self):
        super().__init__('lambda')
    
    def collect_single_region(
        self,
        client: Any,
        region: str,
        account_id: Optional[str] = None
    ) -> List[Dict[str, Any]]:
        """Collect Lambda functions from a region"""
        items = []
        
        try:
            paginator = client.get_paginator('list_functions')
            
            for page in paginator.paginate():
                for function in page.get('Functions', []):
                    function_name = function.get('FunctionName', '')
                    
                    # Get additional details
                    try:
                        # Get function configuration
                        config = client.get_function_configuration(
                            FunctionName=function_name
                        )
                        
                        # Get function tags
                        tags_response = client.list_tags(
                            Resource=function.get('FunctionArn', '')
                        )
                        tags = tags_response.get('Tags', {})
                    except Exception as e:
                        print(f"Warning: Could not get full details for {function_name}: {str(e)}")
                        config = {}
                        tags = {}
                    
                    # Extract environment variables
                    env_vars = config.get('Environment', {}).get('Variables', {})
                    
                    # Extract VPC configuration
                    vpc_config = config.get('VpcConfig', {})
                    
                    items.append({
                        'id': function.get('FunctionArn', function_name),
                        'function_name': function_name,
                        'function_arn': function.get('FunctionArn', ''),
                        'runtime': function.get('Runtime', ''),
                        'role': function.get('Role', ''),
                        'handler': function.get('Handler', ''),
                        'code_size': function.get('CodeSize', 0),
                        'description': function.get('Description', ''),
                        'timeout': config.get('Timeout', 0),
                        'memory_size': config.get('MemorySize', 0),
                        'last_modified': function.get('LastModified', ''),
                        'last_modified_iso': function.get('LastModified', ''),
                        'state': config.get('State', 'Active'),
                        'state_reason': config.get('StateReason', ''),
                        'state_reason_code': config.get('StateReasonCode', ''),
                        'package_type': function.get('PackageType', 'Zip'),
                        'version': function.get('Version', '$LATEST'),
                        'environment_variables': env_vars,
                        'vpc_id': vpc_config.get('VpcId', ''),
                        'subnet_ids': vpc_config.get('SubnetIds', []),
                        'security_group_ids': vpc_config.get('SecurityGroupIds', []),
                        'layers': [layer.get('Arn', '') for layer in function.get('Layers', [])],
                        'tags': tags,
                        'region': region
                    })
        except Exception as e:
            print(f"Error collecting Lambda functions from {region}: {str(e)}")
        
        return items

