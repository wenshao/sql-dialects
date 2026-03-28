# SQL-92 标准 (SQL2)

SQL-92（ISO 9075:1992）是 SQL 发展史上最重要的一个版本。它大幅扩展了语言能力，引入了三个合规级别，并且是大多数引擎声称"兼容 SQL 标准"时实际指的版本。直到今天，许多 SQL 引擎的核心功能集仍以 SQL-92 Entry Level 为基准。

## 三个合规级别

SQL-92 将特性分为三个层级：

| 级别 | 内容 | 引擎达标情况 |
|------|------|------------|
| Entry | 大约等于 SQL-89 + 若干增强 | 大多数引擎均达标 |
| Intermediate | 新增 JOIN 语法、动态 SQL、CAST 等 | 多数商业引擎达标 |
| Full | 所有特性，包括 ASSERTION、DOMAIN 等 | 没有引擎完全达标 |

> NIST 曾运行 SQL 合规性测试套件（FIPS 127-2），但该项目已于 1996 年终止。此后再无官方认证机构。

## 新增数据类型

### VARCHAR

```sql
-- SQL-92 标准语法
CREATE TABLE t (
    name VARCHAR(100),              -- 变长字符串
    code CHAR(10),                  -- 定长字符串（SQL-86 已有）
    amount NUMERIC(12,2),           -- 精确数值（SQL-86 已有，SQL-92 增强）
    rate DECIMAL(5,4)               -- 等同 NUMERIC
);
```

### 日期时间类型

SQL-92 引入了完整的日期时间体系，这是对 SQL-86 的重大补充：

```sql
CREATE TABLE events (
    event_date  DATE,                           -- 年-月-日
    event_time  TIME,                           -- 时:分:秒
    created_at  TIMESTAMP,                      -- 日期+时间
    duration    INTERVAL YEAR TO MONTH,         -- 时间间隔
    precise_ts  TIMESTAMP WITH TIME ZONE        -- 带时区的时间戳
);
```

**日期时间类型支持矩阵：**

| 类型 | MySQL | PostgreSQL | Oracle | SQL Server | SQLite | BigQuery | Snowflake |
|------|-------|-----------|--------|-----------|--------|----------|-----------|
| DATE | ✓ | ✓ | ✓ | ✓ (date) | 文本 | ✓ | ✓ |
| TIME | ✓ | ✓ | ✗ | ✓ (time) | 文本 | ✓ | ✓ |
| TIMESTAMP | ✓ | ✓ | ✓ | datetime2 | 文本 | ✓ | ✓ |
| TIMESTAMP WITH TIME ZONE | ✗ | ✓ | ✓ | datetimeoffset | ✗ | ✓ | ✓ (LTZ) |
| INTERVAL | ✗ | ✓ | ✓ | ✗ | ✗ | ✓ | ✗ |

关键差异：
- **MySQL**：没有 INTERVAL 类型，但 `INTERVAL 1 DAY` 可用于日期运算表达式
- **Oracle**：没有 TIME 类型，使用 `DATE`（含时间分量）或 `TIMESTAMP`
- **SQL Server**：使用 `datetime2` 代替 `TIMESTAMP`（SQL Server 的 `TIMESTAMP` 是行版本号，与标准含义完全不同）
- **SQLite**：没有原生日期时间类型，存储为 TEXT/REAL/INTEGER，通过内置函数处理

## CASE 表达式

SQL-92 引入了两种形式的 CASE 表达式：

```sql
-- 简单 CASE
SELECT name,
    CASE status
        WHEN 'A' THEN '活跃'
        WHEN 'I' THEN '非活跃'
        ELSE '未知'
    END AS status_text
FROM users;

-- 搜索 CASE
SELECT name,
    CASE
        WHEN age < 18 THEN '未成年'
        WHEN age < 65 THEN '成年'
        ELSE '老年'
    END AS age_group
FROM users;
```

**所有主流引擎均完整支持 CASE 表达式。** 但有些引擎提供了非标准的简写：
- MySQL/Oracle：`IF(condition, then, else)`、`DECODE(expr, val1, result1, ...)`
- SQL Server：`IIF(condition, then, else)`
- PostgreSQL：无非标准简写（鼓励使用标准 CASE）

