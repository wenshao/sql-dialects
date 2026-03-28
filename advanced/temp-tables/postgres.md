# PostgreSQL: 临时表

> 参考资料:
> - [PostgreSQL Documentation - CREATE TABLE (TEMPORARY)](https://www.postgresql.org/docs/current/sql-createtable.html)
> - [PostgreSQL Documentation - UNLOGGED tables](https://www.postgresql.org/docs/current/sql-createtable.html#SQL-CREATETABLE-UNLOGGED)

## 临时表 (TEMPORARY TABLE)

```sql
CREATE TEMPORARY TABLE temp_active_users (
    id BIGINT, username VARCHAR(100), email VARCHAR(200)
);

CREATE TEMP TABLE temp_results AS
SELECT user_id, SUM(amount) AS total FROM orders
WHERE order_date >= '2024-01-01' GROUP BY user_id;
```

临时表可以有索引和约束
```sql
CREATE INDEX ON temp_active_users (username);
ALTER TABLE temp_active_users ADD PRIMARY KEY (id);
```

## ON COMMIT 行为

事务提交时保留数据（默认）
```sql
CREATE TEMP TABLE t1 (id INT) ON COMMIT PRESERVE ROWS;
```

事务提交时清空数据（结构保留）
```sql
CREATE TEMP TABLE t2 (id INT) ON COMMIT DELETE ROWS;
```

事务提交时删除表
```sql
CREATE TEMP TABLE t3 (id INT) ON COMMIT DROP;
```

## 临时表的内部实现

临时表存在于专用的 pg_temp_N schema 中（每个会话有自己的）
```sql
SELECT * FROM pg_temp.temp_active_users;  -- pg_temp 是当前会话的别名

-- 内部机制:
--   (a) 临时表的元数据存在 session-local 的系统表中（不写 WAL）
--   (b) 临时表的数据存在本地缓冲区（local buffer，不是 shared buffer）
--   (c) 临时表不写 WAL（崩溃后丢失，但写入更快）
--   (d) 会话结束时自动清理（无需手动 DROP）
--
-- 性能特点:
--   优势: 不写 WAL = 写入快 2-3x，不影响 shared buffer = 不与其他会话竞争
--   劣势: local buffer 较小（temp_buffers 默认 8MB），大临时表可能溢出到磁盘
--         频繁创建/删除临时表增加系统表膨胀（autovacuum 需要清理 pg_class 等）

-- 检查临时表是否存在
SELECT EXISTS (
    SELECT 1 FROM pg_tables
    WHERE tablename = 'temp_active_users' AND schemaname LIKE 'pg_temp%'
);
```

## UNLOGGED 表: 介于普通表和临时表之间

```sql
CREATE UNLOGGED TABLE staging_data (id BIGINT, data JSONB);
```

UNLOGGED 表的特性:
  (a) 不写 WAL（写入快 2-5x）
  (b) 崩溃后数据丢失（自动清空为空表）
  (c) 不复制到备库（流复制跳过 UNLOGGED 表）
  (d) 存在于 shared buffer 中（与临时表不同）
  (e) 对所有会话可见（与临时表不同）

适用场景: ETL 中间表、导入暂存、缓存表、可重建的计算结果

普通表可以改为 UNLOGGED（17+ 不需要重写表）
```sql
ALTER TABLE staging_data SET UNLOGGED;
ALTER TABLE staging_data SET LOGGED;     -- 恢复为普通表
```

## 可写 CTE 作为"临时结果"的替代

归档模式: 单语句完成 DELETE + INSERT（无需临时表）
```sql
WITH deleted AS (
    DELETE FROM orders WHERE status = 'cancelled' RETURNING *
)
INSERT INTO cancelled_orders SELECT * FROM deleted;
```

CTE 物化控制 (12+)
```sql
WITH active AS MATERIALIZED (SELECT * FROM users WHERE status = 1)
SELECT * FROM active WHERE age > 25;
```

## 横向对比: 临时表差异

### 作用域

  PostgreSQL: 会话级（ON COMMIT 控制事务级行为）
  MySQL:      会话级（连接断开时删除）
  Oracle:     全局临时表（定义持久，数据临时）
  SQL Server: #temp（会话级），##temp（全局临时），@table（表变量）

### UNLOGGED 表

  PostgreSQL: UNLOGGED 表（不写 WAL，崩溃丢失）
  MySQL:      无等价功能
  Oracle:     NOLOGGING（减少 redo 但不完全不写）
  SQL Server: 无等价功能

### 临时表 WAL

  PostgreSQL: 临时表不写 WAL
  MySQL:      临时表也写 redo/undo（InnoDB）
  Oracle:     全局临时表也写 undo（不写 redo）

### 临时表开销

  PostgreSQL: 频繁 CREATE/DROP TEMP TABLE 会导致系统表膨胀
  SQL Server: 表变量 @t 无统计信息，大数据集可能选择差的计划

## 对引擎开发者的启示

(1) 临时表使用 local buffer 而非 shared buffer:
    这避免了临时数据污染共享缓存，但也限制了临时表的内存上限。
    temp_buffers 默认只有 8MB——大临时表需要调大。

(2) UNLOGGED 表填补了"高性能临时存储"的空白:
    临时表只对当前会话可见，UNLOGGED 表对所有会话可见。
    ETL 场景经常需要多个会话共享中间数据。

(3) 可写 CTE（WITH ... DELETE RETURNING ... INSERT）
    在很多场景下替代了临时表——更简洁，无元数据开销。

(4) 临时表导致的系统表膨胀是 PostgreSQL 的已知问题:
    每次 CREATE/DROP TEMP TABLE 都会修改 pg_class 等系统表。
    高频创建临时表的应用应考虑 ON COMMIT DELETE ROWS 复用表定义。

## 版本演进

PostgreSQL 全版本: CREATE TEMP TABLE, ON COMMIT
PostgreSQL 9.1:   UNLOGGED 表
PostgreSQL 12:    CTE 物化控制 (MATERIALIZED / NOT MATERIALIZED)
PostgreSQL 17:    ALTER TABLE SET LOGGED/UNLOGGED 不再需要重写表
