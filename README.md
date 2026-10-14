# LangSmith Fleet → Snowflake via managed MCP

How to let LangSmith Fleet agents answer questions from Snowflake data, using a **Snowflake-managed MCP server** and per-user **OAuth**. This repo is a working reference: setup SQL, a smoke test, and Fleet agent instructions, built on Snowflake's TPC-H sample data.

## TL;DR

- Snowflake has no single, account-wide MCP endpoint. You create an **MCP server object** (`CREATE MCP SERVER`), choose which tools it exposes, and grant access to the server **and** to each tool's underlying object.
- One MCP server holds up to 50 tools. Fleet needs **one connection per server**, not one per agent.
- There are two patterns worth using:

| | **A. Fleet → Cortex Agent** | **B. Fleet → Cortex Analyst → run SQL** |
|---|---|---|
| Tools | `CORTEX_AGENT_RUN` | `CORTEX_ANALYST_MESSAGE` + `SYSTEM_EXECUTE_SQL` |
| Who reasons | Cortex Agent, inside Snowflake | The Fleet agent |
| What Fleet gets back | A finished answer, plus the agent's full run (SQL, rows, chart spec, follow-ups) | SQL, then rows |
| Observed latency* | ~18 s, one call | ~4 s + ~2 s, two calls |
| Observed payload* | ~31 KB | < 1 KB per call |
| Visibility in LangSmith | One opaque tool call | Every step, including the SQL |
| Best when | You already have governed Cortex Agents, or want Snowflake to own orchestration (Analyst + Search + charts) | You want Fleet to own reasoning, plus speed, cost control and full traceability |

\* From one test question on an XS warehouse; indicative only.

**Our recommendation:** use A for business-user-facing Q&A where the Cortex Agent is the governed product. Use B when Fleet agents combine Snowflake with other tools and you want every step traced. Both read from the same semantic view, so metric definitions stay consistent.

Patterns we chose not to lead with:
- **Read-only SQL alone, with no semantic layer.** The LLM writes SQL against raw tables, so accuracy is poor and governance rests only on RBAC.
- **`GENERIC` tools** (curated stored procedures). The tightest control, but every new question needs new code.
- **Cortex Search.** An add-on for unstructured documents.
- **The open-source `Snowflake-Labs/mcp` server.** Deprecated; use the managed server.

## Key concepts

- **Semantic view** (the "semantic layer"): a Snowflake object that maps business terms onto physical tables. It defines tables, joins, dimensions, metrics such as `total_revenue = SUM(price * (1 - discount))`, synonyms, and instructions for SQL generation. Cortex Analyst and Cortex Agents use it to write accurate, consistent SQL. It is **not** a security boundary; RBAC still applies.
- **Cortex Analyst** (`CORTEX_ANALYST_MESSAGE`): turns a question into SQL over a semantic view. It **returns SQL, not data.**
- **Cortex Agent** (`CORTEX_AGENT_RUN`): orchestrates tools (Analyst, Search, SQL execution, charts) and returns an answer.
- **An object's `identifier`** (`DB.SCHEMA.NAME`) is where the object lives, not what data it can reach. Agents and semantic views can reference data in other databases and schemas.

## Architecture (this repo)

```
LangSmith Fleet
  ├─ Agent "Snowflake – Cortex Agent"   (tools: sales_agent)
  └─ Agent "Snowflake – Analyst + SQL"  (tools: sales_analyst, run_sql)
        │  one MCP connection, OAuth 2.1 (Manual), runs as the signed-in user
        ▼
FLEET_MCP.AGENTS.FLEET_MCP_SERVER
  ├─ sales_agent    CORTEX_AGENT_RUN        → FLEET_MCP.AGENTS.SALES_AGENT ──┐
  ├─ sales_analyst  CORTEX_ANALYST_MESSAGE  → FLEET_MCP.SEMANTIC.SALES_SV ◀──┘
  └─ run_sql        SYSTEM_EXECUTE_SQL (read_only)
                                              SALES_SV → FLEET_MCP.DATA.* (TPC-H copy)
Session role: FLEET_MCP_ROLE (read-only). Warehouse: FLEET_MCP_WH (XS).
```

