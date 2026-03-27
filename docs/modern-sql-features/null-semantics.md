# NULL 语义全解

NULL 是 SQL 中最容易被误解的概念。它不是"空值"，不是"零"，不是"空字符串"，而是"未知"(UNKNOWN)。这个语义选择影响了 SQL 的每一个角落。

## 三值逻辑的数学基础

### 为什么是三值逻辑

传统布尔代数只有两个值: TRUE 和 FALSE。SQL 引入了第三个值: UNKNOWN（通常由 NULL 参与比较产生）。

```
双值逻辑: {TRUE, FALSE}
三值逻辑: {TRUE, FALSE, UNKNOWN}

NULL 的含义: "这个值存在，但我们不知道它是什么"
关键推论: 任何与"未知"的比较结果也是"未知"
```

### 三值逻辑真值表

```
AND 运算:
         TRUE    FALSE   UNKNOWN
TRUE     TRUE    FALSE   UNKNOWN
FALSE    FALSE   FALSE   FALSE
UNKNOWN  UNKNOWN FALSE   UNKNOWN

规则: FALSE 与任何值 AND 都是 FALSE (FALSE 有"吸收性")

OR 运算:
         TRUE    FALSE   UNKNOWN
TRUE     TRUE    TRUE    TRUE
FALSE    TRUE    FALSE   UNKNOWN
UNKNOWN  TRUE    UNKNOWN UNKNOWN

规则: TRUE 与任何值 OR 都是 TRUE (TRUE 有"吸收性")

NOT 运算:
NOT TRUE    = FALSE
NOT FALSE   = TRUE
NOT UNKNOWN = UNKNOWN
```

### WHERE 子句的过滤规则

```sql
-- WHERE 只保留求值为 TRUE 的行
-- FALSE 和 UNKNOWN 都被过滤掉

SELECT * FROM t WHERE condition;
-- condition = TRUE    -> 保留
-- condition = FALSE   -> 丢弃
-- condition = UNKNOWN -> 丢弃  (与 FALSE 同等对待!)

-- 这就是为什么:
SELECT * FROM t WHERE col = NULL;    -- 永远返回空集! (col = NULL -> UNKNOWN)
SELECT * FROM t WHERE col != NULL;   -- 永远返回空集! (col != NULL -> UNKNOWN)
SELECT * FROM t WHERE col IS NULL;   -- 正确写法
```

## NULL 在各操作中的行为

### 比较运算符

```sql
-- 所有比较运算符遇到 NULL 都返回 UNKNOWN
NULL = NULL     -- UNKNOWN (不是 TRUE!)
NULL <> NULL    -- UNKNOWN (不是 TRUE!)
NULL > 1        -- UNKNOWN
NULL < 1        -- UNKNOWN
NULL >= NULL    -- UNKNOWN
1 = NULL        -- UNKNOWN
```

### IN 与 NOT IN

```sql
-- IN: 展开为 OR 链
col IN (1, 2, NULL)
-- 等价于: col = 1 OR col = 2 OR col = NULL
-- 等价于: col = 1 OR col = 2 OR UNKNOWN
-- 如果 col = 1: TRUE OR FALSE OR UNKNOWN = TRUE  ✓
-- 如果 col = 3: FALSE OR FALSE OR UNKNOWN = UNKNOWN  (被过滤!)

-- NOT IN: 展开为 AND 链 -- 这是最危险的陷阱!
col NOT IN (1, 2, NULL)
-- 等价于: col <> 1 AND col <> 2 AND col <> NULL
-- 等价于: col <> 1 AND col <> 2 AND UNKNOWN
-- 无论 col 是什么值: ... AND UNKNOWN = UNKNOWN
-- 结果: 永远返回空集!!!

-- 经典 bug:
SELECT * FROM employees
WHERE dept_id NOT IN (SELECT dept_id FROM excluded_depts);
-- 如果 excluded_depts 中有任何一行 dept_id IS NULL，结果为空!

-- 安全写法:
SELECT * FROM employees e
WHERE NOT EXISTS (
    SELECT 1 FROM excluded_depts d WHERE d.dept_id = e.dept_id
);
```

