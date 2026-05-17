"""
DynamoDB Storage Utilities
Handles storing and retrieving inventory data from DynamoDB

Python 3.12+ compatible, forward-compatible with Python 3.14+
"""

from __future__ import annotations  # PEP 563 - Deferred evaluation of annotations

import boto3
import json
import os
from typing import List, Dict, Any, Optional
from datetime import datetime, timezone
from decimal import Decimal


class DynamoDBStorage:
    """Manages inventory data storage in DynamoDB"""
    
    def __init__(self):
        self.table_name = os.environ.get('INVENTORY_TABLE_NAME', 'aws-inventory-data')
        self.metadata_table_name = os.environ.get('METADATA_TABLE_NAME', 'aws-inventory-metadata')
        self.dynamodb = boto3.resource('dynamodb', region_name=os.environ.get('AWS_REGION', 'us-east-1'))
        self.table = self.dynamodb.Table(self.table_name)
        self.metadata_table = self.dynamodb.Table(self.metadata_table_name)
    
    def _convert_to_dynamodb_item(self, item: Dict[str, Any]) -> Dict[str, Any]:
        """Convert Python types to DynamoDB-compatible types"""
        def convert_value(value: Any) -> Any:
            if isinstance(value, dict):
                return {k: convert_value(v) for k, v in value.items()}
            elif isinstance(value, list):
                return [convert_value(v) for v in value]
            elif isinstance(value, (int, float)):
                # DynamoDB doesn't support float, convert to Decimal
                return Decimal(str(value)) if isinstance(value, float) else value
            elif isinstance(value, bool):
                return value
            elif value is None:
                return None
            else:
                return str(value)
        
        return convert_value(item)
    
    def _convert_from_dynamodb_item(self, item: Dict[str, Any]) -> Dict[str, Any]:
        """Convert DynamoDB types back to Python types"""
        def convert_value(value: Any) -> Any:
            if isinstance(value, dict):
                return {k: convert_value(v) for k, v in value.items()}
            elif isinstance(value, list):
                return [convert_value(v) for v in value]
            elif isinstance(value, Decimal):
                # Convert Decimal to float
                return float(value)
            else:
                return value
        
        return convert_value(item)
    
    def store_resources(
        self,
        service: str,
        account_id: str,
        region: str,
        resources: List[Dict[str, Any]],
        timestamp: Optional[datetime] = None
    ) -> None:
        """
        Store resources in DynamoDB with history preservation
        
        Each snapshot is stored with a unique timestamp, preserving full history.
        No overwrites - each execution creates a new snapshot.
        
        Args:
            service: Service name (e.g., 'ec2', 's3')
            account_id: AWS account ID
            region: AWS region
            resources: List of resource dictionaries
            timestamp: Timestamp for this collection (defaults to now)
        """
        if timestamp is None:
            timestamp = datetime.now(timezone.utc)
        
        timestamp_str = timestamp.isoformat()
        # Use timestamp as part of sort key to preserve history
        # Format: timestamp#resourceId (ISO format with colons replaced for DynamoDB compatibility)
        timestamp_key = timestamp_str.replace(':', '-').replace('+', '-')
        
        # Batch write new items (DynamoDB batch write limit is 25 items)
        # IMPORTANT: We do NOT delete old items - this preserves history
        batch_size = 25
        for i in range(0, len(resources), batch_size):
            batch = resources[i:i + batch_size]
            
            with self.table.batch_writer() as writer:
                for resource in batch:
                    # Create composite key: service#accountId#region#resourceId
                    resource_id = resource.get('id') or resource.get('instance_id') or resource.get('bucket_name') or \
                                 resource.get('table_name') or resource.get('role_name') or resource.get('vpc_id') or \
                                 resource.get('cluster_name') or resource.get('db_identifier') or \
                                 resource.get('function_name') or 'unknown'
                    
                    # Sort key includes timestamp to preserve history: timestamp#resourceId
                    # This allows multiple snapshots of the same resource
                    item = {
                        'pk': f"{service}#{account_id}#{region}",
                        'sk': f"{timestamp_key}#{resource_id}",
                        'service': service,
                        'accountId': account_id,
                        'region': region,
                        'resourceId': resource_id,
                        'snapshot_timestamp': timestamp_str,
                        'data': self._convert_to_dynamodb_item(resource),
                        'updatedAt': timestamp_str,
                        'ttl': int((timestamp.timestamp() + (90 * 24 * 60 * 60)))  # 90 days TTL
                    }
                    
                    writer.put_item(Item=item)
        
        # Update metadata
        self._update_metadata(service, account_id, region, timestamp_str, len(resources))
    
    def _get_latest_snapshot_timestamp(
        self,
        service: str,
        account_id: str,
        region: str
    ) -> Optional[str]:
        """
        Get the latest snapshot timestamp for a service/account/region combination
        
        Returns:
            ISO timestamp string of the latest snapshot, or None if no snapshots exist
        """
        pk = f"{service}#{account_id}#{region}"
        
        try:
            # Query items and sort by snapshot_timestamp descending
            # Get only the latest snapshot
            response = self.table.query(
                KeyConditionExpression='pk = :pk',
                ExpressionAttributeValues={':pk': pk},
                ProjectionExpression='snapshot_timestamp',
                ScanIndexForward=False,  # Descending order
                Limit=1
            )
            
            items = response.get('Items', [])
            if items and 'snapshot_timestamp' in items[0]:
                return items[0]['snapshot_timestamp']
        except Exception as e:
            print(f"Error getting latest snapshot timestamp: {str(e)}")
        
        return None
    
    def get_resources(
        self,
        service: str,
        account_ids: Optional[List[str]] = None,
        regions: Optional[List[str]] = None,
        snapshot_timestamp: Optional[str] = None
    ) -> List[Dict[str, Any]]:
        """
        Retrieve resources from DynamoDB
        
        By default, returns only the latest snapshot. To get historical data,
        specify snapshot_timestamp.
        
        Args:
            service: Service name
            account_ids: Optional list of account IDs to filter
            regions: Optional list of regions to filter
            snapshot_timestamp: Optional timestamp to get specific snapshot (defaults to latest)
            
        Returns:
            List of resource dictionaries from the latest (or specified) snapshot
        """
        all_resources = []
        
        # Get all accounts if not specified
        if account_ids is None:
            account_ids = self._get_all_accounts()
        
        # Get all regions if not specified
        if regions is None:
            regions = self._get_all_regions(service)
        
        # If no snapshot_timestamp specified, get latest snapshot for each account/region
        if snapshot_timestamp is None:
            # Get latest snapshot timestamp for each account/region combination
            snapshot_timestamps = {}
            for account_id in account_ids:
                for region in regions:
                    latest_ts = self._get_latest_snapshot_timestamp(service, account_id, region)
                    if latest_ts:
                        key = f"{account_id}#{region}"
                        if key not in snapshot_timestamps or latest_ts > snapshot_timestamps[key]:
                            snapshot_timestamps[key] = latest_ts
        
        # Query for each account/region combination
        for account_id in account_ids:
            for region in regions:
                pk = f"{service}#{account_id}#{region}"
                
                try:
                    # Determine which snapshot to query
                    target_timestamp = snapshot_timestamp
                    if target_timestamp is None:
                        key = f"{account_id}#{region}"
                        target_timestamp = snapshot_timestamps.get(key)
                    
                    if target_timestamp:
                        # Query for specific snapshot timestamp
                        # Sort key format: timestamp#resourceId
                        timestamp_key = target_timestamp.replace(':', '-').replace('+', '-')
                        response = self.table.query(
                            KeyConditionExpression='pk = :pk AND begins_with(sk, :timestamp)',
                            ExpressionAttributeValues={
                                ':pk': pk,
                                ':timestamp': timestamp_key
                            }
                        )
                        items = response.get('Items', [])
                    else:
                        # Fallback: get all items and filter to latest
                        response = self.table.query(
                            KeyConditionExpression='pk = :pk',
                            ExpressionAttributeValues={':pk': pk},
                            ScanIndexForward=False  # Descending to get latest first
                        )
                        
                        # Group by resourceId and take only the latest snapshot for each resource
                        seen_resources = {}
                        for item in response.get('Items', []):
                            resource_id = item.get('resourceId', '')
                            item_timestamp = item.get('snapshot_timestamp', '')
                            
                            if resource_id and (resource_id not in seen_resources or 
                                               item_timestamp > seen_resources[resource_id].get('snapshot_timestamp', '')):
                                seen_resources[resource_id] = item
                        
                        # Convert to list
                        items = list(seen_resources.values())
                    
                    for item in items:
                        resource = self._convert_from_dynamodb_item(item.get('data', {}))
                        # Ensure accountId and region are set
                        resource['accountId'] = account_id
                        resource['region'] = region
                        resource['snapshot_timestamp'] = item.get('snapshot_timestamp', '')
                        all_resources.append(resource)
                    
                    # Handle pagination (if not using latest snapshot filtering)
                    if target_timestamp:
                        while 'LastEvaluatedKey' in response:
                            response = self.table.query(
                                KeyConditionExpression='pk = :pk AND begins_with(sk, :timestamp)',
                                ExpressionAttributeValues={
                                    ':pk': pk,
                                    ':timestamp': timestamp_key
                                },
                                ExclusiveStartKey=response['LastEvaluatedKey']
                            )
                            for item in response.get('Items', []):
                                resource = self._convert_from_dynamodb_item(item.get('data', {}))
                                resource['accountId'] = account_id
                                resource['region'] = region
                                resource['snapshot_timestamp'] = item.get('snapshot_timestamp', '')
                                all_resources.append(resource)
                except Exception as e:
                    print(f"Error querying DynamoDB for {service}#{account_id}#{region}: {str(e)}")
                    continue
        
        return all_resources
    
    def _get_inventory_account_name_lookup(self) -> Dict[str, str]:
        """Parse INVENTORY_ACCOUNTS into an account ID -> display name mapping.

        Supports both ``accountId:Name`` and bare ``accountId`` entries.
        Bare account IDs map to themselves so callers can treat the result as a
        complete name lookup without re-implementing parsing rules.
        """
        name_lookup: Dict[str, str] = {}
        for entry in os.environ.get('INVENTORY_ACCOUNTS', '').split(','):
            entry = entry.strip()
            if not entry:
                continue

            if ':' in entry:
                acc_id, acc_name = entry.split(':', 1)
                acc_id = acc_id.strip()
                acc_name = acc_name.strip()
                if acc_id:
                    name_lookup[acc_id] = acc_name or acc_id
            else:
                name_lookup[entry] = entry

        return name_lookup

    def get_distinct_accounts(self) -> List[Dict[str, str]]:
        """Get all distinct accounts that have inventory data in DynamoDB.

        Account IDs come from the metadata table, which is written during every
        refresh run. Names are resolved from the INVENTORY_ACCOUNTS environment
        variable when available; otherwise the account ID is used as the
        display name.

        Returns:
            List of dicts ``{accountId, accountName}``, sorted by accountName.
        """
        name_lookup = self._get_inventory_account_name_lookup()

        account_ids = self._get_all_accounts()
        return sorted(
            [
                {
                    'accountId': acc_id,
                    'accountName': name_lookup.get(acc_id, acc_id),
                }
                for acc_id in account_ids
            ],
            key=lambda x: x['accountName'],
        )

    def _get_all_accounts(self) -> List[str]:
        """Get all unique account IDs from metadata"""
        try:
            response = self.metadata_table.scan(
                ProjectionExpression='accountId'
            )
            account_ids = set()
            for item in response.get('Items', []):
                account_ids.add(item['accountId'])

            # Handle pagination
            while 'LastEvaluatedKey' in response:
                response = self.metadata_table.scan(
                    ProjectionExpression='accountId',
                    ExclusiveStartKey=response['LastEvaluatedKey']
                )
                for item in response.get('Items', []):
                    account_ids.add(item['accountId'])

            return list(account_ids)
        except Exception as e:
            print(f"Error getting accounts from metadata: {str(e)}")
            return []
    
    def _get_all_regions(self, service: str) -> List[str]:
        """Get all unique regions for a service from metadata"""
        try:
            response = self.metadata_table.query(
                KeyConditionExpression='service = :service',
                ExpressionAttributeValues={':service': service},
                ProjectionExpression='region'
            )
            regions = set()
            for item in response.get('Items', []):
                if 'region' in item:
                    regions.add(item['region'])
            
            # Handle pagination
            while 'LastEvaluatedKey' in response:
                response = self.metadata_table.query(
                    KeyConditionExpression='service = :service',
                    ExpressionAttributeValues={':service': service},
                    ProjectionExpression='region',
                    ExclusiveStartKey=response['LastEvaluatedKey']
                )
                for item in response.get('Items', []):
                    if 'region' in item:
                        regions.add(item['region'])
            
            # IAM is a global service — stored under region='global', not a real region
            default = 'global' if service.lower() == 'iam' else 'us-east-1'
            return list(regions) if regions else [default]
        except Exception as e:
            print(f"Error getting regions from metadata: {str(e)}")
            default = 'global' if service.lower() == 'iam' else 'us-east-1'
            return [default]
    
    def _update_metadata(
        self,
        service: str,
        account_id: str,
        region: str,
        timestamp: str,
        resource_count: int
    ) -> None:
        """Update metadata table with last update information"""
        try:
            # Use composite sort key: accountId#region
            account_region = f"{account_id}#{region}"
            self.metadata_table.put_item(
                Item={
                    'service': service,
                    'accountRegion': account_region,
                    'accountId': account_id,
                    'region': region,
                    'updatedAt': timestamp,
                    'resourceCount': resource_count
                }
            )
        except Exception as e:
            print(f"Error updating metadata: {str(e)}")
    
    def get_last_update_time(self, service: Optional[str] = None) -> Optional[datetime]:
        """
        Get the last update time for a service (or overall if service is None)
        
        Args:
            service: Optional service name to filter
            
        Returns:
            Last update datetime or None
        """
        try:
            if service:
                response = self.metadata_table.query(
                    KeyConditionExpression='service = :service',
                    ExpressionAttributeValues={':service': service},
                    ProjectionExpression='updatedAt'
                )
            else:
                response = self.metadata_table.scan(
                    ProjectionExpression='updatedAt'
                )
            
            latest_timestamp = None
            for item in response.get('Items', []):
                updated_at = item.get('updatedAt')
                if updated_at:
                    try:
                        timestamp = datetime.fromisoformat(updated_at.replace('Z', '+00:00'))
                        if latest_timestamp is None or timestamp > latest_timestamp:
                            latest_timestamp = timestamp
                    except Exception:
                        continue
            
            # Handle pagination
            while 'LastEvaluatedKey' in response:
                if service:
                    response = self.metadata_table.query(
                        KeyConditionExpression='service = :service',
                        ExpressionAttributeValues={':service': service},
                        ProjectionExpression='updatedAt',
                        ExclusiveStartKey=response['LastEvaluatedKey']
                    )
                else:
                    response = self.metadata_table.scan(
                        ProjectionExpression='updatedAt',
                        ExclusiveStartKey=response['LastEvaluatedKey']
                    )
                
                for item in response.get('Items', []):
                    updated_at = item.get('updatedAt')
                    if updated_at:
                        try:
                            timestamp = datetime.fromisoformat(updated_at.replace('Z', '+00:00'))
                            if latest_timestamp is None or timestamp > latest_timestamp:
                                latest_timestamp = timestamp
                        except Exception:
                            continue
            
            return latest_timestamp
        except Exception as e:
            print(f"Error getting last update time: {str(e)}")
            return None


# Global instance
storage = DynamoDBStorage()

