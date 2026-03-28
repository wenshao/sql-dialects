# RETURNING / OUTPUT 子句

DML 语句直接返回受影响行——避免额外 SELECT 的关键特性。

## 支持矩阵

| 引擎 | 语法 | INSERT | UPDATE | DELETE | 版本 |
|------|------|--------|--------|--------|------|
| PostgreSQL | `RETURNING` | 支持 | 支持 | 支持 | 8.2+ (2006) |
| SQL Server | `OUTPUT` | 支持 | 支持 | 支持 | 2005+ |
| SQLite | `RETURNING` | 支持 | 支持 | 支持 | 3.35.0+ (2021) |
| MariaDB | `RETURNING` | 不支持 | 不支持 | 仅 DELETE | 10.5+ |
| Oracle | `RETURNING INTO` | 支持 | 支持 | 支持 | 早期(仅 PL/SQL) |
| Firebird | `RETURNING` | 支持 | 支持 | 支持 | 2.1+ |
| CockroachDB | `RETURNING` | 支持 | 支持 | 支持 | GA |
| YugabyteDB | `RETURNING` | 支持 | 支持 | 支持 | GA |
| DuckDB | `RETURNING` | 支持 | 支持 | 支持 | 0.6.0+ |
| MySQL | **不支持** | - | - | - | - |
| BigQuery | **不支持** | - | - | - | DML 返回行数但不返回内容 |
| Snowflake | **不支持** | - | - | - | - |
| ClickHouse | **不支持** | - | - | - | - |

## 设计动机

1. 获取自增 ID

最常见场景——插入一行后需要知道生成的主键：

```sql
-- 没有 RETURNING 时: 两步操作
INSERT INTO users (name, email) VALUES ('Alice', 'alice@example.com');
-- 然后需要额外查询:
SELECT id FROM users WHERE email = 'alice@example.com';  -- 竞态条件!
-- 或者:
SELECT LAST_INSERT_ID();  -- MySQL
SELECT lastval();          -- PostgreSQL（不推荐）
SELECT SCOPE_IDENTITY();   -- SQL Server（旧方式）

-- 有 RETURNING 时: 一步完成
INSERT INTO users (name, email)
VALUES ('Alice', 'alice@example.com')
RETURNING id;
-- 直接返回: | id |
--           | 42 |
```

2. 获取默认值和计算列

```sql
-- 插入时让数据库填充默认值和触发器计算的列
INSERT INTO orders (customer_id, product_id, quantity)
VALUES (100, 200, 5)
RETURNING id, order_date, total_price, status;
-- order_date (DEFAULT NOW), total_price (触发器计算), status (DEFAULT 'pending')
-- 一次 INSERT 就拿到所有计算结果
```

3. 条件删除并获取被删数据

```sql
-- 清理过期数据，同时获取被删除的记录用于归档
DELETE FROM sessions
WHERE expire_time < NOW()
RETURNING session_id, user_id, expire_time;
-- 直接用结果做归档、通知等后续操作
```

4. 乐观锁更新确认

```sql
-- 更新一行，确认是否成功（CAS 操作）
UPDATE products SET stock = stock - 1, version = version + 1
WHERE id = 42 AND version = 7
RETURNING id, stock, version;
-- 如果返回空结果集: 版本冲突，更新失败
-- 如果返回一行: 更新成功，拿到最新的 stock 和 version
```

## 语法对比

### PostgreSQL（RETURNING）

```sql
-- INSERT RETURNING
INSERT INTO users (name, email)
VALUES ('Alice', 'alice@example.com')
RETURNING id, name, created_at;

-- 批量 INSERT RETURNING
INSERT INTO users (name, email)
VALUES ('Alice', 'a@e.com'), ('Bob', 'b@e.com')
RETURNING id, name;
-- 返回两行

-- UPDATE RETURNING（返回更新后的值）
UPDATE products SET price = price * 1.1
WHERE category = 'electronics'
RETURNING id, name, price AS new_price;

-- DELETE RETURNING
DELETE FROM logs WHERE created_at < '2024-01-01'
RETURNING *;

-- RETURNING 配合 CTE（强大组合）
WITH deleted AS (
    DELETE FROM old_orders
    WHERE order_date < '2023-01-01'
    RETURNING *
)
INSERT INTO order_archive SELECT * FROM deleted;
-- 一条语句完成: 从旧表删除 → 插入归档表

-- UPSERT + RETURNING
INSERT INTO kv (key, value) VALUES ('k1', 'v1')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value
RETURNING key, value, (xmax = 0) AS inserted;
-- xmax = 0 时为新插入，否则为更新（PostgreSQL 技巧）
```

