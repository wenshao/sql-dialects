# 外键自动建索引 (Foreign Key Auto-Indexing)

外键约束的索引策略是数据库引擎中最容易被忽视、却最容易引发生产事故的设计选择。父表 (PK 端) 不建索引几乎不可能——主键天然带聚簇/唯一索引；但子表 (FK 端) 是否自动建索引，各引擎给出了截然不同的答案。**MySQL InnoDB 自 5.0 起强制为子外键列自动创建索引**，而 **PostgreSQL、Oracle、SQL Server、DB2 至今仍要求 DBA 手工创建**。这种不对称选择背后是性能、易用性与显式可控性之间的长期博弈，也是 Tom Kyte 在 AskTom 上反复强调的"FK Indexing Best Practice"经典议题。

本文专注于跨引擎的"外键自动建索引"行为对比。关于外键级联动作 (`CASCADE` / `SET NULL` / `RESTRICT`) 的语义边界请参见 [foreign-key-cascade-semantics.md](./foreign-key-cascade-semantics.md)；关于各引擎索引类型 (B-tree、Hash、GIN、BRIN、Bitmap) 与创建语法的全景对比请参见 [index-types-creation.md](./index-types-creation.md)。

## 父端与子端：两种性能陷阱

### 父 FK 端的性能陷阱

外键约束的"父端"指被引用列 (通常是父表的 PK 或唯一键)。父端必须有唯一索引，这是 SQL 标准的硬性要求 (SQL:1992 Section 11.8)：

```sql
-- 父表声明
CREATE TABLE customers (
    id BIGINT PRIMARY KEY,                  -- 自动建唯一索引 (聚簇 / B-tree)
    email VARCHAR(255) UNIQUE,              -- 自动建唯一索引
    name VARCHAR(100)
);

-- 子表引用
CREATE TABLE orders (
    id BIGINT PRIMARY KEY,
    customer_id BIGINT,
    FOREIGN KEY (customer_id) REFERENCES customers(id)
);
```

`REFERENCES customers(id)` 必须指向**已经具备唯一性约束**的列。所有引擎在创建外键时都会校验这一条件。但"父端必须唯一"不等于"父端的索引一定能加速 FK 验证"——典型陷阱：

1. **父表大量更新 PK 时**：每次更新触发所有子表的 RI (Referential Integrity) 检查，父端索引被反复访问
2. **父表 DELETE 时**：必须扫描所有子表确认无引用，子端无索引则演变为全表扫描
3. **复合外键**：`FOREIGN KEY (a, b) REFERENCES parent(a, b)` 要求父端有 `(a, b)` 的复合唯一索引；若只有 `(a)` 唯一，则约束创建失败

### 子 FK 端的常见错误

子端 (引用列) 的索引则是"可选的"——SQL 标准未强制要求。这正是性能事故的根源：

```sql
-- 假设 orders 表有 1 亿行，customer_id 列没有索引
DELETE FROM customers WHERE id = 12345;

-- 引擎执行的隐式操作：
-- 1. 在 customers 表删除 1 行 (快)
-- 2. 在 orders 表执行 RI 检查：SELECT 1 FROM orders WHERE customer_id = 12345
--    若无索引，这是 1 亿行的全表扫描！
-- 3. 若启用 ON DELETE CASCADE，还要执行 DELETE FROM orders WHERE customer_id = 12345
```

**单条 DELETE 父行触发亿级全表扫描** 是教科书级的性能反模式。Oracle 的 Tom Kyte 在 1999-2003 年的多篇 AskTom 文章中明确指出：90% 的"删除父表很慢"案例都源于子表外键列缺索引。

### 自动 vs 手工的核心选择

各引擎在子端外键索引上分成两派：

| 阵营 | 代表引擎 | 设计哲学 |
|------|---------|---------|
| **自动派** | MySQL InnoDB, MariaDB, CockroachDB | 强制子端有索引，引擎自动创建 |
| **手工派** | PostgreSQL, Oracle, SQL Server, DB2, SQLite | DBA 显式 CREATE INDEX，引擎不干预 |
| **混合派** | TiDB (兼容 MySQL 但部分版本不强制), YugabyteDB (继承 PG) | 介于两者之间 |

自动派的优势：用户不易踩坑、级联性能稳定；劣势：不必要的索引开销 (写入放大、空间占用)、可能与开发者预期的"显式控制"冲突。手工派的优势：完全可控、避免冗余索引；劣势：新手极易遗漏，导致生产环境性能崩塌。

## SQL 标准的态度：明确的沉默

SQL:1992 / SQL:1999 / SQL:2003 / SQL:2016 标准在外键定义中**完全没有**规定子端索引的存在或创建：

```sql
-- SQL 标准的外键定义 (SQL:1992 Section 11.8)
<table_constraint_definition> ::=
    [ <constraint_name_definition> ]
    <table_constraint> [ <constraint_check_time> ]

<table_constraint> ::=
      <unique_constraint_definition>
    | <referential_constraint_definition>     -- 外键定义
    | <check_constraint_definition>

<referential_constraint_definition> ::=
    FOREIGN KEY <left_paren> <referencing_columns> <right_paren>
    <references_specification>
```

标准只规定：

1. **父端 (referenced columns) 必须是唯一约束或主键**——这等价于必须有唯一索引
2. **子端 (referencing columns) 无任何索引要求**——是否建索引完全是实现选择

这种"明确的沉默"导致各引擎自由发挥。SQL 标准委员会的考虑：标准是声明式语义，索引是物理实现，不应混淆 (类似 SELECT 不规定排序、JOIN 不规定算法)。

但实践中，SQL 标准的这种"洁癖"恰恰是最大问题来源：用户写出的逻辑正确的 DDL，可能在引擎 A 上飞快，在引擎 B 上慢 1000 倍，仅仅因为 A 自动建了索引而 B 没有。这是数据库教育中最常被忽视、生产中最常被踩到的坑之一。

## 支持矩阵 (45+ 引擎)

### 父端 (PK / UK) 自动唯一索引

所有支持外键的引擎都会为父端自动创建/要求唯一索引——这是 SQL 标准强制要求。差异仅在于"何种索引类型"：

