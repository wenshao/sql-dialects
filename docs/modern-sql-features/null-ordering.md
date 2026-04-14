# NULLS FIRST / NULLS LAST 排序 (NULL Ordering)

把同一条 `ORDER BY salary DESC` 查询从 PostgreSQL 搬到 MySQL，再搬到 SQL Server，你会看到三种不同的 NULL 排列结果——这是 SQL 跨引擎可移植性最经典、也最隐蔽的陷阱之一。NULL 排序的标准只规定了语法，从未规定默认值，于是每个引擎都按自己的"直觉"实现，最终在分页、TOP-N 和指标排行榜上酿出无数 bug。

本文专门聚焦 `ORDER BY` 中 NULL 的排序行为；NULL 在三值逻辑、聚合、JOIN 中的语义见 [`null-semantics.md`](null-semantics.md)，NULL 在比较、UNIQUE、GROUP BY 等场景的处理见 [`null-handling-behavior.md`](null-handling-behavior.md)。

## SQL 标准定义

### SQL:2003 引入的语法

SQL:2003 标准（ISO/IEC 9075-2, Section 10.10 \<sort specification list\>）首次引入了 `NULLS FIRST` 和 `NULLS LAST` 显式语法：

```sql
<sort specification> ::=
    <sort key> [ <ordering specification> ] [ <null ordering> ]

<ordering specification> ::= ASC | DESC

<null ordering> ::= NULLS FIRST | NULLS LAST
```

标准的关键约束：

1. **语法是可选的**：`NULLS FIRST/LAST` 不是必须出现的子句
2. **不强制默认值**：标准只说"如果未指定，由实现定义（implementation-defined）"
3. **与 ASC/DESC 正交**：`ASC NULLS FIRST` 和 `DESC NULLS LAST` 都是合法组合
4. **每列独立指定**：`ORDER BY a ASC NULLS LAST, b DESC NULLS FIRST` 合法

正是因为标准把"默认值"留给实现自己决定，才造成了今天各引擎的混乱局面。同一份 SQL 在不同引擎上跑出截然相反的 NULL 顺序，恰恰是"标准合规"的——每家都符合标准，结果却互相不兼容。

### 标准前的"民间共识"

在 SQL:2003 之前，业界大致存在两派"直觉"：

- **"NULL 是最大值"派**（Oracle、DB2、PostgreSQL）：NULL 表示"未知"，未知的薪资可能比 100 万还高，所以 ASC 时 NULL 排在最后，DESC 时 NULL 排在最前。
- **"NULL 是最小值"派**（MySQL、SQLite、SQL Server）：NULL 表示"没有值"，没有值就是 0 或更小，所以 ASC 时 NULL 排在最前，DESC 时 NULL 排在最后。

两派都没错，只是哲学不同。SQL:2003 没能统一，只给了一个能"显式表达意图"的语法工具。

## 支持矩阵（45+ 引擎综合）

### 1. NULLS FIRST / NULLS LAST 显式语法支持

| 引擎 | 支持显式语法 | 引入版本 | 备注 |
|------|------------|---------|------|
| PostgreSQL | 是 | 8.3 (2008) | 完整支持，每列独立指定 |
| MySQL | 是 | 8.0.12 (2018) | 较晚才补齐，老版本仅有默认行为 |
| MariaDB | 是 | 10.3+ | 兼容 MySQL 8 语法 |
| SQLite | 是 | 3.30 (2019) | 较晚补齐 |
| Oracle | 是 | 8i (1999) | 早期就支持，标准前已实现 |
| SQL Server | **否** | -- | 至今无显式语法，需 CASE WHEN |
| DB2 | 是 | LUW 8.2 / z/OS 9 | 完整支持 |
| Snowflake | 是 | GA | 可通过 session 参数改变默认 |
| BigQuery | 是 | GA | Standard SQL 支持 |
| Redshift | 是 | GA | 继承 PostgreSQL 语法 |
| DuckDB | 是 | 0.2+ | 完整支持 |
| ClickHouse | 是 | 20.7 (2020) | 较晚才补齐显式语法 |
| Trino | 是 | 早期 | 完整支持 |
| Presto | 是 | 0.193+ | 完整支持 |
| Spark SQL | 是 | 1.6+ | 完整支持 |
| Hive | 是 | 2.1.0 (HIVE-9535) | 较晚补齐 |
| Flink SQL | 是 | 1.11+ | 流和批均支持 |
| Databricks | 是 | GA | 继承 Spark |
| Teradata | 是 | V2R6+ | 完整支持 |
| Greenplum | 是 | 继承 PG | 完整支持 |
| CockroachDB | 是 | 2.0+ | 完整支持 |
| TiDB | 是 | 4.0+ | 兼容 MySQL 8 |
| OceanBase | 是 | Oracle/MySQL 双模式 | Oracle 模式默认与 Oracle 一致 |
| YugabyteDB | 是 | 2.0+ | 继承 PostgreSQL |
| SingleStore | 是 | 7.0+ | 完整支持 |
| Vertica | 是 | 7.0+ | 完整支持 |
| Impala | 是 | 1.2+ | 完整支持 |
| StarRocks | 是 | 2.5+ | 完整支持 |
| Doris | 是 | 1.2+ | 完整支持 |
| MonetDB | 是 | Jul2017+ | 完整支持 |
| CrateDB | 是 | 2.0+ | 完整支持 |
| TimescaleDB | 是 | 继承 PG | 完整支持 |
| QuestDB | 否 | -- | 时序场景，无 NULL 排序需求 |
| Exasol | 是 | 6.0+ | 完整支持 |
| SAP HANA | 是 | 1.0+ | 完整支持 |
| Informix | 否 | -- | 仅默认行为 |
| Firebird | 是 | 1.5+ | 完整支持 |
| H2 | 是 | 1.4+ | 完整支持 |
| HSQLDB | 是 | 2.0+ | 完整支持 |
| Derby | 是 | 10.4+ | 完整支持 |
| Amazon Athena | 是 | 继承 Trino | 完整支持 |
| Azure Synapse | 否 | -- | 继承 SQL Server，无显式语法 |
| Google Spanner | 是 | GA | 完整支持 |
| Materialize | 是 | GA | 继承 PG 语义 |
| RisingWave | 是 | GA | 继承 PG 语义 |
| InfluxDB (SQL) | 部分 | -- | IOx 引擎继承 DataFusion，支持 |
| DatabendDB | 是 | GA | 完整支持 |
| Yellowbrick | 是 | GA | 继承 PG |
| Firebolt | 是 | GA | 完整支持 |

