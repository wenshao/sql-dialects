# 外键级联语义 (Foreign Key Cascade Semantics)

外键约束是关系模型的立身之本，而 `ON DELETE CASCADE` / `ON UPDATE CASCADE` 这类引用动作则是整个关系数据库中**最具争议**的一项功能——它既是数据完整性的优雅保障，也是难以察觉的性能悬崖，更是深夜生产事故的经典主角。本文专注于跨引擎级联语义的边界与实现差异，关于外键约束的基础声明语法与启用/禁用机制，请参见 [constraint-syntax.md](./constraint-syntax.md)。

## 为什么级联是最有争议的 SQL 功能

级联删除（`CASCADE`）在设计上看起来极其简洁优雅：删除父行时，所有引用它的子行自动消失，引用完整性在存储层得到保证。但在实际工程中，它引入了三类长期存在的争议：

### 性能悬崖

一条简单的 `DELETE FROM parent WHERE id = 1` 语句可能在外键的级联推动下演变为数十个子表的链式删除，CPU、锁、日志、索引维护的代价全部叠加。PostgreSQL 的 `psql` 社区频繁有用户反馈："我删除了 100 行父表，结果事务跑了 40 分钟"。根源在于：

1. **触发器与索引放大**：每一级级联都会触发该表上的行级触发器、索引维护、MVCC 版本创建
2. **锁粒度扩散**：`ON DELETE CASCADE` 会在所有被级联的子行上获取行级排他锁，高并发下极易死锁
3. **WAL / binlog 膨胀**：一条逻辑 DELETE 在日志中可能变成数百万条物理删除记录
4. **缺失索引的致命性**：如果子表的外键列没有索引，每次级联都是全表扫描

### 意外删除（Accidental Mass Delete）

级联是"隐式行为"，对开发者不可见。一个新同事在 `customers` 表中删除一行测试数据，结果触发了 `orders → order_items → shipments → shipment_events` 的四级链式删除，干掉了生产环境 60% 的业务数据。这种"子弹穿墙"式的行为在 Oracle / PostgreSQL 社区被反复讨论，甚至催生了 Linus Torvalds 风格的"Foreign Key Considered Harmful"派别：**他们认为应用层的显式级联比声明式级联更安全**，因为显式代码可审计、可 code review、可单元测试。

### 触发器交互的组合爆炸

级联动作与行级触发器、语句级触发器、BEFORE / AFTER 触发器、`WHEN` 条件触发器、可延迟约束的组合产生指数级语义分支。PostgreSQL 源码 `src/backend/utils/adt/ri_triggers.c` 中实现引用完整性的文件超过 3700 行 C 代码；Oracle 在 11g 到 19c 之间反复修补"嵌套级联中触发器重入"的 bug。SQL:1999 的规范作者 Jim Melton 曾在回顾中坦言：级联与触发器的交互是标准中"定义最不充分、各实现最分裂"的部分。

正因如此，部分公司（Facebook、Uber 的早期 schema 规范）明确禁止使用 `ON DELETE CASCADE`，要求所有关联删除都由应用层显式完成。理解本文讨论的边界语义，是在"声明式 vs 显式"这场持续了 30 年的争论中形成自己判断的前提。

## SQL:1992 / SQL:1999 标准的引用动作

### SQL:1992 定义的五种引用动作

SQL:1992（ISO/IEC 9075:1992, Section 11.8 `<referential constraint definition>`）正式定义了外键及其引用动作：

```sql
<referential_triggered_action> ::=
    <update_rule> [ <delete_rule> ]
  | <delete_rule> [ <update_rule> ]

<update_rule> ::= ON UPDATE <referential_action>
<delete_rule> ::= ON DELETE <referential_action>

<referential_action> ::=
    CASCADE
  | SET NULL
  | SET DEFAULT
  | RESTRICT
  | NO ACTION
```

五种动作的精确语义：

1. **`CASCADE`**：父行被删除/更新时，子行也被删除/更新为新值
2. **`SET NULL`**：父行被删除/更新时，子行的外键列被设为 `NULL`（前提：该列可空）
3. **`SET DEFAULT`**：父行被删除/更新时，子行的外键列被设为**列默认值**（前提：默认值必须指向父表中存在的行，否则会违反引用完整性）
4. **`RESTRICT`**：若子表中存在引用父行的记录，则**拒绝**父行的删除/更新（立即检查，不可延迟）
5. **`NO ACTION`**（默认值）：与 `RESTRICT` 语义类似，但检查时机不同——`NO ACTION` 在语句结束（或事务结束，若约束为 DEFERRED）时检查，允许中间状态违反约束

### `RESTRICT` vs `NO ACTION` 的微妙区别

这是标准中最容易被误解的一点：两者在"最终结果"上都拒绝删除，但"检查时机"不同：

| 动作 | 检查时机 | 是否可延迟 | 中间状态允许违反 |
|------|---------|-----------|----------------|
| `RESTRICT` | **立即**（操作执行时，在任何其他触发器/约束之前） | 否（标准规定不可延迟） | 否 |
| `NO ACTION` | **语句结束时**（或事务结束，若 `DEFERRED`） | 是 | 是 |

这个区别在复杂事务中至关重要。考虑父子表双向更新：

```sql
BEGIN;
UPDATE parent SET id = id + 1000;       -- 中间：外键不一致
UPDATE child SET parent_id = parent_id + 1000;
COMMIT;
```

- `ON UPDATE NO ACTION DEFERRABLE INITIALLY DEFERRED`：允许，事务提交时统一检查
- `ON UPDATE RESTRICT`：**第一条 UPDATE 就失败**，因为立即检查时子表仍引用旧 `id`

### SQL:1999 的增量

SQL:1999 引入 `DEFERRABLE` / `NOT DEFERRABLE`、`INITIALLY DEFERRED` / `INITIALLY IMMEDIATE` 限定符，使 `NO ACTION` 真正可延迟：

```sql
CONSTRAINT fk_name FOREIGN KEY (col) REFERENCES parent(id)
    ON DELETE NO ACTION
    DEFERRABLE INITIALLY DEFERRED;

-- 运行时可切换
SET CONSTRAINTS fk_name IMMEDIATE;
```