### GROUP BY

```sql
-- GROUP BY 中: NULL 值被归为同一组
SELECT dept_id, COUNT(*)
FROM employees
GROUP BY dept_id;

-- 结果:
-- dept_id | count
-- 1       | 10
-- 2       | 8
-- NULL    | 3     <- 所有 dept_id IS NULL 的行归为一组

-- 这与 = 运算符的行为矛盾!
-- NULL = NULL 返回 UNKNOWN，但 GROUP BY 认为 NULL 等于 NULL
-- SQL 标准明确定义了这个"例外"
```

### ORDER BY

```sql
-- NULL 在排序中的位置因引擎而异

-- PostgreSQL: NULL 默认排在最后 (ASC), 最前 (DESC)
-- 可以用 NULLS FIRST / NULLS LAST 控制
SELECT * FROM t ORDER BY col ASC NULLS FIRST;
SELECT * FROM t ORDER BY col DESC NULLS LAST;

-- MySQL: NULL 被视为最小值
-- ASC: NULL 排最前
-- DESC: NULL 排最后

-- Oracle: NULL 默认排在最后 (ASC), 最前 (DESC)
-- 支持 NULLS FIRST / NULLS LAST

-- SQL Server: NULL 被视为最小值 (与 MySQL 相同)
-- 不支持 NULLS FIRST / NULLS LAST 语法

-- 各引擎默认行为对比
-- ASC 排序中 NULL 的位置:
-- 排最前 (最小): MySQL, SQL Server, SQLite
-- 排最后 (最大): PostgreSQL, Oracle, BigQuery
```

### DISTINCT 与 UNION

```sql
-- DISTINCT: 多个 NULL 被视为相同值 (只保留一个)
SELECT DISTINCT col FROM t;
-- 如果有 3 行 col IS NULL，结果中只有 1 个 NULL

-- UNION (去重): NULL 视为相同
SELECT col FROM a UNION SELECT col FROM b;
-- 两边的 NULL 会被去重

-- 这又是与 = 运算符矛盾的行为
-- DISTINCT 和 UNION 使用 IS NOT DISTINCT FROM 语义
-- 而非 = 语义
```

### 聚合函数

```sql
-- COUNT(*) vs COUNT(col): 核心区别
SELECT COUNT(*),       -- 5 (计算所有行)
       COUNT(col),     -- 3 (忽略 NULL 值)
       COUNT(DISTINCT col)  -- 2 (忽略 NULL，再去重)
FROM (VALUES (1), (2), (2), (NULL), (NULL)) AS t(col);

-- SUM: 忽略 NULL
SELECT SUM(col) FROM (VALUES (1), (2), (NULL)) AS t(col);
-- 结果: 3 (不是 NULL!)

-- 但如果所有值都是 NULL:
SELECT SUM(col) FROM (VALUES (NULL), (NULL)) AS t(col);
-- 结果: NULL (不是 0!)

-- AVG: 忽略 NULL
SELECT AVG(col) FROM (VALUES (10), (20), (NULL)) AS t(col);
-- 结果: 15 (不是 10! 因为 NULL 不参与分母计算)
-- (10 + 20) / 2 = 15, 而非 (10 + 20 + 0) / 3 = 10

-- MIN/MAX: 忽略 NULL
SELECT MIN(col), MAX(col) FROM (VALUES (NULL), (NULL)) AS t(col);
-- 结果: NULL, NULL
```

### CASE WHEN

```sql
-- 简单 CASE: 使用 = 比较，NULL 永远不匹配
CASE col
    WHEN 1 THEN 'one'
    WHEN NULL THEN 'null'  -- 永远不会匹配! (col = NULL -> UNKNOWN)
    ELSE 'other'
END

-- 正确处理 NULL 的写法:
CASE
    WHEN col = 1 THEN 'one'
    WHEN col IS NULL THEN 'null'  -- 使用 IS NULL
    ELSE 'other'
END

-- CASE WHEN 的短路求值:
CASE
    WHEN col IS NOT NULL AND col / 0 > 1 THEN 'x'  -- 安全吗?
    ELSE 'y'
END
-- SQL 标准不保证短路求值! 部分引擎会求值所有分支
-- PostgreSQL: 保证短路
-- MySQL: 保证短路
-- 其他引擎: 不确定，不要依赖此行为
```