## CAST 类型转换

```sql
-- SQL-92 标准
SELECT CAST('123' AS INTEGER);
SELECT CAST(price AS VARCHAR(20));
SELECT CAST('2024-01-15' AS DATE);
```

| 引擎 | 标准 CAST | 非标准替代 |
|------|----------|----------|
| MySQL | ✓ | `CONVERT(expr, type)`、隐式转换非常宽松 |
| PostgreSQL | ✓ | `expr::type`（双冒号语法） |
| Oracle | ✓ | `TO_NUMBER()`、`TO_CHAR()`、`TO_DATE()` |
| SQL Server | ✓ | `CONVERT(type, expr, style)` |
| SQLite | ✓ | 隐式转换（动态类型系统） |
| BigQuery | ✓ | `SAFE_CAST(expr AS type)` 返回 NULL 而非报错 |

## JOIN 语法

SQL-92 之前，连接只能通过 WHERE 子句中的条件实现（隐式连接）。SQL-92 引入了显式 JOIN 语法：

```sql
-- SQL-86 风格（隐式连接）—— 至今仍然合法
SELECT e.name, d.dept_name
FROM employees e, departments d
WHERE e.dept_id = d.dept_id;

-- SQL-92 显式 JOIN 语法
SELECT e.name, d.dept_name
FROM employees e
INNER JOIN departments d ON e.dept_id = d.dept_id;

-- LEFT OUTER JOIN
SELECT e.name, d.dept_name
FROM employees e
LEFT JOIN departments d ON e.dept_id = d.dept_id;

-- RIGHT OUTER JOIN
SELECT e.name, d.dept_name
FROM employees e
RIGHT JOIN departments d ON e.dept_id = d.dept_id;

-- FULL OUTER JOIN
SELECT e.name, COALESCE(d.dept_name, '无部门')
FROM employees e
FULL JOIN departments d ON e.dept_id = d.dept_id;

-- CROSS JOIN
SELECT e.name, p.project_name
FROM employees e
CROSS JOIN projects p;

-- NATURAL JOIN（基于同名列自动匹配）
SELECT e.name, d.dept_name
FROM employees e
NATURAL JOIN departments d;
```

**JOIN 支持矩阵：**

| JOIN 类型 | MySQL | PostgreSQL | Oracle | SQL Server | SQLite | BigQuery | Snowflake | ClickHouse |
|----------|-------|-----------|--------|-----------|--------|----------|-----------|------------|
| INNER JOIN | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| LEFT JOIN | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| RIGHT JOIN | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| FULL OUTER JOIN | ✗ | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ | ✓ |
| CROSS JOIN | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| NATURAL JOIN | ✓ | ✓ | ✓ | ✗ | ✓ | ✗ | ✓ | ✓ |

> **MySQL** 不支持 FULL OUTER JOIN，需要用 LEFT JOIN UNION RIGHT JOIN 模拟。
> **Oracle** 传统使用 `(+)` 语法表示外连接（`WHERE e.dept_id = d.dept_id(+)`），但已推荐使用标准语法。
> **SQL Server** 传统使用 `*=` 和 `=*` 表示外连接，已在 2005 版废弃。

## 子查询

SQL-92 标准化了多种子查询形式：

```sql
-- IN 子查询
SELECT * FROM orders WHERE customer_id IN (SELECT id FROM vip_customers);

-- EXISTS 子查询
SELECT * FROM customers c
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.customer_id = c.id);

-- ALL / ANY / SOME
SELECT * FROM products WHERE price > ALL (SELECT price FROM cheap_products);
SELECT * FROM products WHERE price > ANY (SELECT price FROM products WHERE category = 'A');

-- 标量子查询（返回单值，可用于 SELECT 列表）
SELECT name,
    (SELECT COUNT(*) FROM orders o WHERE o.customer_id = c.id) AS order_count
FROM customers c;
```

所有主流引擎均支持以上子查询形式。性能差异较大：MySQL 在 5.6 之前对 IN 子查询的优化很差（物化策略不佳），5.6+ 有显著改进。

## TEMPORARY TABLE

```sql
-- SQL-92 标准
CREATE LOCAL TEMPORARY TABLE temp_results (
    id    INTEGER,
    value DECIMAL(10,2)
);
-- 会话结束时自动删除
```