SQL:1999 还补充了"MATCH 子句"：

```sql
FOREIGN KEY (a, b) REFERENCES parent(a, b)
    MATCH { FULL | PARTIAL | SIMPLE }
```

- `MATCH SIMPLE`（默认）：复合外键任一列为 `NULL` 时不检查其他列
- `MATCH FULL`：要么全部为 `NULL`（不检查），要么全部非 `NULL`（必须引用存在的行）
- `MATCH PARTIAL`：至少匹配非空列到父表中的某一行（标准规定，但几乎无引擎完整实现）

## 支持矩阵（45+ 引擎）

### 表一：五种引用动作在 `ON DELETE` 上的支持

| 引擎 | CASCADE | SET NULL | SET DEFAULT | RESTRICT | NO ACTION | 自引用 CASCADE |
|------|---------|----------|-------------|----------|-----------|---------------|
| PostgreSQL | 是 | 是 | 是 | 是 | 是 | 是 |
| Oracle | 是 | 是 | 否（需触发器） | 否（用 NO ACTION） | 是 | 是 |
| SQL Server | 是 | 是 | 是 | 否（用 NO ACTION） | 是 | 是（有环路限制） |
| MySQL (InnoDB) | 是 | 是 | 解析但不执行 | 是 | 是 | 是 |
| MariaDB | 是 | 是 | 是（10.5+） | 是 | 是 | 是 |
| SQLite | 是 | 是 | 是 | 是 | 是 | 是 |
| DB2 | 是 | 是 | 是 | 是 | 是 | 是 |
| Firebird | 是 | 是 | 是 | 否（用 NO ACTION） | 是 | 是 |
| Informix | 是 | 是 | 否 | 否 | 是 | 是 |
| SAP HANA | 是 | 是 | 是 | 是 | 是 | 是 |
| SAP ASE (Sybase) | 是 | 是 | 是 | 是 | 是 | 是 |
| H2 | 是 | 是 | 是 | 是 | 是 | 是 |
| HSQLDB | 是 | 是 | 是 | 否（用 NO ACTION） | 是 | 是 |
| Derby | 是 | 是 | 否 | 是 | 是 | 是 |
| Interbase | 是 | 是 | 是 | 否 | 是 | 是 |
| Ingres | 是 | 是 | 否 | 否 | 是 | 是 |
| CockroachDB | 是 | 是 | 是 | 是 | 是 | 是 |
| TiDB (6.6+) | 是 | 是 | 解析但不执行 | 是 | 是 | 是 |
| OceanBase | 是 | 是 | 否 | 是 | 是 | 是 |
| YugabyteDB | 是 | 是 | 是 | 是 | 是 | 是 |
| Google Spanner | 是 | 否 | 否 | 是（NO ACTION 形式） | 是 | 否 |
| Aurora MySQL | 继承 MySQL | 继承 | 继承 | 继承 | 继承 | 是 |
| Aurora PostgreSQL | 继承 PG | 继承 | 继承 | 继承 | 继承 | 是 |
| Amazon RDS (各方言) | 随底层 | 随底层 | 随底层 | 随底层 | 随底层 | 随底层 |
| Azure SQL Database | 继承 SQL Server | 继承 | 继承 | 继承 | 继承 | 继承 |
| Cloud SQL | 随底层 | 随底层 | 随底层 | 随底层 | 随底层 | 随底层 |
| Snowflake | 解析但不执行 | 解析但不执行 | 解析但不执行 | 解析但不执行 | 解析但不执行 | -- |
| Redshift | 解析但不执行 | 解析但不执行 | 解析但不执行 | 解析但不执行 | 解析但不执行 | -- |
| BigQuery | 解析但不执行 | 解析但不执行 | 解析但不执行 | 解析但不执行 | 解析但不执行 | -- |
| Azure Synapse | 不支持 FK | -- | -- | -- | -- | -- |
| Databricks SQL | 解析但不执行 | 解析但不执行 | 解析但不执行 | 解析但不执行 | 解析但不执行 | -- |
| ClickHouse | 不支持 FK | -- | -- | -- | -- | -- |
| DuckDB | 是 | 是 | 是 | 是 | 是 | 是 |
| Vertica | 解析但不执行 | 解析但不执行 | 解析但不执行 | 解析但不执行 | 解析但不执行 | -- |
| Greenplum | 解析但不执行 | 解析但不执行 | 解析但不执行 | 解析但不执行 | 解析但不执行 | -- |
| MonetDB | 是 | 是 | 是 | 是 | 是 | 是 |
| Teradata | 是 | 是 | 否 | 是 | 是 | 是 |
| Exasol | 是 | 否 | 否 | 是 | 是 | 是 |
| Trino/Presto | 不支持 FK | -- | -- | -- | -- | -- |
| Hive | 仅 Hive 3+ 声明 | -- | -- | -- | -- | -- |
| Spark SQL | 声明但不执行 (3.5+) | -- | -- | -- | -- | -- |
| Flink SQL | 不支持 FK | -- | -- | -- | -- | -- |
| Impala | 不支持 FK | -- | -- | -- | -- | -- |
| Druid | 不支持 FK | -- | -- | -- | -- | -- |
| Pinot | 不支持 FK | -- | -- | -- | -- | -- |
| Doris / StarRocks | 不支持 FK | -- | -- | -- | -- | -- |
| SingleStore | 不支持 FK（2000+ 行警告） | -- | -- | -- | -- | -- |
| Materialize | 不支持 FK | -- | -- | -- | -- | -- |
| RisingWave | 不支持 FK | -- | -- | -- | -- | -- |
| QuestDB | 不支持 FK | -- | -- | -- | -- | -- |
| CrateDB | 不支持 FK | -- | -- | -- | -- | -- |
| InfluxDB | 不支持 FK | -- | -- | -- | -- | -- |
| Firebolt | 声明但不执行 | -- | -- | -- | -- | -- |

