-- BigQuery: 迁移速查表 (Migration Cheatsheet)
--
-- 参考资料:
--   [1] BigQuery Migration Guide
--       https://cloud.google.com/bigquery/docs/migration
--   [2] BigQuery SQL Reference
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/

-- ============================================================
-- 一、从其他数据库迁移到 BigQuery
-- ============================================================
-- 数据类型映射:
--   INT/INTEGER    → INT64
--   SMALLINT       → INT64
--   FLOAT/DOUBLE   → FLOAT64
--   DECIMAL(p,s)   → NUMERIC(p,s) 或 BIGNUMERIC
--   VARCHAR/TEXT    → STRING
--   BOOLEAN        → BOOL
--   DATE           → DATE
--   DATETIME       → DATETIME（无时区）
--   TIMESTAMP      → TIMESTAMP（UTC）
--   BLOB/BYTEA     → BYTES
--   JSON           → JSON（BigQuery 原生支持）
--   ARRAY          → ARRAY<T>（原生支持）
--   无             → STRUCT<...>（原生支持）

-- 函数映射（从 SQL Server/MySQL/PostgreSQL）:
--   ISNULL/IFNULL/NVL  → IFNULL(a, b) 或 COALESCE(a, b)
--   GETDATE()/NOW()    → CURRENT_TIMESTAMP()
--   DATEADD/DATE_ADD   → DATE_ADD(d, INTERVAL n DAY)
--   DATEDIFF           → DATE_DIFF(a, b, DAY)
--   TO_CHAR/FORMAT     → FORMAT_TIMESTAMP('%Y-%m-%d', ts)
--   TOP/LIMIT          → LIMIT
--   AUTO_INCREMENT     → 无（使用 GENERATE_UUID() 或应用层生成）
--   STRING_AGG/GROUP_CONCAT → STRING_AGG(col, ',')
--   UNNEST(array)      → UNNEST(array)

-- 常见陷阱:
--   - BigQuery 无主键/唯一约束（仅信息性，不强制）
--   - BigQuery 无索引（靠分区和聚集优化）
--   - BigQuery 无 UPDATE 单行（DML 按分区扫描计费）
--   - BigQuery 无序列/自增（用 ROW_NUMBER 或 UUID）
--   - BigQuery 使用标准 SQL，方言差异需注意
--   - BigQuery 列名大小写不敏感

-- ============================================================
-- 二、自增替代
-- ============================================================
-- BigQuery 没有自增列，使用替代方案:
SELECT GENERATE_UUID() AS id;       -- UUID
SELECT ROW_NUMBER() OVER () AS id;  -- 行号

-- ============================================================
-- 三、日期/时间函数
-- ============================================================
SELECT CURRENT_TIMESTAMP();                 -- 当前 UTC 时间
SELECT CURRENT_DATE();                      -- 当前日期
SELECT DATE_ADD(CURRENT_DATE(), INTERVAL 1 DAY);
SELECT DATE_DIFF(DATE '2024-12-31', DATE '2024-01-01', DAY);
SELECT FORMAT_TIMESTAMP('%Y-%m-%d %H:%M:%S', CURRENT_TIMESTAMP());
SELECT PARSE_TIMESTAMP('%Y-%m-%d', '2024-06-15');

-- ============================================================
-- 四、字符串函数
-- ============================================================
SELECT LENGTH('hello');              -- 字符长度
SELECT UPPER('hello');               -- 大写
SELECT LOWER('HELLO');               -- 小写
SELECT TRIM('  hello  ');            -- 去空格
SELECT SUBSTR('hello', 2, 3);       -- 子串 → 'ell'
SELECT REPLACE('hello', 'l', 'r');   -- 替换
SELECT STRPOS('hello', 'lo');        -- 位置 → 4
SELECT CONCAT('hello', ' world');   -- 连接
SELECT STRING_AGG(name, ', ') FROM users; -- 聚合连接
SELECT SPLIT('a,b,c', ',');          -- 分割为数组