## Setup

Prerequisites:
- `ACCOUNTADMIN`, or equivalent rights to create roles, a warehouse, a database and a security integration.
- Cortex Agents and Analyst available in your region, or cross-region inference enabled.
- Python 3.10+ and `uv`.

### 1. Local tooling (optional; you can also paste the SQL into Snowsight)

```bash
uv venv .venv && uv pip install -p .venv snowflake-connector-python cryptography pyjwt requests python-dotenv
cp .env.example .env    # set account, user, key path, OAuth redirect URI (gitignored)
# Key-pair auth for scripts: generate a key, then set it on your user in Snowsight:
openssl genrsa 2048 | openssl pkcs8 -topk8 -nocrypt -out ~/.snowflake/fleet_mcp_rsa_key.p8 && chmod 600 ~/.snowflake/fleet_mcp_rsa_key.p8
#   ALTER USER <you> SET RSA_PUBLIC_KEY='<public key body>';
```

### 2. Snowflake objects

Environment-specific values live only in `.env`. SQL files use `{{SNOWFLAKE_USER}}` and `{{FLEET_OAUTH_REDIRECT_URI}}` placeholders, which `run_sql.py` validates and fills in (`--dry-run` prints the rendered SQL). If you paste the SQL into Snowsight instead, replace the placeholders by hand. Run in order:

```bash
.venv/bin/python scripts/run_sql.py --role ACCOUNTADMIN sql/01_setup.sql         # warehouse, DB, data copy, role, user defaults
.venv/bin/python scripts/run_sql.py --role ACCOUNTADMIN sql/02_semantic_view.sql
.venv/bin/python scripts/run_sql.py --role ACCOUNTADMIN sql/03_agent.sql
.venv/bin/python scripts/run_sql.py --role ACCOUNTADMIN sql/04_mcp_server.sql
.venv/bin/python scripts/mcp_smoke_test.py      # lists tools, runs pattern A and pattern B end to end
```

### 3. OAuth between Fleet and Snowflake

Snowflake does **not** support dynamic client registration, so Fleet's **OAuth 2.1 (Auto)** mode can't be used. Use **OAuth 2.1 (Manual)**, which means registering the client on both sides:

1. **Pick a LangSmith OAuth provider ID**, e.g. `snowflake-fleet-mcp`. The callback URL is `https://<langsmith-host>/host-oauth-callback/<provider-id>`.
2. **In Snowflake:** set that URL as `FLEET_OAUTH_REDIRECT_URI` in `.env`, then run `scripts/run_sql.py --role ACCOUNTADMIN sql/05_oauth.sql`. Then run `SELECT SYSTEM$SHOW_OAUTH_CLIENT_SECRETS('FLEET_MCP_OAUTH');` to get the client ID and secret.
3. **In LangSmith → Settings → OAuth Providers**, create the provider:

   | Field | Value |
   |---|---|
   | Provider ID | the ID from step 1 |
   | Grant type | **Authorization Code** (Snowflake OAuth has no client-credentials grant) |
   | Client ID / Secret | from step 2 |
   | Authorization URL | `https://<account>.snowflakecomputing.com/oauth/authorize` |
   | Token URL | `https://<account>.snowflakecomputing.com/oauth/token-request` |
   | Scopes | `session:role:FLEET_MCP_ROLE refresh_token` |
   | PKCE | on |

   Take the endpoints from `DESC SECURITY INTEGRATION FLEET_MCP_OAUTH` (`OAUTH_AUTHORIZATION_ENDPOINT` / `OAUTH_TOKEN_ENDPOINT`).