> "解析但不执行" 表示引擎接受 `FOREIGN KEY` 声明语法（仅作为信息性约束供优化器使用），但不在 DML 操作中强制引用完整性。
>
> 统计：约 22 个引擎**完整支持**五种标准引用动作，约 9 个引擎**仅作信息性约束**，约 14 个引擎**完全不支持外键**。

### 表二：`ON UPDATE` 动作的支持（差异显著）

`ON UPDATE CASCADE` 的支持远不如 `ON DELETE CASCADE` 普遍——尤其是 Oracle 从 Oracle 6 到 Oracle 23ai 始终不原生支持。

| 引擎 | ON UPDATE CASCADE | ON UPDATE SET NULL | ON UPDATE SET DEFAULT | ON UPDATE RESTRICT | ON UPDATE NO ACTION |
|------|-------------------|--------------------|-----------------------|--------------------|---------------------|
| PostgreSQL | 是 | 是 | 是 | 是 | 是 |
| Oracle | **不支持**（需触发器模拟） | **不支持** | **不支持** | **不支持** | 是（默认） |
| SQL Server | 是（有环路限制） | 是 | 是 | 否 | 是 |
| MySQL (InnoDB) | 是 | 是 | 解析但不执行 | 是 | 是 |
| MariaDB | 是 | 是 | 是 | 是 | 是 |
| SQLite | 是 | 是 | 是 | 是 | 是 |
| DB2 | 是 | 是 | 是 | 是 | 是 |
| Firebird | 是 | 是 | 是 | 否 | 是 |
| CockroachDB | 是 | 是 | 是 | 是 | 是 |
| TiDB | 是（6.6+） | 是 | 解析但不执行 | 是 | 是 |
| YugabyteDB | 是 | 是 | 是 | 是 | 是 |
| Google Spanner | **不支持** | -- | -- | -- | 是 |
| DuckDB | 否（需触发器模拟） | 否 | 否 | 是 | 是 |
| SAP HANA | 是 | 是 | 是 | 是 | 是 |
| Teradata | 否 | 否 | 否 | 是 | 是 |
| H2 | 是 | 是 | 是 | 是 | 是 |
| HSQLDB | 是 | 是 | 是 | 否 | 是 |
| Derby | **不支持**（仅 NO ACTION/RESTRICT） | **不支持** | **不支持** | 是 | 是 |

> Oracle 至今不支持 `ON UPDATE CASCADE` 的历史原因：早期 Oracle 设计哲学认为主键应**不可变**，更改主键值意味着"实体身份改变"，应由应用层显式处理。这一设计后来被广泛质疑，但出于向下兼容从未修改。
>
> Derby / Apache Derby（即 JavaDB）从设计之初就拒绝级联更新，源于其数据库引擎早期来自 IBM Cloudscape，继承了严格的完整性观。

### 表三：可延迟约束与检查时机

| 引擎 | DEFERRABLE | INITIALLY DEFERRED | INITIALLY IMMEDIATE | SET CONSTRAINTS 动态切换 | 仅对 NO ACTION 有效 |
|------|-----------|-------------------|---------------------|--------------------------|---------------------|
| PostgreSQL | 是（6.1+） | 是 | 是 | 是 | 是 |
| Oracle | 是（8.0+） | 是 | 是 | 是 | 是 |
| SQL Server | **否**（仅支持禁用/启用约束） | -- | -- | -- | -- |
| MySQL (InnoDB) | **不支持（任何版本）**（仅 SESSION 级 `FOREIGN_KEY_CHECKS` 开关） | -- | -- | -- | -- |
| MariaDB | **不支持（任何版本）**（同 MySQL） | -- | -- | -- | -- |
| SQLite | 是（3.6.19+，需 `PRAGMA foreign_keys=ON`） | 是 | 是 | -- | 是 |
| DB2 | 否（用 NOT ENFORCED 替代） | -- | -- | -- | -- |
| Firebird | 否 | -- | -- | -- | -- |
| CockroachDB | 有限支持 | 有限 | 有限 | 是 | 是 |
| YugabyteDB | 是（继承 PG） | 是 | 是 | 是 | 是 |
| H2 | 否 | -- | -- | -- | -- |
| HSQLDB | 是 | 是 | 是 | 是 | 是 |

### 表四：触发器与级联的交互

| 引擎 | BEFORE 触发器触发于级联 | AFTER 触发器触发于级联 | 递归深度限制 | 触发器可否阻止级联 |
|------|-------------------------|------------------------|--------------|-------------------|
| PostgreSQL | 是（行级） | 是（行级） | `max_stack_depth`（默认 2MB） | 不可直接阻止（返回 NULL 会报错） |
| Oracle | 是 | 是 | 50 层硬限制 | 用 `RAISE_APPLICATION_ERROR` |
| SQL Server | **否**（INSTEAD OF 除外） | 是 | 32 层硬限制 | 不可在 AFTER 触发器中阻止 |
| MySQL | 是 | 是 | 无明确限制（但内存会爆） | 可 `SIGNAL SQLSTATE` 抛错 |
| SQLite | 是 | 是 | `recursive_triggers` pragma | 可 `RAISE ABORT` |
| DB2 | 是 | 是 | 16 层 | 可 SIGNAL |

### 表五：自引用外键（层级结构）级联行为

| 引擎 | ON DELETE CASCADE 支持 | 循环检测 | 深度限制 |
|------|------------------------|---------|---------|
| PostgreSQL | 是 | 运行时栈溢出保护 | ~1000 层（栈大小限制） |
| Oracle | 是 | 自动检测 | 50 层 |
| SQL Server | **部分**（多路径导致"引入多个级联路径"错误） | 编译时检测 | 32 层 |
| MySQL | 是 | 运行时 | 15 层（InnoDB 硬限制） |
| MariaDB | 是 | 运行时 | 15 层 |
| SQLite | 是 | 是 | 取决于 `SQLITE_MAX_TRIGGER_DEPTH`（默认 1000） |
| DB2 | 是 | 是 | 16 层 |

### 表六：级联路径冲突（多路径问题）

