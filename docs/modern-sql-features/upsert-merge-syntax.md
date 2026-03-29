# UPSERT 与 MERGE：各 SQL 方言语法全对比

"如果存在则更新，不存在则插入"——这个简单需求在不同引擎中有截然不同的语法、语义和陷阱。

## UPSERT 语法矩阵

| 引擎 | ON DUPLICATE KEY UPDATE | ON CONFLICT DO UPDATE/NOTHING | MERGE INTO | REPLACE INTO / INSERT OR REPLACE | INSERT OVERWRITE |
|------|:-:|:-:|:-:|:-:|:-:|
| MySQL 4.1+ | **主要方式** | - | - | 支持 | - |
| MariaDB 10.5+ | **主要方式** | - | - | 支持 | - |
| TiDB | **主要方式** | - | - | 支持 | - |
| OceanBase (MySQL 模式) | **主要方式** | - | - | 支持 | - |
| OceanBase (Oracle 模式) | - | - | **主要方式** (MERGE INTO) | - | - |
| PostgreSQL 9.5+ | - | **主要方式** | 15+ | - | - |
| CockroachDB | - | **主要方式** | - | - | - |
| YugabyteDB | - | **主要方式** | - | - | - |
| SQLite 3.24+ | - | **主要方式** | - | 支持 | - |
| DuckDB 0.8.0+ | - | **主要方式** | 1.2.0+ | 支持 | - |
| Oracle 9i+ | - | - | **主要方式** | - | - |
| SQL Server 2008+ | - | - | **主要方式** | - | - |
| BigQuery | - | - | **主要方式** | - | - |
| Snowflake | - | - | **主要方式** | - | - |
| Databricks | - | - | **主要方式** (Delta Lake) | - | 支持 |
| Spark SQL | - | - | **主要方式** (Delta Lake) | - | 支持 |
| Hive 2.2+ | - | - | ACID 事务表 | - | **主要方式** |
| Trino | - | - | 部分 connector | - | 支持 (Hive connector 等) |
| StarRocks 3.0+ | - | - | 支持 (仅 PK 表) | - | 支持 |
| Doris 2.1+ | - | - | 支持 (Unique Key 表) | - | 支持 |
| Flink SQL | - | - | - | - | **主要方式** |
| MaxCompute | - | - | - | - | **主要方式** |
| ClickHouse | - | - | - | - | - |

ClickHouse 没有传统的 UPSERT 语义。它使用 ReplacingMergeTree 引擎在后台 merge 时做去重（查询时需加 FINAL 关键字才能看到去重结果），属于"最终一致性去重"而非即时 UPSERT。此外 ClickHouse 支持 ALTER TABLE UPDATE/DELETE（异步 mutation），但性能远低于传统 DML。StarRocks/Doris 的 Primary Key/Unique Key 模型也是类似的 LSM-Tree 异步去重机制。

## 五种 UPSERT 机制详解

#### 1. ON DUPLICATE KEY UPDATE（MySQL 系）

```sql
-- MySQL / MariaDB / TiDB / OceanBase（传统 VALUES() 写法，8.0.20 起弃用）
INSERT INTO users (id, name, email, login_count)
VALUES (1, 'Alice', 'alice@example.com', 1)
ON DUPLICATE KEY UPDATE
    name = VALUES(name),
    email = VALUES(email),
    login_count = login_count + 1;

-- MySQL 8.0.19+ 推荐的 AS 别名写法
INSERT INTO users (id, name, email)
VALUES (1, 'Alice', 'a@x.com'),
       (2, 'Bob', 'b@x.com'),
       (3, 'Charlie', 'c@x.com') AS new_row
ON DUPLICATE KEY UPDATE
    name = new_row.name,
    email = new_row.email;
```

触发条件: PRIMARY KEY 或任意 UNIQUE KEY 冲突。

MySQL 8.0.19+ 引入了 `AS new_row` 别名语法替代 `VALUES()` 函数:

```sql
-- MySQL 8.0.19+ 推荐写法
INSERT INTO users (id, name, email)
VALUES (1, 'Alice', 'alice@example.com') AS new_row
ON DUPLICATE KEY UPDATE
    name = new_row.name,
    email = new_row.email;
```

`VALUES()` 函数在 MySQL 8.0.20 中被标记为 deprecated。

#### 2. ON CONFLICT DO UPDATE / DO NOTHING（PostgreSQL 系）

```sql
-- PostgreSQL 9.5+ / CockroachDB / YugabyteDB
INSERT INTO users (id, name, email, login_count)
VALUES (1, 'Alice', 'alice@example.com', 1)
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    email = EXCLUDED.email,
    login_count = users.login_count + 1;

-- 按唯一约束名指定冲突
INSERT INTO users (id, name, email)
VALUES (1, 'Alice', 'alice@example.com')
ON CONFLICT ON CONSTRAINT users_pkey DO UPDATE SET
    name = EXCLUDED.name;

-- 只跳过冲突行
INSERT INTO users (id, name, email)
VALUES (1, 'Alice', 'alice@example.com')
ON CONFLICT (id) DO NOTHING;

-- 带 WHERE 条件: 只在满足条件时更新
INSERT INTO users (id, name, email, updated_at)
VALUES (1, 'Alice', 'alice@example.com', NOW())
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    email = EXCLUDED.email,
    updated_at = EXCLUDED.updated_at
WHERE users.updated_at < EXCLUDED.updated_at;  -- 仅当新数据更新时才覆盖
```

SQLite 3.24+ 和 DuckDB 0.8.0+ 也使用相同语法:

```sql
-- SQLite / DuckDB
INSERT INTO users (id, name, email)
VALUES (1, 'Alice', 'alice@example.com')
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    email = EXCLUDED.email;
```

#### 3. MERGE INTO（SQL 标准）

```sql
-- SQL:2003 标准 / Oracle / SQL Server / PG 15+ / BigQuery / Snowflake / Databricks
MERGE INTO target t
USING source s ON t.id = s.id
WHEN MATCHED THEN
    UPDATE SET t.name = s.name, t.value = s.value
WHEN NOT MATCHED THEN
    INSERT (id, name, value)
    VALUES (s.id, s.name, s.value);

-- 单行 UPSERT 写法
MERGE INTO users t
USING (SELECT 1 AS id, 'Alice' AS name, 'a@x.com' AS email) s
ON t.id = s.id
WHEN MATCHED THEN UPDATE SET t.name = s.name, t.email = s.email
WHEN NOT MATCHED THEN INSERT (id, name, email) VALUES (s.id, s.name, s.email);
```

MERGE 的详细语法差异见下一节。

#### 4. REPLACE INTO / INSERT OR REPLACE

```sql
-- MySQL: REPLACE INTO
-- 语义: 如果冲突则 DELETE 旧行 + INSERT 新行
REPLACE INTO users (id, name, email)
VALUES (1, 'Alice', 'alice@example.com');

-- SQLite: INSERT OR REPLACE
INSERT OR REPLACE INTO users (id, name, email)
VALUES (1, 'Alice', 'alice@example.com');
```

**危险**: REPLACE 是先删再插，不是原地更新:
- 自增 ID 会变化（如果不指定 ID）
- DELETE + INSERT 触发器都会执行
- 未在 INSERT 中指定的列会被重置为默认值
- **⚠️ 外键级联灾难**: `ON DELETE CASCADE` 会触发——REPLACE 的 DELETE 操作可能级联删除关联表数据，造成"血洗"

#### 5. INSERT OVERWRITE（大数据引擎）

```sql
-- Hive / Spark / Flink / MaxCompute
INSERT OVERWRITE TABLE fact_sales PARTITION (dt = '2024-01-15')
SELECT * FROM staging_sales WHERE dt = '2024-01-15';
```

INSERT OVERWRITE 是分区级别的全量替换，而非行级 UPSERT。适用于 ETL 管道的幂等写入场景。详见 [INSERT OVERWRITE](insert-overwrite.md)（详见项目内对应文档）。

