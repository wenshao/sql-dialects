# DML 结果获取的演进

INSERT/UPDATE/DELETE 执行后返回受影响的行——从 PostgreSQL 的 RETURNING 到 SQL Server 的 OUTPUT，各引擎的实现差异。

## 支持矩阵

| 引擎 | INSERT RETURNING | UPDATE RETURNING | DELETE RETURNING | MERGE RETURNING | 版本 |
|------|-----------------|-----------------|-----------------|----------------|------|
| PostgreSQL | 支持 | 支持 | 支持 | 不支持 | 8.2+ (2006) |
| Oracle | PL/SQL 中支持 | PL/SQL 中支持 | PL/SQL 中支持 | 不支持 | 10g+ |
| SQL Server | OUTPUT | OUTPUT | OUTPUT | OUTPUT | 2005+ |
| SQLite | 支持 | 支持 | 支持 | 不支持 | 3.35.0+ (2021) |
| MariaDB | 支持 | 不支持 | 支持 | 不支持 | 10.5+ (2020) |
| Firebird | 支持 | 支持 | 支持 | 不支持 | 2.0+ |
| CockroachDB | 支持 | 支持 | 支持 | 不支持 | 1.0+ |
| DuckDB | 支持 | 支持 | 支持 | 不支持 | 0.3.0+ |
| MySQL | 不支持 | 不支持 | 不支持 | - | 只有 LAST_INSERT_ID() |
| BigQuery | 不支持 | 不支持 | 不支持 | - | - |
| ClickHouse | 不支持 | - | - | - | - |
| Snowflake | 不支持 | 不支持 | 不支持 | - | - |
| Hive | 不支持 | - | - | - | - |

## 设计动机

### 问题: DML 之后需要知道"发生了什么"

最常见的需求场景：

```sql
-- 场景 1: INSERT 后需要知道自动生成的 ID
INSERT INTO users (name, email) VALUES ('Alice', 'alice@example.com');
-- 刚插入的行的 id 是多少？

-- 场景 2: UPDATE 后需要确认哪些行被修改了
UPDATE products SET price = price * 0.9 WHERE category = 'electronics';
-- 哪些产品被降价了？降价前的价格是什么？

-- 场景 3: DELETE 后需要记录被删除的数据（审计日志）
DELETE FROM orders WHERE status = 'cancelled' AND created_at < '2024-01-01';
-- 删了哪些订单？需要归档

-- 场景 4: UPSERT 后需要知道是插入还是更新
INSERT INTO config (key, value) VALUES ('timeout', '30')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
-- 是新插入的还是更新的？最终值是什么？
```

### 传统解决方案的缺陷

```sql
-- 方案 1: 先查后改（竞态条件!）
SELECT id FROM users WHERE email = 'alice@example.com';  -- 可能没有结果
INSERT INTO users (name, email) VALUES ('Alice', 'alice@example.com');
SELECT id FROM users WHERE email = 'alice@example.com';  -- 两次查询之间可能有并发

-- 方案 2: 用专有函数（只能获取 ID）
INSERT INTO users (name, email) VALUES ('Alice', 'alice@example.com');
SELECT LAST_INSERT_ID();   -- MySQL
SELECT SCOPE_IDENTITY();   -- SQL Server (旧方式)
SELECT currval('users_id_seq');  -- PostgreSQL (旧方式)
-- 只能获取 ID，不能获取整行或表达式

-- 方案 3: 用事务隔离（性能差）
BEGIN;
UPDATE products SET price = price * 0.9 WHERE category = 'electronics';
SELECT * FROM products WHERE category = 'electronics';  -- 额外一次全表扫描
COMMIT;
```

### RETURNING 的解决方案

```sql
-- 一条语句完成: DML + 结果返回
INSERT INTO users (name, email) VALUES ('Alice', 'alice@example.com')
RETURNING id, name, email, created_at;
-- 返回刚插入的完整行，包括所有默认值和自动生成值

UPDATE products SET price = price * 0.9 WHERE category = 'electronics'
RETURNING id, name, price AS new_price;
-- 返回所有被更新的行的新值

DELETE FROM orders WHERE status = 'cancelled'
RETURNING *;
-- 返回所有被删除的行（用于归档）
```

