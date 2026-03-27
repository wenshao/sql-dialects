# MERGE INTO 语法演进

SQL 标准的 UPSERT 方案——功能最强大但也最复杂的 DML 语句。

## 支持矩阵

| 引擎 | 支持 | 版本 | 备注 |
|------|------|------|------|
| Oracle | 完整支持 | 9i+ (2001) | **比标准还早**，语法略有差异 |
| SQL Server | 完整支持 | 2008+ | 有已知 bug（见下文） |
| PostgreSQL | 完整支持 | 15+ (2022) | 很晚才支持 |
| DB2 | 完整支持 | 早期版本 | 接近标准 |
| Snowflake | 完整支持 | GA | - |
| BigQuery | 完整支持 | GA | - |
| Databricks | 完整支持 | Runtime 7.0+ | Delta Lake MERGE |
| Teradata | 完整支持 | 早期版本 | - |
| H2 | 完整支持 | 早期版本 | - |
| DuckDB | 完整支持 | 0.8.0+ | - |
| StarRocks | 部分支持 | 3.0+ | 有限制 |
| MySQL | **不支持** | - | 用 ON DUPLICATE KEY UPDATE |
| MariaDB | **不支持** | - | 同 MySQL |
| SQLite | **不支持** | - | 用 ON CONFLICT |
| ClickHouse | **不支持** | - | 用 ReplacingMergeTree |

## SQL 标准演进

| 标准 | 内容 |
|------|------|
| SQL:2003 | 首次定义 MERGE INTO 语法 |
| SQL:2008 | 增加 DELETE 动作、多 WHEN MATCHED 子句 |
| SQL:2016 | 无重大变化 |

Oracle 在 SQL:2003 标准发布前（2001 年的 9i 版本）就实现了 MERGE，后来标准的定义受到了 Oracle 实现的影响。

## 设计动机

### 核心需求: 条件式插入或更新

```sql
-- 业务场景: 导入一批数据
-- 如果目标表中已存在（按主键匹配），则更新
-- 如果不存在，则插入
-- 可能还需要: 如果满足某条件，则删除

-- 没有 MERGE 时的写法（伪代码）:
FOR each row in source:
    IF EXISTS in target:
        UPDATE target ...
    ELSE:
        INSERT INTO target ...
-- 问题: 多次往返、竞态条件、性能差
```

### MERGE 的解决方案

```sql
MERGE INTO target t
USING source s ON t.id = s.id
WHEN MATCHED THEN UPDATE SET t.value = s.value
WHEN NOT MATCHED THEN INSERT (id, value) VALUES (s.id, s.value);
```

一条语句完成匹配、更新、插入——原子性、高性能。

## 语法对比

### SQL 标准 / PostgreSQL 15+

```sql
-- 基本 MERGE
MERGE INTO target_table t
USING source_table s
ON t.id = s.id
WHEN MATCHED THEN
    UPDATE SET t.name = s.name, t.value = s.value
WHEN NOT MATCHED THEN
    INSERT (id, name, value)
    VALUES (s.id, s.name, s.value);

-- 带条件的多 WHEN 子句（SQL:2008）
MERGE INTO products t
USING new_products s ON t.product_id = s.product_id
WHEN MATCHED AND s.quantity = 0 THEN
    DELETE                                   -- 库存为 0 则删除
WHEN MATCHED THEN
    UPDATE SET t.price = s.price,
               t.quantity = s.quantity       -- 否则更新
WHEN NOT MATCHED THEN
    INSERT (product_id, price, quantity)
    VALUES (s.product_id, s.price, s.quantity);

-- USING 子查询
MERGE INTO target t
USING (SELECT id, value FROM staging WHERE batch_id = 42) s
ON t.id = s.id
WHEN MATCHED THEN UPDATE SET t.value = s.value
WHEN NOT MATCHED THEN INSERT (id, value) VALUES (s.id, s.value);

-- USING VALUES（单行 upsert）
MERGE INTO config t
USING (VALUES ('key1', 'val1')) AS s(key, value)
ON t.key = s.key
WHEN MATCHED THEN UPDATE SET t.value = s.value
WHEN NOT MATCHED THEN INSERT (key, value) VALUES (s.key, s.value);
```

### Oracle