> 统计：约 44 个引擎支持显式 `NULLS FIRST/LAST` 语法，仅 SQL Server 系（含 Synapse）、Informix、QuestDB 缺失。其中 MySQL、SQLite、ClickHouse、Hive 等几个引擎是较晚才补齐的，因此在老版本上仍需要 CASE WHEN 兜底。

### 2. ASC 默认排序（未指定 NULLS FIRST/LAST 时）

| 引擎 | ASC 默认 | 阵营 |
|------|---------|------|
| PostgreSQL | NULLS LAST | "NULL 最大"派 |
| MySQL | **NULLS FIRST** | "NULL 最小"派 |
| MariaDB | **NULLS FIRST** | "NULL 最小"派 |
| SQLite | **NULLS FIRST** | "NULL 最小"派 |
| Oracle | NULLS LAST | "NULL 最大"派 |
| SQL Server | **NULLS FIRST** | "NULL 最小"派 |
| DB2 | NULLS LAST | "NULL 最大"派 |
| Snowflake | **NULLS FIRST** | "NULL 最小"派（可改） |
| BigQuery | **NULLS FIRST** | "NULL 最小"派 |
| Redshift | NULLS LAST | "NULL 最大"派（继承 PG）|
| DuckDB | NULLS LAST | "NULL 最大"派 |
| ClickHouse | NULLS LAST | "NULL 最大"派 |
| Trino | NULLS LAST | "NULL 最大"派 |
| Presto | NULLS LAST | "NULL 最大"派 |
| Spark SQL | **NULLS FIRST** | "NULL 最小"派 |
| Hive | **NULLS FIRST** | "NULL 最小"派 |
| Flink SQL | **NULLS FIRST** | "NULL 最小"派 |
| Databricks | **NULLS FIRST** | 继承 Spark |
| Teradata | NULLS LAST | "NULL 最大"派 |
| Greenplum | NULLS LAST | 继承 PG |
| CockroachDB | NULLS LAST | "NULL 最大"派 |
| TiDB | **NULLS FIRST** | 兼容 MySQL |
| OceanBase (MySQL 模式) | **NULLS FIRST** | 兼容 MySQL |
| OceanBase (Oracle 模式) | NULLS LAST | 兼容 Oracle |
| YugabyteDB | NULLS LAST | 继承 PG |
| SingleStore | **NULLS FIRST** | 兼容 MySQL |
| Vertica | NULLS LAST | "NULL 最大"派 |
| Impala | **NULLS FIRST** | "NULL 最小"派 |
| StarRocks | **NULLS FIRST** | 兼容 MySQL |
| Doris | **NULLS FIRST** | 兼容 MySQL |
| MonetDB | **NULLS FIRST** | "NULL 最小"派 |
| CrateDB | **NULLS FIRST** | "NULL 最小"派 |
| TimescaleDB | NULLS LAST | 继承 PG |
| QuestDB | **NULLS FIRST** | "NULL 最小"派 |
| Exasol | NULLS LAST | "NULL 最大"派 |
| SAP HANA | **NULLS FIRST** | "NULL 最小"派 |
| Informix | **NULLS FIRST** | "NULL 最小"派 |
| Firebird | **NULLS FIRST** | "NULL 最小"派 |
| H2 | **NULLS FIRST** | "NULL 最小"派 |
| HSQLDB | **NULLS FIRST** | "NULL 最小"派 |
| Derby | **NULLS FIRST** | "NULL 最小"派 |
| Amazon Athena | NULLS LAST | 继承 Trino |
| Azure Synapse | **NULLS FIRST** | 继承 SQL Server |
| Google Spanner | **NULLS FIRST** | "NULL 最小"派 |
| Materialize | NULLS LAST | 继承 PG |
| RisingWave | NULLS LAST | 继承 PG |
| DatabendDB | **NULLS FIRST** | "NULL 最小"派 |
| Yellowbrick | NULLS LAST | 继承 PG |
| Firebolt | NULLS LAST | "NULL 最大"派 |

> 关键观察：两派几乎五五分。"NULL 最大"派 ~17 家，"NULL 最小"派 ~32 家。Oracle/PostgreSQL/DB2 这三大老牌商业/开源库共同站在"NULL 最大"一侧，而 MySQL 阵营和大多数 Apache 系（Spark/Hive/Flink/Impala）站在"NULL 最小"一侧。

### 3. DESC 默认排序

