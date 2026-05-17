// Core types for AWS Inventory Dashboard

export interface AWSResource {
  id: string;
  name?: string;
  region: string;
  accountId: string;
  tags?: Record<string, string>;
  [key: string]: any;
}

export interface EC2Instance extends AWSResource {
  instance_id: string;
  name: string;
  state: 'running' | 'stopped' | 'pending' | 'stopping' | 'terminated' | 'shutting-down';
  instance_type: string;
  private_ip?: string;
  public_ip?: string;
  security_groups: string[];
  vpc_id?: string;
  subnet_id?: string;
  launch_time?: string;
}

export interface S3Bucket extends AWSResource {
  bucket_name: string;
  region: string;
  versioning: string;
  encryption: string;
  public: boolean;
  creation_date?: string;
}

export interface RDSInstance extends AWSResource {
  db_identifier: string;
  engine: string;
  engine_version: string;
  status: string;
  instance_class: string;
  endpoint?: string;
  encrypted?: boolean;
}

export interface DynamoDBTable extends AWSResource {
  table_name: string;
  status: string;
  billing_mode: string;
  item_count: number;
  region: string;
}

export interface IAMRole extends AWSResource {
  role_name: string;
  arn: string;
  created: string;
  assume_role_policy?: string;
}

export interface VPC extends AWSResource {
  vpc_id: string;
  cidr_block: string;
  state: string;
  is_default: boolean;
  subnets?: string[];
}

export interface EKSCluster extends AWSResource {
  cluster_name: string;
  status: string;
  version: string;
  endpoint?: string;
  node_groups?: string[];
}

export interface ECSCluster extends AWSResource {
  cluster_name: string;
  status: string;
  active_services?: number;
  running_tasks?: number;
}

export interface LambdaFunction extends AWSResource {
  function_name: string;
  function_arn: string;
  runtime: string;
  role: string;
  handler: string;
  code_size: number;
  description?: string;
  timeout: number;
  memory_size: number;
  last_modified: string;
  state: string;
  package_type: string;
  version: string;
  environment_variables?: Record<string, string>;
  vpc_id?: string;
  subnet_ids?: string[];
  security_group_ids?: string[];
  layers?: string[];
}

export interface CloudFrontDistribution extends AWSResource {
  distribution_id: string;
  arn: string;
  domain_name: string;
  status: string;
  enabled: boolean;
  http_version: string;
  price_class: string;
  is_ipv6_enabled: boolean;
  aliases: string[];
  origins: string[];
  ssl_certificate: string;
  minimum_protocol_version: string;
  web_acl_id?: string;
  allowed_methods?: string[];
  last_modified: string;
}

export interface ACMCertificate extends AWSResource {
  certificate_arn: string;
  domain_name: string;
  status: string;
  type: string;
  key_algorithm: string;
  issuer?: string;
  subject?: string;
  serial?: string;
  created_at?: string;
  issued_at?: string;
  not_before?: string;
  not_after?: string;
  renewal_eligibility?: string;
  renewal_status?: string;
  in_use_by?: string[];
  subject_alternative_names?: string[];
  validation_method?: string;
}

export interface LoadBalancer extends AWSResource {
  arn: string;
  dns_name: string;
  type: 'application' | 'network' | 'gateway';
  scheme: 'internet-facing' | 'internal';
  state: string;
  vpc_id: string;
  ip_address_type: string;
  availability_zones: string[];
  subnet_ids: string[];
  security_groups?: string[];
  canonical_hosted_zone_id?: string;
  created_time: string;
}

export interface NATGateway extends AWSResource {
  nat_gateway_id: string;
  state: string;
  connectivity_type: 'public' | 'private';
  subnet_id: string;
  vpc_id: string;
  public_ip: string;
  private_ip: string;
  public_ips?: string[];
  allocation_id?: string;
  failure_code?: string;
  failure_message?: string;
  created_time?: string;
}

export interface ElasticIP extends AWSResource {
  public_ip: string;
  allocation_id: string;
  association_id?: string;
  associated: boolean;
  domain: string;
  instance_id?: string;
  network_interface_id?: string;
  private_ip_address?: string;
  public_ipv4_pool?: string;
  network_border_group?: string;
}

export interface APIGateway extends AWSResource {
  api_id: string;
  api_version: 'v1' | 'v2';
  protocol_type: 'REST' | 'HTTP' | 'WEBSOCKET';
  description?: string;
  endpoint_type: string;
  stage_count: number;
  stages: string[];
  api_endpoint?: string;
  cors_enabled?: boolean;
  created_date: string;
}

export interface HostedZone extends AWSResource {
  zone_id: string;
  zone_name: string;
  private: boolean;
  record_count: number;
  comment?: string;
  vpc_associations?: string[];
  caller_reference?: string;
}

export interface SecurityGroup extends AWSResource {
  group_id: string;
  description: string;
  vpc_id: string;
  owner_id?: string;
  inbound_rule_count: number;
  outbound_rule_count: number;
  inbound_rules: Array<{ protocol: string; port_range: string; sources: string[] }>;
  outbound_rules: Array<{ protocol: string; port_range: string; sources: string[] }>;
}

export interface CognitoResource extends AWSResource {
  pool_id: string;
  resource_type: 'UserPool' | 'IdentityPool';
  // UserPool fields
  status?: string;
  estimated_user_count?: number;
  mfa_config?: string;
  domain?: string;
  app_client_count?: number;
  lambda_triggers?: string[];
  password_min_length?: number;
  deletion_protection?: string;
  created_date?: string;
  last_modified_date?: string;
  // IdentityPool fields
  allow_unauthenticated?: boolean;
  allow_classic_flow?: boolean;
  identity_providers?: string[];
  saml_provider_arns?: string[];
  supported_login_providers?: string[];
}

export interface WAFWebACL extends AWSResource {
  web_acl_id: string;
  arn: string;
  scope: 'REGIONAL' | 'CLOUDFRONT';
  description?: string;
  metric_name?: string;
  sampled_requests_enabled?: boolean;
  cloudwatch_metrics_enabled?: boolean;
  default_action: string;
  rule_count: number;
  capacity?: number;
  associated_resources?: string[];
  associated_resource_count?: number;
}

export type ServiceType = 
  | 'ec2' 
  | 's3' 
  | 'rds' 
  | 'dynamodb' 
  | 'iam' 
  | 'vpc' 
  | 'eks' 
  | 'ecs'
  | 'lambda'
  | 'cloudfront'
  | 'acm'
  | 'elb'
  | 'nat'
  | 'eip'
  | 'apigw'
  | 'route53'
  | 'sg'
  | 'cognito'
  | 'waf'
  | 'sqs'         // Future
  | 'sns';        // Future

export interface InventoryResponse<T = AWSResource> {
  service: ServiceType;
  total: number;
  page: number;
  size: number;
  items: T[];
  accounts?: string[];
  regions?: string[];
}

export interface User {
  username: string;
  email?: string;
  groups: string[];
}

export interface Account {
  accountId: string;
  accountName: string;
  roleArn: string;
}

export interface Region {
  code: string;
  name: string;
}

