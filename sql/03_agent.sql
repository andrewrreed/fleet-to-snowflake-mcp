-- 03_agent.sql: a Cortex Agent that answers sales questions using the semantic view (pattern A).
-- Run as ACCOUNTADMIN after 02.
USE ROLE ACCOUNTADMIN;

CREATE OR REPLACE AGENT FLEET_MCP.AGENTS.SALES_AGENT
  COMMENT = 'Answers sales questions over SALES_SV'
  FROM SPECIFICATION
  $$
  models:
    orchestration: auto
  orchestration:
    budget:
      seconds: 60
      tokens: 16000
  instructions:
    response: "Answer concisely. Lead with the number(s), then a one-line explanation. Use tables for multi-row results."
    orchestration: "Use sales_analyst for any question about sales, revenue, orders, customers, regions or countries. If the question is outside that data, say so instead of guessing."
    sample_questions:
      - question: "What was total revenue by region in 1995?"
  tools:
    - tool_spec:
        type: "cortex_analyst_text_to_sql"
        name: "sales_analyst"
        description: "Text-to-SQL over sales orders, line items, customers, nations and regions (1992-1998)."
  tool_resources:
    sales_analyst:
      semantic_view: "FLEET_MCP.SEMANTIC.SALES_SV"
      execution_environment:
        type: "warehouse"
        warehouse: "FLEET_MCP_WH"
  $$;

GRANT USAGE ON AGENT FLEET_MCP.AGENTS.SALES_AGENT TO ROLE FLEET_MCP_ROLE;