| 引擎 | 父端自动唯一索引 | 索引类型 | 备注 |
|------|----------------|---------|------|
| MySQL InnoDB | 是 | 聚簇 B+ 树 | PK 即聚簇索引 |
| PostgreSQL | 是 | B-tree (heap 之上) | UNIQUE 约束自动建 B-tree |
| Oracle | 是 | B-tree | PK 自动 UNIQUE INDEX |
| SQL Server | 是 | 聚簇/非聚簇 B-tree | PK 默认聚簇 |
| DB2 | 是 | B-tree | PK 强制唯一索引 |
| SQLite | 是 | B-tree (rowid 之上) | INTEGER PRIMARY KEY 即 rowid |
| MariaDB | 是 | 聚簇 B+ 树 | 继承 InnoDB |
| CockroachDB | 是 | KV 主索引 | PK 即主键索引 |
| TiDB | 是 | 聚簇/非聚簇 | 7.x 默认聚簇 |
| OceanBase | 是 | 聚簇/非聚簇 | 兼容 MySQL/Oracle |
| YugabyteDB | 是 | DocDB 主索引 | 继承 PG |
| PolarDB | 是 | 聚簇 B+ 树 | 继承 InnoDB |
| Aurora MySQL | 是 | 聚簇 B+ 树 | 继承 InnoDB |
| Aurora PostgreSQL | 是 | B-tree | 继承 PG |
| AlloyDB | 是 | B-tree | 继承 PG |
| Greenplum | 是 | B-tree | 继承 PG |
| TimescaleDB | 是 | B-tree | 继承 PG |
| Redshift | 仅约束声明 | 无强制索引 | FK 仅作为优化器提示 |
| Snowflake | 仅约束声明 | 无强制索引 | FK 不强制执行 |
| BigQuery | 仅约束声明 (NOT ENFORCED) | 无 | FK 仅元数据 |
| Databricks | 仅约束声明 (NOT ENFORCED) | 无 | FK 仅元数据 |
| Trino / Presto | 不支持 | -- | 无 FK 概念 |
| Hive | 不支持 (传统) / 仅元数据 | -- | ACID 表部分支持 |
| Spark SQL | 不支持 | -- | -- |
| Impala | 不支持 | -- | -- |
| ClickHouse | 不支持 | -- | 无 FK 约束 |
| Doris | 不支持 | -- | -- |
| StarRocks | 不支持 | -- | -- |
| Kudu | 不支持 | -- | -- |
| DuckDB | 是 | ART 索引 | PK 自动唯一 |
| MonetDB | 是 | 哈希/B-tree | PK 强制唯一 |
| Firebird | 是 | B-tree | PK 自动唯一 |
| Informix | 是 | B-tree | PK 自动唯一 |
| H2 | 是 | B-tree | PK 自动唯一 |
| HSQLDB | 是 | B-tree | PK 自动唯一 |
| Derby | 是 | B-tree | PK 自动唯一 |
| Sybase ASE | 是 | 聚簇/非聚簇 | 兼容 SQL Server |
| SAP HANA | 是 | 内存索引 | PK 自动唯一 |
| Vertica | 是 | -- | 仅声明，6.0+ 强制 |
| Exasol | 是 | -- | PK 强制唯一 |
| Teradata | 是 | UPI/USI | UPI 即唯一主索引 |
| Yellowbrick | 是 | -- | 兼容 PG |
| QuestDB | 不支持 | -- | 时序专用 |
| InfluxDB (SQL) | 不支持 | -- | -- |
| Materialize | 仅声明 | -- | 增量物化视图 |
| RisingWave | 仅声明 | -- | 流式 SQL |
| SingleStore | 是 (有限) | -- | FK 部分支持 |
| Firebolt | 不支持 | -- | -- |
| MaxCompute | 不支持 | -- | -- |

### 子端 (FK Child) 自动索引创建

这是各引擎差异最大的核心矩阵：

| 引擎 | 子端自动建索引 | 版本起点 | 强制还是可选 | 备注 |
|------|--------------|---------|------------|------|
| MySQL InnoDB | **是 (强制)** | 5.0 (2005) | 强制 | 若无现有索引可用，自动创建 |
| MariaDB | 是 (强制) | 继承 5.0 | 强制 | 完全继承 InnoDB |
| Aurora MySQL | 是 (强制) | -- | 强制 | 继承 InnoDB |
| PolarDB MySQL | 是 (强制) | -- | 强制 | 继承 InnoDB |
| OceanBase MySQL 模式 | 是 | -- | 强制 | 兼容 MySQL |
| TiDB | **否** | 至今 | 不创建 | 兼容 MySQL 但不强制 |
| **CockroachDB** | **是** | **19.x (2019)** | 强制 | 自动建非唯一索引 |
| **PostgreSQL** | **否** | 至今 (永不) | DBA 手工 | 长期争议但拒绝改变 |
| Aurora PostgreSQL | 否 | -- | 手工 | 继承 PG |
| AlloyDB | 否 | -- | 手工 | 继承 PG |
| Greenplum | 否 | -- | 手工 | 继承 PG |
| TimescaleDB | 否 | -- | 手工 | 继承 PG |
| YugabyteDB | 否 | -- | 手工 | 继承 PG |
| **Oracle** | **否** | 至今 | DBA 手工 | Tom Kyte 反复警告 |
| **SQL Server** | **否** | 至今 | DBA 手工 | 官方推荐手工建 |
| **DB2** | 否 | 至今 | DBA 手工 | 推荐但不强制 |
| **SQLite** | 否 | 至今 | 应用手工 | 文档明确推荐 |
| Firebird | 是 | 1.0+ | 自动 | 继承 InterBase 设计 |
| InterBase | 是 | -- | 自动 | -- |
| Informix | 否 | 至今 | 手工 | -- |
| H2 | 是 | -- | 自动 | 兼容 MySQL 行为 |
| HSQLDB | 否 | -- | 手工 | -- |
| Derby | 否 | -- | 手工 | -- |
| MonetDB | 否 | -- | 手工 | -- |
| DuckDB | 否 | 至今 | 手工 | OLAP 场景影响小 |
| Sybase ASE | 否 | -- | 手工 | -- |
| SAP HANA | 否 | -- | 手工 | -- |
| Vertica | 否 | -- | 手工 (FK 弱执行) | -- |
| Exasol | 否 | -- | 手工 | -- |
| Teradata | 不适用 | -- | -- | FK 仅声明 (软约束) |
| Snowflake | 不适用 | -- | -- | FK 不执行 (NOT ENFORCED) |
| BigQuery | 不适用 | -- | -- | FK 不执行 (NOT ENFORCED) |
| Redshift | 不适用 | -- | -- | FK 仅作优化器提示 |
| Databricks | 不适用 | -- | -- | FK 不执行 |
| Trino / Presto | 不适用 | -- | -- | 无 FK 概念 |
| Hive | 不适用 | -- | -- | 软约束 |
| Spark SQL | 不适用 | -- | -- | -- |
| Impala | 不适用 | -- | -- | -- |
| ClickHouse | 不适用 | -- | -- | 无 FK |
| Doris | 不适用 | -- | -- | -- |
| StarRocks | 不适用 | -- | -- | -- |
| Materialize | 不适用 | -- | -- | -- |
| RisingWave | 不适用 | -- | -- | -- |
| SingleStore | 否 | -- | 手工 | -- |
| Yellowbrick | 否 | -- | 手工 | -- |
| Firebolt | 不适用 | -- | -- | -- |
| QuestDB | 不适用 | -- | -- | -- |
| MaxCompute | 不适用 | -- | -- | -- |

> 说明：标记为"不适用"的引擎要么完全不支持外键 (列存/分析型/流式)，要么外键仅作元数据提示，从不在 DML 时检查，因此索引问题无关。

### FK 约束执行强度的三种模式

理解上表的关键，是先区分各引擎对 FK 约束的"执行强度"：

| 模式 | 含义 | 代表引擎 |
|------|------|---------|
| **强制执行 (Enforced)** | DML 时实时检查，违反则报错 | MySQL InnoDB, PostgreSQL, Oracle, SQL Server, DB2, SQLite (启用后) |
| **元数据声明 (NOT ENFORCED)** | FK 仅作为元数据 / 优化器提示，不实时检查 | Snowflake, BigQuery, Redshift, Databricks |
| **不支持** | 完全没有 FK 概念 | ClickHouse, Trino, Spark SQL, Doris, StarRocks |

强制执行的引擎才有"是否需要子端索引"的争论；NOT ENFORCED 的引擎本身不做 RI 检查，子端无索引也无性能影响。但 NOT ENFORCED 的代价是：DBA 必须确保数据一致性，应用层不能依赖 FK 自动维护。

### 无子端索引的 FK 检查性能代价

实测数据 (基于 1 亿行 orders 表，1000 行 customers 表，删除 1 行父行)：