| 引擎 | DESC 默认 | 与 ASC 是否对称 |
|------|----------|---------------|
| PostgreSQL | NULLS FIRST | 对称（NULL 始终是"最大值"）|
| MySQL | NULLS LAST | 对称（NULL 始终是"最小值"）|
| MariaDB | NULLS LAST | 对称 |
| SQLite | NULLS LAST | 对称 |
| Oracle | NULLS FIRST | 对称 |
| SQL Server | NULLS LAST | 对称 |
| DB2 | NULLS FIRST | 对称 |
| Snowflake | NULLS LAST | 对称 |
| BigQuery | NULLS LAST | 对称 |
| Redshift | NULLS FIRST | 对称（继承 PG）|
| DuckDB | NULLS FIRST | 对称 |
| ClickHouse | NULLS LAST | **非对称**（ASC 和 DESC 都 NULLS LAST，2020 年前）|
| Trino | NULLS LAST | **非对称**（NULL 始终最后）|
| Presto | NULLS LAST | **非对称** |
| Spark SQL | NULLS LAST | 对称 |
| Hive | NULLS LAST | 对称 |
| Flink SQL | NULLS LAST | 对称 |
| Teradata | NULLS FIRST | 对称 |
| CockroachDB | NULLS FIRST | 对称 |
| TiDB | NULLS LAST | 对称 |
| Vertica | NULLS FIRST | 对称 |
| Impala | NULLS LAST | 对称 |
| StarRocks | NULLS LAST | 对称 |
| Doris | NULLS LAST | 对称 |
| Exasol | NULLS FIRST | 对称 |
| SAP HANA | NULLS LAST | **非对称** |
| Firebird | NULLS LAST | 对称 |
| H2 | NULLS LAST | 对称 |

> 重要提醒：**Trino / Presto / 早期 ClickHouse / SAP HANA** 是"非对称派"——无论 ASC 还是 DESC，NULL 都默认排最后。这与 PG/Oracle/MySQL 的"对称"行为完全不同，迁移时尤其要注意。

### 4. 是否需要 CASE WHEN 兜底

| 引擎/场景 | 是否需要 CASE WHEN | 说明 |
|----------|------------------|------|
| SQL Server (任何版本) | **是** | 唯一始终需要的引擎 |
| Azure Synapse | **是** | 继承 SQL Server |
| MySQL < 8.0.12 | 是 | 老版本无显式语法 |
| MySQL >= 8.0.12 | 否 | 已支持显式语法 |
| SQLite < 3.30 | 是 | 老版本无显式语法 |
| ClickHouse < 20.7 | 是 | 老版本无显式语法 |
| Hive < 2.1.0 | 是 | 老版本无显式语法 |
| Informix | 是 | 至今无显式语法 |
| QuestDB | 部分 | 时序场景较少需要 |
| 其他 40+ 引擎 | 否 | 直接使用显式语法 |

### 5. 索引对 NULL 排序的支持

| 引擎 | B-Tree 索引存储 NULL | 索引 NULL 顺序可控 | 说明 |
|------|-------------------|------------------|------|
| PostgreSQL | 是 | 是（CREATE INDEX ... NULLS FIRST/LAST）| 索引和查询 NULL 顺序需匹配才能避免排序 |
| Oracle | 否（默认）| 部分 | 默认 B-Tree 不存全 NULL 行，函数索引可绕过 |
| MySQL InnoDB | 是 | 否 | 总按 NULL FIRST 存储 |
| SQL Server | 是 | 否 | 总按 NULL FIRST 存储 |
| DB2 | 是 | 是 | LUW 9.7+ 支持 INCLUDE NULL KEYS 控制 |
| SQLite | 是 | 否 | 总按 NULL FIRST 存储 |
| ClickHouse (Sparse) | 是 | 部分 | 跳数索引不强制 NULL 顺序 |
| DuckDB | 是 | 是 | 支持 NULLS FIRST/LAST 索引 |
| CockroachDB | 是 | 是 | 完整支持 |
| YugabyteDB | 是 | 是 | 继承 PG |

> PostgreSQL 是少数允许在创建索引时指定 NULL 顺序的引擎。如果索引创建为 `NULLS LAST` 但查询请求 `NULLS FIRST`，优化器无法用该索引避免排序。

### 6. ORDER BY + LIMIT 与 NULL 的边缘情况

| 场景 | PostgreSQL | MySQL 8 | SQL Server | 注意 |
|------|-----------|---------|-----------|------|
| `ORDER BY col ASC LIMIT 10`（含大量 NULL）| 取最小的 10 个非 NULL | 取 10 个 NULL | 取 10 个 NULL | 默认行为差异巨大 |
| `ORDER BY col DESC LIMIT 10` | 取 10 个 NULL | 取最大的 10 个非 NULL | 取最大的 10 个非 NULL | 同上反向 |
| Top-N 排行榜（"前 10 高薪"）| 必须 `DESC NULLS LAST` | 必须 `DESC NULLS LAST` | 必须 CASE 兜底 | 否则 NULL 占据榜首/榜末 |
| 分页 keyset (col > $last) | NULL 永远不被 `>` 选中 | 同 PG | 同 PG | 必须用 `(col, id)` 复合 keyset |
| 联合排序 `ORDER BY a, b` | 每列独立 NULL 顺序 | 同 PG | 需多个 CASE | -- |

## 各引擎详解

### PostgreSQL（"NULL 最大"派的标杆）

```sql
-- ASC 默认 NULLS LAST
SELECT name, salary FROM employees ORDER BY salary;
-- 结果: 5000, 7000, 9000, ..., NULL, NULL

-- DESC 默认 NULLS FIRST (对称)
SELECT name, salary FROM employees ORDER BY salary DESC;
-- 结果: NULL, NULL, ..., 9000, 7000, 5000

-- 显式覆盖
SELECT name, salary FROM employees ORDER BY salary ASC NULLS FIRST;
SELECT name, salary FROM employees ORDER BY salary DESC NULLS LAST;

-- 多列独立指定
SELECT * FROM orders
ORDER BY priority DESC NULLS LAST,
         created_at ASC NULLS FIRST;

-- 索引匹配 NULL 顺序
CREATE INDEX idx_emp_salary ON employees (salary DESC NULLS LAST);
-- 此索引仅能服务 ORDER BY salary DESC NULLS LAST
```

