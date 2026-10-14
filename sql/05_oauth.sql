-- 05_oauth.sql: Snowflake OAuth client for Fleet's "OAuth 2.1 (Manual)" connection.
-- Run as ACCOUNTADMIN. Set FLEET_OAUTH_REDIRECT_URI in .env to https://<langsmith-host>/host-oauth-callback/<provider-id>.
-- Then fetch the client ID/secret in Snowsight (never commit them):
--   SELECT SYSTEM$SHOW_OAUTH_CLIENT_SECRETS('FLEET_MCP_OAUTH');
-- Fleet values:
--   Authorization URL (use OAUTH_AUTHORIZATION_ENDPOINT from DESC SECURITY INTEGRATION FLEET_MCP_OAUTH):
--                      https://<host>/oauth/authorize
--   Token URL:         https://<host>/oauth/token-request
--   Scope:             session:role:FLEET_MCP_ROLE   (optional; default role is used otherwise)
USE ROLE ACCOUNTADMIN;

CREATE SECURITY INTEGRATION IF NOT EXISTS FLEET_MCP_OAUTH
  TYPE = OAUTH
  ENABLED = TRUE
  OAUTH_CLIENT = CUSTOM
  OAUTH_CLIENT_TYPE = 'CONFIDENTIAL'
  OAUTH_REDIRECT_URI = '{{FLEET_OAUTH_REDIRECT_URI}}'
  OAUTH_ISSUE_REFRESH_TOKENS = TRUE
  OAUTH_REFRESH_TOKEN_VALIDITY = 86400
  OAUTH_USE_SECONDARY_ROLES = NONE
  ALLOWED_ROLES_LIST = ('FLEET_MCP_ROLE')
  COMMENT = 'LangSmith Fleet -> FLEET_MCP_SERVER';
