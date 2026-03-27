-- TimescaleDB: 数据库、模式与用户管理
--
-- 参考资料:
--   [1] TimescaleDB Documentation - Setup
--       https://docs.timescale.com/self-hosted/latest/install/
--   [2] PostgreSQL Documentation (TimescaleDB 基于 PostgreSQL)
--       https://www.postgresql.org/docs/current/sql-createdatabase.html

-- ============================================================
-- TimescaleDB 是 PostgreSQL 扩展，完全兼容 PostgreSQL
-- 命名层级: cluster > database > schema > object
-- 所有 PostgreSQL 的用户/数据库管理语法都适用
-- ============================================================

-- ============================================================
-- 1. 数据库管理（同 PostgreSQL）
-- ============================================================

CREATE DATABASE myapp;

CREATE DATABASE myapp
    OWNER = myuser
    ENCODING = 'UTF8'
    TEMPLATE = template0;

ALTER DATABASE myapp SET timezone TO 'UTC';

DROP DATABASE myapp;
DROP DATABASE IF EXISTS myapp;

-- ============================================================
-- 2. 安装 TimescaleDB 扩展
-- ============================================================

-- 在目标数据库中启用 TimescaleDB
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- 查看已安装扩展
SELECT * FROM pg_extension WHERE extname = 'timescaledb';

-- TimescaleDB 工具扩展
CREATE EXTENSION IF NOT EXISTS timescaledb_toolkit;

-- ============================================================
-- 3. 模式管理（同 PostgreSQL）
-- ============================================================

CREATE SCHEMA myschema;
CREATE SCHEMA IF NOT EXISTS myschema;

DROP SCHEMA myschema CASCADE;

SET search_path TO myschema, public;

-- ============================================================
-- 4. 用户与角色（同 PostgreSQL）
-- ============================================================

CREATE USER myuser WITH PASSWORD 'secret123';
CREATE ROLE analyst NOLOGIN;

GRANT CONNECT ON DATABASE myapp TO myuser;
GRANT USAGE ON SCHEMA myschema TO analyst;
GRANT SELECT ON ALL TABLES IN SCHEMA myschema TO analyst;

ALTER DEFAULT PRIVILEGES IN SCHEMA myschema
    GRANT SELECT ON TABLES TO analyst;

GRANT analyst TO myuser;

DROP USER myuser;

-- ============================================================
-- 5. TimescaleDB Cloud（Timescale Cloud 特有）
-- ============================================================

-- Timescale Cloud 通过 Web Console 管理：
-- - 数据库实例创建/删除
-- - 用户管理
-- - 连接安全（SSL/IP 白名单）
-- - 自动备份和恢复

-- ============================================================
-- 6. 查询元数据
-- ============================================================

SELECT current_database(), current_schema(), current_user;

-- TimescaleDB 特有视图
SELECT * FROM timescaledb_information.hypertables;
SELECT * FROM timescaledb_information.continuous_aggregates;
SELECT * FROM timescaledb_information.compression_settings;
SELECT * FROM timescaledb_information.data_nodes;  -- 多节点

-- 注意：TimescaleDB 的所有数据库/用户管理
-- 完全继承自 PostgreSQL，没有额外扩展
-- TimescaleDB 添加的是时序数据处理能力（hypertable, 连续聚合等）