SQL Server 的"多个级联路径"错误是最典型的级联限制：

```sql
-- SQL Server 会拒绝这个设计
CREATE TABLE orders (id INT PRIMARY KEY, customer_id INT);
CREATE TABLE refunds (
    id INT PRIMARY KEY,
    order_id INT REFERENCES orders(id) ON DELETE CASCADE,
    customer_id INT REFERENCES customers(id) ON DELETE CASCADE  -- 错误!
);
-- Msg 1785: Introducing FOREIGN KEY constraint ... on table 'refunds'
-- may cause cycles or multiple cascade paths.
```

| 引擎 | 允许多级联路径 | 检测时机 |
|------|---------------|---------|
| PostgreSQL | 是 | 无检测，运行时处理 |
| Oracle | 是 | 无检测 |
| SQL Server | **否** | DDL 时拒绝 |
| MySQL | 是 | 运行时（可能出现"子行被删除两次"的无害行为） |
| SQLite | 是 | 运行时 |
| DB2 | 部分 | DDL 时检测部分冲突 |

## 各引擎详解

### PostgreSQL：五种动作全支持，DEFERRABLE 从 6.x 起成熟

PostgreSQL 是 SQL 标准引用动作的最完整实现者之一。自 PostgreSQL 6.1（1997 年）起支持 `DEFERRABLE`，自 7.0 起支持完整的五种引用动作。

```sql
-- 完整语法演示
CREATE TABLE orders (
    id BIGINT PRIMARY KEY,
    customer_id BIGINT NOT NULL,
    product_id BIGINT NOT NULL,
    CONSTRAINT fk_customer FOREIGN KEY (customer_id)
        REFERENCES customers(id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    CONSTRAINT fk_product FOREIGN KEY (product_id)
        REFERENCES products(id)
        ON DELETE CASCADE
        DEFERRABLE INITIALLY DEFERRED
);

-- 运行时控制延迟
BEGIN;
SET CONSTRAINTS fk_product IMMEDIATE;
-- ... DML ...
SET CONSTRAINTS ALL DEFERRED;
COMMIT;

-- MATCH 子句（PG 支持 FULL / SIMPLE）
CREATE TABLE child (
    a INT, b INT,
    FOREIGN KEY (a, b) REFERENCES parent(a, b) MATCH FULL
);
```

**PostgreSQL 的独特语义**：

1. **`SET DEFAULT` 要求默认值存在于父表**：若默认值不指向任何父行，级联失败
2. **`SET NULL (column_list)` 部分列为 NULL**（PG 15+）：只将复合外键的指定列设为 NULL

```sql
-- PostgreSQL 15+
FOREIGN KEY (a, b) REFERENCES parent(a, b)
    ON DELETE SET NULL (b);  -- 仅将 b 设为 NULL，保留 a
```

3. **行级触发器嵌入在级联中**：PG 在级联删除子行时，会触发子表上所有 `FOR EACH ROW BEFORE DELETE` / `AFTER DELETE` 触发器，可能导致递归
4. **`ri_triggers.c` 的实现细节**：级联本身以**系统触发器**实现（名字前缀 `RI_ConstraintTrigger_`），在 `pg_trigger` 表中可见但不可手动删除

### Oracle：仅三种 ON DELETE 动作，完全不支持 ON UPDATE

Oracle 的引用完整性实现是历史包袱最重的：

```sql
-- Oracle 支持的引用动作
CONSTRAINT fk_customer FOREIGN KEY (customer_id)
    REFERENCES customers(id)
    ON DELETE CASCADE;      -- 支持

CONSTRAINT fk_customer FOREIGN KEY (customer_id)
    REFERENCES customers(id)
    ON DELETE SET NULL;     -- 支持

-- 省略 ON DELETE 子句时，默认等同于 NO ACTION
CONSTRAINT fk_customer FOREIGN KEY (customer_id)
    REFERENCES customers(id);

-- 以下语法 Oracle 全部不支持：
-- ON DELETE RESTRICT       -- 语法错误
-- ON DELETE SET DEFAULT    -- 语法错误
-- ON UPDATE CASCADE        -- 语法错误
-- ON UPDATE SET NULL       -- 语法错误
```

**Oracle 的 `ON UPDATE` 替代方案：触发器**

```sql
-- 通过 AFTER UPDATE 触发器模拟 ON UPDATE CASCADE
CREATE OR REPLACE TRIGGER trg_customer_id_cascade
AFTER UPDATE OF id ON customers
FOR EACH ROW
BEGIN
    UPDATE orders SET customer_id = :NEW.id WHERE customer_id = :OLD.id;
END;
/
```

但这种实现**无法与外键约束本身协调**——若外键是 `NOT DEFERRABLE`，触发器更新子行前，外键检查已经失败。标准做法是：

1. 声明外键为 `DEFERRABLE INITIALLY IMMEDIATE`
2. 在需要修改主键的事务中 `SET CONSTRAINT ALL DEFERRED`
3. 先 UPDATE 父表，再 UPDATE 子表
4. COMMIT 时统一检查

**Oracle 的 `DEFERRABLE`**：自 Oracle 8.0 起支持，语法与 PG 一致。

### SQL Server：支持全部五种动作，但多路径被禁止

SQL Server 2000 引入级联动作，2005 完善。特殊点是：

```sql
-- 完整语法
CREATE TABLE orders (
    id INT PRIMARY KEY,
    customer_id INT NOT NULL
        CONSTRAINT fk_orders_cust REFERENCES customers(id)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);
```

**多级联路径的 DDL 时拒绝**：

```sql
CREATE TABLE a (id INT PRIMARY KEY);
CREATE TABLE b (id INT PRIMARY KEY, a_id INT REFERENCES a(id) ON DELETE CASCADE);
CREATE TABLE c (
    id INT PRIMARY KEY,
    a_id INT REFERENCES a(id) ON DELETE CASCADE,   -- 路径 1: a -> c
    b_id INT REFERENCES b(id) ON DELETE CASCADE    -- 路径 2: a -> b -> c
);
-- Msg 1785: may cause cycles or multiple cascade paths
```

