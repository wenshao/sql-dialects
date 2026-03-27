-- SQL 标准: 缓慢变化维度 (Slowly Changing Dimension)
--
-- 参考资料:
--   [1] ISO/IEC 9075 SQL Standard - MERGE (SQL:2003)
--   [2] ISO/IEC 9075 SQL Standard - Temporal Tables (SQL:2011)
--   [3] Kimball Group - SCD Types

-- ============================================================
-- SCD Type 1: MERGE（SQL:2003 标准）
-- ============================================================
MERGE INTO dim_customer AS t
USING stg_customer AS s
ON t.customer_id = s.customer_id
WHEN MATCHED AND (t.name <> s.name OR t.city <> s.city)
    THEN UPDATE SET t.name = s.name, t.city = s.city, t.tier = s.tier
WHEN NOT MATCHED
    THEN INSERT (customer_id, name, city, tier)
         VALUES (s.customer_id, s.name, s.city, s.tier);

-- ============================================================
-- SQL:2011 时态表标准
-- ============================================================
-- CREATE TABLE dim_customer_temporal (
--     customer_id VARCHAR(20) PRIMARY KEY,
--     name        VARCHAR(100),
--     sys_start   TIMESTAMP(6) GENERATED ALWAYS AS ROW START,
--     sys_end     TIMESTAMP(6) GENERATED ALWAYS AS ROW END,
--     PERIOD FOR SYSTEM_TIME (sys_start, sys_end)
-- ) WITH SYSTEM VERSIONING;

-- ============================================================
-- 各数据库 MERGE / SCD 支持对照
-- ============================================================
-- SQL Server:   MERGE (2008+), Temporal Tables (2016+)
-- Oracle:       MERGE (9i+), Flashback Query
-- PostgreSQL:   MERGE (15+), INSERT ON CONFLICT (9.5+)
-- MySQL:        无 MERGE, 用 INSERT ON DUPLICATE KEY / 多步
-- BigQuery:     MERGE
-- Snowflake:    MERGE, Time Travel
-- ClickHouse:   ReplacingMergeTree
-- Hive:         MERGE (2.2+, ACID 表)
-- Spark:        Delta Lake / Iceberg MERGE
-- MariaDB:      无 MERGE, System Versioning (10.3+)
-- DB2:          MERGE, Temporal Tables
-- Teradata:     MERGE, Temporal Tables
-- Databricks:   Delta MERGE