## MERGE 语法差异

### WHEN MATCHED / NOT MATCHED 子句

| 引擎 | 多 WHEN MATCHED | 带条件 WHEN | WHEN 中 DELETE | WHEN NOT MATCHED BY SOURCE |
|------|:-:|:-:|:-:|:-:|
| SQL 标准 (SQL:2008) | 支持 | 支持 | 支持 | - |
| Oracle 9i+ (23c 前仅 1 个，23c+ 多个) | 23c+ 支持 | 支持 | 支持 (特殊语义) | - |
| SQL Server 2008+ | 最多 2 个 | 支持 | 支持 | **支持** |
| PostgreSQL 15+ | 支持 | 支持 | 支持 | - |
| PostgreSQL 17+ | 支持 | 支持 | 支持 | **支持** |
| BigQuery | 支持 | 支持 | 支持 | **支持** |
| Snowflake | 支持 | 支持 | 支持 | - |
| Databricks | 支持 | 支持 | 支持 | **支持** |
| DuckDB | 支持 | 支持 | 支持 | - |
| Hive 2.2+ | 支持 | 支持 | - | - |
| StarRocks | 有限 | 有限 | - | - |

### WHEN NOT MATCHED BY SOURCE

这个子句处理"目标表中存在但源表中不存在"的行——实现全量同步时最关键的功能:

```sql
-- SQL Server 2008+ / BigQuery / Databricks / PG 17+
MERGE INTO target t
USING source s ON t.id = s.id
WHEN MATCHED THEN
    UPDATE SET t.name = s.name
WHEN NOT MATCHED THEN  -- SQL:2003 标准
    INSERT (id, name) VALUES (s.id, s.name)
WHEN NOT MATCHED BY SOURCE THEN
    DELETE;  -- 目标中有但源中没有的行: 删除

-- 带条件: 不删除某些行
WHEN NOT MATCHED BY SOURCE AND t.protected = FALSE THEN
    DELETE;
```

没有此子句的引擎要实现全量同步，需要额外的 DELETE 语句:

```sql
-- Oracle / Snowflake 等不支持 NOT MATCHED BY SOURCE 的引擎
MERGE INTO target t USING source s ON t.id = s.id
WHEN MATCHED THEN UPDATE SET t.name = s.name
WHEN NOT MATCHED THEN INSERT (id, name) VALUES (s.id, s.name);

-- 额外步骤: 删除源中不存在的行
DELETE FROM target WHERE NOT EXISTS (SELECT 1 FROM source WHERE source.id = target.id);
-- ⚠️ 不要用 NOT IN：source.id 含 NULL 时会返回空集！
```

### Oracle MERGE 的特殊行为

```sql
-- Oracle 的 DELETE 只能跟在 UPDATE 后面
MERGE INTO target t
USING source s ON (t.id = s.id)
WHEN MATCHED THEN
    UPDATE SET t.name = s.name
    DELETE WHERE t.status = 'inactive'  -- 先 UPDATE，再检查是否需要 DELETE
WHEN NOT MATCHED THEN
    INSERT (id, name) VALUES (s.id, s.name)
    WHERE s.status = 'active';          -- INSERT 也可以带 WHERE 过滤
```

Oracle MERGE 中的 DELETE 只能删除被 MATCHED 且 UPDATE 过的行，无法独立使用 `WHEN MATCHED THEN DELETE`（这与其他引擎不同）。

## RETURNING / OUTPUT：UPSERT 后取回受影响行