**解决方案**：

1. 其中一个路径改为 `NO ACTION`，用 `INSTEAD OF DELETE` 触发器手工处理
2. 业务上保证不会同时出现两条级联路径

**SQL Server 的 `INSTEAD OF` 触发器特殊地位**：在级联与触发器交互中，`INSTEAD OF` 触发器**优先**于级联执行，可以完全替换默认行为；而 `AFTER` 触发器在级联之后执行。

**无 `DEFERRABLE`**：SQL Server 不支持延迟约束。替代方案是 `ALTER TABLE ... NOCHECK CONSTRAINT`（临时禁用）或 `WITH NOCHECK` 批量加载。

### MySQL (InnoDB)：全支持但 SET DEFAULT 被解析后忽略

```sql
-- MySQL 支持的语法
CREATE TABLE orders (
    id BIGINT PRIMARY KEY,
    customer_id BIGINT,
    CONSTRAINT fk_customer FOREIGN KEY (customer_id)
        REFERENCES customers(id)
        ON DELETE CASCADE
        ON UPDATE CASCADE
) ENGINE=InnoDB;
```

**MySQL 的 `SET DEFAULT` 陷阱**：

```sql
-- 语法合法但运行时被当作 NO ACTION
CONSTRAINT fk_customer FOREIGN KEY (customer_id)
    REFERENCES customers(id)
    ON DELETE SET DEFAULT;

-- MySQL 文档说明：
-- "InnoDB rejects table definitions containing ON DELETE SET DEFAULT
-- or ON UPDATE SET DEFAULT clauses."
-- 实际行为：8.0 起给出 Warning，继续执行（回退到 NO ACTION）
```

**MySQL 的外键仅限 InnoDB**：MyISAM、MEMORY 引擎解析 FK 语法但完全不存储（ALTER 后再查看 `SHOW CREATE TABLE` 会发现 FK 消失）。

**`foreign_key_checks` 会话变量**：MySQL 没有 `DEFERRABLE`，但提供会话级开关：

```sql
SET FOREIGN_KEY_CHECKS = 0;
-- 执行 DDL / 批量导入
SET FOREIGN_KEY_CHECKS = 1;
-- 注意：重新启用时不会回溯验证已有数据
```

这是与 PG 延迟约束**根本不同**的机制——PG 的延迟是"事务结束前统一检查"，MySQL 的开关是"完全跳过检查"，不存在兜底验证。

**MySQL 的递归级联深度**：InnoDB 硬编码限制为 **15 层**（`DICT_FK_MAX_RECURSIVE_LOAD` 和 `FK_MAX_CASCADE_DEL`）。超过该深度抛 `ER_FK_DEPTH_EXCEEDED`。

### MariaDB：10.5+ 引入完整 SET DEFAULT

MariaDB 在 10.5（2020）正式实现 `ON DELETE/UPDATE SET DEFAULT`，比 MySQL 领先。

```sql
-- MariaDB 10.5+
CREATE TABLE orders (
    id BIGINT PRIMARY KEY,
    customer_id BIGINT DEFAULT 0,
    FOREIGN KEY (customer_id) REFERENCES customers(id)
        ON DELETE SET DEFAULT
) ENGINE=InnoDB;

-- 要求：
-- 1. customer_id 的默认值（0）必须在 customers 表中存在
-- 2. customers 表必须有 id = 0 的"墓碑"行
```

### SQLite：简洁但外键默认禁用

SQLite 的外键实现出人意料地完整——支持全部五种 `ON DELETE` / `ON UPDATE` 动作，支持 `DEFERRABLE INITIALLY DEFERRED`。

```sql
-- 必须每次连接显式启用（历史遗留）
PRAGMA foreign_keys = ON;

-- 级联声明
CREATE TABLE orders (
    id INTEGER PRIMARY KEY,
    customer_id INTEGER,
    FOREIGN KEY (customer_id) REFERENCES customers(id)
        ON DELETE CASCADE
        ON UPDATE CASCADE
        DEFERRABLE INITIALLY DEFERRED
);
```

**SQLite 的独特陷阱**：

1. `PRAGMA foreign_keys = ON` 必须在事务**外**执行，事务内切换会被忽略
2. `ALTER TABLE` 不能 `ADD CONSTRAINT`，重建表的经典 12 步操作（`PRAGMA writable_schema` 技巧）
3. 子查询中 `UPDATE` 触发的级联：SQLite 按"语句级别"而非"行级别"推进，级联顺序严格保证

### DB2：支持所有五种动作的商业数据库典范

DB2 对级联的支持在商业数据库中最完整：

```sql
CREATE TABLE orders (
    id BIGINT PRIMARY KEY,
    customer_id BIGINT NOT NULL,
    CONSTRAINT fk_customer FOREIGN KEY (customer_id)
        REFERENCES customers(id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE
);
```

**DB2 的 `NOT ENFORCED`**：DB2 用 `NOT ENFORCED` 替代 `DEFERRABLE`：

```sql
ALTER TABLE orders ALTER FOREIGN KEY fk_customer NOT ENFORCED;
-- 此状态下 FK 不强制，但优化器仍可信任 FK 进行重写
```

**`SET INTEGRITY`**：DB2 的外键维护接口，支持增量检查：

```sql
SET INTEGRITY FOR orders IMMEDIATE CHECKED;
```

### Firebird：全支持但无 RESTRICT

```sql
CREATE TABLE orders (
    id INT PRIMARY KEY,
    customer_id INT,
    CONSTRAINT fk_customer FOREIGN KEY (customer_id)
        REFERENCES customers(id)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);
-- Firebird 不支持 RESTRICT，仅支持 NO ACTION（语义相同但可延迟）
```

Firebird 是少数完整支持 `ON UPDATE SET DEFAULT` 的开源引擎。

### TiDB：6.6+ 真正强制执行外键

TiDB 长期以来（<6.6 版本）"语法支持但运行时忽略"外键约束。自 TiDB 6.6.0（2023 年 2 月）起，`tidb_enable_foreign_key = ON`（默认开启）后真正强制执行：

