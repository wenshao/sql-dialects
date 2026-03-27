-- PostgreSQL: 迁移速查表 (Migration Cheatsheet)
--
-- 参考资料:
--   [1] PostgreSQL Wiki - Converting from other Databases
--       https://wiki.postgresql.org/wiki/Converting_from_other_Databases_to_PostgreSQL

-- ============================================================
-- 一、从 MySQL 迁移到 PostgreSQL
-- ============================================================

-- 1. 数据类型映射
--   MySQL               → PostgreSQL
--   TINYINT(1)/BOOL      → BOOLEAN
--   INT UNSIGNED          → BIGINT（无 UNSIGNED）
--   TINYTEXT/MEDIUMTEXT   → TEXT（统一无限制）
--   LONGBLOB              → BYTEA
--   DATETIME              → TIMESTAMP
--   TIMESTAMP             → TIMESTAMPTZ（推荐）
--   ENUM('a','b')         → CREATE TYPE ... AS ENUM 或 VARCHAR+CHECK
--   SET('a','b')          → TEXT[]
--   JSON                  → JSONB（推荐）
--   AUTO_INCREMENT        → GENERATED ALWAYS AS IDENTITY

-- 2. 函数映射
--   IFNULL(a,b)           → COALESCE(a,b)
--   IF(cond,t,f)          → CASE WHEN cond THEN t ELSE f END
--   GROUP_CONCAT(...)     → STRING_AGG(col,',')
--   DATE_FORMAT(d,f)      → TO_CHAR(d,f)  -- 格式符不同!
--   DATEDIFF(a,b)         → a - b（DATE相减返回INTEGER天数）
--   NOW()                 → NOW()（相同）
--   `backtick`            → "double_quotes"
--   LIMIT n OFFSET m      → LIMIT n OFFSET m（相同）

-- 3. 常见陷阱
--   - || 在 MySQL 是 OR，在 PostgreSQL 是字符串拼接
--   - PostgreSQL 标识符默认折叠为小写
--   - PostgreSQL 字符串只能用单引号（双引号是标识符）
--   - PostgreSQL 没有 ON UPDATE CURRENT_TIMESTAMP（需触发器）
--   - PostgreSQL GROUP BY 严格（所有非聚合列必须出现）
--   - PostgreSQL 事务中语句失败 → 整个事务中止

-- ============================================================
-- 二、从 SQL Server 迁移到 PostgreSQL
-- ============================================================

-- 1. 数据类型映射
--   NVARCHAR(n)           → VARCHAR(n)（PostgreSQL 原生 Unicode）
--   NVARCHAR(MAX)         → TEXT
--   BIT                   → BOOLEAN
--   UNIQUEIDENTIFIER      → UUID
--   DATETIME2             → TIMESTAMP
--   DATETIMEOFFSET        → TIMESTAMPTZ
--   MONEY                 → NUMERIC(19,4)
--   IDENTITY(1,1)         → GENERATED ALWAYS AS IDENTITY

-- 2. 函数映射
--   ISNULL(a,b)           → COALESCE(a,b)
--   GETDATE()             → NOW()
--   DATEPART(part,d)      → EXTRACT(part FROM d)
--   DATEADD(day,n,d)      → d + INTERVAL 'n days'
--   TOP n                 → LIMIT n
--   STRING_SPLIT(s,d)     → UNNEST(STRING_TO_ARRAY(s,d))
--   NEWID()               → gen_random_uuid()
--   [bracket]             → "double_quotes"
--   CROSS APPLY           → LATERAL JOIN
--   #temp_table           → CREATE TEMP TABLE

-- ============================================================
-- 三、从 Oracle 迁移到 PostgreSQL
-- ============================================================

-- 1. 数据类型映射
--   NUMBER(p,s)           → NUMERIC(p,s)
--   VARCHAR2(n)           → VARCHAR(n)
--   CLOB                  → TEXT
--   DATE                  → TIMESTAMP（Oracle DATE 含时间!）
--   TIMESTAMP WITH TZ     → TIMESTAMPTZ

-- 2. 函数映射
--   NVL(a,b)              → COALESCE(a,b)
--   DECODE(a,b,c,d)       → CASE a WHEN b THEN c ELSE d END
--   SYSDATE               → NOW()
--   ROWNUM                → ROW_NUMBER() OVER() 或 LIMIT
--   CONNECT BY            → WITH RECURSIVE
--   MINUS                 → EXCEPT
--   SEQUENCE.NEXTVAL      → nextval('sequence')
--   DUAL                  → 不需要（SELECT 1 即可）
--   (+) 外连接            → LEFT/RIGHT JOIN

-- 3. 常见陷阱
--   - Oracle 空字符串 '' = NULL，PostgreSQL '' ≠ NULL
--   - Oracle DATE 含时间，PostgreSQL DATE 不含
--   - Oracle PL/SQL → PL/pgSQL（语法相似但有差异）
--   - Oracle 包(PACKAGE) → PostgreSQL 用 Schema + 函数替代

-- ============================================================
-- 四、PostgreSQL 独有特性（迁移后可利用）
-- ============================================================

-- 这些是迁移到 PostgreSQL 后可以使用的"升级"功能:
--   RETURNING *         — INSERT/UPDATE/DELETE 返回受影响的行
--   :: 类型转换          — 比 CAST 更简洁: '42'::INT
--   JSONB + GIN 索引     — 内置文档存储能力
--   数组类型 + GIN 索引  — 原生数组支持
--   generate_series      — 序列生成（日期填充、测试数据）
--   DISTINCT ON          — 分组取首行的最简语法
--   FILTER 子句          — 条件聚合最简洁方式
--   DDL 事务性           — BEGIN; CREATE TABLE; ROLLBACK; 可回滚
--   Advisory Locks       — 应用级分布式锁
--   LISTEN/NOTIFY        — 数据库内置 pub-sub
--   RLS 行级安全         — 数据库级多租户隔离
--   可写 CTE             — 单语句完成归档等复杂操作