## 各引擎语法详解

### PostgreSQL RETURNING（最全面）

```sql
-- INSERT ... RETURNING（包括默认值、序列值）
INSERT INTO users (name, email) VALUES ('Alice', 'alice@example.com')
RETURNING id, name, email, created_at;

-- UPDATE ... RETURNING
UPDATE products SET price = price * 1.1 WHERE category = 'food'
RETURNING id, name, price AS new_price;

-- DELETE ... RETURNING
DELETE FROM expired_sessions WHERE expires_at < NOW()
RETURNING session_id, user_id;

-- 表达式和 CTE 结合: DML 结果作为后续查询的输入
WITH deleted AS (
    DELETE FROM orders WHERE status = 'cancelled' RETURNING *
)
INSERT INTO order_archive SELECT *, NOW() AS archived_at FROM deleted;

-- UPSERT + RETURNING
INSERT INTO config (key, value) VALUES ('timeout', '30')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value
RETURNING key, value, xmax = 0 AS is_insert;
-- xmax = 0 时为 INSERT，否则为 UPDATE (PostgreSQL 特有技巧)
```

### SQL Server OUTPUT

SQL Server 的 OUTPUT 子句是最一致的设计——所有 DML 语句使用相同的语法，且可以同时访问修改前后的值。

```sql
-- INSERT ... OUTPUT
INSERT INTO users (name, email)
OUTPUT inserted.id, inserted.name, inserted.created_at
VALUES ('Alice', 'alice@example.com');
-- inserted.* 引用新插入的行

-- UPDATE ... OUTPUT (可以同时获取旧值和新值!)
UPDATE products
SET price = price * 1.1
OUTPUT deleted.price AS old_price,    -- deleted.* = 修改前的值
       inserted.price AS new_price,   -- inserted.* = 修改后的值
       inserted.id, inserted.name
WHERE category = 'food';
-- 这是 SQL Server OUTPUT 最强大的特性: 新旧值对比

-- DELETE ... OUTPUT
DELETE FROM expired_sessions
OUTPUT deleted.session_id, deleted.user_id, deleted.expires_at
WHERE expires_at < GETDATE();

-- MERGE ... OUTPUT (最完整的 DML 结果获取)
MERGE INTO target t
USING source s ON t.id = s.id
WHEN MATCHED THEN
    UPDATE SET t.name = s.name, t.value = s.value
WHEN NOT MATCHED THEN
    INSERT (id, name, value) VALUES (s.id, s.name, s.value)
WHEN NOT MATCHED BY SOURCE THEN
    DELETE
OUTPUT $action,              -- 'INSERT', 'UPDATE', 或 'DELETE'
       inserted.id, inserted.name,   -- 新值 (DELETE 时为 NULL)
       deleted.id, deleted.name;     -- 旧值 (INSERT 时为 NULL)

-- OUTPUT INTO: 将结果写入表（而非返回给客户端）
DECLARE @affected TABLE (id INT, old_price DECIMAL(10,2), new_price DECIMAL(10,2));
UPDATE products
SET price = price * 1.1
OUTPUT inserted.id, deleted.price, inserted.price
INTO @affected
WHERE category = 'food';

-- 然后可以查询结果
SELECT * FROM @affected WHERE new_price > 100;
```

### Oracle RETURNING（仅 PL/SQL）

```sql
-- Oracle 的 RETURNING 只能在 PL/SQL 中使用，纯 SQL 不支持
DECLARE v_id NUMBER;
BEGIN
    INSERT INTO users (name, email) VALUES ('Alice', 'alice@example.com')
    RETURNING id INTO v_id;
END;
-- 批量操作: RETURNING id BULK COLLECT INTO v_ids
```

### SQLite RETURNING (3.35.0+) / MariaDB (10.5+)

```sql
-- SQLite: INSERT/UPDATE/DELETE 都支持 RETURNING
INSERT INTO users (name, email) VALUES ('Alice', 'alice@example.com')
RETURNING id, name, email;

-- MariaDB: INSERT 和 DELETE 支持 RETURNING，UPDATE 不支持
DELETE FROM old_logs WHERE ts < '2024-01-01' RETURNING *;
```

### MySQL（不支持 RETURNING）