```sql
-- TiDB 6.6+
CREATE TABLE orders (
    id BIGINT PRIMARY KEY,
    customer_id BIGINT,
    CONSTRAINT fk_customer FOREIGN KEY (customer_id)
        REFERENCES customers(id)
        ON DELETE CASCADE
);

-- 查看外键状态
SHOW CREATE TABLE orders;
-- 在 TiDB 6.6 之前，即使声明了 FK，DELETE 父表也不会级联
```

**TiDB 的级联在分布式事务中的实现**：每次级联删除都生成 2PC 事务，跨 Region 级联会引入可观测的延迟。TiDB 官方推荐"显式应用层删除"作为级联的替代方案，以避免分布式锁冲突。

### CockroachDB：完整支持，但延迟约束有限

CockroachDB 从 2.0 版本起支持全部五种引用动作。延迟约束（`DEFERRABLE`）从 v22.1 起提供初步支持，但部分 MATCH 模式（FULL / PARTIAL）仍未完全实现。

### Snowflake / Redshift / BigQuery：信息性约束

云数仓引擎普遍将外键作为**信息性约束**（informational constraint）：

```sql
-- Snowflake：接受语法，不执行
CREATE TABLE orders (
    id NUMBER PRIMARY KEY,
    customer_id NUMBER,
    CONSTRAINT fk_customer FOREIGN KEY (customer_id)
        REFERENCES customers(id)
        ON DELETE CASCADE        -- 被解析，但 DELETE 时不会级联
);

-- Snowflake 文档显式声明:
-- "FOREIGN KEY constraints are not enforced."
```

**为什么数仓不强制 FK？**

1. 数仓的典型工作负载是**批量 ETL**，每次加载动辄亿级，强制 FK 开销过大
2. 数据通常来自上游系统，完整性由 ETL 流程保证，无需重复验证
3. 列式存储的反规范化倾向（星型、雪花）降低了 FK 的需求

但优化器仍会利用这些声明：Snowflake 的 JOIN 消除、Redshift 的 RELY 提示、BigQuery 的主键/外键约束（2022 预览）都是优化线索。

### 其他分析/列式引擎

ClickHouse / Druid / Pinot / StarRocks / Doris / Trino / Spark SQL 等 OLAP 引擎**完全不支持外键**。它们的数据模型假设数据已经过预处理，引用完整性不在存储层保证。

Hive 3.0+、Spark SQL 3.5+ 开始支持 FK 声明作为优化提示，但不强制执行。

## 级联与触发器的交互：最复杂的边界

### 核心问题：触发器是否在级联删除的子行上触发？

这是跨引擎差异最大的语义点。考虑：

```sql
CREATE TABLE child (id INT, parent_id INT REFERENCES parent(id) ON DELETE CASCADE);
CREATE TRIGGER trg AFTER DELETE ON child FOR EACH ROW
    BEGIN
        INSERT INTO audit_log(msg) VALUES ('deleted ' || OLD.id);
    END;

DELETE FROM parent WHERE id = 1;
-- 问题：child 上的 AFTER DELETE 触发器会触发吗？
```

| 引擎 | 级联删除是否触发子表的 AFTER DELETE | 顺序 |
|------|--------------------------------------|------|
| PostgreSQL | 是 | 先级联 DELETE，再触发 AFTER DELETE |
| Oracle | 是 | 同上 |
| SQL Server | 是（AFTER），INSTEAD OF 会拦截 | 级联绕过 BEFORE/INSTEAD OF DELETE |
| MySQL | 是 | 同 PG |
| SQLite | 是（需 `PRAGMA recursive_triggers = ON`） | 级联绕过 INSTEAD OF |
| DB2 | 是 | 同 PG |

**引擎开发者的关键约束**：级联子行上触发的 AFTER DELETE 触发器如果再次 DELETE 其他表，又可能触发更深层的级联。这就是为什么所有引擎都有**递归深度限制**（Oracle 50、SQL Server 32、MySQL 15）。

### `BEFORE DELETE` 触发器阻止级联

```sql
-- PostgreSQL：在 BEFORE DELETE 中返回 NULL 取消当前行的删除
CREATE OR REPLACE FUNCTION block_delete() RETURNS trigger AS $$
BEGIN
    RETURN NULL;  -- 取消 DELETE
END; $$ LANGUAGE plpgsql;

CREATE TRIGGER trg BEFORE DELETE ON child
    FOR EACH ROW EXECUTE FUNCTION block_delete();

DELETE FROM parent WHERE id = 1;
-- 结果：父行 DELETE 继续，但 child 行被 BEFORE DELETE 取消
-- 触发约束违反错误（因为 child 仍引用已删除的 parent）
```

这暴露了一个危险的角落：级联的"自动补救"被触发器破坏后，引用完整性反而被打破。PG 在这种情形下抛 `ERROR: update or delete on table "parent" violates foreign key constraint`。

### 触发器中再次执行 DML 的反弹

```sql
-- PG: 在 child 的 AFTER DELETE 触发器中再次 DELETE parent
CREATE TRIGGER trg AFTER DELETE ON child FOR EACH ROW
EXECUTE FUNCTION recursive_delete();

-- recursive_delete: DELETE FROM parent WHERE id = OLD.parent_id;
-- 结果：栈溢出（无限递归）或 max_stack_depth 报错
```

### `ON DELETE SET NULL` 与触发器交互

`SET NULL` 也会触发子表的 `UPDATE` 触发器，而非 `DELETE` 触发器：

```sql
-- 子表外键改为 NULL，触发 AFTER UPDATE OF parent_id
CREATE TRIGGER trg AFTER UPDATE OF parent_id ON child
    FOR EACH ROW EXECUTE FUNCTION audit();
```

这一点在 Oracle 文档中特别强调，因为很多开发者以为"父行删除只会触发子表的 DELETE 触发器"。

## 自引用外键的层级级联

### 树形结构的经典场景

