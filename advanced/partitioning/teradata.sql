-- Teradata: 表分区策略
--
-- 参考资料:
--   [1] Teradata Documentation - Partitioned Primary Index
--       https://docs.teradata.com/r/Teradata-Database-SQL-Data-Definition-Language

-- ============================================================
-- PPI（分区主索引）
-- ============================================================

CREATE TABLE orders (
    id BIGINT, user_id BIGINT, amount DECIMAL(10,2), order_date DATE
) PRIMARY INDEX (user_id)
  PARTITION BY RANGE_N(order_date
    BETWEEN DATE '2023-01-01' AND DATE '2025-12-31'
    EACH INTERVAL '1' MONTH);

-- ============================================================
-- CASE_N 分区
-- ============================================================

CREATE TABLE users_status (
    id BIGINT, username VARCHAR(100), status INTEGER
) PRIMARY INDEX (id)
  PARTITION BY CASE_N(
    status = 1,
    status = 2,
    status = 3,
    NO CASE, UNKNOWN
);

-- ============================================================
-- 多级分区（MLP, 14.0+）
-- ============================================================

CREATE TABLE sales (
    id BIGINT, sale_date DATE, region VARCHAR(20), amount DECIMAL(10,2)
) PRIMARY INDEX (id)
  PARTITION BY (
    RANGE_N(sale_date BETWEEN DATE '2024-01-01' AND DATE '2025-12-31'
            EACH INTERVAL '1' MONTH),
    CASE_N(region = 'East', region = 'West', NO CASE)
);

-- ============================================================
-- 分区管理
-- ============================================================

-- Teradata 分区在 DDL 时定义，管理通过 DDL 变更

-- 查看分区信息
SELECT * FROM DBC.PartitioningConstraintsV WHERE DatabaseName = 'mydb';

-- 注意：Teradata 使用 PPI（分区主索引）
-- 注意：RANGE_N 定义范围分区，CASE_N 定义条件分区
-- 注意：EACH INTERVAL 自动生成等间隔分区
-- 注意：14.0+ 支持多级分区（MLP）
-- 注意：分区裁剪在查询优化中自动进行
