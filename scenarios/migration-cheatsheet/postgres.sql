-- PostgreSQL: 迁移速查表 (Migration Cheatsheet)
--
-- 参考资料:
--   [1] PostgreSQL Documentation - SQL Conformance
--       https://www.postgresql.org/docs/current/features.html
--   [2] PostgreSQL Wiki - Converting from other Databases
--       https://wiki.postgresql.org/wiki/Converting_from_other_Databases_to_PostgreSQL
--   [3] pgLoader - 自动迁移工具
--       https://pgloader.io/

-- ============================================================
-- 一、从 MySQL 迁移到 PostgreSQL
-- ============================================================

-- 1. 数据类型映射
--    MySQL                → PostgreSQL
--    TINYINT              → SMALLINT
--    INT / INTEGER        → INTEGER
--    BIGINT               → BIGINT
--    FLOAT                → REAL
--    DOUBLE               → DOUBLE PRECISION
--    DECIMAL(p,s)         → NUMERIC(p,s)
--    TINYINT(1) / BOOL    → BOOLEAN
--    VARCHAR(n)           → VARCHAR(n)
--    TEXT / MEDIUMTEXT     → TEXT（无长度限制）
--    LONGTEXT             → TEXT
--    BLOB / LONGBLOB      → BYTEA
--    DATETIME             → TIMESTAMP
--    DATE                 → DATE
--    TIME                 → TIME
--    TIMESTAMP            → TIMESTAMPTZ（推荐）
--    ENUM('a','b')        → VARCHAR + CHECK 或 CREATE TYPE ... AS ENUM
--    SET('a','b')         → TEXT[] 或 VARCHAR + CHECK
--    JSON                 → JSONB（推荐）或 JSON
--    AUTO_INCREMENT       → SERIAL / BIGSERIAL / GENERATED ALWAYS AS IDENTITY

-- 2. 函数等价映射
--    MySQL                → PostgreSQL
--    IFNULL(a, b)         → COALESCE(a, b)
--    IF(cond, t, f)       → CASE WHEN cond THEN t ELSE f END
--    CONCAT(a, b)         → a || b  或  CONCAT(a, b)
--    GROUP_CONCAT(...)    → STRING_AGG(col, ',')
--    NOW()                → NOW()  或  CURRENT_TIMESTAMP
--    CURDATE()            → CURRENT_DATE
--    DATE_FORMAT(d,f)     → TO_CHAR(d, f)   -- 格式符不同！
--    STR_TO_DATE(s,f)     → TO_DATE(s, f) / TO_TIMESTAMP(s, f)
--    DATEDIFF(a, b)       → a - b  (DATE相减返回INTEGER天数; TIMESTAMP相减返回INTERVAL)
--    DATE_ADD(d, INTERVAL)→ d + INTERVAL '1 day'
--    SUBSTRING_INDEX()    → SPLIT_PART()
--    FIND_IN_SET()        → ANY(STRING_TO_ARRAY())
--    LIMIT n OFFSET m     → LIMIT n OFFSET m（相同）
--    `backtick`           → "double_quotes"（标识符引用）
--    @@变量               → SHOW / current_setting()

-- 3. 常见陷阱
--    - PostgreSQL 标识符默认小写，MySQL 大小写取决于 lower_case_table_names
--    - PostgreSQL 的 BOOLEAN 是真正的布尔类型（TRUE/FALSE），不是 0/1
--    - PostgreSQL 字符串只能用单引号 'abc'，不能用双引号
--    - PostgreSQL 没有 ON UPDATE CURRENT_TIMESTAMP，需要触发器
--    - PostgreSQL 的 GROUP BY 更严格（所有非聚合列必须出现）
--    - PostgreSQL 的事务是严格的（语句失败后整个事务中止）
--    - ENUM 类型需要先 CREATE TYPE

-- ============================================================
-- 二、从 SQL Server 迁移到 PostgreSQL
-- ============================================================

-- 1. 数据类型映射
--    SQL Server           → PostgreSQL
--    NVARCHAR(n)          → VARCHAR(n)（PostgreSQL 原生支持 Unicode）
--    NVARCHAR(MAX)        → TEXT
--    NTEXT                → TEXT
--    BIT                  → BOOLEAN
--    UNIQUEIDENTIFIER     → UUID
--    DATETIME / DATETIME2 → TIMESTAMP
--    DATETIMEOFFSET       → TIMESTAMPTZ
--    MONEY                → NUMERIC(19,4)
--    IMAGE / VARBINARY    → BYTEA
--    XML                  → XML
--    IDENTITY(1,1)        → GENERATED ALWAYS AS IDENTITY
--    HIERARCHYID          → LTREE（需要扩展）

-- 2. 函数等价映射
--    SQL Server           → PostgreSQL
--    ISNULL(a, b)         → COALESCE(a, b)
--    GETDATE()            → NOW()
--    GETUTCDATE()         → NOW() AT TIME ZONE 'UTC'
--    DATEPART(part, d)    → DATE_PART('part', d) 或 EXTRACT(part FROM d)
--    DATEADD(part, n, d)  → d + INTERVAL 'n part'
--    DATEDIFF(part, a, b) → DATE_PART('part', b - a)
--    CONVERT(type, v)     → CAST(v AS type) 或 v::type
--    LEN(s)               → LENGTH(s)
--    CHARINDEX(sub, s)    → POSITION(sub IN s)
--    TOP n                → LIMIT n
--    STRING_SPLIT(s, d)   → UNNEST(STRING_TO_ARRAY(s, d))
--    STUFF()              → OVERLAY()
--    IIF(cond, t, f)      → CASE WHEN cond THEN t ELSE f END
--    @@IDENTITY           → lastval() / currval()
--    NEWID()              → gen_random_uuid()
--    [bracket]            → "double_quotes"

