# Oracle: 字符串类型

> 参考资料:
> - [Oracle SQL Language Reference - Character Data Types](https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/Data-Types.html)

## 字符串类型概览

CHAR(n):     定长，最大 2000 字节，空格填充
VARCHAR2(n): 变长，最大 4000 字节（标准），32767 字节（EXTENDED）
NCHAR(n):    定长 Unicode
NVARCHAR2(n): 变长 Unicode
CLOB:        大文本，最大 (4GB - 1) * 数据库块大小
NCLOB:       Unicode 大文本

```sql
CREATE TABLE examples (
    code    CHAR(10),                 -- 定长（空格填充到 10 字节）
    name    VARCHAR2(255),            -- 变长（推荐）
    content CLOB                      -- 大文本
);
```

## VARCHAR2 vs VARCHAR（Oracle 独有的区别）

Oracle 推荐用 VARCHAR2 而非 VARCHAR
VARCHAR 是 SQL 标准保留字，Oracle 文档警告"未来可能改变 VARCHAR 的语义"
实际上 VARCHAR 和 VARCHAR2 在 Oracle 中行为相同（目前）
但最佳实践: 永远使用 VARCHAR2

横向对比:
  Oracle:     VARCHAR2（推荐）/ VARCHAR（不推荐）
  PostgreSQL: VARCHAR / TEXT（TEXT 推荐，无长度限制）
  MySQL:      VARCHAR（最大 65535 字节）
  SQL Server: VARCHAR（最大 8000 字节）/ VARCHAR(MAX)

## 字节语义 vs 字符语义（Oracle 独有的关键设计）

VARCHAR2(100 BYTE): 100 字节（默认!）
VARCHAR2(100 CHAR): 100 字符

默认行为由 NLS_LENGTH_SEMANTICS 参数控制:
```sql
ALTER SESSION SET NLS_LENGTH_SEMANTICS = 'CHAR';
```

为什么这很重要?
UTF-8 编码下，中文字符占 3 字节:
VARCHAR2(100 BYTE): 最多存 33 个中文字符
VARCHAR2(100 CHAR): 最多存 100 个中文字符

横向对比:
  Oracle:     VARCHAR2(n) 默认字节语义（容易出错!）
  PostgreSQL: VARCHAR(n) 字符语义（安全）
  MySQL:      VARCHAR(n) 字符语义（安全）
  SQL Server: VARCHAR(n) 字节语义 / NVARCHAR(n) 字符语义

对引擎开发者的启示:
  推荐默认使用字符语义（CHARACTER）而非字节语义。
  字节语义在多字节编码下会导致用户困惑和数据截断。

## 12c+: VARCHAR2 最大长度扩展

12c+: 可以扩展到 32767 字节
```sql
ALTER SYSTEM SET MAX_STRING_SIZE = EXTENDED;
```

> **注意**: 一旦启用不可撤销!

## '' = NULL: Oracle 最大的字符串陷阱

这是 Oracle 最著名、最有争议的设计决策:
空字符串 '' 等于 NULL

证据:
```sql
SELECT CASE WHEN '' IS NULL THEN 'yes' ELSE 'no' END FROM DUAL;  -- 'yes'
SELECT NVL('', 'was null') FROM DUAL;           -- 'was null'
SELECT LENGTH('') FROM DUAL;                    -- NULL（不是 0）

-- 影响:
-- 1. NOT NULL 约束拒绝空字符串
--    INSERT INTO t (name) VALUES ('');  -- ORA-01400: cannot insert NULL
--
-- 2. WHERE col = '' 永远不返回行
--    因为 col = NULL 的结果是 UNKNOWN
--
-- 3. || 运算符对 NULL 友好: 'a' || NULL → 'a'
--    这是 Oracle 对 '' = NULL 的补偿设计
--    其他数据库: 'a' || NULL → NULL
--
-- 4. DISTINCT 中 '' 和 NULL 被视为同一个值
--
-- 5. 索引不包含全 NULL 的行，所以 WHERE name = '' 不走索引

-- 历史原因:
--   Oracle V2 (1979) 将 VARCHAR 实现为 CHAR 的变长版本。
--   CHAR 类型中空字符串被存储为 NULL（节省存储）。
--   为了兼容性，这个行为被保留了 45+ 年。
--   Oracle 官方文档: "Do not use '' to represent NULL; use NULL."
--   但同时承认: '' 和 NULL 在 Oracle 中是等价的。

-- 对引擎开发者的启示:
--   绝对不要模仿 '' = NULL 的设计。
--   SQL 标准明确规定: '' 是长度为 0 的字符串，不是 NULL。
--   这个设计导致了 Oracle 最多的迁移问题和用户困惑。
```

## 排序规则（Collation）

传统方式: 由 NLS_SORT 和 NLS_COMP 控制（会话级）
```sql
ALTER SESSION SET NLS_SORT = 'BINARY_CI';       -- 大小写不敏感
ALTER SESSION SET NLS_COMP = 'LINGUISTIC';
```

12c R2+: 列级排序规则
```sql
CREATE TABLE t (name VARCHAR2(100) COLLATE BINARY_CI);
```

横向对比:
  Oracle:     NLS 参数控制（会话级）或 COLLATE（12c R2+，列级）
  PostgreSQL: 建库时指定 + 列级 COLLATE
  MySQL:      4 级层次（Server > Database > Table > Column）
  SQL Server: 建库时指定 + 列级 COLLATE

## 对引擎开发者的总结

1. '' = NULL 是 Oracle 最大的设计遗憾，影响了约束、索引、比较、聚合的所有行为。
2. VARCHAR2(n) 默认字节语义在多字节编码下容易导致数据截断。
3. VARCHAR2 vs VARCHAR 的区分是 Oracle 独有的历史包袱。
4. CLOB 类型没有长度限制，但有使用限制（不能直接比较、不能在 GROUP BY 中使用）。
5. 新引擎应统一使用字符语义、严格区分 '' 和 NULL、使用 TEXT/VARCHAR 单一类型。