### SQL Server（OUTPUT）

```sql
-- INSERT OUTPUT（注意: 用 INSERTED 伪表）
INSERT INTO users (name, email)
OUTPUT INSERTED.id, INSERTED.name, INSERTED.created_at
VALUES ('Alice', 'alice@example.com');

-- UPDATE OUTPUT（可以同时获取更新前后的值！）
UPDATE products
SET price = price * 1.1
OUTPUT
    DELETED.price AS old_price,     -- 更新前
    INSERTED.price AS new_price     -- 更新后
WHERE category = 'electronics';

-- DELETE OUTPUT（用 DELETED 伪表）
DELETE FROM logs
OUTPUT DELETED.*
WHERE created_at < '2024-01-01';

-- OUTPUT INTO（输出到表变量或另一个表）
DECLARE @InsertedIds TABLE (id INT);
INSERT INTO users (name, email)
OUTPUT INSERTED.id INTO @InsertedIds
VALUES ('Alice', 'alice@example.com');

-- MERGE OUTPUT（配合 MERGE 使用，可以获取 $action）
MERGE INTO target t
USING source s ON t.id = s.id
WHEN MATCHED THEN UPDATE SET t.value = s.value
WHEN NOT MATCHED THEN INSERT (id, value) VALUES (s.id, s.value)
OUTPUT $action, INSERTED.id, INSERTED.value;
-- $action 返回 'INSERT' 或 'UPDATE'
```

### Oracle（RETURNING INTO —— 仅 PL/SQL）

```sql
-- Oracle 的 RETURNING 必须配合 INTO 子句，限制在 PL/SQL 中使用
DECLARE
    v_id NUMBER;
    v_name VARCHAR2(100);
BEGIN
    INSERT INTO users (name, email) VALUES ('Alice', 'alice@example.com')
    RETURNING id, name INTO v_id, v_name;
    DBMS_OUTPUT.PUT_LINE('Inserted: ' || v_id || ' - ' || v_name);
END;
/

-- 批量操作配合 BULK COLLECT
DECLARE
    TYPE id_array IS TABLE OF NUMBER;
    v_ids id_array;
BEGIN
    DELETE FROM logs WHERE created_at < SYSDATE - 365
    RETURNING id BULK COLLECT INTO v_ids;
    DBMS_OUTPUT.PUT_LINE('Deleted ' || v_ids.COUNT || ' rows');
END;
/
```

### SQLite（3.35.0+）

```sql
-- SQLite 的 RETURNING 语法与 PostgreSQL 完全一致
INSERT INTO users (name, email)
VALUES ('Alice', 'alice@example.com')
RETURNING id, name, created_at;

UPDATE products SET price = price * 1.1
WHERE category = 'electronics'
RETURNING id, name, price;

DELETE FROM logs WHERE created_at < '2024-01-01'
RETURNING *;
```

### MariaDB（仅 DELETE）

```sql
-- MariaDB 10.5+ 仅在 DELETE 中支持 RETURNING
DELETE FROM logs WHERE created_at < '2024-01-01'
RETURNING id, message, created_at;

-- INSERT / UPDATE 不支持 RETURNING
```

### MySQL 替代方案

