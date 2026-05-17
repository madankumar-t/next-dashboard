/**
 * AWS Cognito Authentication with SAML Federation Support
 * 
 * Supports:
 * - OAuth2 Authorization Code flow via Cognito Hosted UI
 * - SAML federation (Azure AD, Okta, Ping, ADFS)
 * - Automatic token refresh
 * - Session management
 */

import { CognitoUserPool, CognitoUser, AuthenticationDetails } from 'amazon-cognito-identity-js';

const userPoolId = process.env.NEXT_PUBLIC_COGNITO_USER_POOL_ID || '';
const clientId = process.env.NEXT_PUBLIC_COGNITO_CLIENT_ID || '';
const region = process.env.NEXT_PUBLIC_COGNITO_REGION || 'us-east-1';
const cognitoDomain = process.env.NEXT_PUBLIC_COGNITO_DOMAIN || '';

if (!userPoolId || !clientId) {
  console.warn('Cognito configuration missing. Set NEXT_PUBLIC_COGNITO_USER_POOL_ID and NEXT_PUBLIC_COGNITO_CLIENT_ID');
}

// Lazy-initialized so that importing this module at Next.js static build time
// does not throw when NEXT_PUBLIC_COGNITO_* env vars are absent.
// The pool is created on first use (i.e. in the browser after auth is needed).
let _userPool: CognitoUserPool | null = null;

function getUserPool(): CognitoUserPool | null {
  if (!userPoolId || !clientId) return null;
  if (!_userPool) {
    _userPool = new CognitoUserPool({ UserPoolId: userPoolId, ClientId: clientId });
  }
  return _userPool;
}

export interface AuthSession {
  idToken: string;
  accessToken: string;
  refreshToken: string;
  expiresAt: number;
  groups: string[];
  username: string;
}

/**
 * Get current authenticated user
 */
export function getCurrentUser(): CognitoUser | null {
  return getUserPool()?.getCurrentUser() ?? null;
}

/**
 * Get ID token from current session
 * First tries localStorage session (from OAuth2 flow), then falls back to CognitoUserPool
 */
export async function refreshStoredSession(): Promise<AuthSession | null> {
  if (typeof window === 'undefined') return null;
  const stored = localStorage.getItem('aws-inventory-session');
  if (!stored) return null;
  try {
    const session = JSON.parse(stored);
    if (!session.refreshToken) return null;
    const tokenUrl = `https://${cognitoDomain}.auth.${region}.amazoncognito.com/oauth2/token`;
    const params = new URLSearchParams({
      grant_type: 'refresh_token',
      client_id: clientId,
      refresh_token: session.refreshToken,
    });
    const response = await fetch(tokenUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: params.toString(),
    });
    if (!response.ok) return null;
    const data = await response.json();
    if (!data.id_token) return null;
    const payload = JSON.parse(atob(data.id_token.split('.')[1]));
    const newSession: AuthSession = {
      idToken: data.id_token,
      accessToken: data.access_token,
      refreshToken: session.refreshToken, // refresh_token not returned on refresh
      expiresAt: (payload.exp * 1000) || (Date.now() + 3600000),
      groups: payload['cognito:groups'] || session.groups || [],
      username: payload['cognito:username'] || payload.sub || session.username,
    };
    localStorage.setItem('aws-inventory-session', JSON.stringify(newSession));
    return newSession;
  } catch {
    return null;
  }
}

export async function getIdToken(): Promise<string | null> {
  // First, try to get from localStorage (our custom OAuth2 flow)
  const storedSession = getStoredSession();
  if (storedSession && storedSession.idToken) {
    return storedSession.idToken;
  }

  // Session expired — try to refresh using the refresh_token
  const rawStored = typeof window !== 'undefined' ? localStorage.getItem('aws-inventory-session') : null;
  if (rawStored) {
    try {
      const expired = JSON.parse(rawStored);
      if (expired.refreshToken) {
        const refreshed = await refreshStoredSession();
        if (refreshed) return refreshed.idToken;
      }
    } catch { /* ignore */ }
  }

  // Fallback to CognitoUserPool session (legacy path)
  return new Promise((resolve, reject) => {
    const user = getCurrentUser();
    if (!user) {
      console.warn('⚠️ No stored session and no CognitoUser');
      resolve(null);
      return;
    }

    user.getSession((err: Error | null, session: any) => {
      if (err) {
        reject(err);
        return;
      }

      if (session.isValid()) {
        resolve(session.getIdToken().getJwtToken());
      } else {
        // Try to refresh
        user.refreshSession(session.getRefreshToken(), (refreshErr: Error | null, newSession: any) => {
          if (refreshErr) {
            reject(refreshErr);
          } else {
            resolve(newSession.getIdToken().getJwtToken());
          }
        });
      }
    });
  });
}