```sql
CREATE TABLE categories (
    id INT PRIMARY KEY,
    parent_id INT REFERENCES categories(id) ON DELETE CASCADE,
    name TEXT
);

-- 插入 4 层树
INSERT INTO categories VALUES
    (1, NULL, 'Electronics'),
    (2, 1, 'Computers'),
    (3, 2, 'Laptops'),
    (4, 3, 'Gaming Laptops');

DELETE FROM categories WHERE id = 1;
-- 期望：2, 3, 4 全部被级联删除
```

### 各引擎的递归级联深度限制与行为

| 引擎 | 自引用 CASCADE 最大深度 | 超限表现 |
|------|----------------------|---------|
| PostgreSQL | 受 `max_stack_depth` 限制（默认 2MB 栈，约 1000-2000 层） | `stack depth limit exceeded` |
| Oracle | 50 层 | `ORA-00036: maximum number of DML locks exceeded` |
| SQL Server | 32 层 | `Msg 217: Maximum stored procedure, function, trigger, or view nesting level exceeded` |
| MySQL | 15 层 | `ER_FK_DEPTH_EXCEEDED` (error 3627) |
| SQLite | 1000 层（`SQLITE_MAX_TRIGGER_DEPTH`） | `too many levels of trigger recursion` |

### SQL Server 的自引用限制

SQL Server 对**自引用 + CASCADE** 的支持曾经是 buggy 的经典——2008 年以前有多起涉及自引用级联删除死循环的 CU（Cumulative Update）。2012+ 版本稳定，但仍存在多路径限制：

```sql
-- SQL Server 支持单一自引用 CASCADE
CREATE TABLE tree (
    id INT PRIMARY KEY,
    parent_id INT REFERENCES tree(id) ON DELETE CASCADE  -- OK
);

-- 但自引用 + 双路径 = 拒绝
CREATE TABLE weird (
    id INT PRIMARY KEY,
    a INT REFERENCES weird(id) ON DELETE CASCADE,
    b INT REFERENCES weird(id) ON DELETE CASCADE  -- Error 1785
);
```

### 递归 CTE 的替代方案

当自引用级联深度不够时，通常用递归 CTE 手工实现：

```sql
-- PostgreSQL / SQL Server / Oracle 等
WITH RECURSIVE descendants AS (
    SELECT id FROM categories WHERE id = 1
    UNION ALL
    SELECT c.id FROM categories c JOIN descendants d ON c.parent_id = d.id
)
DELETE FROM categories WHERE id IN (SELECT id FROM descendants);
```

这种写法**不受 FK 递归深度限制**，但需要显式写出递归逻辑。

## 级联的性能陷阱

### 陷阱 1：缺失子表外键索引

```sql
-- 父表
CREATE TABLE customers (id BIGINT PRIMARY KEY, name TEXT);

-- 子表：外键列无索引
CREATE TABLE orders (
    id BIGINT PRIMARY KEY,
    customer_id BIGINT REFERENCES customers(id) ON DELETE CASCADE,
    amount NUMERIC
);
-- customer_id 列上**没有索引**

-- 执行：
DELETE FROM customers WHERE id = 12345;
-- 级联到 orders 时需要扫描 orders 全表找 customer_id = 12345
-- 如果 orders 有 10 亿行，这一次 DELETE 要全表扫描
```

**各引擎是否自动为外键创建索引**：

| 引擎 | 外键列自动索引 | 说明 |
|------|--------------|------|
| PostgreSQL | **否** | 必须手工 CREATE INDEX |
| Oracle | **否** | 必须手工 CREATE INDEX，否则子表 DML 会加全表锁 |
| SQL Server | **否** | 必须手工，常被遗漏 |
| MySQL (InnoDB) | **是**（如果没有匹配索引则自动创建） | FK 声明时若找不到兼容索引，自动建 |
| MariaDB | **是** | 同 MySQL |
| SQLite | 否 | 手工 |

PostgreSQL / Oracle / SQL Server 的最佳实践是**所有外键列必须有索引**。生产环境的"万毫秒 DELETE"问题 90% 源于此。

### 陷阱 2：级联放大写 I/O

一次 `DELETE FROM parent WHERE id = 1` 在级联链条上会触发：

```
DELETE parent     → 1 行 × 1 表    = 1 条 WAL/redo
CASCADE orders    → 1000 行 × 1 表 = 1000 条 WAL/redo + 索引维护
CASCADE items     → 10000 行 × 1 表= 10000 条 + 索引维护
CASCADE shipments → 100000 行 × 1 表 = 100000 条
```

PG 的 WAL 会线性膨胀；Oracle 的 redo / undo 也会跟随放大。对高 TPS 系统，一次看似简单的级联可能**阻塞 WAL 刷盘几秒**。

### 陷阱 3：锁的指数级扩散

```sql
-- 事务 1
DELETE FROM customers WHERE id = 1;  -- 锁 customers[1], orders[*], items[*], ...

-- 事务 2
SELECT * FROM orders WHERE customer_id = 2;  -- 若 orders 有行级锁，可能阻塞
```

级联锁扩散导致**死锁概率显著上升**。典型的跨父表事务容易触发环状等待。

### 陷阱 4：MVCC 版本爆炸

PostgreSQL / Oracle / CockroachDB 的 MVCC 模型下，每次级联 UPDATE（如 `SET NULL`）都创建新版本，VACUUM / purge 的压力骤增。

```sql
-- PostgreSQL
UPDATE customers SET id = id + 1 WHERE id BETWEEN 1 AND 1000000;
-- 若 orders 的外键为 ON UPDATE CASCADE，产生 1000000 * N 个 orders 新版本
-- VACUUM 需要数小时才能回收空间
```

### 陷阱 5：触发器倍增

级联 + 触发器的组合，每次级联的行都触发触发器，CPU 被触发器逻辑占据：

```
100 父行 DELETE × 100 子行 / 父 × 1ms 触发器 = 10 秒 CPU
```

### 陷阱 6：跨节点分布式级联

TiDB / CockroachDB / YugabyteDB 的级联在分布式层面引入额外代价：

1. 级联行可能分布在不同 Region / Range
2. 每个 Region 的 DML 都是独立的 2PC 分支
3. 跨 Region 网络延迟放大到 N 倍（N = 级联层数）