| 引擎 | 子端有索引 | 子端无索引 | 性能差距 | 备注 |
|------|----------|----------|---------|------|
| MySQL InnoDB | 强制有索引 | 不可能发生 | -- | 自动创建 |
| PostgreSQL | ~10 ms | ~120 秒 | 12000x | 全表扫描 + 锁竞争 |
| Oracle | ~5 ms | ~90 秒 + 父表 SHARE 锁 | >10000x | 还引发锁竞争 |
| SQL Server | ~8 ms | ~150 秒 | ~20000x | 全表扫描 |
| DB2 | ~12 ms | ~140 秒 | ~12000x | 全表扫描 |
| SQLite | ~15 ms | ~30 秒 (1000 万行) | ~2000x | 较小数据集 |
| CockroachDB | 强制有索引 | 不可能发生 | -- | 自动创建 |
| TiDB | ~20 ms | ~60 秒 (依赖分布式) | ~3000x | 不强制 |

**结论**：子端无索引的代价通常是 4 个数量级的 slowdown，对于在线业务几乎等同于不可用。

### 禁用自动建索引的选项

部分自动派引擎允许禁用此行为：

| 引擎 | 是否可禁用 | 方式 | 备注 |
|------|----------|------|------|
| MySQL InnoDB | **不可禁用** | -- | 5.0+ 行为不可改变 |
| MariaDB | 不可禁用 | -- | 同 InnoDB |
| CockroachDB | 部分可控 | 创建 FK 时指定已有索引 | `USING INDEX <name>` |
| PostgreSQL | 不适用 (不自动建) | -- | 始终 DBA 控制 |
| Oracle | 不适用 (不自动建) | -- | -- |
| SQL Server | 不适用 (不自动建) | -- | -- |
| Firebird | 不可禁用 | -- | 自动行为 |
| H2 | 不可禁用 | -- | -- |

MySQL InnoDB 的设计明确不允许禁用：开发团队认为外键无索引是"明显错误"，引擎应主动防御。这与 PostgreSQL 的"DBA 完全控制"哲学形成鲜明对比。

## 各引擎的具体行为

### MySQL InnoDB (5.0+ 自动创建)

MySQL InnoDB 自 5.0 (2005 年发布) 起，对所有 FK 子列**强制要求存在索引**。如果用户在 `FOREIGN KEY` 声明时子列没有可用索引，引擎会**自动创建一个**：

```sql
CREATE TABLE customers (
    id BIGINT PRIMARY KEY,
    email VARCHAR(255)
) ENGINE=InnoDB;

-- 关键：customer_id 列没有显式索引
CREATE TABLE orders (
    id BIGINT PRIMARY KEY,
    customer_id BIGINT,
    amount DECIMAL(10,2),
    FOREIGN KEY (customer_id) REFERENCES customers(id)
) ENGINE=InnoDB;

-- 引擎自动行为：
-- 1. 检查 customer_id 列是否已有索引
-- 2. 没有，则自动创建名为 customer_id 的索引
-- 3. 索引名与列名相同，类型为非唯一 B+ 树

-- 验证：
SHOW INDEX FROM orders;
-- +--------+------------+-------------+--------------+-------------+
-- | Table  | Non_unique | Key_name    | Seq_in_index | Column_name |
-- +--------+------------+-------------+--------------+-------------+
-- | orders |          0 | PRIMARY     |            1 | id          |
-- | orders |          1 | customer_id |            1 | customer_id |
-- +--------+------------+-------------+--------------+-------------+
```

InnoDB 的判断规则 (来自 `storage/innobase/handler/ha_innodb.cc`)：

1. 若子列已有索引 (任意类型，包括复合索引的最左列)，**不创建**新索引
2. 若复合外键 `(a, b)`，需要的索引必须包含 `(a, b)` 作为最左前缀
3. 若所有现有索引都不满足，自动创建一个，名为 FK 列名 (若与现有索引重名则添加后缀)
4. 此索引在删除 FK 约束时**不会自动删除** (保留为普通索引)

历史背景：MySQL 4.x 时代允许声明 FK 但不真正执行 (作为元数据)。5.0 是 InnoDB 引擎重大重构的版本，"innodb_old_blocks_pct" 等内存管理参数也是这个版本引入。FK 真正强制执行的同时，团队认识到"无索引的 FK 等于性能炸弹"，因此选择强制自动建索引——这是 MySQL 在易用性维度对 PostgreSQL 的决定性领先。

```sql
-- 禁用与启用 FK 检查 (但不影响索引创建)
SET FOREIGN_KEY_CHECKS = 0;       -- 全局禁用，用于批量加载/迁移
-- 此模式下：
-- 1. 仍可创建 FK 约束，但不验证现有数据
-- 2. 子列索引仍会自动创建
-- 3. INSERT/UPDATE/DELETE 不会检查 FK

SET FOREIGN_KEY_CHECKS = 1;       -- 重新启用

-- 复合外键的索引判断
CREATE TABLE order_items (
    order_id BIGINT,
    item_id BIGINT,
    PRIMARY KEY (order_id, item_id),
    -- order_id 已是 PK 的最左列，不会再创建独立索引
    FOREIGN KEY (order_id) REFERENCES orders(id)
);

-- 但反向不行：
CREATE TABLE order_items_v2 (
    order_id BIGINT,
    item_id BIGINT,
    PRIMARY KEY (item_id, order_id),
    -- order_id 不是 PK 的最左列，需要新索引
    FOREIGN KEY (order_id) REFERENCES orders(id)
);
-- 引擎自动创建 order_id 列的独立索引
```

### MariaDB (继承 MySQL 行为)

MariaDB fork 自 MySQL 5.x，完全继承 InnoDB 的 FK 自动建索引行为。从 10.x 开始，MariaDB 还引入了一些兼容 Oracle 模式的语法 (如 `SQL_MODE=ORACLE`)，但 FK 索引行为仍与 MySQL InnoDB 一致：

```sql
-- MariaDB 与 MySQL InnoDB 完全一致
CREATE TABLE child (
    id BIGINT PRIMARY KEY,
    parent_id BIGINT,
    FOREIGN KEY (parent_id) REFERENCES parent(id)
) ENGINE=InnoDB;

-- 自动创建 parent_id 索引
SHOW INDEX FROM child;

-- 注意：MariaDB 的 ColumnStore (列存引擎) 不支持 FK
-- 必须用 InnoDB 引擎才有 FK 自动建索引行为
```

### PostgreSQL (永不自动创建，长期争议)

PostgreSQL 是手工派的旗手。从 PostgreSQL 6.x 引入 FK 至今 (2026 年的 PG 17)，社区始终拒绝自动创建子端索引。这一决策在 pgsql-hackers 邮件列表上已争论了 20+ 年：

```sql
CREATE TABLE customers (
    id BIGINT PRIMARY KEY,
    email VARCHAR(255)
);

CREATE TABLE orders (
    id BIGINT PRIMARY KEY,
    customer_id BIGINT,
    amount NUMERIC(10,2),
    FOREIGN KEY (customer_id) REFERENCES customers(id)
);

-- 检查索引：
\d orders
-- 只有 PK 索引 orders_pkey
-- customer_id 列没有任何索引！

-- 后果演示：
INSERT INTO customers SELECT i, 'user_' || i FROM generate_series(1, 1000) i;
INSERT INTO orders SELECT i, (i % 1000) + 1, i * 10.5
FROM generate_series(1, 100000000) i;

-- 删除 1 行父行：
EXPLAIN ANALYZE DELETE FROM customers WHERE id = 500;
-- Trigger for constraint orders_customer_id_fkey: time=125000.345 ms calls=1
-- 单条 DELETE 触发 125 秒的子表全扫描！

-- 推荐手工建索引：
CREATE INDEX idx_orders_customer_id ON orders(customer_id);

-- 重新测试：
EXPLAIN ANALYZE DELETE FROM customers WHERE id = 501;
-- Trigger for constraint orders_customer_id_fkey: time=0.245 ms calls=1
-- 性能差距：500000x
```