```sql
-- Oracle MERGE（比标准略有差异）
MERGE INTO target t
USING source s ON (t.id = s.id)       -- ON 条件要括号（Oracle 惯例）
WHEN MATCHED THEN
    UPDATE SET t.name = s.name, t.value = s.value
    DELETE WHERE t.status = 'inactive' -- Oracle 独有: MATCHED + DELETE
WHEN NOT MATCHED THEN
    INSERT (id, name, value)
    VALUES (s.id, s.name, s.value)
    WHERE s.status = 'active';         -- Oracle 独有: INSERT WHERE 过滤

-- Oracle 的 DELETE 行为特殊:
-- 先 UPDATE，然后对更新后的行检查 DELETE WHERE 条件
-- 只能删除被 UPDATE 的行（不能删除未匹配的行）
```

### SQL Server

```sql
-- SQL Server MERGE（必须以分号结尾!）
MERGE INTO target AS t
USING source AS s
ON t.id = s.id
WHEN MATCHED THEN
    UPDATE SET t.name = s.name, t.value = s.value
WHEN NOT MATCHED BY TARGET THEN           -- 标准中叫 NOT MATCHED
    INSERT (id, name, value)
    VALUES (s.id, s.name, s.value)
WHEN NOT MATCHED BY SOURCE THEN           -- SQL Server 独有!
    DELETE;                                -- 分号必须!

-- NOT MATCHED BY SOURCE: 目标表中有但源表中没有的行
-- 这让 MERGE 可以实现完全同步（增、改、删）
```

### Snowflake

```sql
-- Snowflake MERGE
MERGE INTO target t
USING source s ON t.id = s.id
WHEN MATCHED AND s.deleted = TRUE THEN DELETE
WHEN MATCHED THEN UPDATE SET t.name = s.name, t.value = s.value
WHEN NOT MATCHED THEN INSERT (id, name, value) VALUES (s.id, s.name, s.value);

-- Snowflake 简写（无 USING，直接用 VALUES）
MERGE INTO target t USING (
    SELECT $1 AS id, $2 AS name FROM VALUES (1, 'a'), (2, 'b')
) s ON t.id = s.id
WHEN MATCHED THEN UPDATE SET t.name = s.name
WHEN NOT MATCHED THEN INSERT (id, name) VALUES (s.id, s.name);
```

### BigQuery

```sql
-- BigQuery MERGE
MERGE INTO dataset.target t
USING dataset.source s
ON t.id = s.id
WHEN MATCHED THEN
    UPDATE SET t.name = s.name, t.updated_at = CURRENT_TIMESTAMP()
WHEN NOT MATCHED THEN
    INSERT (id, name, created_at, updated_at)
    VALUES (s.id, s.name, CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP())
WHEN NOT MATCHED BY SOURCE THEN
    DELETE;
```

### Databricks（Delta Lake）

```sql
-- Databricks MERGE INTO（Delta Lake 专用）
MERGE INTO target t
USING source s ON t.id = s.id
WHEN MATCHED AND s.is_deleted THEN DELETE
WHEN MATCHED THEN UPDATE SET *             -- SET * 自动匹配所有列
WHEN NOT MATCHED THEN INSERT *;            -- INSERT * 自动匹配所有列
-- SET * 和 INSERT * 是 Databricks 的便利语法
```

## MERGE vs ON CONFLICT vs ON DUPLICATE KEY

| 特性 | MERGE INTO | ON CONFLICT (PG) | ON DUPLICATE KEY (MySQL) |
|------|-----------|-------------------|--------------------------|
| 标准 | SQL:2003 | PostgreSQL 9.5+ 专有 | MySQL 专有 |
| 数据源 | 表/子查询 | 单条 INSERT 的值 | 单条 INSERT 的值 |
| 匹配条件 | 任意 ON 表达式 | 唯一约束 / 唯一索引 | 唯一约束 / 主键 |
| DELETE 动作 | 支持 | 不支持 | 不支持 |
| 多 WHEN 条件 | 支持 | 不支持 | 不支持 |
| NOT MATCHED BY SOURCE | SQL Server 支持 | 不支持 | 不支持 |
| DO NOTHING | 用空 WHEN MATCHED | `ON CONFLICT DO NOTHING` | `INSERT IGNORE` |
| 语法复杂度 | 高 | 中 | 低 |
| 批量操作 | 优秀 | 一般 | 一般 |