-- 3. 常见陷阱
--    - SQL Server 默认大小写不敏感，PostgreSQL 默认大小写敏感
--    - SQL Server 的 += 字符串连接 → PostgreSQL 用 ||
--    - TOP 语法不同：SELECT TOP 10 → SELECT ... LIMIT 10
--    - 临时表: #temp → CREATE TEMP TABLE
--    - 存储过程语法完全不同（T-SQL → PL/pgSQL）
--    - 没有 CROSS APPLY → 使用 LATERAL JOIN

-- ============================================================
-- 三、从 Oracle 迁移到 PostgreSQL
-- ============================================================

-- 1. 数据类型映射
--    Oracle               → PostgreSQL
--    NUMBER(p,s)          → NUMERIC(p,s)
--    NUMBER               → NUMERIC 或 DOUBLE PRECISION
--    VARCHAR2(n)          → VARCHAR(n)
--    CLOB                 → TEXT
--    BLOB                 → BYTEA
--    RAW                  → BYTEA
--    DATE                 → TIMESTAMP（Oracle DATE 包含时间！）
--    TIMESTAMP WITH TZ    → TIMESTAMPTZ

-- 2. 函数等价映射
--    Oracle               → PostgreSQL
--    NVL(a, b)            → COALESCE(a, b)
--    NVL2(a, b, c)        → CASE WHEN a IS NOT NULL THEN b ELSE c END
--    DECODE(a,b,c,d)      → CASE a WHEN b THEN c ELSE d END
--    SYSDATE              → CURRENT_TIMESTAMP 或 NOW()
--    TO_DATE(s, f)        → TO_DATE(s, f) / TO_TIMESTAMP(s, f)
--    TO_CHAR(d, f)        → TO_CHAR(d, f)（格式基本兼容）
--    ROWNUM               → ROW_NUMBER() OVER () 或 LIMIT
--    CONNECT BY           → WITH RECURSIVE
--    MINUS                → EXCEPT
--    || (字符串连接)      → ||（相同）
--    LISTAGG()            → STRING_AGG()
--    ROWID                → ctid（但语义不同）
--    DUAL                 → 不需要（SELECT 1 即可）
--    (+) 外连接           → LEFT/RIGHT JOIN
--    SEQUENCE.NEXTVAL     → nextval('sequence_name')

-- 3. 常见陷阱
--    - Oracle 空字符串 '' 等于 NULL，PostgreSQL 空字符串是空字符串
--    - Oracle DATE 包含时间部分，PostgreSQL DATE 不包含
--    - Oracle 的 ROWNUM 在 WHERE 之前求值，PostgreSQL 用 LIMIT 或窗口函数
--    - Oracle 包（PACKAGE）在 PostgreSQL 中用 SCHEMA + 函数替代
--    - Oracle 的 PL/SQL 需要转换为 PL/pgSQL

-- ============================================================
-- 四、自增/序列迁移
-- ============================================================
-- MySQL AUTO_INCREMENT:
CREATE TABLE t (id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY);
-- 或
CREATE TABLE t (id BIGSERIAL PRIMARY KEY);

-- Oracle SEQUENCE:
CREATE SEQUENCE my_seq START WITH 1 INCREMENT BY 1;
-- 使用: nextval('my_seq')

-- SQL Server IDENTITY:
CREATE TABLE t (id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY);

-- ============================================================
-- 五、日期/时间函数映射
-- ============================================================
-- 当前时间
SELECT NOW();                       -- 事务开始时间
SELECT CLOCK_TIMESTAMP();           -- 真实当前时间
SELECT CURRENT_DATE;                -- 当前日期
SELECT CURRENT_TIME;                -- 当前时间

-- 日期加减
SELECT CURRENT_DATE + INTERVAL '1 day';
SELECT CURRENT_TIMESTAMP - INTERVAL '2 hours';

-- 日期格式化
SELECT TO_CHAR(NOW(), 'YYYY-MM-DD HH24:MI:SS');
-- 格式: YYYY=年, MM=月, DD=日, HH24=24小时, MI=分, SS=秒

-- ============================================================
-- 六、字符串函数映射
-- ============================================================
SELECT LENGTH('hello');             -- 字符串长度
SELECT UPPER('hello');              -- 大写
SELECT LOWER('HELLO');              -- 小写
SELECT TRIM('  hello  ');           -- 去空格
SELECT SUBSTRING('hello' FROM 2 FOR 3);  -- 子串 → 'ell'
SELECT REPLACE('hello', 'l', 'r'); -- 替换
SELECT POSITION('lo' IN 'hello');  -- 位置 → 4
SELECT 'hello' || ' world';       -- 连接
SELECT STRING_AGG(name, ', ')      -- 聚合连接
    FROM users;
SELECT SPLIT_PART('a,b,c', ',', 2); -- 分割取段 → 'b'