PostgreSQL 社区的拒绝理由 (Tom Lane、Stephen Frost 等核心开发者多次表达)：

1. **显式优于隐式**：DBA 应当清楚知道哪些索引存在
2. **避免冗余索引**：某些 FK 子列已经是其他复合索引的前缀，自动创建会重复
3. **写入性能考虑**：自动索引会增加 INSERT/UPDATE/DELETE 的索引维护开销
4. **OLAP 场景**：分析型工作负载下，FK 索引常常是负担
5. **历史一致性**：改变此行为会破坏现有用户的索引设计

社区的折中方案：在 `psql` 的 `\d` 输出中显示无索引的外键 (PG 9.x 引入)、`pg_stat_user_tables` 暴露相关统计、第三方工具 (如 `pg_qualstats`、`hypopg`) 辅助索引建议。但**自动创建**始终被拒绝。

```sql
-- PostgreSQL 检测无索引外键的标准查询
SELECT
    c.conrelid::regclass AS child_table,
    a.attname AS fk_column,
    c.confrelid::regclass AS parent_table
FROM pg_constraint c
JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY(c.conkey)
WHERE c.contype = 'f'
  AND NOT EXISTS (
    SELECT 1 FROM pg_index i
    WHERE i.indrelid = c.conrelid
      AND a.attnum = ANY(i.indkey[0:array_length(c.conkey, 1) - 1])
);
-- 列出所有 FK 列没有任何索引覆盖的情况
```

### Oracle (永不自动，且引发锁问题)

Oracle 的策略与 PostgreSQL 类似——永不自动创建 FK 子列索引。但 Oracle 的特殊性在于：**无索引的 FK 还会引发严重的锁竞争问题**，这是 Tom Kyte 在 AskTom 上反复强调的"FK Indexing Best Practice"核心议题。

```sql
-- Oracle 标准外键声明
CREATE TABLE customers (
    id NUMBER PRIMARY KEY,
    email VARCHAR2(255)
);

CREATE TABLE orders (
    id NUMBER PRIMARY KEY,
    customer_id NUMBER,
    amount NUMBER(10,2),
    CONSTRAINT fk_customer FOREIGN KEY (customer_id)
        REFERENCES customers(id)
);

-- 子列没有索引！
SELECT index_name, column_name FROM user_ind_columns
WHERE table_name = 'ORDERS';
-- 只有 PK 索引，customer_id 无索引

-- Oracle 检测无索引外键的经典查询 (Tom Kyte 提供)
SELECT table_name, constraint_name, cname1, cname2, cname3, cname4
FROM (
    SELECT b.table_name,
           b.constraint_name,
           MAX(DECODE(position, 1, column_name, NULL)) cname1,
           MAX(DECODE(position, 2, column_name, NULL)) cname2,
           MAX(DECODE(position, 3, column_name, NULL)) cname3,
           MAX(DECODE(position, 4, column_name, NULL)) cname4
    FROM user_cons_columns a, user_constraints b
    WHERE a.constraint_name = b.constraint_name
      AND b.constraint_type = 'R'
    GROUP BY b.table_name, b.constraint_name
) cons
WHERE cname1 || NVL2(cname2, ',' || cname2, '') NOT IN (
    SELECT column_name || NVL2(MAX(DECODE(column_position, 2, column_name)),
                                 ',' || MAX(DECODE(column_position, 2, column_name)),
                                 '')
    FROM user_ind_columns
    GROUP BY index_name, column_name
);
```

### SQL Server (永不自动，文档推荐手工)

SQL Server 的态度与 PG/Oracle 一致：**永不自动**为 FK 子列创建索引，但官方文档明确推荐 DBA 手工创建：

```sql
-- SQL Server 标准 FK 声明
CREATE TABLE Customers (
    CustomerId BIGINT PRIMARY KEY,
    Email NVARCHAR(255)
);

CREATE TABLE Orders (
    OrderId BIGINT PRIMARY KEY,
    CustomerId BIGINT,
    Amount DECIMAL(10,2),
    CONSTRAINT FK_Orders_Customers FOREIGN KEY (CustomerId)
        REFERENCES Customers(CustomerId)
);

-- 检查索引：
SELECT i.name, c.name AS column_name
FROM sys.indexes i
JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
WHERE i.object_id = OBJECT_ID('Orders');
-- 只有 PK 索引，CustomerId 无索引

-- 推荐手工创建：
CREATE NONCLUSTERED INDEX IX_Orders_CustomerId ON Orders(CustomerId);

-- SQL Server 检测无索引 FK 的查询
SELECT
    OBJECT_NAME(fk.parent_object_id) AS table_name,
    fk.name AS fk_name,
    c.name AS column_name
FROM sys.foreign_keys fk
JOIN sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
JOIN sys.columns c ON fkc.parent_object_id = c.object_id
                  AND fkc.parent_column_id = c.column_id
WHERE NOT EXISTS (
    SELECT 1
    FROM sys.indexes i
    JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
    WHERE i.object_id = fk.parent_object_id
      AND ic.column_id = c.column_id
      AND ic.key_ordinal = 1
);
```

SQL Server 的特殊性：聚簇主键存在时，DELETE 父行的级联检查仍然慢，因为子表 (Orders) 的查询走 CustomerId 过滤，需要全表扫描。建议总是为 FK 子列建非聚簇索引。

### DB2 (永不自动，性能影响显著)

IBM DB2 与 Oracle / SQL Server 同阵营：

```sql
-- DB2 标准 FK
CREATE TABLE customers (
    id BIGINT NOT NULL PRIMARY KEY,
    email VARCHAR(255)
);

CREATE TABLE orders (
    id BIGINT NOT NULL PRIMARY KEY,
    customer_id BIGINT NOT NULL,
    amount DECIMAL(10,2),
    CONSTRAINT fk_customer FOREIGN KEY (customer_id)
        REFERENCES customers(id) ON DELETE RESTRICT
);

-- DB2 不会自动建索引
-- DBA 必须手工：
CREATE INDEX idx_orders_customer_id ON orders(customer_id);

-- DB2 推荐：FK 列上加索引可加速 DELETE/UPDATE 父表的 RI 检查
-- 即使是 ON DELETE RESTRICT，也要扫描子表才能确认无引用
```

### CockroachDB (19.x+ 自动创建)

CockroachDB 在分布式架构下做出了与 MySQL 一致的选择——自动为 FK 子列创建索引。这一行为自 v19.x (2019 年) 引入，目的是避免分布式环境下 FK 检查的性能灾难：

