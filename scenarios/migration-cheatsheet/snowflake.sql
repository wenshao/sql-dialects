-- Snowflake: 迁移速查表 (Migration Cheatsheet)
--
-- 参考资料:
--   [1] Snowflake Documentation - Migration Guide
--       https://docs.snowflake.com/en/user-guide/migration
--   [2] Snowflake SQL Reference
--       https://docs.snowflake.com/en/sql-reference

-- ============================================================
-- 一、从其他数据库迁移到 Snowflake
-- ============================================================
-- 数据类型映射:
--   INT/INTEGER    → NUMBER(38,0) 或 INT
--   FLOAT/DOUBLE   → FLOAT
--   DECIMAL(p,s)   → NUMBER(p,s)
--   VARCHAR/TEXT    → VARCHAR (默认 16MB)
--   BOOLEAN        → BOOLEAN
--   DATE           → DATE
--   DATETIME       → TIMESTAMP_NTZ
--   TIMESTAMP+TZ   → TIMESTAMP_TZ / TIMESTAMP_LTZ
--   BLOB/BYTEA     → BINARY
--   JSON/JSONB     → VARIANT
--   ARRAY          → VARIANT (ARRAY)
--   AUTO_INCREMENT → AUTOINCREMENT 或 IDENTITY

-- 函数映射:
--   ISNULL/IFNULL/NVL   → NVL(a,b) / IFNULL(a,b) / COALESCE
--   GETDATE()/NOW()     → CURRENT_TIMESTAMP()
--   DATEADD             → DATEADD(part, n, d)
--   DATEDIFF            → DATEDIFF(part, a, b)
--   TO_CHAR/FORMAT      → TO_CHAR(d, 'YYYY-MM-DD')
--   STRING_AGG          → LISTAGG(col, ',')
--   CONCAT              → CONCAT(a, b) 或 a || b

-- 常见陷阱:
--   - Snowflake 的 PK/UK 是信息性约束，不强制
--   - Snowflake 标识符默认大写（除非用双引号）
--   - Snowflake 的 VARIANT 类型处理半结构化数据
--   - Snowflake 的 Time Travel 替代手工版本管理

-- ============================================================
-- 二、自增/序列
-- ============================================================
CREATE TABLE t (id NUMBER AUTOINCREMENT START 1 INCREMENT 1);
CREATE SEQUENCE my_seq START = 1 INCREMENT = 1;
SELECT my_seq.NEXTVAL;

-- ============================================================
-- 三、日期/时间函数
-- ============================================================
SELECT CURRENT_TIMESTAMP();
SELECT CURRENT_DATE();
SELECT DATEADD('day', 1, CURRENT_DATE());
SELECT DATEDIFF('day', '2024-01-01', '2024-12-31');
SELECT TO_CHAR(CURRENT_TIMESTAMP(), 'YYYY-MM-DD HH24:MI:SS');

-- ============================================================
-- 四、字符串函数
-- ============================================================
SELECT LENGTH('hello');              -- 字符长度
SELECT UPPER('hello');               -- 大写
SELECT TRIM('  hello  ');            -- 去空格
SELECT SUBSTR('hello', 2, 3);       -- 子串 → 'ell'
SELECT REPLACE('hello', 'l', 'r');   -- 替换
SELECT POSITION('lo' IN 'hello');    -- 位置 → 4
SELECT 'hello' || ' world';         -- 连接
SELECT LISTAGG(name, ', ') WITHIN GROUP (ORDER BY name) FROM users;
SELECT SPLIT_PART('a,b,c', ',', 2); -- → 'b'