## Oracle 的特殊行为: 空字符串等于 NULL

```sql
-- Oracle 中 '' (空字符串) 等于 NULL
-- 这是所有主流数据库中独一无二的行为!

-- Oracle:
SELECT CASE WHEN '' IS NULL THEN 'yes' ELSE 'no' END FROM dual;
-- 结果: 'yes'

SELECT LENGTH('') FROM dual;
-- 结果: NULL (不是 0!)

SELECT '' || 'hello' FROM dual;
-- 结果: 'hello' (NULL || 'hello' = 'hello'，而非标准的 NULL)
-- 注意: Oracle 对 || 的 NULL 处理也是非标准的

-- PostgreSQL (标准行为):
SELECT CASE WHEN '' IS NULL THEN 'yes' ELSE 'no' END;
-- 结果: 'no'

SELECT LENGTH('');
-- 结果: 0

SELECT '' || 'hello';
-- 结果: 'hello' (PostgreSQL 也对 || 做了特殊处理)

-- 迁移陷阱:
-- 从 Oracle 迁移到 PostgreSQL/MySQL 时，
-- 所有依赖 '' = NULL 的逻辑都会出 bug
-- 需要检查: IS NULL 条件、NVL 调用、字符串拼接
```

## NULL 安全比较

### IS DISTINCT FROM (SQL:1999)

```sql
-- 标准语法: 将 NULL 视为可比较的值
-- PostgreSQL, BigQuery, DuckDB, Trino, Spark SQL 支持

-- IS NOT DISTINCT FROM: NULL 等于 NULL
NULL IS NOT DISTINCT FROM NULL;  -- TRUE
1 IS NOT DISTINCT FROM 1;       -- TRUE
1 IS NOT DISTINCT FROM 2;       -- FALSE
1 IS NOT DISTINCT FROM NULL;    -- FALSE

-- IS DISTINCT FROM: NULL 不等于 NULL
NULL IS DISTINCT FROM NULL;     -- FALSE
1 IS DISTINCT FROM 2;           -- TRUE
1 IS DISTINCT FROM NULL;        -- TRUE
```

### MySQL <=> 运算符

```sql
-- MySQL / MariaDB 独有的 NULL-safe equal 运算符
NULL <=> NULL;  -- 1 (TRUE)
1 <=> 1;        -- 1 (TRUE)
1 <=> 2;        -- 0 (FALSE)
1 <=> NULL;     -- 0 (FALSE)

-- 等价于 IS NOT DISTINCT FROM
-- 但没有对应的 "不等于" 版本，需要: NOT (a <=> b)
```

## NULL 处理函数对比

### COALESCE (SQL 标准)

```sql
-- 返回第一个非 NULL 参数 (SQL:1999 标准)
COALESCE(a, b, c)
-- 等价于:
CASE WHEN a IS NOT NULL THEN a
     WHEN b IS NOT NULL THEN b
     ELSE c END

-- 所有主流引擎都支持
-- 可以接受任意数量的参数
SELECT COALESCE(phone, mobile, email, 'no contact') FROM users;
```

### 各引擎的专有函数

```sql
-- NVL (Oracle, 2参数版的 COALESCE)
SELECT NVL(col, 'default') FROM t;           -- Oracle
SELECT NVL(col, 'default') FROM t;           -- Snowflake (兼容)
-- NVL 总是求值两个参数; COALESCE 可能短路

-- IFNULL (MySQL / SQLite, 2参数)
SELECT IFNULL(col, 'default') FROM t;        -- MySQL
SELECT IFNULL(col, 'default') FROM t;        -- SQLite

-- ISNULL (SQL Server, 2参数)
SELECT ISNULL(col, 'default') FROM t;        -- SQL Server
-- 注意: ISNULL 返回第一个参数的类型!
-- ISNULL(NULL, 1)   -> INT (因为 1 是 INT)
-- COALESCE(NULL, 1) -> INT (因为 1 是 INT)
-- 但当类型不同时行为差异很大

-- NVL2 (Oracle, 三元运算)
SELECT NVL2(col, 'has value', 'no value') FROM t;
-- col IS NOT NULL -> 'has value'
-- col IS NULL     -> 'no value'

-- NULLIF (标准, 条件返回 NULL)
SELECT NULLIF(col, 0) FROM t;
-- 等价于: CASE WHEN col = 0 THEN NULL ELSE col END
-- 常用于防止除以零: x / NULLIF(y, 0)
```