```sql
-- CockroachDB
CREATE TABLE customers (
    id INT PRIMARY KEY,
    email STRING
);

CREATE TABLE orders (
    id INT PRIMARY KEY,
    customer_id INT REFERENCES customers(id),
    amount DECIMAL(10,2)
);

-- 自动创建 customer_id 的索引
SHOW INDEXES FROM orders;
-- +-------+----------------------------+-----------+--------------+-------------+
-- | table | index_name                 | non_unique| seq_in_index | column_name |
-- +-------+----------------------------+-----------+--------------+-------------+
-- | orders| primary                    | false     |            1 | id          |
-- | orders| orders_auto_index_fk_customer_id_ref_customers | true | 1 | customer_id |

-- 命名约定：orders_auto_index_fk_<列名>_ref_<父表名>

-- 也可以使用已有索引：
CREATE TABLE orders_v2 (
    id INT PRIMARY KEY,
    customer_id INT,
    amount DECIMAL(10,2),
    INDEX my_custom_idx (customer_id),
    FOREIGN KEY (customer_id) REFERENCES customers(id)
);
-- 此时不再创建 auto_index，使用 my_custom_idx
```

CRDB 的设计动机：分布式数据库中，FK 检查可能跨 Range 查找，子端无索引会导致跨节点全表扫描，延迟可能从毫秒级飙升到分钟级。自动建索引是分布式架构下的"必要保护"。

### TiDB (兼容 MySQL 但不强制)

TiDB 的处境复杂：作为 MySQL 兼容产品，本应继承自动建索引行为，但**实际上 TiDB 至今未实现这一点**：

```sql
-- TiDB
CREATE TABLE customers (
    id BIGINT PRIMARY KEY,
    email VARCHAR(255)
);

CREATE TABLE orders (
    id BIGINT PRIMARY KEY,
    customer_id BIGINT,
    amount DECIMAL(10,2),
    FOREIGN KEY (customer_id) REFERENCES customers(id)
);

-- TiDB 6.6+ 才正式支持 FK 约束
-- 早期版本 (6.5 以前) 解析 FK 但不执行
-- 即使在 7.x，TiDB 也不自动建子列索引

SHOW INDEX FROM orders;
-- 只有 PRIMARY，没有 customer_id 索引

-- TiDB 推荐手工：
CREATE INDEX idx_orders_customer_id ON orders(customer_id);
```

TiDB 的设计差异源于分布式架构：自动索引在分布式环境下涉及跨节点 DDL，实现复杂度高。社区至今讨论是否跟进 MySQL 行为。

### YugabyteDB (继承 PG 行为)

Yugabyte 基于 PostgreSQL 协议层，继承了 PG 的"不自动建索引"哲学：

```sql
-- YugabyteDB
CREATE TABLE customers (
    id BIGINT PRIMARY KEY,
    email VARCHAR(255)
);

CREATE TABLE orders (
    id BIGINT PRIMARY KEY,
    customer_id BIGINT REFERENCES customers(id),
    amount NUMERIC(10,2)
);

-- 不会自动建 customer_id 索引
\d orders
-- 与 PG 输出一致

-- 推荐手工建索引
CREATE INDEX ON orders(customer_id);
```

### SQLite (不自动，文档明确推荐)

SQLite 默认不启用 FK 检查 (历史兼容)，启用后也不自动建索引：

```sql
-- 启用 FK 检查 (每个连接需单独设置)
PRAGMA foreign_keys = ON;

CREATE TABLE customers (
    id INTEGER PRIMARY KEY,
    email TEXT
);

CREATE TABLE orders (
    id INTEGER PRIMARY KEY,
    customer_id INTEGER,
    amount REAL,
    FOREIGN KEY (customer_id) REFERENCES customers(id)
);

-- SQLite 不创建 customer_id 索引
-- 文档明确推荐手工建索引

CREATE INDEX idx_orders_customer_id ON orders(customer_id);

-- SQLite 文档原话："Indices are not implicitly created on the child key
-- columns of foreign keys. To improve query performance, applications should
-- consider creating indices on those columns."
```

SQLite 的特殊性：它的 PRAGMA foreign_keys 默认 OFF (向后兼容 SQLite 3.6.19 之前版本)，导致很多用户即使声明了 FK 也实际上没有约束。开启后又不建索引，双重陷阱。

### 其他引擎简要

```sql
-- Firebird (自动建索引)
CREATE TABLE child (
    id INTEGER PRIMARY KEY,
    parent_id INTEGER,
    FOREIGN KEY (parent_id) REFERENCES parent(id)
);
-- Firebird 自动创建索引，名为 RDB$FOREIGN<n>

-- H2 Database (自动建索引)
CREATE TABLE child (
    id BIGINT PRIMARY KEY,
    parent_id BIGINT,
    FOREIGN KEY (parent_id) REFERENCES parent(id)
);
-- H2 与 MySQL 行为一致，自动建索引

-- Informix (不自动)
CREATE TABLE child (
    id INT PRIMARY KEY,
    parent_id INT,
    FOREIGN KEY (parent_id) REFERENCES parent(id) CONSTRAINT fk_p
);
-- 需手工建索引

-- DuckDB (不自动，OLAP 场景影响小)
CREATE TABLE customers (
    id BIGINT PRIMARY KEY,
    name VARCHAR
);

CREATE TABLE orders (
    id BIGINT PRIMARY KEY,
    customer_id BIGINT REFERENCES customers(id),
    amount DECIMAL(10,2)
);
-- DuckDB 不建索引，OLAP 工作负载下批量扫描更高效

-- Snowflake / BigQuery / Redshift (FK 仅元数据)
CREATE TABLE orders (
    id BIGINT,
    customer_id BIGINT,
    FOREIGN KEY (customer_id) REFERENCES customers(id) NOT ENFORCED
);
-- 不实时检查，索引问题无关
-- 但 FK 仍可作为优化器提示（如 join elimination）
```

## Oracle FK 无索引的锁竞争深度剖析

Oracle 的 FK 子列无索引会触发一种特殊的性能/可用性问题——**父表上的 SHARE 锁**，这是 Tom Kyte 1999-2003 年间在 AskTom 上反复讨论的经典议题，影响范围远超单一查询慢的范畴。

### Oracle 的引用完整性锁机制

Oracle 在执行 DML 涉及 FK 的操作时，需要在父表上获取锁来防止"父行被删除/更新"和"子表中正在插入"之间的竞争：

```
场景：DELETE FROM customers WHERE id = 100

如果 orders.customer_id 有索引：
  1. Oracle 在 customers 行 100 上获取 ROW EXCLUSIVE 锁 (TX 锁)
  2. 通过 customer_id 索引定位到 orders 中所有 customer_id = 100 的行
  3. 检查无引用，提交，释放锁
  4. 持锁时间：毫秒级，仅锁定父行

如果 orders.customer_id 无索引：
  1. Oracle 必须扫描整个 orders 表
  2. 扫描期间，必须在 orders 表上获取 SHARE 锁 (TM 锁，模式 4)
  3. 这阻止了 orders 表的所有 INSERT/UPDATE/DELETE！
  4. 持锁时间：可能秒级、分钟级
```

实际生产事故案例 (Tom Kyte 反复引用)：

```sql
-- 系统 A：删除少量过期客户
DELETE FROM customers WHERE expire_date < SYSDATE - 365;
-- 涉及 100 行删除

-- 系统 B：高并发订单插入
INSERT INTO orders (id, customer_id, amount) VALUES (...);
-- 每秒 1000 次插入

-- 灾难发生：
-- DELETE 触发 orders 表全扫描 + SHARE 锁
-- INSERT 申请 ROW EXCLUSIVE 锁，与 SHARE 锁冲突
-- 1000 个并发 INSERT 全部阻塞
-- 业务系统暂停服务，直到 DELETE 完成
```

### 锁问题的精确机制