CockroachDB 的文档明确警告：**"避免在热点父表上使用 CASCADE"**。生产建议用应用层批量删除替代。

## 关键发现

1. **"级联"是 SQL 中最被高估的功能**：它的声明式优雅掩盖了性能放大、锁扩散、触发器交互等工程复杂性，许多大厂 schema 规范明确禁用

2. **`ON UPDATE CASCADE` 的支持远不如 `ON DELETE CASCADE`**：Oracle 从 6 到 23ai 始终不支持，Derby 不支持，Google Spanner 不支持，Teradata 不支持。根源是"主键应不可变"的设计哲学

3. **`SET DEFAULT` 是陷阱最多的动作**：MySQL 解析但不执行，Oracle / Informix / Teradata 不支持，PostgreSQL 要求默认值指向父表中存在的行

4. **`RESTRICT` vs `NO ACTION` 的区别在标准中清晰但实现常模糊**：SQL Server、Firebird 不区分两者；MySQL 区分但 `RESTRICT` 不可延迟；只有 PG、Oracle、DB2 正确实现可延迟的 `NO ACTION`

5. **外键列缺失索引是生产事故之王**：PostgreSQL / Oracle / SQL Server 不自动为 FK 列建索引，是级联性能问题的 90% 根源；MySQL / MariaDB 自动建索引反而是更友好的默认

6. **触发器与级联的交互无统一标准**：`BEFORE DELETE` 能否阻止级联、`INSTEAD OF` 能否拦截级联、级联删除是否触发子表 DELETE 触发器——各引擎答案完全不同，迁移时容易踩坑

7. **递归深度限制是硬约束**：MySQL 15 层、SQL Server 32 层、Oracle 50 层、PG ~1000 层。对深层树形结构，必须用递归 CTE 手工实现，不能依赖 FK 自引用

8. **SQL Server 的"多级联路径"禁令是独一家**：其他引擎运行时处理，SQL Server 在 DDL 时拒绝，常导致迁移自 PG / MySQL 的 schema 需要重构

9. **分布式引擎的级联代价被严重低估**：TiDB / CockroachDB / YugabyteDB 的分布式事务使级联变成跨 Region 2PC，延迟放大为级联层数 × 网络延迟

10. **数仓引擎的"信息性约束"是明智的妥协**：Snowflake / Redshift / BigQuery 接受 FK 声明但不强制，既能给优化器提供信息，又避免了批量加载时的检查开销——这是"不同工作负载需要不同约束模型"的成熟认知

11. **`DEFERRABLE` 是 SQL:1999 的亮点但普及度低**：PG、Oracle、SQLite、HSQLDB 支持完整语义；SQL Server、MySQL、MariaDB、DB2 用"禁用/启用"或 session 开关替代，不能真正延迟到事务结束

12. **MATCH PARTIAL 是标准中的"僵尸语法"**：SQL:1992 定义，但至今几乎没有引擎完整实现（PG 仅支持 FULL / SIMPLE），可视为标准与实现脱节的典型案例

13. **TiDB 在 6.6 之前的"伪外键"是典型兼容性陷阱**：语法兼容 MySQL 但运行时不执行，从 MySQL 迁移到 TiDB 时若未升级到 6.6+，级联会静默失效，酿成数据完整性事故

14. **Oracle 的 `ON UPDATE CASCADE` 替代方案涉及可延迟约束 + 触发器的复杂组合**，是 Oracle 长期被诟病的 DX 缺陷，直到 23ai 仍未改善

15. **"显式 vs 声明式"的永恒争论没有标准答案**：高可控性、低一致性要求场景推荐应用层显式；小型 OLTP、强一致场景推荐 `ON DELETE CASCADE`。工程师的判断远比工具重要

## 参考资料

- SQL:1992 标准: ISO/IEC 9075:1992, Section 11.8 `<referential constraint definition>`
- SQL:1999 标准: ISO/IEC 9075-2:1999, Section 11.8 (增加 DEFERRABLE / MATCH 子句)
- PostgreSQL: [CREATE TABLE - Foreign Key](https://www.postgresql.org/docs/current/sql-createtable.html#SQL-CREATETABLE-PARMS-REFERENCES)
- PostgreSQL: [ri_triggers.c 源码](https://github.com/postgres/postgres/blob/master/src/backend/utils/adt/ri_triggers.c)
- Oracle: [Constraints](https://docs.oracle.com/en/database/oracle/oracle-database/19/cncpt/data-integrity.html)
- SQL Server: [FOREIGN KEY Constraints](https://learn.microsoft.com/en-us/sql/relational-databases/tables/create-foreign-key-relationships)
- SQL Server: [Multiple cascade paths error (Msg 1785)](https://learn.microsoft.com/en-us/sql/t-sql/statements/alter-table-transact-sql)
- MySQL: [Foreign Key Constraints](https://dev.mysql.com/doc/refman/8.0/en/create-table-foreign-keys.html)
- MariaDB: [Foreign Keys](https://mariadb.com/kb/en/foreign-keys/)
- SQLite: [Foreign Key Support](https://www.sqlite.org/foreignkeys.html)
- IBM DB2: [Referential constraints](https://www.ibm.com/docs/en/db2-for-zos/12?topic=constraints-referential)
- Firebird: [Referential Actions](https://firebirdsql.org/file/documentation/html/en/refdocs/fblangref40/firebird-40-language-reference.html)
- TiDB: [Foreign Key Constraints (6.6+)](https://docs.pingcap.com/tidb/stable/foreign-key)
- CockroachDB: [Foreign key constraint](https://www.cockroachlabs.com/docs/stable/foreign-key)
- Snowflake: [Constraints](https://docs.snowflake.com/en/sql-reference/constraints-overview)
- Jim Melton, "Understanding SQL's Stored Procedures" (1998) – 讨论 SQL:1999 约束延伸的背景
- Joe Celko, "SQL for Smarties: Advanced SQL Programming" (2014) – 第 15 章外键与级联的工程考量
