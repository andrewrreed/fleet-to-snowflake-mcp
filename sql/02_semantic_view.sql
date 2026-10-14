-- 02_semantic_view.sql: the "semantic layer" — business names and metric definitions over TPCH.
-- Run as ACCOUNTADMIN after 01.
USE ROLE ACCOUNTADMIN;

CREATE OR REPLACE SEMANTIC VIEW FLEET_MCP.SEMANTIC.SALES_SV
  TABLES (
    region     AS FLEET_MCP.DATA.REGION   PRIMARY KEY (R_REGIONKEY)
      WITH SYNONYMS = ('geography', 'territory') COMMENT = 'World sales regions',
    nation     AS FLEET_MCP.DATA.NATION   PRIMARY KEY (N_NATIONKEY)
      WITH SYNONYMS = ('country') COMMENT = 'Countries',
    customers  AS FLEET_MCP.DATA.CUSTOMER PRIMARY KEY (C_CUSTKEY)
      WITH SYNONYMS = ('clients', 'accounts') COMMENT = 'Customers who place orders',
    orders     AS FLEET_MCP.DATA.ORDERS   PRIMARY KEY (O_ORDERKEY)
      COMMENT = 'One row per customer order',
    line_items AS FLEET_MCP.DATA.LINEITEM PRIMARY KEY (L_ORDERKEY, L_LINENUMBER)
      COMMENT = 'One row per product line on an order'
  )
  RELATIONSHIPS (
    nation_to_region   AS nation (N_REGIONKEY)    REFERENCES region,
    customer_to_nation AS customers (C_NATIONKEY) REFERENCES nation,
    order_to_customer  AS orders (O_CUSTKEY)      REFERENCES customers,
    line_to_order      AS line_items (L_ORDERKEY) REFERENCES orders
  )
  FACTS (
    line_items.net_revenue AS line_items.L_EXTENDEDPRICE * (1 - line_items.L_DISCOUNT)
      COMMENT = 'Line revenue after discount',
    line_items.quantity AS line_items.L_QUANTITY
  )
  DIMENSIONS (
    region.region_name AS region.R_NAME WITH SYNONYMS = ('region'),
    nation.nation_name AS nation.N_NAME WITH SYNONYMS = ('country name'),
    customers.customer_name AS customers.C_NAME WITH SYNONYMS = ('customer', 'client name'),
    customers.market_segment AS customers.C_MKTSEGMENT WITH SYNONYMS = ('segment'),
    orders.order_date AS orders.O_ORDERDATE,
    orders.order_year AS YEAR(orders.O_ORDERDATE),
    orders.order_month AS DATE_TRUNC('MONTH', orders.O_ORDERDATE),
    orders.order_status AS orders.O_ORDERSTATUS COMMENT = 'F = fulfilled, O = open, P = partial',
    orders.order_priority AS orders.O_ORDERPRIORITY,
    line_items.return_flag AS line_items.L_RETURNFLAG COMMENT = 'R = returned, A = accepted, N = not yet returnable',
    line_items.ship_date AS line_items.L_SHIPDATE
  )
  METRICS (
    line_items.total_revenue AS SUM(line_items.net_revenue)
      WITH SYNONYMS = ('revenue', 'sales', 'net sales') COMMENT = 'Sum of extended price after discount',
    line_items.total_quantity AS SUM(line_items.quantity) WITH SYNONYMS = ('units sold'),
    orders.order_count AS COUNT(orders.O_ORDERKEY) WITH SYNONYMS = ('number of orders'),
    orders.total_order_value AS SUM(orders.O_TOTALPRICE) WITH SYNONYMS = ('order value', 'gross order value'),
    orders.average_order_value AS AVG(orders.O_TOTALPRICE) WITH SYNONYMS = ('AOV'),
    customers.customer_count AS COUNT(customers.C_CUSTKEY)
  )
  COMMENT = 'Sales orders, customers and revenue (TPC-H sample data, 1992-1998)'
  AI_SQL_GENERATION 'Data covers 1992-08 through 1998-12. "Revenue" means total_revenue unless the user says order value. Round currency to 2 decimals. For questions by year, month or date, filter and group on orders.order_date (order_year, order_month) unless the user explicitly asks about shipping.';

GRANT SELECT ON SEMANTIC VIEW FLEET_MCP.SEMANTIC.SALES_SV TO ROLE FLEET_MCP_ROLE;