```sql
-- MySQL 不支持 RETURNING，常用替代:

-- 方案 1: LAST_INSERT_ID()（仅获取自增 ID）
INSERT INTO users (name, email) VALUES ('Alice', 'alice@example.com');
SELECT LAST_INSERT_ID() AS id;

-- 方案 2: 事务 + SELECT（获取完整行）
START TRANSACTION;
INSERT INTO users (name, email) VALUES ('Alice', 'alice@example.com');
SELECT * FROM users WHERE id = LAST_INSERT_ID();
COMMIT;

-- 方案 3: 应用层生成 ID（如 UUID）
SET @uuid = UUID();
INSERT INTO users (id, name, email) VALUES (@uuid, 'Alice', 'alice@example.com');
-- 不需要查询，客户端已经知道 id
```

## PostgreSQL RETURNING vs SQL Server OUTPUT 对比

| 特性 | PostgreSQL RETURNING | SQL Server OUTPUT |
|------|---------------------|-------------------|
| 位置 | 语句末尾 | INSERT: 中间位置 |
| 更新前的值 | 不支持 | `DELETED.col` |
| 更新后的值 | `RETURNING col` | `INSERTED.col` |
| 输出到变量 | 不需要（直接返回结果集） | `OUTPUT INTO @table` |
| 配合 CTE | 支持（强大） | 支持 |
| MERGE 中 | N/A (PG15 MERGE 暂不支持 RETURNING) | `OUTPUT $action` |

SQL Server 的 OUTPUT 在 UPDATE 场景更强大——可以同时返回更新前（DELETED）和更新后（INSERTED）的值。PostgreSQL 的 RETURNING 只能返回更新后的值。

## 对引擎开发者的实现建议

1. 执行器改造

RETURNING 的核心实现是让 DML 执行器"顺便"输出受影响的行：

```
InsertExecutor:
    for each row to insert:
        actual_row = insert(row)        // 执行插入（填充默认值、自增 ID）
        output(project(actual_row, returning_columns))  // 投影 RETURNING 列

UpdateExecutor:
    for each row matching WHERE:
        old_row = current_row
        new_row = apply_updates(old_row)
        update(old_row → new_row)
        output(project(new_row, returning_columns))     // 投影新值

DeleteExecutor:
    for each row matching WHERE:
        deleted_row = delete(row)
        output(project(deleted_row, returning_columns)) // 投影被删除的行
```

2. 触发器时序

RETURNING 返回的值应该是**触发器执行后**的最终值：

```
BEFORE INSERT 触发器 → 修改行 → 实际插入 → AFTER INSERT 触发器 → RETURNING 输出
```

即 RETURNING 看到的是 AFTER 触发器运行前、实际存储的行。

3. 客户端协议

RETURNING 使 DML 语句也返回结果集。需要修改客户端协议处理：

- 传统 DML: 返回 affected_rows 计数
- DML + RETURNING: 返回结果集（如同 SELECT）

大多数数据库协议已经支持这种双模式（如 PostgreSQL 的 CommandComplete + DataRow）。

4. 并发安全

RETURNING 的值必须来自实际写入的行——在 MVCC 引擎中，这是事务可见性规则自然保证的：

- INSERT: 返回刚插入的行（当前事务内可见）
- UPDATE: 返回更新后的新版本（当前事务内可见）
- DELETE: 返回被标记删除的行（当前事务内仍可见，提交后不可见）

5. 性能影响

RETURNING 几乎零额外开销——DML 执行器本来就要读取/写入这些行，顺便投影输出不需要额外 I/O。这比"DML 后 SELECT"高效得多：

| 方案 | 额外开销 |
|------|---------|
| RETURNING | 几乎为零（仅投影 + 网络传输） |
| DML + SELECT | 额外一次索引查找 + 可能的锁竞争 |
| DML + LAST_INSERT_ID | 仅获取一个标量（功能有限） |

## 参考资料

- PostgreSQL: [RETURNING](https://www.postgresql.org/docs/current/dml-returning.html)
- SQL Server: [OUTPUT Clause](https://learn.microsoft.com/en-us/sql/t-sql/queries/output-clause-transact-sql)
- SQLite: [RETURNING](https://www.sqlite.org/lang_returning.html)
- MariaDB: [DELETE RETURNING](https://mariadb.com/kb/en/delete/#returning)
