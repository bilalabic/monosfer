// Test-only values. Never load these into a deployed application.
export const authEnv = {
  SIWE_DOMAIN: 'app.example.com', SIWE_URI: 'https://app.example.com', SIWE_CHAIN_ID: '10143',
  SIWE_STATEMENT: 'Sign in to Monosfer.', SIWE_RPC_URL: 'https://127.0.0.1:1',
  SESSION_COOKIE_SECRET: 'test-only-secret-with-at-least-32-characters',
  SESSION_TTL_SECONDS: '86400', NONCE_TTL_SECONDS: '300',
  AUTH_RATE_LIMIT_WINDOW_SECONDS: '60', AUTH_RATE_LIMIT_MAX: '1000',
};
export const localAuthEnv = { ...authEnv, SIWE_DOMAIN: 'localhost:3000', SIWE_URI: 'http://localhost:3000' };