| 引擎 | 语法 | UPSERT 是否支持 | 示例 |
|------|------|:-:|------|
| PostgreSQL 9.5+ | `RETURNING` | **支持** | `INSERT ... ON CONFLICT DO UPDATE ... RETURNING *` |
| SQLite 3.35+ | `RETURNING` | **支持** | `INSERT ... ON CONFLICT DO UPDATE ... RETURNING *` |
| CockroachDB | `RETURNING` | **支持** | 同 PostgreSQL |
| YugabyteDB | `RETURNING` | **支持** | 同 PostgreSQL |
| DuckDB | `RETURNING` | **支持** | 同 PostgreSQL |
| SQL Server 2008+ | `OUTPUT` | **MERGE 支持** | `MERGE ... OUTPUT $action, inserted.*, deleted.*` |
| Oracle | `RETURNING INTO` | **仅 PL/SQL** | 需要在过程块中使用 |
| MySQL | **不支持** | - | 只能用 `ROW_COUNT()` 和 `LAST_INSERT_ID()` |
| MariaDB | `RETURNING` (10.5+) | **支持** | INSERT/REPLACE/DELETE/ON DUPLICATE KEY UPDATE 均支持 RETURNING |
| BigQuery | **不支持** | - | - |
| Snowflake | **不支持** | - | 但 MERGE 返回行数统计 |

### PostgreSQL ON CONFLICT RETURNING

```sql
-- 插入或更新后，直接拿到最终行的完整数据
INSERT INTO users (id, name, email, login_count)
VALUES (1, 'Alice', 'alice@example.com', 1)
ON CONFLICT (id) DO UPDATE SET
    login_count = users.login_count + 1,
    last_login = NOW()
RETURNING id, name, login_count, last_login;
-- 返回:
-- | id | name  | login_count | last_login          |
-- | 1  | Alice | 5           | 2025-03-28 10:00:00 |
```

### SQL Server MERGE OUTPUT

```sql
MERGE INTO users AS t
USING (VALUES (1, 'Alice', 'a@x.com')) AS s(id, name, email)
ON t.id = s.id
WHEN MATCHED THEN UPDATE SET t.name = s.name, t.email = s.email
WHEN NOT MATCHED THEN INSERT (id, name, email) VALUES (s.id, s.name, s.email)
OUTPUT $action AS action,           -- 'INSERT' 或 'UPDATE'
       inserted.id,
       inserted.name,
       ISNULL(deleted.name, '') AS old_name;
-- $action 列指明每一行是被 INSERT 还是 UPDATE 还是 DELETE
```

### MySQL 的替代方案

```sql
-- MySQL 没有 RETURNING，只能依赖函数
INSERT INTO users (id, name, email)
VALUES (1, 'Alice', 'alice@example.com')
ON DUPLICATE KEY UPDATE name = VALUES(name);

-- 然后检查:
SELECT ROW_COUNT();        -- 1=INSERT, 2=UPDATE, 0=无变化
SELECT LAST_INSERT_ID();   -- 仅 INSERT 时有意义
```

## 并发安全

### 原子性对比

| 引擎/语法 | 原子性 | 并发安全 | 备注 |
|-----------|:------:|:-------:|------|
| PG `ON CONFLICT` | 原子 | **安全** | 利用唯一索引锁，无竞态条件 |
| MySQL `ON DUPLICATE KEY UPDATE` | 原子 | **⚠️ 有 deadlock 风险** | 行锁 + Next-Key Lock；并发时共享→排他锁升级可能死锁 |
| MySQL `REPLACE INTO` | 原子 | **有隐患** | DELETE + INSERT 两步；触发器看到的是先删后插 |
| SQLite `ON CONFLICT` | 原子 | **安全** | 库级锁（WAL 模式下写锁） |
| Oracle `MERGE` | 原子 | **安全** | 行锁 + 快照隔离 |
| SQL Server `MERGE` | ⚠️ 有并发风险 | 需 HOLDLOCK | 需加 `WITH (HOLDLOCK)` 提示，否则有竞态条件 |
| PG `MERGE` (15+) | 原子 | 快照隔离 | 快照隔离 + 行锁（非 ON CONFLICT 级别的并发优化） |
| Snowflake `MERGE` | 原子 | **表级锁** | 单表写串行化，不存在竞态 |
| BigQuery `MERGE` | 原子 | **快照** | 快照隔离，冲突时失败重试 |
| Databricks `MERGE` | 原子 | **乐观锁** | 乐观并发，冲突时失败重试 |

### PostgreSQL ON CONFLICT 为什么是真正原子的