### 函数兼容性矩阵

| 函数 | PostgreSQL | MySQL | Oracle | SQL Server | BigQuery | Snowflake |
|------|-----------|-------|--------|-----------|---------|-----------|
| `COALESCE` | Y | Y | Y | Y | Y | Y |
| `NVL` | N | N | Y | N | N | Y |
| `IFNULL` | N | Y | N | N | Y | Y |
| `ISNULL` | N | N | N | Y | N | N |
| `NVL2` | N | N | Y | N | N | Y |
| `NULLIF` | Y | Y | Y | Y | Y | Y |

## NULL 在索引中的行为

### B-tree 索引中的 NULL

```sql
-- PostgreSQL: 索引包含 NULL 值
-- IS NULL 可以使用索引
CREATE INDEX idx_col ON t(col);
SELECT * FROM t WHERE col IS NULL;  -- 使用 idx_col

-- 部分索引 (Partial Index): 排除 NULL 以减小索引大小
CREATE INDEX idx_active ON t(col) WHERE col IS NOT NULL;
-- 索引更小、更快，但 WHERE col IS NULL 不能用这个索引

-- MySQL InnoDB: 索引包含 NULL 值
-- IS NULL 可以使用索引 (MySQL 5.7+)
SELECT * FROM t WHERE col IS NULL;  -- 可以使用索引

-- Oracle: 单列索引不包含全 NULL 的行!
CREATE INDEX idx_col ON t(col);
SELECT * FROM t WHERE col IS NULL;  -- 不使用索引! 需要全表扫描

-- Oracle 变通方案: 组合索引包含非 NULL 常量
CREATE INDEX idx_col ON t(col, 0);  -- 加一个常量列
SELECT * FROM t WHERE col IS NULL;  -- 现在可以使用索引

-- SQL Server: 索引包含 NULL 值
-- 过滤索引 (Filtered Index): 类似 PostgreSQL 的部分索引
CREATE INDEX idx_active ON t(col) WHERE col IS NOT NULL;
```

### UNIQUE 约束中的 NULL

```sql
-- NULL 在 UNIQUE 约束中的行为差异巨大

-- PostgreSQL: 多个 NULL 可以共存 (SQL 标准行为)
CREATE TABLE t (col INT UNIQUE);
INSERT INTO t VALUES (NULL);  -- 成功
INSERT INTO t VALUES (NULL);  -- 成功! 多个 NULL 不违反 UNIQUE

-- MySQL: 同 PostgreSQL，多个 NULL 可以共存
-- SQL Server: 同 PostgreSQL (但可以用 filtered index 改变行为)

-- Oracle: 单列 UNIQUE 允许多个 NULL
--         但组合 UNIQUE 中如果所有列都是 NULL，则被忽略

-- SQLite: 多个 NULL 可以共存

-- 如果想要"NULL 也唯一":
-- PostgreSQL: CREATE UNIQUE INDEX ON t(col) WHERE col IS NOT NULL;
--             + 另一个约束确保最多一个 NULL
-- SQL Server: CREATE UNIQUE INDEX ON t(col) WHERE col IS NOT NULL;
```

## 对引擎开发者: NULL 是 bug 最密集的区域

### 常见实现错误