/**
 * Login via Cognito Hosted UI (SAML/OAuth2)
 * Redirects to Cognito Hosted UI for SSO
 * @throws {Error} If Cognito configuration is missing
 */
export function loginWithHostedUI(): void {
  // Enhanced logging for production debugging
  console.log('🔐 loginWithHostedUI called');
  console.log('🔐 Cognito Config:', {
    domain: cognitoDomain || 'MISSING',
    clientId: clientId ? `${clientId.substring(0, 10)}...` : 'MISSING',
    region: region,
    origin: typeof window !== 'undefined' ? window.location.origin : 'N/A'
  });

  if (!cognitoDomain || !clientId) {
    const error = 'Cognito is not configured. Please set up Cognito first or use mock authentication for local development.';
    console.error('❌ Cognito configuration missing. Cannot redirect to login.');
    console.error('❌ Missing values:', {
      cognitoDomain: !cognitoDomain,
      clientId: !clientId
    });
    console.error('❌ Environment variables should be set at BUILD TIME (NEXT_PUBLIC_*)');
    throw new Error(error);
  }

  if (typeof window === 'undefined') {
    throw new Error('loginWithHostedUI can only be called in the browser');
  }

  // No trailing slash — must match exactly what is registered in Cognito app client
  const redirectUri = `${window.location.origin}/auth/callback`;

  // Get SAML provider name from environment (optional, for direct SAML redirect)
  // If NEXT_PUBLIC_SAML_PROVIDER_NAME is set, redirect directly to SAML
  // Otherwise, use /login which will show identity provider selection
  const samlProviderName = process.env.NEXT_PUBLIC_SAML_PROVIDER_NAME || '';
  const loginEndpoint = samlProviderName 
    ? `/oauth2/authorize?identity_provider=${encodeURIComponent(samlProviderName)}&`
    : '/login?';

  const cognitoLoginUrl = `https://${cognitoDomain}.auth.${region}.amazoncognito.com${loginEndpoint}` +
    `client_id=${clientId}&` +
    `response_type=code&` +
    `scope=email+openid+profile&` +
    `redirect_uri=${encodeURIComponent(redirectUri)}`;

  console.log('🔐 Redirecting to Cognito:', cognitoLoginUrl.substring(0, 100) + '...');
  if (samlProviderName) {
    console.log('🔐 Direct SAML redirect to provider:', samlProviderName);
  }
  window.location.href = cognitoLoginUrl;
}

/**
 * Handle OAuth callback and exchange code for tokens
 */