```sql
-- 两个并发事务同时执行:
-- TX1: INSERT INTO t (id, val) VALUES (1, 'A') ON CONFLICT (id) DO UPDATE SET val = 'A';
-- TX2: INSERT INTO t (id, val) VALUES (1, 'B') ON CONFLICT (id) DO UPDATE SET val = 'B';

-- 流程:
-- 1. TX1 尝试 INSERT，成功获取行锁
-- 2. TX2 尝试 INSERT，发现唯一冲突，等待 TX1 提交
-- 3. TX1 提交
-- 4. TX2 重新检查冲突，执行 UPDATE，获取行锁
-- 5. TX2 提交
-- 结果: val = 'B'（后提交的胜出），无错误，无竞态
```

### SQL Server MERGE 的竞态问题

```sql
-- 不安全写法:
MERGE INTO users AS t
USING (VALUES (1, 'Alice')) AS s(id, name) ON t.id = s.id
WHEN MATCHED THEN UPDATE SET t.name = s.name
WHEN NOT MATCHED THEN INSERT (id, name) VALUES (s.id, s.name);
-- 并发执行可能抛出: 违反唯一约束!

-- 安全写法: 加 HOLDLOCK（等价于 SERIALIZABLE 隔离级别的锁）
MERGE INTO users WITH (HOLDLOCK) AS t
USING (VALUES (1, 'Alice')) AS s(id, name) ON t.id = s.id
WHEN MATCHED THEN UPDATE SET t.name = s.name
WHEN NOT MATCHED THEN INSERT (id, name) VALUES (s.id, s.name);
```

### REPLACE INTO 不是真正的 UPSERT

```sql
-- MySQL REPLACE INTO 的问题
CREATE TABLE orders (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT,
    amount DECIMAL(10,2),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY (user_id)
);

INSERT INTO orders (user_id, amount) VALUES (100, 50.00);
-- id=1, user_id=100, amount=50.00, created_at='2025-01-01 10:00:00'

REPLACE INTO orders (user_id, amount) VALUES (100, 75.00);
-- id=2(!), user_id=100, amount=75.00, created_at='2025-01-01 10:05:00'
-- 旧行被 DELETE，新行被 INSERT:
--   auto_increment ID 变了
--   created_at 被重置
--   如果有 ON DELETE CASCADE 外键，关联数据被级联删除!
```

## 部分更新：冲突时只更新指定列

各语法引用"待插入值"的方式不同:

| 语法 | 引用新值 | 引用旧值 |
|------|---------|---------|
| PG `ON CONFLICT` | `EXCLUDED.col` | `table_name.col` 或 `t.col` |
| MySQL `ON DUPLICATE KEY` (< 8.0.19) | `VALUES(col)` | `col` 或 `table_name.col` |
| MySQL `ON DUPLICATE KEY` (8.0.19+) | `alias.col` (AS 别名) | `col` 或 `table_name.col` |
| SQLite `ON CONFLICT` | `EXCLUDED.col` | `table_name.col` |
| DuckDB `ON CONFLICT` | `EXCLUDED.col` | `table_name.col` |
| MERGE (所有引擎) | `s.col` (源表别名) | `t.col` (目标表别名) |

### 条件式部分更新

```sql
-- PostgreSQL: 仅当新值更大时才更新
INSERT INTO metrics (sensor_id, max_value, last_seen)
VALUES (42, 100, NOW())
ON CONFLICT (sensor_id) DO UPDATE SET
    max_value = GREATEST(metrics.max_value, EXCLUDED.max_value),
    last_seen = EXCLUDED.last_seen;
-- max_value: 取新旧中较大的
-- last_seen: 始终更新

-- MySQL: 同等逻辑
INSERT INTO metrics (sensor_id, max_value, last_seen)
VALUES (42, 100, NOW()) AS new_row
ON DUPLICATE KEY UPDATE
    max_value = GREATEST(max_value, new_row.max_value),
    last_seen = new_row.last_seen;  -- 8.0.19+ AS 别名语法

-- MERGE: 同等逻辑
MERGE INTO metrics t
USING (SELECT 42 AS sensor_id, 100 AS max_value, CURRENT_TIMESTAMP AS last_seen) s
ON t.sensor_id = s.sensor_id
WHEN MATCHED THEN UPDATE SET
    t.max_value = GREATEST(t.max_value, s.max_value),
    t.last_seen = s.last_seen
WHEN NOT MATCHED THEN INSERT (sensor_id, max_value, last_seen)
    VALUES (s.sensor_id, s.max_value, s.last_seen);
```