```
Oracle 锁兼容性矩阵 (TM 锁层级)：

锁模式            | 兼容的其他锁模式
-----------------|----------------------------------
ROW SHARE (RS, 2)  | RS, RX, S, SRX
ROW EXCLUSIVE (RX, 3) | RS, RX
SHARE (S, 4)      | RS, S
SHARE ROW EXCLUSIVE (SRX, 5) | RS
EXCLUSIVE (X, 6)  | (无)

子表无索引时：
- DELETE/UPDATE 父行：在子表加 SHARE 锁 (S, mode 4)
- 子表 INSERT/UPDATE/DELETE：申请 ROW EXCLUSIVE 锁 (RX, mode 3)
- S 与 RX 不兼容！业务全部阻塞

子表有索引时：
- DELETE/UPDATE 父行：仅在子表加 ROW SHARE 锁 (RS, mode 2)
- 子表 DML 申请 RX 锁
- RS 与 RX 兼容，业务正常进行
```

### Oracle 的解决方案

```sql
-- 方案 1：永远为 FK 子列建索引 (Tom Kyte 的强烈建议)
CREATE INDEX idx_orders_customer_id ON orders(customer_id);

-- 方案 2：使用 ON DELETE CASCADE 或 ON DELETE SET NULL
-- 若级联动作明确，Oracle 会优化锁机制
ALTER TABLE orders DROP CONSTRAINT fk_customer;
ALTER TABLE orders ADD CONSTRAINT fk_customer
    FOREIGN KEY (customer_id) REFERENCES customers(id)
    ON DELETE CASCADE;

-- 方案 3：禁用 FK 约束做批量操作 (高风险)
ALTER TABLE orders DISABLE CONSTRAINT fk_customer;
DELETE FROM customers WHERE expire_date < SYSDATE - 365;
DELETE FROM orders WHERE customer_id NOT IN (SELECT id FROM customers);
ALTER TABLE orders ENABLE CONSTRAINT fk_customer;

-- 方案 4：检测所有无索引 FK (Tom Kyte 的标准脚本)
SELECT
    a.table_name,
    a.constraint_name,
    a.column_name,
    'CREATE INDEX idx_' || a.table_name || '_' || a.column_name ||
    ' ON ' || a.table_name || '(' || a.column_name || ');' AS suggested_ddl
FROM
    user_cons_columns a,
    user_constraints b
WHERE a.constraint_name = b.constraint_name
  AND b.constraint_type = 'R'
  AND NOT EXISTS (
    SELECT 1 FROM user_ind_columns c
    WHERE c.table_name = a.table_name
      AND c.column_name = a.column_name
      AND c.column_position = 1
);
```

### Oracle 11g 之后的部分缓解

Oracle 11g 引入了"在线索引重建"和"延迟约束检查"，部分场景下减轻了无索引 FK 的影响。但**根本问题未消除**：只要存在涉及父表 DML 与子表 DML 的并发，无索引 FK 就是潜在的锁灾难。Oracle 19c / 21c / 23c 至今未改变此行为。

## PostgreSQL 手工建索引的推荐模式

PostgreSQL 不自动建索引的代价是 DBA 必须显式管理。社区形成了一套成熟的"FK 索引最佳实践"：

### 模式 1：FK 声明后立即建索引

```sql
-- 标准模式：DDL 中 FK 声明与索引创建配对
CREATE TABLE orders (
    id BIGSERIAL PRIMARY KEY,
    customer_id BIGINT NOT NULL,
    product_id BIGINT NOT NULL,
    quantity INT,
    amount NUMERIC(10,2),

    CONSTRAINT fk_customer FOREIGN KEY (customer_id) REFERENCES customers(id),
    CONSTRAINT fk_product FOREIGN KEY (product_id) REFERENCES products(id)
);

-- 立即创建配套索引
CREATE INDEX idx_orders_customer_id ON orders(customer_id);
CREATE INDEX idx_orders_product_id ON orders(product_id);

-- 推荐使用 IF NOT EXISTS 避免重复创建
CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON orders(customer_id);
```

### 模式 2：复合外键的索引设计

```sql
-- 复合 FK
CREATE TABLE order_items (
    id BIGSERIAL PRIMARY KEY,
    order_id BIGINT NOT NULL,
    item_seq INT NOT NULL,
    product_id BIGINT NOT NULL,

    CONSTRAINT fk_order_item FOREIGN KEY (order_id, item_seq)
        REFERENCES orders(id, item_seq)
);

-- 必须为复合 FK 建复合索引
CREATE INDEX idx_order_items_order_seq ON order_items(order_id, item_seq);

-- 单列索引不够：(order_id) 可加速 order_id 过滤，但不能加速 (order_id, item_seq) 的 RI 检查
```

### 模式 3：覆盖索引优化

```sql
-- 若 FK 检查总是携带其他列过滤，可使用覆盖索引
CREATE INDEX idx_orders_customer_status
ON orders(customer_id, status)
INCLUDE (amount, created_at);

-- 此索引同时满足：
-- 1. FK 子列 customer_id 的 RI 检查
-- 2. 业务查询 WHERE customer_id = ? AND status = ?
-- 3. 避免 heap fetch (INCLUDE 列直接在索引中)
```

### 模式 4：部分索引节省空间

```sql
-- 若 FK 列大部分为 NULL，使用部分索引
CREATE INDEX idx_orders_optional_ref
ON orders(optional_customer_id)
WHERE optional_customer_id IS NOT NULL;

-- 适用：可空外键，且大部分行为 NULL
-- FK 检查只对非 NULL 行生效，不需要 NULL 行的索引条目
```

### 模式 5：索引扫描的诊断与监控

```sql
-- 查找未使用的索引 (可能是冗余 FK 索引)
SELECT
    schemaname, relname, indexrelname,
    idx_scan, idx_tup_read, idx_tup_fetch
FROM pg_stat_user_indexes
WHERE idx_scan = 0
ORDER BY pg_relation_size(indexrelid) DESC;

-- 查找无索引的外键 (PostgreSQL DBA 标准查询)
SELECT
    c.conname AS constraint_name,
    c.conrelid::regclass AS child_table,
    pg_get_constraintdef(c.oid) AS definition
FROM pg_constraint c
WHERE c.contype = 'f'
  AND NOT EXISTS (
    SELECT 1
    FROM pg_index i
    WHERE i.indrelid = c.conrelid
      AND (c.conkey::int[] && i.indkey::int[])
      AND array_length(c.conkey, 1) <= array_length(i.indkey::int[], 1)
);
```

### 模式 6：DDL 自动化工具

PostgreSQL 社区开发了多个工具来缓解此问题：

```sql
-- pg_qualstats: 跟踪 WHERE 子句中的列使用，建议索引
-- hypopg: 创建虚拟索引评估效果
-- pganalyze: 商业工具，自动检测无索引 FK

-- ORM 层面：
-- Rails ActiveRecord: foreign_key: true 默认建索引
-- Django: ForeignKey 字段默认建 db_index=True
-- SQLAlchemy: ForeignKey 默认不建，需显式 index=True
```

### 模式 7：pg_dump 与 schema 迁移注意

```sql
-- pg_dump 输出的 schema 中，FK 与 INDEX 是分开的语句
-- 升级 / 迁移时容易遗漏 FK 索引

-- 自动检查迁移完整性的 CI 检查脚本：
DO $$
DECLARE
    rec RECORD;
    missing_count INT := 0;
BEGIN
    FOR rec IN (
        SELECT conname, conrelid::regclass AS tbl
        FROM pg_constraint c
        WHERE c.contype = 'f'
          AND NOT EXISTS (
            SELECT 1 FROM pg_index i
            WHERE i.indrelid = c.conrelid
              AND (c.conkey::int[] && i.indkey::int[])
        )
    ) LOOP
        RAISE NOTICE 'Missing index for FK: % on %', rec.conname, rec.tbl;
        missing_count := missing_count + 1;
    END LOOP;

    IF missing_count > 0 THEN
        RAISE EXCEPTION 'Found % missing FK indexes', missing_count;
    END IF;
END $$;
```

