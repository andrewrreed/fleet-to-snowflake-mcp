-- 04_mcp_server.sql: one Snowflake-managed MCP server exposing both patterns.
--   Pattern A: sales_agent                     (agent writes + runs SQL, returns an answer)
--   Pattern B: sales_analyst -> run_sql         (Analyst returns SQL; the client runs it)
-- Run as ACCOUNTADMIN after 03.
-- Production note: Snowflake recommends putting run_sql on its own server + least-privileged role.
USE ROLE ACCOUNTADMIN;

CREATE OR REPLACE MCP SERVER FLEET_MCP.AGENTS.FLEET_MCP_SERVER
  FROM SPECIFICATION
  $$
  tools:
    - title: "Sales agent"
      name: "sales_agent"
      type: "CORTEX_AGENT_RUN"
      identifier: "FLEET_MCP.AGENTS.SALES_AGENT"
      description: "Ask a natural-language question about sales, revenue, orders, customers, nations or regions (1992-1998). Returns a finished answer with the data."
    - title: "Sales analyst (text-to-SQL)"
      name: "sales_analyst"
      type: "CORTEX_ANALYST_MESSAGE"
      identifier: "FLEET_MCP.SEMANTIC.SALES_SV"
      description: "Turns a natural-language sales question into SQL using the governed sales semantic view. Returns SQL only; run it with run_sql."
    - title: "Run read-only SQL"
      name: "run_sql"
      type: "SYSTEM_EXECUTE_SQL"
      description: "Executes a read-only SQL SELECT in Snowflake and returns rows. Use it to run SQL produced by sales_analyst."
      config:
        read_only: true
        query_timeout: 60
        warehouse: "FLEET_MCP_WH"
  $$;

GRANT USAGE ON MCP SERVER FLEET_MCP.AGENTS.FLEET_MCP_SERVER TO ROLE FLEET_MCP_ROLE;