## 性能差异

### INSERT ... ON CONFLICT vs MERGE

| 场景 | ON CONFLICT | MERGE |
|------|------------|-------|
| 单行 UPSERT | 更优 — 语法简洁、无 JOIN | 开销大 — 需要构造 USING 子查询 |
| 批量 UPSERT (VALUES 列表) | 良好 — 直接多行 VALUES | 良好 — USING 子查询 |
| 表间批量同步 | INSERT...SELECT + ON CONFLICT（不能删除） | **更优** — USING source_table |
| 需要 DELETE 动作 | 不支持 | 支持 |
| 需要多条件分支 | 不支持 | 支持多 WHEN 子句 |

### 批量 UPSERT 模式

```sql
-- PostgreSQL: 批量 ON CONFLICT（推荐 1000-5000 行/批）
INSERT INTO users (id, name, email)
VALUES (1, 'A', 'a@x.com'),
       (2, 'B', 'b@x.com'),
       (3, 'C', 'c@x.com')
       -- ... 数千行
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    email = EXCLUDED.email;

-- MySQL: 批量 ON DUPLICATE KEY UPDATE
INSERT INTO users (id, name, email)
VALUES (1, 'A', 'a@x.com'),
       (2, 'B', 'b@x.com'),
       (3, 'C', 'c@x.com') AS new_row
ON DUPLICATE KEY UPDATE
    name = new_row.name,
    email = new_row.email;

-- MERGE: 批量同步（从临时表/Staging 表）
MERGE INTO users t
USING staging_users s ON t.id = s.id
WHEN MATCHED THEN UPDATE SET t.name = s.name, t.email = s.email
WHEN NOT MATCHED THEN INSERT (id, name, email) VALUES (s.id, s.name, s.email);
```

### 性能提示

1. **唯一索引是关键**: ON CONFLICT 和 ON DUPLICATE KEY 都依赖唯一索引快速检测冲突。缺少合适索引会显著恶化执行计划。
2. **MERGE 的 ON 条件要走索引**: 确保 target 表的 JOIN 列上有索引，否则性能急剧下降。
3. **避免宽 MERGE**: 只 SET 需要更新的列，不要 SET 所有列（减少 WAL/redo 日志）。
4. **PostgreSQL ON CONFLICT 的 HOT 优化**: 如果更新的列上没有索引，PostgreSQL 可以做 Heap-Only Tuple 优化，不更新索引页。
5. **MySQL ON DUPLICATE KEY 的 deadlock（单行也会！）**: InnoDB 中即使两条相同的单行 `INSERT ... ODKU` 并发执行，也可能死锁——两事务都因唯一键冲突获取共享锁（S Lock），然后都尝试升级为排他锁（X Lock）执行 UPDATE，互相等待导致死锁。这是插入意向锁与间隙锁的结构性冲突，不仅限于批量场景。建议：应用层做好 deadlock 重试逻辑。

## 横向总结

### 应用层单行 UPSERT 推荐写法

| 引擎 | 推荐写法 | 理由 |
|------|---------|------|
| PostgreSQL | `INSERT ... ON CONFLICT DO UPDATE` | 真正原子、支持 RETURNING、语法清晰 |
| MySQL | `INSERT ... ON DUPLICATE KEY UPDATE` | 原子、支持批量 |
| Oracle | `MERGE INTO ... USING DUAL` | 唯一选择 |
| SQL Server | `INSERT + UPDATE`（显式分支） | MERGE 需加 HOLDLOCK 防止并发问题 |
| SQLite | `INSERT ... ON CONFLICT DO UPDATE` | 3.24+ 支持，语法同 PG |
| DuckDB | `INSERT ... ON CONFLICT DO UPDATE` | 0.8.0+ 支持，语法同 PG |
| BigQuery | `MERGE` | 唯一选择 |
| Snowflake | `MERGE` | 唯一选择 |
| CockroachDB | `INSERT ... ON CONFLICT DO UPDATE` | 语法同 PG |
| ClickHouse | ReplacingMergeTree + `INSERT` | 无原子 UPSERT，最终一致去重 |