| 引擎 | 语法 | 作用域 |
|------|------|-------|
| MySQL | `CREATE TEMPORARY TABLE t (...)` | 会话级 |
| PostgreSQL | `CREATE TEMPORARY TABLE t (...)` | 会话级（可选 ON COMMIT DROP） |
| Oracle | `CREATE GLOBAL TEMPORARY TABLE t (...) ON COMMIT PRESERVE/DELETE ROWS` | 全局定义，数据会话级 |
| SQL Server | `CREATE TABLE #t (...)`（本地）/ `CREATE TABLE ##t (...)`（全局） | 会话/全局 |
| SQLite | `CREATE TEMPORARY TABLE t (...)` | 连接级 |

## CASCADE / RESTRICT 引用动作

```sql
-- SQL-92 标准
CREATE TABLE orders (
    order_id   INTEGER PRIMARY KEY,
    customer_id INTEGER REFERENCES customers(id)
        ON DELETE CASCADE           -- 删除客户时级联删除订单
        ON UPDATE RESTRICT          -- 禁止更新被引用的客户 id
);

-- 可选动作: CASCADE, RESTRICT, SET NULL, SET DEFAULT, NO ACTION
```

| 动作 | MySQL | PostgreSQL | Oracle | SQL Server | SQLite |
|------|-------|-----------|--------|-----------|--------|
| CASCADE | ✓ | ✓ | ✓ (DELETE) | ✓ | ✓ |
| RESTRICT | ✓ | ✓ | ✗ | ✗ | ✓ |
| SET NULL | ✓ | ✓ | ✓ | ✓ | ✓ |
| SET DEFAULT | ✓ | ✓ | ✗ | ✓ | ✓ |
| NO ACTION | ✓ | ✓ (默认) | ✓ (默认) | ✓ (默认) | ✓ |

> `NO ACTION` 和 `RESTRICT` 的区别：`RESTRICT` 立即检查约束，`NO ACTION` 在语句结束时检查（允许中间状态违反约束）。PostgreSQL 严格区分两者。

## 其他 SQL-92 新增特性

- **COALESCE(a, b, c)**：返回第一个非 NULL 值，等价于嵌套 CASE
- **NULLIF(a, b)**：当 a=b 时返回 NULL，否则返回 a
- **字符串连接 `||`**：标准运算符，但 MySQL 默认将其视为逻辑 OR（需设置 `PIPES_AS_CONCAT`）
- **TRIM / UPPER / LOWER / SUBSTRING**：标准字符串函数
- **集合操作 UNION / INTERSECT / EXCEPT**：MySQL 直到 8.0 才支持 INTERSECT 和 EXCEPT
- **INFORMATION_SCHEMA**：标准化的元数据视图，多数引擎支持

## 对引擎开发者的实现建议

1. **优先达到 Entry Level 合规**。这是用户和 ORM 框架的基本期望，覆盖了绝大多数日常 SQL。
2. **显式 JOIN 语法是必须实现的**。包括 INNER、LEFT、RIGHT、CROSS。FULL OUTER JOIN 可以稍后实现（MySQL 至今未支持）。NATURAL JOIN 优先级低（容易出问题且不推荐使用）。
3. **CASE 和 CAST 是高优先级**。它们被广泛用于应用程序和 BI 工具生成的 SQL 中。
4. **日期时间类型要认真设计**。DATE、TIME、TIMESTAMP 的精度、时区处理、隐式转换规则会影响大量用户。建议参考 PostgreSQL 的实现。
5. **INFORMATION_SCHEMA 对生态兼容性很重要**。MySQL 兼容引擎必须实现它，因为 ORM、数据库管理工具、迁移框架都依赖它。
6. **子查询优化很重要**。实现正确性不难，但性能优化（子查询去关联、物化策略）是查询优化器的重要课题。

## 延伸阅读

- SQL:1999 在此基础上引入了递归查询、用户自定义类型等高级特性 → [sql-1999.md](sql-1999.md)
- JOIN 语法详情 → [../../query/joins/](../../query/joins/)
- 日期时间类型详情 → [../../types/datetime/](../../types/datetime/)