4. **In Fleet → Add custom MCP:**
   - URL: `https://<org>-<account>.snowflakecomputing.com/api/v2/databases/FLEET_MCP/schemas/AGENTS/mcp-servers/FLEET_MCP_SERVER`
   - Authentication: OAuth 2.1 (Manual), with the provider from step 3
   - Save, then sign in to Snowflake and approve.

### 4. Fleet agents

Create the two agents using the instructions in [`fleet/agent_instructions.md`](fleet/agent_instructions.md), then try the test questions listed there.

## Access control checklist

USAGE on the MCP server only lets a client connect and list tools. **Each tool needs its own grant.**

| Needed by | Grant to the runtime role |
|---|---|
| Everything | USAGE on the warehouse, database and schemas; `SNOWFLAKE.CORTEX_USER` |
| MCP server | `USAGE ON MCP SERVER` |
| `sales_agent` | `USAGE ON AGENT`; `SNOWFLAKE.CORTEX_AGENT_USER`; plus everything the agent's own tools use |
| `sales_analyst` | `SELECT ON SEMANTIC VIEW` |
| `run_sql` | `SELECT` on whatever tables it may read (it can run **any** SELECT the role allows) |
| The user | `DEFAULT_ROLE` = the runtime role and a `DEFAULT_WAREHOUSE` (MCP sessions use the defaults; without a warehouse, sessions fail) |

## Gotchas we hit or confirmed

- **Analyst returns SQL only.** Pattern B needs `run_sql`, or the client has to run the SQL some other way.
- **Ambiguity shows up as different answers.** For "revenue in 1995", Analyst first filtered on ship date while the agent used order date. One `AI_SQL_GENERATION` instruction on the semantic view fixed it for both consumers. Put business rules in the semantic view, not in each agent.
- **The agent tool's response is large.** Pattern A returns the Cortex Agent's whole run, about 31 KB. Tell the Fleet agent to use only the final answer.
- **Admin roles can't use OAuth.** `ACCOUNTADMIN`, `ORGADMIN` and `SECURITYADMIN` are blocked by default, so the signing-in user needs a non-admin default role.
- **`tools/call` responds with SSE** (`text/event-stream`). Clients must send `Accept: application/json, text/event-stream`. Fleet handles this.
- **Network policies.** If your account has one, allowlist Fleet's egress IPs. A blocked IP shows up as `invalid_client`.
- **Tool argument names:** the agent tool takes `text`, Analyst takes `message`, and SQL takes `sql`.

## Production notes

- **Put `run_sql` on its own MCP server with its own least-privileged role** (Snowflake's recommendation). On a shared server it can bypass the agent's governance. This demo keeps a single server for simplicity, because its role only reads sample data.
- One Snowflake OAuth integration can serve several MCP servers. Each server is a separate Fleet connection.
- Set `OAUTH_USE_SECONDARY_ROLES = NONE` and a tight `ALLOWED_ROLES_LIST`, and never grant MCP roles to `PUBLIC`.
- Write precise tool names and descriptions; the Fleet LLM picks tools from them.
- MCP servers are not replicated by failover groups. Recreate them with the same scripts in the secondary account.

## Teardown

```bash
.venv/bin/python scripts/run_sql.py --role ACCOUNTADMIN sql/99_teardown.sql
```

This drops the OAuth integration, the `FLEET_MCP` database (data, semantic view, agent and MCP server), the warehouse and the role. It also unsets the user's default role and warehouse. Remove the LangSmith OAuth provider and the Fleet MCP connection separately.

## References

- [Snowflake-managed MCP server](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-mcp)
- [CREATE MCP SERVER](https://docs.snowflake.com/en/sql-reference/sql/create-mcp-server)
- [Semantic views](https://docs.snowflake.com/en/user-guide/views-semantic/overview)
- [CREATE AGENT](https://docs.snowflake.com/en/sql-reference/sql/create-agent)
- [Fleet remote MCP servers](https://docs.langchain.com/langsmith/fleet/remote-mcp-servers)