### 功能对比总表

| 能力 | ON CONFLICT (PG) | ON DUPLICATE KEY (MySQL) | MERGE (标准) | REPLACE INTO |
|------|:-:|:-:|:-:|:-:|
| 行级原子 UPSERT | 支持 | 支持 | 支持 (SQL Server 需 HOLDLOCK) | DELETE+INSERT |
| 跳过冲突行 (DO NOTHING) | `DO NOTHING` | `INSERT IGNORE`（⚠️ 非严格等价 DO NOTHING，IGNORE 会吞掉所有错误） | 省略 WHEN MATCHED 子句 | 不支持 |
| 按条件决定是否更新 | WHERE 子句 | 条件表达式 | WHEN MATCHED AND ... | 不支持 |
| 引用新值 | `EXCLUDED.col` | `VALUES(col)` / 别名 | `s.col` | 不适用 |
| 引用旧值 | `table.col` | `col` | `t.col` | 不适用 |
| DELETE 动作 | 不支持 | 不支持 | 支持 | 不支持 |
| 多条件分支 | 不支持 | 不支持 | 支持多 WHEN | 不支持 |
| RETURNING | 支持 | 不支持 | SQL Server OUTPUT | 不支持 |
| 跨表数据源 | 不支持 | 不支持 | 支持 USING | 不支持 |
| 全量同步 (增删改) | 不支持 | 不支持 | BY SOURCE (部分引擎) | 不支持 |

### 选择决策树

```
需要 UPSERT?
├── 只需跳过重复? → INSERT IGNORE (MySQL) / ON CONFLICT DO NOTHING (PG)
├── 单行/少量行 UPSERT?
│   ├── PG/SQLite/DuckDB/CockroachDB → ON CONFLICT DO UPDATE
│   ├── MySQL/MariaDB/TiDB → ON DUPLICATE KEY UPDATE
│   └── Oracle/BigQuery/Snowflake → MERGE INTO ... USING (单行子查询)
├── 批量表间同步?
│   ├── 只需增+改 → MERGE INTO ... USING source_table
│   └── 需要增+改+删 → MERGE + NOT MATCHED BY SOURCE (SQL Server/BigQuery/Databricks/PG 17+)
├── 分区级全量替换?
│   └── Hive/Spark/Flink/MaxCompute → INSERT OVERWRITE
└── ClickHouse? → ReplacingMergeTree + 接受最终一致性
```

## 参考资料

- PostgreSQL: [INSERT ON CONFLICT](https://www.postgresql.org/docs/current/sql-insert.html)
- PostgreSQL 17: [MERGE NOT MATCHED BY SOURCE](https://www.postgresql.org/docs/17/sql-merge.html)
- MySQL: [INSERT ON DUPLICATE KEY UPDATE](https://dev.mysql.com/doc/refman/8.0/en/insert-on-duplicate.html)
- Oracle: [MERGE](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/MERGE.html)
- SQL Server: [MERGE](https://learn.microsoft.com/en-us/sql/t-sql/statements/merge-transact-sql)
- SQL Server MERGE bugs: [Use Caution with MERGE](https://www.mssqltips.com/sqlservertip/3074/)
- SQLite: [UPSERT](https://www.sqlite.org/lang_upsert.html)
- DuckDB: [INSERT ON CONFLICT](https://duckdb.org/docs/sql/statements/insert.html#on-conflict-clause)
- Databricks: [MERGE INTO](https://docs.databricks.com/en/sql/language-manual/delta-merge-into.html)
