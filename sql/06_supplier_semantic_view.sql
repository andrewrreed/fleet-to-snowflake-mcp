-- 06_supplier_semantic_view.sql: a second business domain (suppliers), used to test multi-view setups.
-- Run as ACCOUNTADMIN after 01.
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE FLEET_MCP_WH;

CREATE TABLE IF NOT EXISTS FLEET_MCP.DATA.SUPPLIER AS SELECT * FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.SUPPLIER;
GRANT SELECT ON TABLE FLEET_MCP.DATA.SUPPLIER TO ROLE FLEET_MCP_ROLE;

CREATE OR REPLACE SEMANTIC VIEW FLEET_MCP.SEMANTIC.SUPPLIER_SV
  TABLES (
    region    AS FLEET_MCP.DATA.REGION   PRIMARY KEY (R_REGIONKEY) WITH SYNONYMS = ('geography'),
    nation    AS FLEET_MCP.DATA.NATION   PRIMARY KEY (N_NATIONKEY) WITH SYNONYMS = ('country'),
    suppliers AS FLEET_MCP.DATA.SUPPLIER PRIMARY KEY (S_SUPPKEY)
      WITH SYNONYMS = ('vendors') COMMENT = 'Companies that supply parts'
  )
  RELATIONSHIPS (
    nation_to_region   AS nation (N_REGIONKEY)    REFERENCES region,
    supplier_to_nation AS suppliers (S_NATIONKEY) REFERENCES nation
  )
  DIMENSIONS (
    region.region_name AS region.R_NAME WITH SYNONYMS = ('region'),
    nation.nation_name AS nation.N_NAME WITH SYNONYMS = ('country name'),
    suppliers.supplier_name AS suppliers.S_NAME WITH SYNONYMS = ('vendor name')
  )
  METRICS (
    suppliers.supplier_count AS COUNT(suppliers.S_SUPPKEY) WITH SYNONYMS = ('number of suppliers', 'vendor count'),
    suppliers.total_supplier_balance AS SUM(suppliers.S_ACCTBAL) WITH SYNONYMS = ('supplier account balance')
  )
  COMMENT = 'Suppliers (vendors) by nation and region (TPC-H sample data)';

GRANT SELECT ON SEMANTIC VIEW FLEET_MCP.SEMANTIC.SUPPLIER_SV TO ROLE FLEET_MCP_ROLE;