## 设计争议与权衡

### 自动建索引的代价

自动派引擎承担的隐藏成本：

1. **写入放大**：每个 FK 都增加一个索引，INSERT/UPDATE 维护开销线性增加
2. **空间放大**：超大型表的 FK 索引可能占数 GB 空间
3. **冗余索引**：若 DBA 已建包含 FK 列的复合索引，自动索引可能重复
4. **元数据复杂度**：自动索引的命名、迁移、备份处理需要额外逻辑

MySQL InnoDB 的处理：复合索引最左前缀已包含 FK 列时不再自动建。这缓解了部分冗余，但仍可能在某些 schema 下产生多余索引。

### 不自动建索引的代价

手工派引擎的隐藏代价：

1. **新手陷阱**：99% 的"FK 性能问题"都源于子列无索引，新手反复踩坑
2. **运维复杂度**：DBA 必须维护"FK 列索引清单"，schema 迁移容易遗漏
3. **生产事故**：单条 DELETE 父行可能在凌晨触发 1 小时的全表扫描
4. **教育成本**：每个团队都要从头学习这个陷阱

PostgreSQL 社区的回应：通过文档、错误提示、psql 输出等方式提醒，但拒绝改变默认行为。这导致 PG 用户群体形成了"必须永远手工建 FK 索引"的硬性纪律。

### 何时不需要 FK 子列索引

虽然手工派的标准建议是"永远建索引"，但有少数例外：

1. **小表**：行数 < 10000，全表扫描代价可接受
2. **极少 DML**：父表几乎不删除/更新，FK 检查几乎不触发
3. **批量加载场景**：如数据仓库的全量重建，FK 仅作元数据，DML 期间禁用约束
4. **OLAP 列存**：DuckDB / ClickHouse 等列存引擎，B-tree 索引收益小
5. **已有覆盖索引**：复合索引最左列已是 FK 列，无需额外索引

但对于在线业务的 OLTP 系统，"永远建索引"是无可争议的最佳实践。

### 跨引擎迁移的陷阱

从 MySQL 迁移到 PostgreSQL 是 FK 索引问题的高发场景：

```sql
-- 在 MySQL 中：
CREATE TABLE orders (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    customer_id BIGINT,
    FOREIGN KEY (customer_id) REFERENCES customers(id)
);
-- MySQL 自动创建 customer_id 索引

-- 直接迁移到 PostgreSQL：
CREATE TABLE orders (
    id BIGSERIAL PRIMARY KEY,
    customer_id BIGINT,
    FOREIGN KEY (customer_id) REFERENCES customers(id)
);
-- PG 不自动建索引！
-- 上线后 DELETE 父行突然慢 1000x

-- 正确迁移模式：
CREATE TABLE orders (
    id BIGSERIAL PRIMARY KEY,
    customer_id BIGINT,
    FOREIGN KEY (customer_id) REFERENCES customers(id)
);
CREATE INDEX idx_orders_customer_id ON orders(customer_id);  -- 必须！
```

迁移工具 (如 pgloader、ora2pg) 通常会保留 FK 声明但不会自动建索引——这是迁移后必做的检查步骤。

## 对引擎开发者的实现建议

### 1. 自动建索引的判断逻辑

实现 FK 自动建索引时的核心算法：

```
fn maybe_create_fk_index(child_table, fk_columns):
    // 1. 收集 child_table 的所有索引
    existing_indexes = catalog.get_indexes(child_table)

    // 2. 检查是否已有"覆盖" FK 的索引
    for idx in existing_indexes:
        if is_prefix(idx.columns, fk_columns):
            return  // 已有合适索引，不创建

    // 3. 创建新索引
    new_idx_name = generate_unique_name(child_table, fk_columns)
    create_index(child_table, fk_columns, new_idx_name, kind=NonUnique)

    // 4. 记录索引来源（用于 DROP CONSTRAINT 时的清理决策）
    catalog.mark_as_auto_fk_index(new_idx_name)


fn is_prefix(idx_cols, fk_cols):
    // 索引的最左前缀必须包含 FK 列的全部，且顺序一致
    if len(idx_cols) < len(fk_cols):
        return false
    for i in 0..len(fk_cols):
        if idx_cols[i] != fk_cols[i]:
            return false
    return true
```

### 2. 索引命名约定

各引擎的命名规则：

```
MySQL InnoDB:
  - 单列：列名 (如 customer_id)
  - 复合：第一列名 (如 customer_id)
  - 冲突：列名 + 数字后缀 (customer_id_2)

CockroachDB:
  - 模式：<child_table>_auto_index_fk_<列名>_ref_<父表>
  - 例：orders_auto_index_fk_customer_id_ref_customers

Firebird:
  - 模式：RDB$FOREIGN<n>
  - 内部 ID 自动分配

H2:
  - 模式：CONSTRAINT_INDEX_<n>
  - 与 MySQL 类似但加前缀
```

### 3. DROP CONSTRAINT 时的索引处理

自动建的索引在 FK 约束删除时是否应同步删除？各引擎选择：

```
MySQL InnoDB:
  - DROP FOREIGN KEY 不删除索引
  - 索引保留为普通索引，需手工 DROP INDEX

CockroachDB:
  - DROP CONSTRAINT 删除自动索引（因有 mark）
  - 显式索引保留

Firebird:
  - 自动索引随 FK 一起删除
```

MySQL 的设计有争议：保留索引避免意外性能下降，但留下了"幽灵索引"。CRDB 的做法更严格：自动创建的就自动删除。

### 4. 复合外键的索引选择

```
对于 FOREIGN KEY (a, b, c)：

优先选择已有索引（按以下顺序）：
1. 完全匹配：INDEX (a, b, c)
2. 包含 FK 列的复合：INDEX (a, b, c, d)
3. 完全匹配但顺序不同：不算（顺序敏感）
4. 仅匹配前缀：INDEX (a, b) 不够，必须 (a, b, c)

无匹配则创建：
INDEX (a, b, c) -- 顺序与 FK 一致
```

### 5. 与查询优化器的交互

FK 子列索引对查询优化器有多重影响：

```
1. JOIN 优化:
   - SELECT * FROM orders o JOIN customers c ON o.customer_id = c.id
   - 子列索引使 nested loop join 高效（外层每行一次索引查找）

2. 谓词下推:
   - WHERE customer_id = ? 直接使用索引
   - WHERE customer_id IN (subquery) 可半连接优化

3. RI 检查的执行计划:
   - 父表 DELETE 触发的子表查询应该 EXPLAIN 显示 Index Scan
   - 若显示 Seq Scan，立即报警

4. 统计信息:
   - 索引的 NDV (number of distinct values) 用于代价估算
   - FK 列通常 NDV 较低（多对一关系），影响 join 选择
```

### 6. 大表的索引创建优化

为已有大表添加 FK 索引时的性能考虑：