PostgreSQL 的语义可以用一条统一规则记住："NULL 在排序键中视为正无穷大"。所以 ASC 时 NULL 在末尾、DESC 时 NULL 在开头，完全对称。

### Oracle（与 PostgreSQL 完全一致）

```sql
-- ASC 默认 NULLS LAST
SELECT ename, sal FROM emp ORDER BY sal;
-- NULL 在末尾

-- DESC 默认 NULLS FIRST
SELECT ename, sal FROM emp ORDER BY sal DESC;
-- NULL 在开头

-- 显式语法（Oracle 8i 起支持，比 PG 早 9 年）
SELECT * FROM emp ORDER BY comm DESC NULLS LAST;

-- 索引特殊性：默认 B-Tree 不索引全 NULL 行
CREATE INDEX idx_comm ON emp(comm);
-- 上述索引中 comm IS NULL 的行不会被存储

-- 绕过方法：函数索引或包含常量
CREATE INDEX idx_comm_full ON emp(comm, 1);
-- 这样 NULL 行也会被索引
```

Oracle 是历史上最早实现 `NULLS FIRST/LAST` 的主流商业数据库（8i, 1999），SQL:2003 标准其实是事后追认了 Oracle 的实现。

### MySQL（最戏剧性的演化故事）

```sql
-- MySQL 5.x / 8.0.11 及之前：无 NULLS FIRST/LAST 语法
-- 默认行为：NULL 总是被视为"最小值"
SELECT name, salary FROM employees ORDER BY salary;
-- NULL 在最前

SELECT name, salary FROM employees ORDER BY salary DESC;
-- NULL 在最后

-- 老版本想要 NULLS LAST 必须用 CASE 或 IS NULL
SELECT name, salary FROM employees
ORDER BY salary IS NULL, salary;
-- (salary IS NULL) 返回 0/1，0 排在 1 前面，所以 NULL 排末尾

-- 或者用 -salary 反转
SELECT name, salary FROM employees
ORDER BY -salary DESC;  -- NULL 仍在最后（因为 -NULL = NULL 仍是最小）

-- MySQL 8.0.12+ 终于支持显式语法
SELECT name, salary FROM employees ORDER BY salary ASC NULLS LAST;
SELECT name, salary FROM employees ORDER BY salary DESC NULLS FIRST;
```

**MySQL 与 PG/Oracle 阵营完全相反**——MySQL 把 NULL 当"最小值"，PG/Oracle 把 NULL 当"最大值"。这是历史上最常见的迁移坑，大量从 MySQL 迁移到 PG 的项目都因为 Top-N 排行榜的 NULL 位置变化而出现 bug。

### SQL Server（至今无显式语法）

```sql
-- SQL Server 至今 (2022) 仍不支持 NULLS FIRST/LAST 语法
-- 默认行为：与 MySQL 同，NULL 是"最小值"
SELECT name, salary FROM employees ORDER BY salary;
-- NULL 在最前

-- 想要 ASC NULLS LAST 必须用 CASE WHEN
SELECT name, salary FROM employees
ORDER BY CASE WHEN salary IS NULL THEN 1 ELSE 0 END, salary;

-- 或者更简洁的 IIF (SQL Server 2012+)
SELECT name, salary FROM employees
ORDER BY IIF(salary IS NULL, 1, 0), salary;

-- DESC NULLS LAST
SELECT name, salary FROM employees
ORDER BY CASE WHEN salary IS NULL THEN 1 ELSE 0 END, salary DESC;

-- 多列的复杂场景非常啰嗦
SELECT * FROM orders
ORDER BY CASE WHEN priority IS NULL THEN 1 ELSE 0 END, priority DESC,
         CASE WHEN created_at IS NULL THEN 0 ELSE 1 END, created_at ASC;
```

