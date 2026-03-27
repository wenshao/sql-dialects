-- DuckDB: 数据去重策略（Deduplication）(v0.9+)
--
-- 参考资料:
--   [1] DuckDB Documentation - Window Functions
--       https://duckdb.org/docs/sql/window_functions
--   [2] DuckDB Documentation - QUALIFY
--       https://duckdb.org/docs/sql/query_syntax/qualify
--   [3] DuckDB Documentation - DISTINCT ON
--       https://duckdb.org/docs/sql/query_syntax/select#distinct-on-clause

-- ============================================================
-- 示例数据上下文
-- ============================================================
-- 假设表结构:
--   users(user_id INTEGER, email VARCHAR, username VARCHAR, created_at TIMESTAMP)

-- ============================================================
-- 1. 查找重复数据
-- ============================================================

SELECT email, COUNT(*) AS cnt
FROM users
GROUP BY email
HAVING COUNT(*) > 1;

-- ============================================================
-- 2. QUALIFY 去重（推荐方式）
-- ============================================================

SELECT user_id, email, username, created_at
FROM users
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY email
    ORDER BY created_at DESC
) = 1;

-- ============================================================
-- 3. DISTINCT ON（DuckDB 支持 PostgreSQL 语法）
-- ============================================================

SELECT DISTINCT ON (email)
       user_id, email, username, created_at
FROM users
ORDER BY email, created_at DESC;

-- ============================================================
-- 4. 传统 ROW_NUMBER 方式
-- ============================================================

SELECT *
FROM (
    SELECT user_id, email, username, created_at,
           ROW_NUMBER() OVER (
               PARTITION BY email
               ORDER BY created_at DESC
           ) AS rn
    FROM users
) ranked
WHERE rn = 1;

-- ============================================================
-- 5. 删除重复数据
-- ============================================================

DELETE FROM users
WHERE rowid NOT IN (
    SELECT MIN(rowid)
    FROM users
    GROUP BY email
);

-- CTAS 方式
CREATE OR REPLACE TABLE users AS
SELECT user_id, email, username, created_at
FROM users
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY email
    ORDER BY created_at DESC
) = 1;

-- ============================================================
-- 6. 直接从文件去重
-- ============================================================

-- 从 Parquet 文件直接去重查询
SELECT user_id, email, username, created_at
FROM read_parquet('users.parquet')
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY email
    ORDER BY created_at DESC
) = 1;

-- 从 CSV 文件去重并写入新文件
COPY (
    SELECT DISTINCT ON (email)
           user_id, email, username, created_at
    FROM read_csv_auto('users.csv')
    ORDER BY email, created_at DESC
) TO 'users_deduped.parquet' (FORMAT PARQUET);

-- ============================================================
-- 7. 近似去重
-- ============================================================

SELECT approx_count_distinct(email) AS approx_distinct
FROM users;

-- ============================================================
-- 8. DISTINCT vs GROUP BY
-- ============================================================

SELECT DISTINCT email FROM users;
SELECT email FROM users GROUP BY email;

-- ============================================================
-- 9. 性能考量
-- ============================================================

-- DuckDB 同时支持 QUALIFY 和 DISTINCT ON
-- 列式引擎，去重操作自动向量化
-- 直接从 Parquet/CSV 文件去重，无需导入
-- 无需手动创建索引