```
1. Hash Join 的 NULL 处理:
   - 错误: NULL 值被 hash 到某个桶，与其他 NULL 匹配
   - 正确: NULL 值不参与 JOIN (除非使用 IS NOT DISTINCT FROM)

2. 聚合函数的空输入:
   - 错误: SUM 在无输入时返回 0
   - 正确: SUM 在无输入时返回 NULL (COUNT 返回 0)

3. IN 子查询的 NULL:
   - 错误: NOT IN (子查询含 NULL) 返回预期结果
   - 正确: 返回空集

4. UNION 去重:
   - 错误: 两个 NULL 不去重 (使用 = 比较)
   - 正确: 两个 NULL 去重 (使用 IS NOT DISTINCT FROM)

5. ORDER BY 的稳定性:
   - 需要明确决定 NULL 排在最前还是最后
   - 且需要支持 NULLS FIRST / NULLS LAST 语法

6. CASE WHEN 的 NULL 比较:
   - 简单 CASE (CASE x WHEN NULL) 不能匹配 NULL
   - 需要在文档中明确说明
```

### NULL 处理的测试清单

```
基础操作:
  [ ] NULL = NULL -> UNKNOWN
  [ ] NULL <> NULL -> UNKNOWN
  [ ] NULL AND TRUE -> UNKNOWN
  [ ] NULL AND FALSE -> FALSE
  [ ] NULL OR TRUE -> TRUE
  [ ] NULL OR FALSE -> UNKNOWN
  [ ] NOT NULL -> UNKNOWN

聚合:
  [ ] COUNT(*) 计入 NULL 行
  [ ] COUNT(col) 不计入 NULL
  [ ] SUM/AVG/MIN/MAX 忽略 NULL
  [ ] SUM 空输入返回 NULL
  [ ] COUNT 空输入返回 0

分组与去重:
  [ ] GROUP BY 中 NULL 归为一组
  [ ] DISTINCT 中 NULL 去重
  [ ] UNION 中 NULL 去重
  [ ] UNION ALL 中 NULL 不去重

排序:
  [ ] ORDER BY ASC 中 NULL 的位置
  [ ] ORDER BY DESC 中 NULL 的位置
  [ ] NULLS FIRST / NULLS LAST 支持

子查询:
  [ ] IN (列表含 NULL) 的行为
  [ ] NOT IN (列表含 NULL) 返回空集
  [ ] EXISTS 对 NULL 的处理

JOIN:
  [ ] NULL 键不匹配 (等值 JOIN)
  [ ] LEFT JOIN 产生的 NULL
  [ ] Hash Join 桶中的 NULL 处理

窗口函数:
  [ ] PARTITION BY NULL 的分组
  [ ] ORDER BY NULL 的排序
  [ ] LAG/LEAD 默认值为 NULL
```

### 推荐的内部实现方案

```
1. 值的内部表示:
   方案 A: 额外的 NULL bitmap (PostgreSQL 方式)
     - 每行一个 bitmap，每列一个 bit
     - 空间高效，cache 友好
     - 推荐

   方案 B: 特殊值标记 (某些引擎)
     - 用 NaN、MIN_VALUE 等表示 NULL
     - 省去 bitmap 开销
     - 但占用了一个合法值

   方案 C: Optional 包装 (Rust/Java 风格)
     - 每个值用 Option<T> / Optional<T>
     - 类型安全，但内存开销大

2. 比较函数:
   - 每个类型都需要两套比较器:
     a) SQL 语义: NULL 参与 -> 返回 UNKNOWN
     b) 排序语义: NULL 有确定位置 (NULLS FIRST/LAST)
   - DISTINCT/GROUP BY 使用排序语义的比较器

3. 表达式求值:
   - 所有运算符需要先检查操作数是否为 NULL
   - 三值逻辑的 AND/OR 需要实现短路求值
   - COALESCE 需要实现惰性求值 (不求值后续参数)
```

## 参考资料

- SQL 标准: ISO/IEC 9075-2 Section 8.7 "null predicate"
- C.J. Date: "SQL and Relational Theory" Chapter 4: NULL
- PostgreSQL: [NULL Handling](https://www.postgresql.org/docs/current/functions-comparison.html)
- MySQL: [Working with NULL Values](https://dev.mysql.com/doc/refman/8.0/en/working-with-null.html)
- Oracle: [Nulls](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/Nulls.html)
- E.F. Codd: "Missing Information" in RM/V2 (1990)