```sql
-- 只能用 LAST_INSERT_ID() 获取自增 ID（无法获取其他列）
INSERT INTO users (name, email) VALUES ('Alice', 'alice@example.com');
SELECT LAST_INSERT_ID();

-- 批量插入时只返回第一个 ID; UPDATE 只能获取 ROW_COUNT()
```

## 设计分析

### RETURNING vs OUTPUT 的设计差异

| 特性 | RETURNING (PostgreSQL 等) | OUTPUT (SQL Server) |
|------|--------------------------|---------------------|
| 位置 | DML 语句末尾 | DML 语句中间（INSERT/UPDATE 后） |
| 新值 | 直接引用列名 | `inserted.*` 前缀 |
| 旧值 | 不支持 | `deleted.*` 前缀 |
| 新旧对比 | 不支持 | 支持（UPDATE 中同时用 inserted/deleted） |
| 操作类型 | 不标识 | MERGE 中有 `$action` |
| 输出到表 | 用 CTE 实现 | `OUTPUT INTO @table` |

SQL Server 的 `inserted/deleted` 伪表设计与触发器中的概念一致，学习成本低。且能同时获取新旧值是巨大优势。

PostgreSQL 的 RETURNING 位于语句末尾，语法更简洁，但缺少旧值访问能力（UPDATE 中无法获取修改前的值）。

### MERGE + RETURNING 为什么少见

MERGE 的 RETURNING 有特殊的复杂性：

1. MERGE 可以同时执行 INSERT、UPDATE、DELETE
2. RETURNING 需要标识每行是哪种操作
3. INSERT 产生 `inserted`、DELETE 产生 `deleted`、UPDATE 两者都产生

SQL Server 的 `OUTPUT $action` 解决了这个问题，但其他引擎大多没有实现。

## 对引擎开发者的实现建议

### 1. 语法解析

```
-- PostgreSQL 风格
dml_statement:
    insert_statement [RETURNING expr_list]
  | update_statement [RETURNING expr_list]
  | delete_statement [RETURNING expr_list]

-- SQL Server 风格
insert_statement:
    INSERT INTO table (columns) OUTPUT expr_list VALUES ...
update_statement:
    UPDATE table SET ... OUTPUT expr_list WHERE ...
delete_statement:
    DELETE FROM table OUTPUT expr_list WHERE ...
```

### 2. 在 DML 执行器中返回行的投影

核心实现思路：在 DML 执行器中增加一个投影步骤。

```
DML 执行流程（无 RETURNING）:
    for each row:
        apply DML operation (insert/update/delete)
        count++
    return count

DML 执行流程（有 RETURNING）:
    result_set = []
    for each row:
        old_row = current_row  (UPDATE/DELETE 时)
        apply DML operation
        new_row = result_row   (INSERT/UPDATE 时)
        projected = project(new_row, returning_expressions)
        result_set.append(projected)
    return result_set
```

### 3. 旧值访问与触发器交互

支持 SQL Server 风格新旧值同时访问: 更新前复制行数据（`deleted.*`），更新后取新行（`inserted.*`），或利用 MVCC 旧版本。

触发器交互需要注意: PostgreSQL 的 RETURNING 返回 BEFORE 触发器修改后的值（AFTER 触发器尚未执行）; SQL Server 的 OUTPUT 返回触发器执行前的值。时机差异需明确文档化。

### 4. RETURNING 结果作为表表达式

PostgreSQL 允许 DML RETURNING 在 CTE 中使用（`WITH ins AS (INSERT ... RETURNING *) SELECT * FROM ins`），执行计划中 CTE 子计划是 DML 节点而非 SELECT 节点。

## 参考资料

- PostgreSQL: [RETURNING](https://www.postgresql.org/docs/current/dml-returning.html)
- SQL Server: [OUTPUT Clause](https://learn.microsoft.com/en-us/sql/t-sql/queries/output-clause-transact-sql)
- SQLite: [RETURNING](https://www.sqlite.org/lang_returning.html)
- MariaDB: [RETURNING](https://mariadb.com/kb/en/insertreturning/)
- Oracle: [RETURNING INTO](https://docs.oracle.com/en/database/oracle/oracle-database/19/lnpls/RETURNING-INTO-clause.html)