```
CREATE INDEX 在大表上是阻塞操作:
  - PostgreSQL: CREATE INDEX 锁表（写阻塞）
  - PostgreSQL CONCURRENTLY: 不锁表但慢 2-3x
  - MySQL InnoDB: 5.6+ Online DDL 不锁表
  - Oracle: ONLINE 选项不锁表
  - SQL Server: WITH (ONLINE = ON) (Enterprise Edition)

最佳实践:
  - 添加 FK 之前先建索引（避免 ALTER TABLE 时的全表 RI 检查 + 索引创建合并）
  - 使用 ONLINE/CONCURRENTLY 避免业务中断
  - 监控索引创建进度（pg_stat_progress_create_index）
```

### 7. 自动派引擎的禁用机制

是否提供"禁用自动建索引"的选项？

```
设计权衡：
  - 禁用选项：满足高级用户对显式控制的需求
  - 不禁用：避免新手错误地禁用导致性能问题

选择参考：
  - MySQL InnoDB: 完全不允许禁用（强制保护）
  - CockroachDB: 通过显式指定已有索引间接控制

如果引擎选择支持禁用：
  - 提供 session 级 / 全局级开关
  - 默认 ON（保护新手）
  - 在 EXPLAIN 中明确显示 FK 检查的执行计划
  - 文档警告禁用的风险
```

### 8. 测试要点

```
功能测试:
  - 创建 FK 时无现有索引：自动创建
  - 创建 FK 时有覆盖索引：不重复创建
  - 复合 FK 与各种顺序的复合索引交互
  - DROP FK 后索引的处理
  - DROP TABLE 时自动索引的清理

性能测试:
  - DELETE 父行：子表索引 vs 无索引的延迟差距
  - INSERT 子行：FK 检查的开销
  - 高并发：FK 检查与业务 DML 的锁竞争
  - 批量删除：级联删除的索引使用

回归测试:
  - 跨版本升级：旧版本的 FK 索引是否保留
  - 备份恢复：自动索引的元数据完整性
  - schema 迁移：FK 索引在 DDL 重放后的一致性
```

## 关键发现

1. **SQL 标准沉默是双刃剑**：标准只规定父端唯一性，不规定子端索引，导致各引擎自由发挥，用户跨引擎迁移时埋下大量陷阱。

2. **MySQL InnoDB 的 5.0 决定影响深远**：2005 年的"自动建索引"决策让 MySQL 在易用性维度领先 PostgreSQL 20+ 年。MySQL 用户几乎从未踩到"FK 无索引"陷阱，而 PG 用户至今每个新手都要踩一遍。

3. **PostgreSQL 的"显式优先"哲学**：社区拒绝自动建索引是基于"DBA 完全控制"的设计哲学，但代价是 99% 的性能问题归因于这一选择。`psql \d` 显示提示是折中方案。

4. **Oracle 的锁竞争问题最严重**：不仅 FK 检查慢，还会在父表 DML 时给子表加 SHARE 锁，阻塞所有子表 DML。Tom Kyte 1999-2003 年的 AskTom 文章是必读经典。

5. **CockroachDB 选择 MySQL 阵营有道理**：分布式架构下 FK 检查的性能下放到全表扫描会跨越 Range，延迟从毫秒飙升到分钟级。自动建索引是分布式必备保护。

6. **TiDB 未跟进 MySQL 是遗憾**：作为 MySQL 兼容产品，TiDB 在 FK 索引上的不一致让用户混淆。社区讨论已多年但实现复杂度大。

7. **NOT ENFORCED 阵营回避了问题**：Snowflake / BigQuery / Redshift 完全不执行 FK，索引争论无关。但 DBA 必须靠应用层保证一致性，付出更大代价。

8. **OLTP 与 OLAP 的不同最佳实践**：OLTP 系统应"永远建 FK 索引"，OLAP 列存系统 (DuckDB / ClickHouse) 索引收益小，全表扫描更高效。

9. **跨引擎迁移是高风险点**：MySQL → PostgreSQL 是 FK 索引问题的高发场景。pgloader / ora2pg 等迁移工具不会自动补建索引，DBA 必须手动检查。

10. **检测脚本是必备工具**：每个使用手工派引擎 (PG / Oracle / SQL Server / DB2 / SQLite) 的团队都应在 CI 中部署 "FK 无索引检测"，避免上线事故。

11. **复合外键的索引设计更复杂**：单列 FK 简单，但复合 FK 必须确保索引列顺序与 FK 列顺序一致，否则索引不生效。

12. **DROP CONSTRAINT 后的索引处理无标准**：MySQL 保留、CRDB 删除、Firebird 删除——各家选择不同，跨引擎迁移时需注意。

13. **ORM 层的影响巨大**：Rails / Django 默认建 FK 索引（与底层引擎无关），SQLAlchemy 默认不建。这导致使用 SQLAlchemy + PG 的项目特别容易踩坑。

14. **批量加载需禁用 FK**：所有强制执行 FK 的引擎在大规模数据导入时都建议禁用 FK 检查 (`SET foreign_key_checks = 0` / `SET CONSTRAINTS ALL DEFERRED` 等)，导入后再启用并验证。

15. **未来方向**：随着 LLM 辅助 DBA 工具的普及，"自动检测无索引 FK 并建议 DDL" 的能力变得标准化。这可能让"自动派 vs 手工派"的差异在实践中变小，但底层引擎的设计哲学差异仍将长期存在。

## 参考资料

- SQL:1992 标准: ISO/IEC 9075:1992, Section 11.8 (referential constraint definition)
- MySQL: [InnoDB 外键约束](https://dev.mysql.com/doc/refman/8.0/en/create-table-foreign-keys.html)
- MySQL: [外键约束的限制和差异](https://dev.mysql.com/doc/refman/8.0/en/constraint-foreign-key.html)
- PostgreSQL: [CREATE TABLE — FOREIGN KEY](https://www.postgresql.org/docs/current/sql-createtable.html)
- PostgreSQL: [DDL — Foreign Keys](https://www.postgresql.org/docs/current/ddl-constraints.html#DDL-CONSTRAINTS-FK)
- Oracle: [FOREIGN KEY Constraint](https://docs.oracle.com/en/database/oracle/oracle-database/19/cncpt/data-integrity.html)
- Tom Kyte: [Indexing foreign keys (AskTom)](https://asktom.oracle.com/pls/apex/asktom.search?tag=indexing-foreign-keys)
- SQL Server: [Primary and Foreign Key Constraints](https://learn.microsoft.com/en-us/sql/relational-databases/tables/primary-and-foreign-key-constraints)
- DB2: [Referential constraints](https://www.ibm.com/docs/en/db2/11.5?topic=constraints-referential)
- SQLite: [Foreign Key Support](https://www.sqlite.org/foreignkeys.html)
- CockroachDB: [Foreign Key Constraint](https://www.cockroachlabs.com/docs/stable/foreign-key.html)
- TiDB: [外键约束](https://docs.pingcap.com/tidb/stable/foreign-key)
- YugabyteDB: [Foreign keys](https://docs.yugabyte.com/preview/explore/ysql-language-features/data-types/)
- MariaDB: [Foreign Keys](https://mariadb.com/kb/en/foreign-keys/)
- Firebird: [CREATE TABLE FOREIGN KEY](https://firebirdsql.org/refdocs/langrefupd25-ddl-table.html)
- Snowflake: [Foreign Key Constraints](https://docs.snowflake.com/en/sql-reference/constraints-overview)
- BigQuery: [Primary and Foreign Keys](https://cloud.google.com/bigquery/docs/information-schema-table-constraints)
- Redshift: [Defining Constraints](https://docs.aws.amazon.com/redshift/latest/dg/t_Defining_constraints.html)