export async function handleAuthCallback(code: string): Promise<AuthSession> {
  console.log('🔐 handleAuthCallback called with code:', code.substring(0, 10) + '...');

  if (!cognitoDomain || !clientId) {
    console.error('❌ Cognito configuration missing!');
    console.error('cognitoDomain:', cognitoDomain);
    console.error('clientId:', clientId);
    throw new Error('Cognito configuration missing. Cannot handle auth callback.');
  }

  // In production, this should be handled server-side for security
  // For now, we'll use the client-side flow
  // Must match exactly what loginWithHostedUI uses (no trailing slash)
  const redirectUri = typeof window !== 'undefined'
    ? `${window.location.origin}/auth/callback`
    : '';

  console.log('🔐 Token exchange parameters:');
  console.log('  - Token URL:', `https://${cognitoDomain}.auth.${region}.amazoncognito.com/oauth2/token`);
  console.log('  - Client ID:', clientId);
  console.log('  - Redirect URI:', redirectUri);
  console.log('  - Redirect URI must match login redirect_uri EXACTLY');

  // Exchange authorization code for tokens
  const tokenUrl = `https://${cognitoDomain}.auth.${region}.amazoncognito.com/oauth2/token`;

  const params = new URLSearchParams({
    grant_type: 'authorization_code',
    client_id: clientId,
    code: code,
    redirect_uri: redirectUri
  });

  console.log('🔄 Sending token exchange request...');
  console.log('🔄 Request body (sanitized):', {
    grant_type: 'authorization_code',
    client_id: clientId.substring(0, 10) + '...',
    code: code.substring(0, 10) + '...',
    redirect_uri: redirectUri
  });
  
  const response = await fetch(tokenUrl, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded'
    },
    body: params.toString()
  });

  console.log('📡 Token response status:', response.status, response.statusText);
  console.log('📡 Token response headers:', Object.fromEntries(response.headers.entries()));

  if (!response.ok) {
    const errorData = await response.json().catch(() => ({}));
    console.error('❌ Token exchange failed:', errorData);
    const errorMessage = errorData.error_description || errorData.error || 'Failed to exchange authorization code';
    throw new Error(errorMessage);
  }

  const data = await response.json();

  if (!data.id_token || !data.access_token) {
    throw new Error('Invalid token response from Cognito');
  }

  // Parse JWT to get groups and expiration
  try {
    const idTokenPayload = JSON.parse(atob(data.id_token.split('.')[1]));
    const expiresAt = (idTokenPayload.exp * 1000) || (Date.now() + 3600000);
    const groups = idTokenPayload['cognito:groups'] || [];

    return {
      idToken: data.id_token,
      accessToken: data.access_token,
      refreshToken: data.refresh_token,
      expiresAt,
      groups: Array.isArray(groups) ? groups : (typeof groups === 'string' ? groups.split(',') : []),
      username: idTokenPayload['cognito:username'] || idTokenPayload.sub || 'unknown'
    };
  } catch (parseError) {
    console.error('Failed to parse JWT token:', parseError);
    throw new Error('Failed to parse authentication token');
  }
}

/**
 * Logout current user
 */
export function logout(): void {
  const user = getCurrentUser();
  if (user) {
    user.signOut();
  }

  // Clear any stored session
  if (typeof window !== 'undefined') {
    localStorage.removeItem('aws-inventory-session');
    window.location.href = '/';
  }
}

/**
 * Check if user has required group/role
 */
export function hasGroup(groups: string[], requiredGroup: string): boolean {
  return groups.includes(requiredGroup);
}

/**
 * Check if user can access service based on groups
 */
export function canAccessService(groups: string[], service: string): boolean {
  // Admin has access to everything
  if (groups.includes('admins') || groups.includes('infra-admins')) {
    return true;
  }

  // Read-only can access EC2 and S3
  if (groups.includes('read-only') || groups.includes('cloud-readonly')) {
    return ['ec2', 's3'].includes(service);
  }

  // Security group can access IAM and security-related info
  if (groups.includes('security')) {
    return ['iam', 'ec2', 's3', 'rds', 'cloudfront', 'acm', 'elb', 'eip', 'sg', 'cognito', 'waf'].includes(service);
  }

  // Network group can access network-related services
  if (groups.includes('network') || groups.includes('infra-network')) {
    return ['vpc', 'nat', 'eip', 'elb', 'ec2', 'sg', 'route53', 'apigw', 'waf'].includes(service);
  }

  return false;
}

/**
 * Store session in localStorage (for client-side persistence)
 */
export function storeSession(session: AuthSession): void {
  if (typeof window !== 'undefined') {
    localStorage.setItem('aws-inventory-session', JSON.stringify(session));
  }
}

/**
 * Get stored session from localStorage
 */
export function getStoredSession(): AuthSession | null {
  if (typeof window === 'undefined') {
    return null;
  }

  const stored = localStorage.getItem('aws-inventory-session');
  if (!stored) {
    return null;
  }

  try {
    const session = JSON.parse(stored);
    // Check if session is still valid
    if (session.expiresAt && session.expiresAt > Date.now()) {
      return session;
    }
    return null;
  } catch {
    return null;
  }
}