选择建议：
- **批量 ETL/数据同步**: MERGE（功能最强）
- **应用层单行 upsert**: ON CONFLICT / ON DUPLICATE KEY（语法更简洁）
- **全量同步（增删改）**: MERGE + NOT MATCHED BY SOURCE（仅 SQL Server/BigQuery）

## SQL Server MERGE 的 Bug 历史

SQL Server 的 MERGE 语句有一系列**已知但长期未修复**的 bug，这在数据库引擎中极为罕见：

### 1. 竞态条件 (Race Condition)

```sql
-- 并发 MERGE 可能导致违反唯一约束
-- KB: https://support.microsoft.com/kb/2646486
MERGE INTO t WITH (HOLDLOCK) ...  -- 微软建议加 HOLDLOCK 提示
```

没有 HOLDLOCK 时，两个并发 MERGE 可能同时判断"不存在"然后都尝试 INSERT，导致唯一键冲突。

### 2. 外键约束违反

MERGE 在某些情况下不正确地检查外键约束，可能产生孤儿行。

### 3. 触发器问题

MERGE 触发的 INSTEAD OF 触发器在某些边界情况下行为异常。

### 4. 社区反应

由于这些 bug，许多 SQL Server 专家（包括 Aaron Bertrand、Paul White）建议**避免使用 MERGE**，改用显式的 INSERT + UPDATE + DELETE：

```sql
-- 安全替代方案（SQL Server）
BEGIN TRANSACTION;

UPDATE t SET t.value = s.value
FROM target t INNER JOIN source s ON t.id = s.id;

INSERT INTO target (id, value)
SELECT s.id, s.value FROM source s
WHERE NOT EXISTS (SELECT 1 FROM target t WHERE t.id = s.id);

COMMIT;
```

## 对引擎开发者的实现建议

### 1. 执行计划

MERGE 的执行计划核心是一个 JOIN + 条件路由：

```
MergeJoin / HashJoin (target, source, ON condition)
  → 对每一行根据匹配状态路由:
    - MATCHED + condition → UpdateExecutor
    - MATCHED + condition → DeleteExecutor
    - NOT MATCHED → InsertExecutor
```

### 2. 匹配语义

关键设计决策：当 source 中多行匹配 target 中的同一行时怎么处理？

| 引擎 | 行为 |
|------|------|
| SQL 标准 | 未定义（应报错或取一行） |
| SQL Server | 报错: "The MERGE statement attempted to UPDATE or DELETE the same row more than once" |
| Oracle | 报错: ORA-30926 |
| PostgreSQL | 报错 |
| Snowflake | 报错（除非用 MERGE 的非确定性模式） |

建议: 检测到 1:N 匹配时报错，这是最安全的行为。

### 3. 并发控制

MERGE 涉及读和写同一张表，需要特殊的锁策略：

- **MVCC 引擎（PostgreSQL）**: 使用 snapshot 隔离，MERGE 在快照上匹配，写时检查冲突
- **锁引擎（SQL Server）**: 需要适当的锁提示确保隔离（如 HOLDLOCK）
- **OLAP 引擎**: 通常不需要担心并发，但需要保证原子性

### 4. 分布式 MERGE

在分布式引擎中，MERGE 特别复杂：

- target 和 source 可能在不同节点
- 需要将 source 数据 shuffle 到 target 的 partition 所在节点
- 或者将两者 co-locate 后本地执行

Databricks Delta Lake 的做法：
1. Scan source，按 target 的分区策略 shuffle
2. 对每个 partition，执行本地 MERGE
3. 用 copy-on-write 或 merge-on-read 策略写回

### 5. MERGE 的优化

- **索引利用**: ON 条件中的列应利用 target 的索引
- **谓词下推**: WHEN 子句中的条件可以下推到 scan 阶段
- **批量写入**: 不要逐行执行 INSERT/UPDATE/DELETE，应批量化

## 参考资料

- SQL:2003 标准: ISO/IEC 9075-2:2003 Section 14.9
- PostgreSQL 15: [MERGE](https://www.postgresql.org/docs/15/sql-merge.html)
- SQL Server: [MERGE](https://learn.microsoft.com/en-us/sql/t-sql/statements/merge-transact-sql)
- Oracle: [MERGE](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/MERGE.html)
- SQL Server MERGE bugs: [Use Caution with SQL Server's MERGE Statement](https://www.mssqltips.com/sqlservertip/3074/)