SQL Server 已经被社区呼吁加入 `NULLS FIRST/LAST` 语法十多年（[Connect/UserVoice 投票数千](https://feedback.azure.com/d365community/idea/4eb47a83-ad25-ec11-b6e6-000d3a4f0da0)），但官方至今未实现。Azure Synapse 同样缺失。

### DB2（早期标准实现者）

```sql
-- ASC 默认 NULLS LAST（与 PG/Oracle 一致）
SELECT name, salary FROM employees ORDER BY salary;

-- 显式语法
SELECT * FROM employees ORDER BY salary DESC NULLS LAST;

-- DB2 LUW 9.7+ 支持索引 NULL 顺序控制
CREATE INDEX idx_sal ON employees (salary DESC NULLS LAST)
INCLUDE NULL KEYS;
```

DB2 在 LUW 8.2 / z/OS 9 就支持显式语法，是商业数据库中最早跟进 SQL:2003 的之一。

### SQLite（小型库，跟着 MySQL 阵营）

```sql
-- SQLite 默认 ASC NULLS FIRST
SELECT name, salary FROM employees ORDER BY salary;
-- NULL 在最前

-- SQLite 3.30 (2019) 加入显式语法
SELECT name, salary FROM employees ORDER BY salary ASC NULLS LAST;

-- 老版本绕过
SELECT name, salary FROM employees
ORDER BY salary IS NULL, salary;
```

SQLite 在 3.30 之前不支持显式语法，许多嵌入式应用代码至今还保留着 `salary IS NULL` 的 hack。

### Snowflake（NULLS FIRST + 可参数化）

```sql
-- 默认 ASC NULLS FIRST（与 BigQuery 一致，与 PG 相反）
SELECT * FROM employees ORDER BY salary;

-- 显式语法
SELECT * FROM employees ORDER BY salary ASC NULLS LAST;

-- Snowflake 独有：通过 session 参数改变默认行为
ALTER SESSION SET DEFAULT_NULL_ORDERING = 'LOW';
-- 'LOW' = NULL 视为最小（ASC 时在前），'HIGH' = NULL 视为最大
-- 注意：此参数自 2014 年起可用，是 Snowflake 独家特性

ALTER SESSION SET DEFAULT_NULL_ORDERING = 'HIGH';
SELECT * FROM employees ORDER BY salary;  -- 现在 NULL 在末尾
```

Snowflake 是少数允许通过会话参数动态调整全局默认 NULL 排序的引擎，对从其他系统迁移的工作负载非常友好。

### BigQuery（NULLS FIRST 默认）

```sql
-- ASC 默认 NULLS FIRST
SELECT name, salary FROM employees ORDER BY salary;
-- NULL 在最前

-- 显式语法
SELECT * FROM employees ORDER BY salary ASC NULLS LAST;
SELECT * FROM employees ORDER BY salary DESC NULLS FIRST;

-- BigQuery 对 ARRAY 元素的排序也支持 NULL 顺序
SELECT ARRAY(SELECT x FROM UNNEST([1, NULL, 3]) AS x ORDER BY x NULLS LAST);
```

BigQuery 默认 `NULLS FIRST` 与 PostgreSQL 不同，从 PG 迁移到 BigQuery 的查询如果只指定 `ORDER BY` 而未显式 `NULLS LAST`，会得到不同结果。

### ClickHouse（20.7 之前的非对称）

```sql
-- ClickHouse 历史上的奇特行为：
-- 20.7 之前，ASC 和 DESC 都默认 NULLS LAST
-- 这是"非对称"的，与 PG/MySQL 都不同

-- 20.7 (2020) 起加入显式 NULLS FIRST/LAST 语法
SELECT name, salary FROM employees ORDER BY salary ASC NULLS FIRST;
SELECT name, salary FROM employees ORDER BY salary DESC NULLS LAST;

-- ClickHouse 的 Nullable 类型本身就有特殊存储
-- ORDER BY 在 Nullable 列上需要额外的 null map 解析开销
```

ClickHouse 的"非对称"默认源自其早期对 NULL 的支持本身就不完整（Nullable 是后加的类型）。20.7 之后建议始终显式指定。

### DuckDB（NULL 视为最大，与 PG 一致）

```sql
-- ASC 默认 NULLS LAST
SELECT name, salary FROM employees ORDER BY salary;

-- 显式语法
SELECT * FROM employees ORDER BY salary ASC NULLS FIRST;

-- DuckDB 还支持配置默认行为
SET default_null_order = 'NULLS_FIRST';
-- 之后 ORDER BY 默认 NULLS_FIRST
```

DuckDB 与 PostgreSQL 阵营一致（NULL 视为最大），同时也提供了类似 Snowflake 的会话级开关。

### Spark SQL / Hive / Databricks

```sql
-- Spark SQL 默认 ASC NULLS FIRST
SELECT name, salary FROM employees ORDER BY salary;
-- NULL 在最前（与 MySQL 一致）

-- 显式
SELECT * FROM employees ORDER BY salary ASC NULLS LAST;

-- Spark 支持 SORT BY（分区内排序）也支持 NULL 顺序
SELECT * FROM employees DISTRIBUTE BY dept SORT BY salary DESC NULLS LAST;
```

Apache 系（Spark/Hive/Flink/Impala）大多默认 `NULLS FIRST`，与 PG/Oracle 阵营相反，与 MySQL/SQL Server 阵营一致。

### Trino / Presto（非对称：始终 NULLS LAST）

```sql
-- Trino 默认行为非常特殊：ASC 和 DESC 都把 NULL 放最后
SELECT name, salary FROM employees ORDER BY salary;
-- 非 NULL 升序 + NULL 在末尾

SELECT name, salary FROM employees ORDER BY salary DESC;
-- 非 NULL 降序 + NULL 在末尾（NOT 反转！）

-- 显式语法当然支持
SELECT * FROM employees ORDER BY salary DESC NULLS FIRST;
```

Trino/Presto 的"非对称"行为是经过深思熟虑的——通常用户做 Top-N 时希望 NULL 不要污染榜首/榜末。但这与 PG/MySQL 都不同，从其他系统迁移过来的 SQL 经常出问题。

## MySQL 8.0.12 演化深度回顾

### 演化前的世界

MySQL 5.7 及之前没有任何方式直接表达"我想要 NULLS LAST"。开发者发明了三种主流 hack：

```sql
-- Hack 1: 利用 IS NULL 的布尔结果
SELECT * FROM t ORDER BY col IS NULL, col;
-- (col IS NULL) 返回 0 (FALSE) 或 1 (TRUE)
-- 0 < 1, 所以非 NULL 行排在前
-- 这是最常见的写法，至今仍在大量代码中存在

-- Hack 2: 利用 -col 反转
SELECT * FROM t ORDER BY -col DESC;
-- 数值列适用，但 -NULL = NULL 仍是最小

-- Hack 3: COALESCE 兜底
SELECT * FROM t ORDER BY COALESCE(col, 9999999);
-- 用一个"足够大"的哨兵值替换 NULL
-- 风险：哨兵值可能与真实数据冲突
```

每种 hack 都有缺点：Hack 1 增加排序键宽度；Hack 2 仅适用于数值；Hack 3 依赖于人工选择哨兵。

### 8.0.12 引入的官方语法

```sql
-- WL#9354 实现，2018 年 7 月发布
SELECT * FROM t ORDER BY col ASC NULLS LAST;
SELECT * FROM t ORDER BY col DESC NULLS FIRST;

-- 与索引联动
CREATE INDEX idx_t_col ON t (col DESC);
-- 注意：MySQL 索引仍按内部规则存储 NULL，不能像 PG 那样指定 NULLS 顺序
```

但 MySQL 的实现并不彻底：

1. **执行层仍按老规则排序**：8.0.12 实际上是把 `NULLS LAST` 重写为等价的 CASE WHEN 表达式插入排序键。性能略差于原生支持。
2. **索引未参与**：InnoDB B-Tree 仍按"NULL 最小"存储，所以即使 `ORDER BY col ASC NULLS LAST` 命中索引，仍需要额外的内存排序步骤。
3. **优化器不会等价转换**：`ORDER BY col ASC NULLS FIRST`（相当于默认）才能完美利用索引。

### 迁移影响

任何从 MySQL 5.7 迁移到 8.0 或迁移到 PG/Oracle 的项目都应该审视一遍 ORDER BY 语句。常见 bug：

```sql
-- 业务代码：取薪资最高的 10 人
SELECT * FROM employees ORDER BY salary DESC LIMIT 10;

-- MySQL 5.7: salary 最高的 10 个非 NULL 行
-- PostgreSQL: 10 个 NULL 行（NULL 视为最大，DESC 时在前）
-- 业务结果：排行榜首页全是空白！
```

正确写法：

```sql
SELECT * FROM employees
ORDER BY salary DESC NULLS LAST
LIMIT 10;
-- 在 MySQL 8.0.12+, PG, Oracle, DB2 等均得到一致结果
```

## SQL Server CASE WHEN 兜底详解

由于 SQL Server 至今不支持 `NULLS FIRST/LAST`，所有移植性场景都依赖 CASE WHEN。

### 基础 4 种组合

```sql
-- 1. ASC NULLS FIRST（=SQL Server 默认，无需 CASE）
SELECT * FROM t ORDER BY col ASC;

-- 2. ASC NULLS LAST
SELECT * FROM t
ORDER BY CASE WHEN col IS NULL THEN 1 ELSE 0 END, col ASC;

-- 3. DESC NULLS FIRST
SELECT * FROM t
ORDER BY CASE WHEN col IS NULL THEN 0 ELSE 1 END, col DESC;

-- 4. DESC NULLS LAST（=SQL Server 默认，无需 CASE）
SELECT * FROM t ORDER BY col DESC;
```

### IIF 简写

```sql
SELECT * FROM t
ORDER BY IIF(col IS NULL, 1, 0), col ASC;  -- ASC NULLS LAST
```

### 多列复杂场景

```sql
-- 想表达：ORDER BY a DESC NULLS LAST, b ASC NULLS FIRST
SELECT * FROM t
ORDER BY IIF(a IS NULL, 1, 0), a DESC,
         IIF(b IS NULL, 0, 1), b ASC;
```

### 性能影响

CASE WHEN 排序键会让 SQL Server 优化器失去使用单列索引的能力——即使有 `(a)` 索引也无法直接服务于 `ORDER BY CASE WHEN a IS NULL THEN 1 ELSE 0 END, a` 的请求。常见的解决方案：

```sql
-- 为常用的 NULLS LAST 查询创建计算列 + 索引
ALTER TABLE t ADD a_null_marker AS (CASE WHEN a IS NULL THEN 1 ELSE 0 END) PERSISTED;
CREATE INDEX idx_t_a_nl ON t(a_null_marker, a);

-- 之后查询能命中索引
SELECT * FROM t ORDER BY a_null_marker, a;
```

或者在查询时通过 `WHERE a IS NOT NULL` 把 NULL 行单独 UNION：

```sql
SELECT * FROM (
    SELECT * FROM t WHERE a IS NOT NULL
    ORDER BY a OFFSET 0 ROWS
) x
UNION ALL
SELECT * FROM t WHERE a IS NULL;
```

## 索引对 NULL 排序的支持

### PostgreSQL：唯一允许在 CREATE INDEX 中指定 NULL 顺序的主流引擎

```sql
-- 创建一个 DESC NULLS LAST 的索引
CREATE INDEX idx_emp_salary_desc_nl ON employees (salary DESC NULLS LAST);

-- 此索引仅能服务匹配的 ORDER BY
EXPLAIN SELECT * FROM employees ORDER BY salary DESC NULLS LAST LIMIT 10;
-- Index Scan using idx_emp_salary_desc_nl

EXPLAIN SELECT * FROM employees ORDER BY salary DESC NULLS FIRST LIMIT 10;
-- 仍可用，因为 PG 可以反向扫描索引（DESC NULLS LAST 反向 = ASC NULLS FIRST，不匹配）
-- 实际：Sort + Seq Scan，无法用索引

-- 多列索引每列独立指定
CREATE INDEX idx_orders ON orders (priority DESC NULLS LAST, created_at ASC NULLS FIRST);
```

PG 的索引存储顺序必须与查询完全一致（或完全反向），才能避免排序步骤。这是 PG 在 NULL 排序设计上最严谨的体现。

### Oracle：B-Tree 默认不索引全 NULL 行

```sql
-- 默认行为：NULL 行不进入 B-Tree 索引
CREATE INDEX idx_comm ON emp(comm);
SELECT * FROM emp WHERE comm IS NULL;  -- 全表扫描，索引无法用

-- 解决方案 1: 复合索引（多列时只要有一列非 NULL 就会被索引）
CREATE INDEX idx_comm ON emp(comm, dummy);

-- 解决方案 2: 函数索引
CREATE INDEX idx_comm_nvl ON emp(NVL(comm, -1));
SELECT * FROM emp WHERE NVL(comm, -1) = -1;

-- 解决方案 3: 位图索引（包含 NULL）
CREATE BITMAP INDEX idx_comm_bm ON emp(comm);
```

Oracle 的"NULL 不索引"是性能优化（节省存储），但带来了"NULL 查找无法走索引"的副作用。

### MySQL InnoDB：始终按"NULL 最小"存储

```sql
-- InnoDB B+ 树中 NULL 总是排在键值最前
CREATE INDEX idx_t_a ON t(a);
-- 对应 ORDER BY a ASC NULLS FIRST 可以完美利用

EXPLAIN SELECT * FROM t ORDER BY a ASC LIMIT 10;
-- 使用索引，无 filesort

EXPLAIN SELECT * FROM t ORDER BY a ASC NULLS LAST LIMIT 10;
-- 使用索引但需 filesort（MySQL 8.0.12+ 把 NULLS LAST 转为 CASE WHEN）
```

### 列存引擎中的 NULL 排序

```
列存（Parquet/ORC/ClickHouse MergeTree）的特点：
  - NULL 单独存在 null bitmap 中
  - 排序键的 NULL 顺序通常存储在 metadata
  - SYSTEM 采样、min/max 索引等对 NULL 的处理与行存不同

ClickHouse MergeTree:
  - ORDER BY 子句定义的列必须是 Nullable 才能存 NULL
  - 排序时 NULL 默认在末尾（无论 ASC/DESC）
  - 跳数索引（minmax/set）对 NULL 的处理依赖列定义
```

## 关键发现

### 1. SQL:2003 解决了语法问题，没解决默认值问题

标准给了 `NULLS FIRST/LAST` 关键字，但默认值由实现自定。这个"开放"决定让两大派系合法共存了 20 多年，至今没有统一的迹象。任何宣称"符合 SQL 标准"的引擎在 NULL 排序上都可能与你预期的不同。

### 2. 两大阵营的分布几乎五五开

- **NULL 最大派**（ASC NULLS LAST）：PostgreSQL、Oracle、DB2、DuckDB、Trino/Presto、Snowflake（可改）、BigQuery（反例）等
- **NULL 最小派**（ASC NULLS FIRST）：MySQL、SQL Server、SQLite、Spark/Hive/Flink、SAP HANA 等

老牌商业关系库（Oracle、DB2、PG）站在"NULL 最大"，而流行的 OLTP 库（MySQL、SQL Server、SQLite）和大数据系统（Spark/Hive）站在"NULL 最小"。这意味着 OLTP 和大数据迁移到分析型 OLAP 时几乎一定会踩坑。

### 3. SQL Server 是最大的钉子户

SQL Server 至今（2024 SQL Server 2022 + Azure Synapse）不支持 `NULLS FIRST/LAST` 语法。这是社区长期以来抱怨最多的可移植性 gap。所有需要跨 SQL Server 移植的代码都必须保留 CASE WHEN 兜底层。

### 4. MySQL 8.0.12 是分水岭

MySQL 在 2018 年才补齐显式语法，而且实现是"语法糖式"的——执行层并未真正按 NULL 顺序优化索引扫描。从 MySQL 5.7 升级到 8.0 时，原本的 `salary IS NULL, salary` hack 仍然有效，但建议统一改写为 `NULLS FIRST/LAST`。

### 5. 非对称派的存在容易被忽视

Trino/Presto、SAP HANA、早期 ClickHouse 采用"非对称"默认——无论 ASC 还是 DESC，NULL 都默认在末尾。这与所有其他主流引擎都不同。从 Hive on Tez 迁移到 Presto/Trino 是高频踩坑场景。

### 6. 索引 NULL 顺序只有 PG 系做得最好

只有 PostgreSQL 及其衍生（Greenplum、Yellowbrick、CockroachDB、YugabyteDB）允许在 `CREATE INDEX` 时指定 NULL 顺序。其他引擎要么强制按引擎默认存储，要么干脆不索引 NULL（Oracle）。这意味着在 PG 之外，跨默认值的 NULL 排序查询几乎一定要做内存排序。

### 7. 防御性编程的最佳实践

无论目标引擎如何，**始终显式写 NULLS FIRST/LAST**。代价仅是 12 个字符，收益是跨引擎可移植 + 可读性 + 避免业务 bug：

```sql
-- 推荐
SELECT * FROM employees ORDER BY salary DESC NULLS LAST LIMIT 10;

-- 不推荐
SELECT * FROM employees ORDER BY salary DESC LIMIT 10;
```

唯一例外是 SQL Server / Synapse / Informix / 老 MySQL，这些环境必须用 CASE WHEN 包裹一层兼容层。

### 8. ORDER BY + LIMIT 是最大的业务陷阱

排行榜（"销售额前 10 商品"、"评分最高 10 部电影"、"延迟最低的 10 个 API"）几乎都有 NULL 数据。在没有显式 `NULLS LAST` 的情况下：

- PG/Oracle/DB2: 榜首/榜尾被 NULL 占据
- MySQL/SQL Server: 榜尾/榜首被 NULL 占据
- 所有引擎都"符合标准"，但业务结果完全不同

Top-N 查询是 NULL 排序差异最致命的场景，必须强制显式指定。

### 9. 引擎实现建议

对于新设计的 SQL 引擎：

- **默认值选择**：建议选择"NULL 最大"（PG 路线），符合"NULL 表示未知值"的语义直觉
- **必须支持显式语法**：`NULLS FIRST/LAST` 已是事实标准
- **索引 NULL 顺序可控**：参考 PG 的 `CREATE INDEX ... NULLS FIRST/LAST`
- **优化器规则**：能识别 `ORDER BY ... NULLS X LIMIT N` 模式，避免全排序
- **会话参数开关**：参考 Snowflake 的 `DEFAULT_NULL_ORDERING`，对迁移用户友好
- **统计信息**：直方图应区分 NULL 和非 NULL，便于 Top-N 优化器精确估算

## 总结对比矩阵

### NULL 排序行为速查

| 引擎 | ASC 默认 | DESC 默认 | 显式语法 | 索引 NULL 可控 | 阵营 |
|------|---------|----------|---------|-------------|------|
| PostgreSQL | NULLS LAST | NULLS FIRST | 是 | 是 | NULL 最大 |
| Oracle | NULLS LAST | NULLS FIRST | 是 (8i+) | 部分 | NULL 最大 |
| DB2 | NULLS LAST | NULLS FIRST | 是 | 是 | NULL 最大 |
| MySQL 8+ | NULLS FIRST | NULLS LAST | 是 (8.0.12+) | 否 | NULL 最小 |
| MySQL 5.x | NULLS FIRST | NULLS LAST | **否** | 否 | NULL 最小 |
| SQL Server | NULLS FIRST | NULLS LAST | **否** | 否 | NULL 最小 |
| SQLite | NULLS FIRST | NULLS LAST | 是 (3.30+) | 否 | NULL 最小 |
| Snowflake | NULLS FIRST | NULLS LAST | 是 | -- | 可改 |
| BigQuery | NULLS FIRST | NULLS LAST | 是 | -- | NULL 最小 |
| Redshift | NULLS LAST | NULLS FIRST | 是 | 是 | NULL 最大 |
| DuckDB | NULLS LAST | NULLS FIRST | 是 | 是 | NULL 最大 |
| ClickHouse 20.7+ | NULLS LAST | NULLS LAST | 是 | 部分 | 非对称 |
| Trino/Presto | NULLS LAST | NULLS LAST | 是 | -- | 非对称 |
| Spark SQL | NULLS FIRST | NULLS LAST | 是 | -- | NULL 最小 |
| Hive 2.1+ | NULLS FIRST | NULLS LAST | 是 | -- | NULL 最小 |
| SAP HANA | NULLS FIRST | NULLS LAST | 是 | -- | 非对称（部分）|
| CockroachDB | NULLS LAST | NULLS FIRST | 是 | 是 | NULL 最大 |
| TiDB | NULLS FIRST | NULLS LAST | 是 | 否 | NULL 最小 |

### 迁移风险等级

| 迁移方向 | 风险等级 | 主要问题 |
|---------|---------|---------|
| MySQL → PostgreSQL | 高 | NULL 默认位置反转，所有 ORDER BY 需审视 |
| MySQL → Oracle | 高 | 同上 |
| PostgreSQL → MySQL | 高 | 同上反向 |
| MySQL 5.7 → MySQL 8 | 低 | 默认行为兼容，可逐步采用新语法 |
| Oracle → PostgreSQL | 低 | 默认值一致，无 NULL 排序差异 |
| PostgreSQL → Greenplum/Redshift | 低 | 完全兼容 |
| PostgreSQL → Trino | 中 | DESC 时 NULL 位置不同 |
| Hive → Trino/Presto | 中 | DESC 时 NULL 位置不同 |
| MySQL → SQL Server | 低 | 默认行为相同，但 SQL Server 无显式语法 |
| 任何 → SQL Server | 高 | 必须重写为 CASE WHEN |

## 参考资料

- SQL:2003 标准: ISO/IEC 9075-2, Section 10.10 (sort specification list)
- PostgreSQL: [SELECT ORDER BY](https://www.postgresql.org/docs/current/sql-select.html#SQL-ORDERBY)
- PostgreSQL: [CREATE INDEX with NULLS FIRST/LAST](https://www.postgresql.org/docs/current/sql-createindex.html)
- Oracle: [ORDER BY Clause](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/SELECT.html)
- MySQL 8.0.12 release notes: [WL#9354 NULLS FIRST/LAST](https://dev.mysql.com/doc/relnotes/mysql/8.0/en/news-8-0-12.html)
- MySQL: [ORDER BY Optimization](https://dev.mysql.com/doc/refman/8.0/en/order-by-optimization.html)
- SQL Server: [ORDER BY Clause](https://learn.microsoft.com/en-us/sql/t-sql/queries/select-order-by-clause-transact-sql)
- SQL Server feedback: [Add NULLS FIRST/LAST syntax](https://feedback.azure.com/d365community/idea/4eb47a83-ad25-ec11-b6e6-000d3a4f0da0)
- DB2 LUW: [ORDER BY clause](https://www.ibm.com/docs/en/db2/11.5?topic=queries-select-statement)
- SQLite 3.30 release notes: [NULLS FIRST/LAST](https://www.sqlite.org/releaselog/3_30_0.html)
- Snowflake: [DEFAULT_NULL_ORDERING parameter](https://docs.snowflake.com/en/sql-reference/parameters)
- BigQuery: [ORDER BY](https://cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#order_by_clause)
- ClickHouse 20.7 release notes: [NULLS FIRST/LAST in ORDER BY](https://clickhouse.com/docs/en/whats-new/changelog/)
- Trino: [ORDER BY Clause](https://trino.io/docs/current/sql/select.html#order-by-clause)
- Spark SQL: [ORDER BY Clause](https://spark.apache.org/docs/latest/sql-ref-syntax-qry-select-orderby.html)
- DuckDB: [ORDER BY](https://duckdb.org/docs/sql/query_syntax/orderby)
