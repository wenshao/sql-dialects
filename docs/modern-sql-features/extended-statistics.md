# 扩展统计信息 (Multi-column and Correlation Statistics)

优化器对单列统计信息的依赖是 CBO 的基础，但现实数据中列与列之间从来不是独立的——zipcode 决定 city、月份决定季度、品牌决定价格区间、设备型号决定操作系统。当优化器盲目假设独立性（Attribute Value Independence, AVI），就会把 `WHERE city='Beijing' AND zip='100084'` 的选择性估算成两个概率相乘，得到一个比实际小 1000 倍的结果，最终输出 Nested Loop + Index Seek 的灾难性计划，而正确的计划本应是 Hash Join + 并行扫描。本文专注于**多列统计（multi-column statistics）与列相关性（correlation statistics）**——扩展统计信息是解决这一根本性缺陷的唯一手段，也是当代 CBO 从"能用"走向"准"的分水岭。

> 本文是"统计信息"系列的第二篇。第一篇 [`statistics-histograms.md`](./statistics-histograms.md) 系统介绍了单列统计（NDV、直方图、MCV）。本文专注于多列 / 函数依赖 / 相关性这一维度，建议两篇配合阅读。

## 为什么单列统计会错得离谱

现代 CBO 在估算复合谓词时，默认采用**属性值独立性假设（Attribute Value Independence, AVI）**：

```
sel(p1 AND p2) = sel(p1) × sel(p2)
```

这在 p1、p2 所作用的列彼此独立时是正确的。但在真实数据中，列之间往往存在以下三种相关性：

1. **函数依赖（Functional Dependency）**：给定 A 的值，B 的值就被完全确定（或高度受限）。典型例子：`zip → city`、`product_id → brand`、`ip → country`。
2. **部分相关（Partial Correlation）**：A 和 B 不完全互相决定，但存在统计相关性。典型例子：`age 与 income`、`device_type 与 os`。
3. **联合频率倾斜（Joint Frequency Skew）**：单独看 A 或 B 的分布都不算极端，但某个 (a, b) 组合特别高频或特别稀少。典型例子：`(country=US, language=en)` 极高频、`(country=JP, language=ar)` 几乎为零。

当优化器忽略这些相关性，选择性估计可能偏差 10×、100× 甚至 10000×。具体误差方向：

- 对 **AND** 谓词（两列同时命中）：优化器会**低估**结果行数。因为两列其实强相关（比如 `city='Beijing' AND zip='100084'`），而 AVI 假设两者独立 → sel 相乘 → 估算远低于真实。
- 对 **GROUP BY 多列**：优化器会**高估**分组数量。`GROUP BY city, zip` 的真实 NDV 可能只有 40 万个组合（每个 city 对应少数 zip），但 AVI 假设 NDV(city) × NDV(zip) = 数百万组合。
- 对 **JOIN on (A, B)**：当 JOIN 键是多列且相关时，AVI 导致选择性严重低估，输出行数估计过小，错误选择 Nested Loop。

### 一个经典案例

```sql
-- 表 addresses: 1000 万行
-- NDV(city) = 500
-- NDV(zip) = 40000
-- 但 (city, zip) 的组合实际只有 45000 种（每个 city 平均 90 个 zip）

-- 优化器在 AVI 下估算:
--   sel(city='Beijing') = 1/500 = 0.002
--   sel(zip='100084')   = 1/40000 = 0.000025
--   sel(AND)            = 0.002 × 0.000025 = 5e-8
--   estimated rows       = 1e7 × 5e-8 = 0.5 行

-- 真实情况（zip 决定 city）:
--   zip='100084' 本身有 250 行，且全部 city='Beijing'
--   所以 sel(AND) = 250/1e7 = 2.5e-5
--   actual rows = 250 行

-- 估算误差: 500 倍低估
-- 后果: 优化器选择 Nested Loop + Index Seek，实际需要处理 250 行却以为只有 0.5 行，
--       JOIN 另一表时代价估算失真 500 倍，整个计划崩溃
```

这不是理论上的边缘情况。Oracle、PostgreSQL、SQL Server 的用户邮件列表里，"city/zip"、"order_status/payment_status"、"product_category/brand"、"manufacturer/model" 是最常见的性能问题模式。

## 没有 SQL 标准

ISO/IEC 9075（SQL 标准的各个版本）**从未对统计信息收集做任何规定**，多列 / 扩展统计信息当然也不例外。每个数据库厂商各自发明语法：

- PostgreSQL 的 `CREATE STATISTICS ... ON (a, b) FROM t`
- Oracle 的 `DBMS_STATS.CREATE_EXTENDED_STATS(schema, table, '(a, b)')`
- SQL Server 的 `CREATE STATISTICS ... ON t(a, b)`
- DB2 的 `RUNSTATS ON TABLE t ON COLUMNS ((a, b))`
- Teradata 的 `COLLECT STATISTICS ON t COLUMN (a, b)`
- CockroachDB 的 `CREATE STATISTICS n ON (a, b) FROM t`

语法差异看似表面，实际背后是**完全不同的数据结构和代价模型**。PostgreSQL 的 `dependencies` 类型存储的是一组条件概率 p(a|b) 和 p(b|a)；Oracle 的扩展列组本质上是虚拟列；SQL Server 的多列统计只记录第一列的直方图外加前 N 列的密度向量（density vector）——这三种方案对同一份数据产生的基数估计可能差一个数量级。

因此，扩展统计不是"可移植的 SQL 特性"，而是每家数据库 CBO 的**私有优化能力**。把 PostgreSQL 的多列统计迁移到 SQL Server，你不仅要改语法，还要重新理解 SQL Server 的"第一列直方图 + 密度向量"到底对哪些查询有效。

## 支持矩阵（综合）

### 多列统计（Multi-column Statistics）

| 引擎 | 多列语法 | 存储结构 | 版本 | 自动创建 |
|------|---------|---------|------|---------|
| PostgreSQL | `CREATE STATISTICS s ON (a, b) FROM t` | 独立对象，三种类型 | 10+ (2017) | 否 |
| Oracle | `DBMS_STATS.CREATE_EXTENDED_STATS` | 虚拟列 + 常规统计 | 11g+ (2007) | 11g `MONITOR_EXTENDED_STATS` 可推荐 |
| SQL Server | `CREATE STATISTICS s ON t(a, b)` | 首列直方图 + 密度向量 | 2000+ | `AUTO_CREATE_STATISTICS` 单列 |
| DB2 (LUW) | `RUNSTATS ON TABLE t ON COLUMNS ((a, b))` | 列组基数 + 联合直方图 | 9.5+ | 否 |
| MySQL | -- | -- | -- | 不支持 |
| MariaDB | -- | -- | -- | 不支持 |
| SQLite | -- | -- | -- | 仅 sqlite_stat4 间接 |
| CockroachDB | `CREATE STATISTICS s ON (a,b) FROM t` | 多列直方图 | 20.1+ | 是（自动） |
| TiDB | -- | -- | -- | 不支持（v7.x） |
| OceanBase | `DBMS_STATS.CREATE_EXTENDED_STATS` | 兼容 Oracle | 3.x+ | 否 |
| YugabyteDB | `CREATE STATISTICS` | 继承 PG | 2.6+ | 否 |
| Greenplum | `CREATE STATISTICS` | 继承 PG | 7.0+ | 否 |
| TimescaleDB | `CREATE STATISTICS` | 继承 PG | 继承 | 继承 |
| Teradata | `COLLECT STATISTICS ON t COLUMN (a, b)` | 多列直方图 | V2R5+ | 否 |
| Vertica | -- | -- | -- | 不支持 |
| SAP HANA | `CREATE STATISTICS ON t(a, b) TYPE HISTOGRAM` | data statistics object | 2.0+ | 是（可配） |
| Impala | -- | -- | -- | 不支持 |
| Spark SQL | -- | -- | -- | 不支持 |
| Databricks | -- | -- | -- | 不支持 |
| Hive | -- | -- | -- | 不支持 |
| Flink SQL | -- | -- | -- | 不支持 |
| Trino | -- | -- | -- | 不支持 |
| Presto | -- | -- | -- | 不支持 |
| Snowflake | 内部 | 完全托管 | GA | 是（不可见） |
| BigQuery | 内部 | 完全托管 | GA | 是（不可见） |
| Redshift | -- | -- | -- | 不支持 |
| ClickHouse | -- | -- | -- | 不支持（传统意义） |
| DuckDB | -- | -- | -- | 不支持 |
| StarRocks | -- | -- | -- | 不支持（3.x 规划中） |
| Doris | -- | -- | -- | 不支持 |
| SingleStore | -- | -- | -- | 不支持 |
| Informix | `UPDATE STATISTICS ... MULTIPLE COLUMN DISTRIBUTION` | 多列分布 | 14.10+ | 否 |
| MonetDB | -- | -- | -- | 不支持 |
| CrateDB | -- | -- | -- | 不支持 |
| QuestDB | -- | -- | -- | 不支持 |
| Exasol | 内部 | 自动维护 | 6+ | 是（不可见） |
| Firebird | -- | -- | -- | 不支持 |
| H2 | -- | -- | -- | 不支持 |
| HSQLDB | -- | -- | -- | 不支持 |
| Derby | -- | -- | -- | 不支持 |
| Azure Synapse | `CREATE STATISTICS` | 继承 SQL Server | GA | 是 |
| Amazon Athena | -- | -- | -- | 不支持 |
| Google Spanner | 内部 | 完全托管 | GA | 是（不可见） |
| Materialize | -- | -- | -- | 不适用 |
| RisingWave | -- | -- | -- | 不适用 |
| InfluxDB (SQL) | -- | -- | -- | 不适用 |
| DatabendDB | -- | -- | -- | 不支持 |
| Yellowbrick | `CREATE STATISTICS` | 继承 PG | GA | 否 |
| Firebolt | -- | -- | -- | 不暴露 |

> 统计：在 45+ 数据库中，仅约 **14 个引擎**原生支持用户定义的多列统计，另有约 5 个托管服务在内部实现但不暴露。开源 MPP（StarRocks / Doris / Trino）和嵌入式引擎（DuckDB / SQLite）普遍缺失这一能力。

### 函数依赖统计（Functional Dependency Statistics）

| 引擎 | 函数依赖 | 条件概率 p(b\|a) | 多向依赖 | 语法示例 |
|------|---------|----------------|---------|---------|
| PostgreSQL | 是 | 是 | 是 | `CREATE STATISTICS s (dependencies) ON a, b FROM t` |
| Oracle | 间接（通过 column group） | 是（NDV 推断） | 否 | `CREATE_EXTENDED_STATS` |
| SQL Server | 间接（density vector） | 单向 | 否 | `CREATE STATISTICS` |
| DB2 | 是（column group） | 是 | 是 | `RUNSTATS ON COLUMN GROUP` |
| CockroachDB | 否 | -- | -- | -- |
| TiDB | 否 | -- | -- | -- |
| OceanBase | 间接 | 是 | 否 | DBMS_STATS 兼容 Oracle |
| Teradata | 是 | 是 | 是 | `COLLECT STATISTICS ON COLUMN (a, b)` |
| Greenplum | 是 | 是 | 是 | 继承 PG |
| SAP HANA | 是 | 是 | 是 | data statistics dependencies |
| 其他 | -- | -- | -- | 不支持 |

### MCV 列表支持（Most Common Values）

| 引擎 | 单列 MCV | 多列 MCV | MCV 最大长度 | 版本 |
|------|---------|---------|-------------|------|
| PostgreSQL | 是 | 是（PG 12+） | `statistics_target`（默认 100） | 12+ |
| Oracle | 是（frequency + top-freq） | -- | 254（12c 起部分到 2048） | 所有版本 |
| SQL Server | -- | -- | -- | 不支持 |
| DB2 | 是（quantile） | 是 | 可配 | 9.5+ |
| Teradata | 是（biased values） | 是 | 可配 | V2R5+ |
| TiDB | 是（Top-N） | -- | 1024 | v5.1+ |
| StarRocks | 是 | -- | 可配 | 2.5+ |
| Doris | 是 | -- | 可配 | 2.0+ |
| CockroachDB | 是（直方图桶） | -- | 可配 | 20.1+ |
| MySQL | -- (仅直方图 singleton) | -- | -- | -- |
| MariaDB | -- | -- | -- | -- |
| SAP HANA | 是 | 是 | 可配 | 2.0+ |
| 其他 | -- | -- | -- | 不支持 |

### 每列 NDV（Number of Distinct Values）与相关系数

| 引擎 | 单列 NDV | 多列 NDV | 列-物理顺序相关性 | 版本 |
|------|---------|---------|-----------------|------|
| PostgreSQL | 是 (`n_distinct`) | 是 (`CREATE STATISTICS ... (ndistinct)`) | 是 (`correlation` in pg_stats) | 10+ 多列 |
| Oracle | 是 | 是（列组 NDV） | 是（clustering factor） | 所有 |
| SQL Server | 是 (`density`) | 是（density vector） | 是（按索引） | 所有 |
| MySQL | 是 | -- | -- | 所有 |
| MariaDB | 是 | -- | -- | 10.0+ |
| DB2 | 是 | 是 | 是 (`CLUSTERRATIO`) | 所有 |
| SQLite | 是 (sqlite_stat1) | 是 (sqlite_stat4) | -- | 3.7+ |
| CockroachDB | 是 | 是 | -- | 19.2+ |
| TiDB | 是 | -- | -- | 所有 |
| OceanBase | 是 | 是 | -- | 3.x+ |
| Teradata | 是 | 是 | -- | 所有 |
| Vertica | 是 | -- | -- | 所有 |
| Snowflake | 是（内部） | -- | -- | GA |
| BigQuery | 是（动态） | -- | -- | GA |
| Trino | 是 | -- | -- | 所有 |
| Spark SQL | 是 | -- | -- | 3.0+ |
| Databricks | 是 | -- | -- | GA |
| Hive | 是 | -- | -- | 所有 |
| StarRocks | 是 | -- | -- | 2.5+ |
| Doris | 是 | -- | -- | 2.0+ |
| DuckDB | 是（运行时） | -- | -- | 所有 |
| ClickHouse | 是（稀疏） | -- | -- | 所有 |
| SAP HANA | 是 | 是 | 是 | 2.0+ |

### 表达式 / 函数统计（Expression Statistics）

| 引擎 | 表达式统计 | 语法示例 | 版本 |
|------|-----------|---------|------|
| PostgreSQL | 是 | `CREATE STATISTICS s ON lower(email) FROM t` | 14+ (2021) |
| Oracle | 是 | `DBMS_STATS.CREATE_EXTENDED_STATS(... '(LOWER(col))')` | 11g+ |
| SQL Server | 间接（computed column + stats） | `CREATE STATISTICS ... ON t(computed_col)` | 所有 |
| DB2 | 间接（expression-based index） | `CREATE INDEX ON t(UPPER(col))` | 9+ |
| 其他 | -- | -- | 不支持 |

## 各引擎深度解析

### PostgreSQL：CREATE STATISTICS 的三种类型（10+，2017）

PostgreSQL 10（2017 年 10 月发布）引入 `CREATE STATISTICS`，是开源数据库中最早、最完整的扩展统计实现。后续版本持续增强：

- **PG 10（2017）**：引入 `dependencies` 和 `ndistinct` 两种类型
- **PG 12（2019）**：引入 `mcv` 类型（多列 MCV 列表）
- **PG 14（2021）**：引入表达式统计（expressions）
- **PG 15+**：优化器能力持续改进，例如 JOIN 中使用扩展统计

#### 基本语法

```sql
CREATE STATISTICS [ IF NOT EXISTS ] statistics_name
    [ ( statistics_kind [, ...] ) ]
    ON column_name [, ...] | ( expression ) [, ...]
    FROM table_name;

-- statistics_kind 可选: ndistinct, dependencies, mcv
-- 若省略 (...) 则收集全部三种类型
```

#### ndistinct 类型（多列组合 NDV）

```sql
-- 解决 GROUP BY 多列时 NDV 过度估计问题
CREATE STATISTICS addr_city_zip_ndv (ndistinct)
    ON city, zip FROM addresses;

ANALYZE addresses;

-- 查看扩展统计
SELECT stxname, stxkeys, stxkind, stxndistinct
FROM pg_statistic_ext
JOIN pg_statistic_ext_data USING (oid)
WHERE stxname = 'addr_city_zip_ndv';

-- 返回 stxndistinct 形如:
--   {"3, 4": 45000}
-- 含义: 列 3 (city) + 列 4 (zip) 组合的 distinct 值 = 45000
```

**效果：** 未加扩展统计时，`GROUP BY city, zip` 的估算是 `NDV(city) × NDV(zip) = 500 × 40000 = 2000 万`；加了之后变成真实值 45000。这个差异会让 `GROUP BY` 选择完全不同的执行路径（哈希聚合的 bucket 大小、sort-based 聚合的内存分配、并行度）。

#### dependencies 类型（函数依赖）

```sql
-- 解决 WHERE 多个相关列 AND 时选择性低估问题
CREATE STATISTICS addr_city_zip_dep (dependencies)
    ON city, zip FROM addresses;

ANALYZE addresses;

-- 查看函数依赖系数
SELECT stxname, stxdependencies
FROM pg_statistic_ext
JOIN pg_statistic_ext_data USING (oid)
WHERE stxname = 'addr_city_zip_dep';

-- 返回 stxdependencies 形如:
--   {"3 => 4": 0.002, "4 => 3": 1.0}
-- 含义:
--   "3 => 4" (city → zip) 依赖度 0.002（city 值不强决定 zip）
--   "4 => 3" (zip => city) 依赖度 1.0（zip 完全决定 city，完美函数依赖）
```

**选择性重写公式**：当优化器遇到 `WHERE city = 'Beijing' AND zip = '100084'`，检测到 `4 => 3` 的依赖度为 1.0，就会将选择性估算改为：

```
sel(city AND zip) = sel(zip) × (dependency_coefficient + (1 - dep) × sel(city))
                  = sel(zip) × (1.0 + 0 × sel(city))
                  = sel(zip) = 1/NDV(zip)
```

从 5e-8 修正到 2.5e-5，误差从 500 倍降到 2 倍以内。

#### mcv 类型（多列 MCV 列表，PG 12+）

```sql
-- 解决特定组合高频或稀有的场景
CREATE STATISTICS addr_city_zip_mcv (mcv)
    ON city, zip FROM addresses;

ANALYZE addresses;

-- 查看 MCV 列表
SELECT m.*
FROM pg_statistic_ext
JOIN pg_statistic_ext_data USING (oid),
     pg_mcv_list_items(stxdmcv) m
WHERE stxname = 'addr_city_zip_mcv';

-- 返回:
--   index | values                 | nulls       | frequency | base_frequency
--   0     | {Beijing, 100084}      | {false,false}| 0.00003   | 5e-8
--   1     | {Shanghai, 200000}     | {false,false}| 0.000025  | 4e-8
--   ...
```

多列 MCV 是三种类型中最强大的：它不仅能处理函数依赖，还能处理任意的联合频率倾斜（joint frequency skew）。代价是存储成本高（每个 MCV 项占用更多空间），不宜对高基数组合使用。

#### 表达式统计（PG 14+）

```sql
-- 解决对计算结果的选择性估计
CREATE STATISTICS users_lower_email (mcv)
    ON lower(email) FROM users;

CREATE STATISTICS orders_date_parts (ndistinct)
    ON extract(year from order_date), extract(month from order_date)
    FROM orders;

CREATE STATISTICS logs_ts_bucket (mcv, ndistinct)
    ON date_trunc('hour', ts) FROM request_logs;

ANALYZE users;
ANALYZE orders;
ANALYZE request_logs;
```

在 PG 14 之前，对 `WHERE lower(email) = 'x@y.com'` 的选择性估算完全依赖默认 0.005 的猜测值，毫无准确性可言。PG 14 的表达式统计彻底修复了这个盲区。

#### 组合：三种类型一起用

```sql
-- 同一组列上可以叠加多种类型
CREATE STATISTICS addr_full (ndistinct, dependencies, mcv)
    ON city, state, zip FROM addresses;

-- 或者完全省略 kind，默认收集全部三种
CREATE STATISTICS addr_full ON city, state, zip FROM addresses;

ANALYZE addresses;
```

#### pg_stats_ext 视图

```sql
-- 友好视图
SELECT * FROM pg_stats_ext WHERE tablename = 'addresses';

-- 字段:
--   statistics_name         扩展统计对象名
--   attnames                涉及列名数组
--   kinds                   类型数组 {'d', 'f', 'm'} （d=dependencies, f=ndistinct, m=mcv）
--   n_distinct              多列 NDV JSON
--   dependencies            依赖度 JSON
--   most_common_vals        多列 MCV 值数组
--   most_common_freqs       多列 MCV 频率数组
```

### Oracle：DBMS_STATS 扩展统计（11g，2007）

Oracle 11g（2007）引入扩展统计，早于 PostgreSQL 10 年。它的实现路径与 PostgreSQL 完全不同——通过**虚拟列（virtual column）**间接实现。

#### 列组统计（Column Groups）

```sql
-- 创建扩展统计 = 创建虚拟列 + 在虚拟列上收集统计
-- 返回生成的虚拟列名
SELECT DBMS_STATS.CREATE_EXTENDED_STATS(
    ownname   => 'SCOTT',
    tabname   => 'ADDRESSES',
    extension => '(city, zip)'
) FROM DUAL;

-- 收集统计（此时虚拟列会被 ANALYZE）
EXEC DBMS_STATS.GATHER_TABLE_STATS('SCOTT', 'ADDRESSES',
    method_opt => 'FOR ALL COLUMNS SIZE AUTO FOR COLUMNS SIZE 254 (city, zip)');

-- 查看
SELECT extension_name, extension
FROM user_stat_extensions
WHERE table_name = 'ADDRESSES';

-- 删除
EXEC DBMS_STATS.DROP_EXTENDED_STATS('SCOTT', 'ADDRESSES', '(city, zip)');
```

#### 表达式统计

```sql
-- 表达式作为 extension
SELECT DBMS_STATS.CREATE_EXTENDED_STATS(
    'SCOTT', 'EMPLOYEES', '(UPPER(last_name))'
) FROM DUAL;

-- 收集
EXEC DBMS_STATS.GATHER_TABLE_STATS('SCOTT', 'EMPLOYEES',
    method_opt => 'FOR ALL COLUMNS SIZE AUTO FOR COLUMNS (UPPER(last_name)) SIZE 254');
```

#### 自动扩展统计推荐（11gR2+）

Oracle 最独特的能力：它能**监控**工作负载并推荐需要扩展统计的列组：

```sql
-- 开启监控
EXEC DBMS_STATS.SEED_COL_USAGE(
    sqlset_name => 'MY_SQLSET',
    owner_name  => 'SCOTT',
    time_limit  => 600);

-- 运行工作负载...

-- 获取推荐
SELECT DBMS_STATS.REPORT_COL_USAGE('SCOTT', 'ADDRESSES') FROM DUAL;

-- 自动创建推荐的扩展统计
SELECT DBMS_STATS.CREATE_EXTENDED_STATS('SCOTT', 'ADDRESSES') FROM DUAL;
-- 注意：不带 extension 参数时，会基于监控结果自动创建
```

#### 虚拟列的代价

Oracle 扩展统计本质上是**隐藏的虚拟列**：

```sql
-- 创建扩展统计后，表上多了一个隐藏虚拟列
SELECT column_name, virtual_column, hidden_column, data_default
FROM user_tab_cols
WHERE table_name = 'ADDRESSES';

-- column_name                       virtual  hidden  data_default
-- SYS_STUQKP3_WQZ1...              YES      YES     SYS_OP_COMBINED_HASH("CITY","ZIP")
```

这带来两个副作用：

1. **DDL 限制**：修改表结构时需要先删除扩展统计
2. **优化器能力**：虚拟列可以被索引（函数索引），但扩展统计生成的虚拟列**不能**手动索引

### SQL Server：多列统计与密度向量

SQL Server 支持多列统计由来已久（2000+），但实现比 PostgreSQL 简陋：

#### 基本语法

```sql
-- 用户创建的多列统计
CREATE STATISTICS stats_orders_cust_date
    ON dbo.Orders(CustomerID, OrderDate);

-- 带 FULLSCAN
CREATE STATISTICS stats_orders_cust_date
    ON dbo.Orders(CustomerID, OrderDate) WITH FULLSCAN;

-- 查看详细内容
DBCC SHOW_STATISTICS('dbo.Orders', stats_orders_cust_date);

-- 输出三部分:
-- 1. Header: 行数、采样行数、步数 (最多 201)
-- 2. Density Vector: 多列前缀的 (1/NDV)
-- 3. Histogram: 仅第一列的 201 桶等深直方图
```

#### Density Vector 的核心设计

SQL Server 的多列统计**只对第一列构建直方图**，其余列通过**密度向量（density vector）**间接参与：

```
举例: stats_orders_cust_date (CustomerID, OrderDate)
Density Vector 输出:
  All density    Average Length    Columns
  0.000025       4                 CustomerID
  1.5e-7         12                CustomerID, OrderDate

含义:
  - 单看 CustomerID: 1/NDV = 0.000025 → NDV = 40000
  - 组合 (CustomerID, OrderDate): 1/NDV = 1.5e-7 → NDV ≈ 6.67M

选择性估算:
  WHERE CustomerID = 123                  → 使用 histogram on CustomerID
  WHERE CustomerID = 123 AND OrderDate=?  → 使用 density vector (1.5e-7)
```

#### 自动创建列统计 vs 用户创建

```sql
-- 数据库级开关
ALTER DATABASE MyDB SET AUTO_CREATE_STATISTICS ON;

-- 查看自动创建的统计（名字以 _WA_Sys_ 开头）
SELECT name, auto_created, user_created
FROM sys.stats
WHERE object_id = OBJECT_ID('dbo.Orders');

-- name                                auto_created user_created
-- PK__Orders__...                     0            0  (由索引自动维护)
-- _WA_Sys_00000002_...                1            0  (AUTO_CREATE_STATISTICS)
-- stats_orders_cust_date              0            1  (用户创建)
```

SQL Server **不会自动创建多列统计**——自动创建仅针对单列。多列统计必须由 DBA 显式创建，或者由索引隐式带出来（创建复合索引会同时创建对应的多列统计）。

#### 与索引的关系

```sql
-- 创建复合索引会自动创建同名的多列统计
CREATE INDEX idx_orders_cust_date ON dbo.Orders(CustomerID, OrderDate);

-- 这等价于 CREATE STATISTICS + CREATE INDEX 的组合
-- 索引名 = 统计名

-- 如果只需要统计不需要索引（省空间）:
CREATE STATISTICS stats_orders_cust_date
    ON dbo.Orders(CustomerID, OrderDate) WITH FULLSCAN, NORECOMPUTE;
```

### MySQL：无多列统计（仅单列直方图 8.0.3+）

MySQL 到今天（8.0、8.4、9.x）**仍然只支持单列直方图**，不支持多列统计。

```sql
-- 这是 MySQL 的全部能力: 单列直方图
ANALYZE TABLE orders UPDATE HISTOGRAM ON customer_id WITH 1024 BUCKETS;

-- 下面这种"多列"语法并不存在于 MySQL
-- ANALYZE TABLE orders UPDATE HISTOGRAM ON (customer_id, status);  -- 错误
```

MySQL 对多列相关谓词的估算完全依赖 AVI 假设 + InnoDB 索引的密度向量（如果存在复合索引）。这是 MySQL 优化器在复杂 OLAP 查询上显著弱于 PostgreSQL、Oracle、SQL Server 的根本原因之一。

MySQL 社区有长达十年的讨论（WL#9223、WL#13918），但截至本文写作时仍未实现多列统计。MariaDB 也未实现。

### DB2：Column Group Statistics

DB2 LUW（Linux/Unix/Windows）自 9.5（2007）起支持列组统计，能力接近 Oracle：

```sql
-- 收集列组统计
RUNSTATS ON TABLE schema.addresses
    ON COLUMNS ((city, zip), (state, country))
    AND INDEXES ALL;

-- WITH DISTRIBUTION 收集多列 MCV
RUNSTATS ON TABLE schema.addresses
    ON COLUMNS (city, zip)
    WITH DISTRIBUTION ON COLUMNS ((city, zip))
    DEFAULT NUM_FREQVALUES 100;

-- 查看
SELECT COLGROUP, COLGROUPSCHEMA, COLGROUPCOLCOUNT, COLCARD, STATS_TIME
FROM SYSSTAT.COLGROUPS
WHERE TABNAME = 'ADDRESSES';
```

DB2 的列组统计提供：

- **列组基数**（COLGROUP COLCARD）：多列组合的 distinct 数
- **列组 MCV**（COLGROUPDIST）：高频组合列表
- **列组分布**（COLGROUPDISTCOUNTS）：分位数

DB2 在 OLTP + OLAP 混合场景下的 CBO 质量历来稳定，列组统计是关键组件。

### CockroachDB：自动收集的多列统计（20.1+）

CockroachDB 是少数**默认自动收集多列统计**的引擎：

```sql
-- 显式创建
CREATE STATISTICS combined ON city, zip FROM addresses;

-- 查看
SHOW STATISTICS FOR TABLE addresses;
SHOW STATISTICS FOR TABLE addresses WITH HISTOGRAM;

-- 自动收集
SET CLUSTER SETTING sql.stats.automatic_collection.enabled = true;
SET CLUSTER SETTING sql.stats.multi_column_collection.enabled = true;
```

CockroachDB 的多列统计主要用于**列式过滤选择性**，而不是函数依赖建模。对 `WHERE city='Beijing' AND zip='100084'` 会使用多列直方图相交算法，但不会像 PostgreSQL 一样识别 `zip → city` 的函数依赖。

### ClickHouse：没有传统统计（但 23.x 开始补课）

ClickHouse 的架构决定了它不需要也不依赖传统统计信息：稀疏主键索引 + skip index + 运行时信息就够了。但 23.x 起，引入实验性的列级统计（单列）：

```sql
-- 实验性: 列级 tdigest 统计 (23.9+)
ALTER TABLE events MODIFY COLUMN user_id UInt64 STATISTIC(tdigest);
ALTER TABLE events MATERIALIZE STATISTIC user_id;

-- 目前仅支持 tdigest (percentile 估算) 和 uniq (HLL)
-- 还不支持多列或相关性统计
```

这个方向值得关注，但短期内 ClickHouse 不会有 PostgreSQL 级别的多列扩展统计。

### Snowflake / BigQuery / Google Spanner：黑箱自动化

```sql
-- Snowflake: 没有 ANALYZE, 没有 CREATE STATISTICS
-- 统计完全自动在 micro-partition 元数据中维护
-- 多列相关性通过 clustering key 间接影响性能
ALTER TABLE orders CLUSTER BY (customer_id, order_date);
```

这类托管服务的"多列统计"其实被 clustering / partitioning / auto-refreshed micro-partition metadata 取代。用户失去了对扩展统计的任何显式控制。

### Teradata：最早的多列统计实现者之一

```sql
-- 单列
COLLECT STATISTICS COLUMN (customer_id) ON orders;

-- 多列（从 V2R3，上世纪 90 年代就支持）
COLLECT STATISTICS COLUMN (customer_id, region) ON orders;

-- 多列带 histogram
COLLECT STATISTICS COLUMN (customer_id, region)
    USING MAXINTERVALS 500
    ON orders;

-- 采样
COLLECT STATISTICS USING SAMPLE 5 PERCENT
    COLUMN (customer_id, region) ON orders;

-- 查看
HELP STATISTICS orders;
SHOW STATISTICS VALUES ON orders COLUMN (customer_id, region);
```

Teradata 在 MPP 数据仓库场景下，多列统计是 JOIN 重排序的核心输入。商业客户通常会对所有 JOIN 键、GROUP BY 键、WHERE 热点组合显式 COLLECT。

### SAP HANA：Data Statistics Object

```sql
-- 创建多列 HISTOGRAM 统计
CREATE STATISTICS stats_addr ON addresses(city, zip) TYPE HISTOGRAM;

-- 创建依赖统计
CREATE STATISTICS stats_addr_dep ON addresses(city, zip) TYPE RECORD COUNT;

-- 创建 SIMPLE 统计（仅 NDV）
CREATE STATISTICS ON addresses(city, zip) TYPE SIMPLE;

-- 刷新
REFRESH STATISTICS ON addresses;

-- 查看
SELECT * FROM M_DATA_STATISTICS WHERE TABLE_NAME = 'ADDRESSES';
```

SAP HANA 的 data statistics 支持多种类型（SIMPLE、RECORD COUNT、HISTOGRAM、TOPK、SKETCH），多列版本都可用。

## PostgreSQL CREATE STATISTICS 深度剖析

PostgreSQL 的 `CREATE STATISTICS` 是开源世界中最完整的扩展统计实现，值得拆开逐类详细讨论。

### ndistinct 类型：多列组合的 NDV

#### 问题场景

```sql
-- 表结构
CREATE TABLE addresses (
    id SERIAL PRIMARY KEY,
    city TEXT,
    state TEXT,
    zip TEXT,
    country TEXT
);

-- 假设数据:
-- 行数: 10,000,000
-- NDV(city) = 500
-- NDV(state) = 50
-- NDV(zip) = 40000
-- NDV(country) = 200
-- 真实 NDV(city, state) = 550  -- 几乎决定性 (每个 city 基本对应 1 个 state)
-- 真实 NDV(city, zip) = 45000  -- 每个 city 约 90 个 zip
-- 真实 NDV(city, state, zip) = 45000  -- 加 state 没有增加组合

-- 不加扩展统计时:
--   EXPLAIN SELECT COUNT(*) FROM addresses GROUP BY city, state, zip;
--   优化器估算的 GROUP 数 = 500 * 50 * 40000 = 10 亿
--   但表只有 1000 万行! 这种估算是灾难性的
```

#### 创建 ndistinct 统计

```sql
CREATE STATISTICS addr_group_ndv (ndistinct)
    ON city, state, zip FROM addresses;

ANALYZE addresses;

-- 验证
SELECT stxname,
       stxkeys,
       stxndistinct
FROM pg_statistic_ext
JOIN pg_statistic_ext_data USING (oid)
WHERE stxname = 'addr_group_ndv';

-- stxndistinct 内容示意:
-- {
--   "2, 3":    550,    -- (city, state)
--   "2, 4":    45000,  -- (city, zip)
--   "3, 4":    40000,  -- (state, zip)
--   "2, 3, 4": 45000   -- (city, state, zip)
-- }
```

注意 ndistinct 类型会存储**所有子集组合**的 NDV，而不仅仅是用户指定的 3 列组合。这样对 `GROUP BY city, state` 和 `GROUP BY city, state, zip` 都能用。

#### 对查询计划的影响

```sql
-- Before (无扩展统计)
EXPLAIN (ANALYZE, BUFFERS)
SELECT city, state, zip, COUNT(*)
FROM addresses
GROUP BY city, state, zip;

-- Planner's estimate: 10 亿 行
-- Actual: 45000 行
-- 结果: 选择了巨大的 hash table, work_mem 不够 -> 溢写磁盘

-- After (有扩展统计)
-- Planner's estimate: 45000 行
-- Actual: 45000 行
-- 结果: 小 hash table, 全内存聚合, 快 10 倍
```

### dependencies 类型：函数依赖建模

#### 数据结构

PostgreSQL 在磁盘上存储的 `stxdependencies` 是一个 JSON map：

```
{
  "A => B": coefficient,
  "B => A": coefficient,
  "A, B => C": coefficient,
  ...
}

coefficient = P(同一元组中 A 的值决定 B) 的经验估计
```

系数值域 [0, 1]：

- **1.0**：完美函数依赖（每个 A 值对应且仅对应一个 B 值）
- **0.0**：完全独立
- 中间值：部分依赖

#### 选择性修正公式

当优化器遇到 `WHERE a = va AND b = vb`：

```
-- 原始 AVI 估算
sel_avi = sel(a=va) × sel(b=vb)

-- 函数依赖修正 (假设 a => b 的系数为 f)
-- 直觉: 如果 a 决定 b, 那么在 a=va 为真时, b=vb 的概率要么是 1 (如果 va 对应的唯一 b 值就是 vb), 要么是 0
-- PostgreSQL 的近似公式:
sel_corrected = sel(a=va) × (f × 1 + (1 - f) × sel(b=vb))

-- 等价于: 以概率 f 走 "依赖路径" (sel = sel(a=va)), 以概率 (1-f) 走 "独立路径" (sel = sel_avi)
```

#### 方向性

`dependencies` 是**非对称**的：`A => B` 的系数与 `B => A` 的系数通常不同。

```sql
-- zip 完全决定 city（邮编唯一对应城市）
-- 系数: zip => city = 1.0

-- city 不决定 zip（一个城市多个邮编）
-- 系数: city => zip = 0.002
```

PostgreSQL 会存储**两个方向**的系数，优化器根据谓词形式选择使用哪个。

#### 创建与使用

```sql
CREATE STATISTICS addr_dep (dependencies)
    ON city, zip FROM addresses;

ANALYZE addresses;

-- 查询
EXPLAIN SELECT * FROM addresses
WHERE city = 'Beijing' AND zip = '100084';

-- 没有扩展统计时: Planner estimate = 0.5 rows
-- 有扩展统计时:  Planner estimate = 250 rows (修正后)
```

#### 多列依赖

```sql
-- 支持 A, B => C 形式
CREATE STATISTICS addr_dep3 (dependencies)
    ON city, state, zip FROM addresses;

-- stxdependencies 示意:
-- {
--   "4 => 2": 1.0,         -- zip => city
--   "4 => 3": 1.0,         -- zip => state
--   "2 => 3": 0.99,        -- city => state (极少有歧义)
--   "3 => 2": 0.02,        -- state => city (一个州多个城市)
--   "2, 4 => 3": 1.0,      -- (city, zip) => state
--   ...
-- }
```

### mcv 类型：多列 MCV 列表（PG 12+）

`dependencies` 假设依赖是均匀的——即对所有 `(a, b)` 组合，依赖系数一致。但现实中依赖强度可能**因值而异**：

```
示例: user_event 表
- 对于 event_type='login', os='Windows' 占 80% (热门组合)
- 对于 event_type='error', os='Linux' 占 70% (运维类错误)
- 对于 event_type='purchase', os 均匀分布

用 dependencies 会把这些全部平均为一个系数，
用 mcv 则能精确存储每个组合的频率
```

#### 创建与查看

```sql
CREATE STATISTICS events_type_os_mcv (mcv)
    ON event_type, os FROM user_events;

ANALYZE user_events;

-- 查看 MCV 列表
SELECT m.*
FROM pg_statistic_ext
JOIN pg_statistic_ext_data USING (oid),
     pg_mcv_list_items(stxdmcv) m
WHERE stxname = 'events_type_os_mcv'
ORDER BY m.frequency DESC
LIMIT 20;

-- index | values                  | nulls       | frequency | base_frequency
-- 0     | {login, Windows}        | {f,f}       | 0.45      | 0.12       <-- 独立假设会估 0.12
-- 1     | {login, macOS}          | {f,f}       | 0.08      | 0.09
-- 2     | {purchase, Windows}     | {f,f}       | 0.05      | 0.06
-- ...
```

- **frequency**：观测到的真实联合频率
- **base_frequency**：独立假设下应该出现的频率（乘积）

差异越大，扩展统计的价值越高。PostgreSQL 优化器在选择性估算时会直接使用 `frequency`。

#### MCV 的存储成本

```sql
-- stxdmcv 是 bytea 存储的序列化 MCV 列表
-- 列数 × 列数 × statistics_target 近似决定大小

-- 查看存储大小
SELECT stxname, pg_column_size(stxdmcv)
FROM pg_statistic_ext_data
WHERE stxdmcv IS NOT NULL;
```

对高基数组合，MCV 列表可能迅速膨胀。推荐仅在热点组合明确时使用。

### expressions 类型（PG 14+）

```sql
-- 场景: 应用大量使用 lower(email), extract(year from date) 等
-- PG 14 之前这些表达式的选择性是写死的默认值

CREATE STATISTICS users_email_expr (ndistinct, mcv)
    ON lower(email), extract(domain from email) FROM users;

-- 注意: 多个表达式的 ndistinct 需要的是一个带括号的 expression 列表
```

表达式统计本质上是 ndistinct / mcv 在虚拟列（表达式结果）上的应用，语法糖级的统一包装。

### 何时使用哪种类型

| 场景 | 推荐类型 | 原因 |
|------|---------|------|
| `GROUP BY a, b` 估算分组数 | ndistinct | 直接给 NDV(a, b) |
| `WHERE a = va AND b = vb`（均匀依赖）| dependencies | 小体积，足以修正 |
| `WHERE a = va AND b = vb`（特定值强相关）| mcv | 精确到每个组合 |
| 多列 JOIN 基数估计 | ndistinct + mcv | JOIN key 组合 NDV + 热点 |
| `WHERE func(col) = ?` | expressions (PG 14+) | 替代默认 0.005 |
| 不知道哪种 | 三种都建 | `CREATE STATISTICS ... ON a, b`（省略 kind） |

### 运维注意事项

```sql
-- 1. 扩展统计不随索引自动生成 (与 SQL Server 不同)
--    必须显式 CREATE STATISTICS + ANALYZE

-- 2. ANALYZE 时扩展统计和常规列统计一起收集
--    ANALYZE 时间和内存会增加

-- 3. 扩展统计受 default_statistics_target 影响
--    增大 target 会增加 MCV 列表长度和精度

-- 4. 在分区表上的行为 (PG 12+)
CREATE STATISTICS addr_stats ON city, zip FROM addresses;  -- 父表
-- 子分区也会各自收集，用于分区特定估算

-- 5. 监控未使用的扩展统计 (PG 14+)
SELECT stxname, stxkeys, stxkind
FROM pg_statistic_ext
WHERE NOT EXISTS (
    SELECT 1 FROM pg_statistic_ext_data
    WHERE stxoid = pg_statistic_ext.oid
      AND (stxdndistinct IS NOT NULL
           OR stxddependencies IS NOT NULL
           OR stxdmcv IS NOT NULL)
);
-- 如果返回行, 说明定义了但从未 ANALYZE 成功
```

## 一个完整的相关性案例：(zip, city) 冗余

让我们用一个端到端例子展示扩展统计从"症状"到"修复"的完整流程。

### 数据准备

```sql
CREATE TABLE addresses (
    id SERIAL PRIMARY KEY,
    city TEXT NOT NULL,
    state TEXT NOT NULL,
    zip TEXT NOT NULL,
    full_address TEXT
);

-- 插入 1000 万条记录
-- 分布:
--   500 个城市 (city)
--   50 个州   (state)
--   40000 个邮编 (zip)
--   每个 zip 对应唯一一个 city 和 state  <-- 函数依赖 zip => (city, state)
--   每个 city 平均对应 90 个 zip 和 1 个 state

-- 生成器伪代码（省略具体数据）
INSERT INTO addresses (city, state, zip, full_address)
SELECT ...;

-- 确保分布合理
VACUUM ANALYZE addresses;
```

### 症状：无扩展统计时的查询

```sql
-- 查询 1: WHERE 多列相关
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM addresses
WHERE city = 'Beijing' AND zip = '100084';

--                                         QUERY PLAN
-- ---------------------------------------------------------------
-- Index Scan using idx_zip on addresses
--   Index Cond: (zip = '100084'::text)
--   Filter: (city = 'Beijing'::text)
--   Rows Removed by Filter: 0
--   Planner estimate: 0.5 rows      <<< 严重低估
--   Actual rows: 250
--   ratio: 500x underestimate

-- 查询 2: GROUP BY 多列
EXPLAIN (ANALYZE)
SELECT city, state, zip, COUNT(*) FROM addresses GROUP BY 1, 2, 3;

-- HashAggregate
--   Group Key: city, state, zip
--   Planner estimate: 1,000,000,000 rows   <<< 严重高估（500×50×40000）
--   Actual rows: 45000
--   ratio: 22222x overestimate
--   Memory: 2GB requested, only 16MB needed

-- 查询 3: 多表 JOIN
EXPLAIN (ANALYZE)
SELECT a.city, u.name
FROM addresses a
JOIN users u ON u.addr_zip = a.zip AND u.addr_city = a.city
WHERE a.state = 'Beijing-Area';

-- Nested Loop         <<< 因为低估了 JOIN 输入行数, 错误选择 NL
--   -> Index Scan on addresses
--   -> Index Scan on users
--   Actual: slow, 5 min
-- 理想: Hash Join, 30 sec
```

### 修复：添加扩展统计

```sql
-- 综合方案: 三种类型一起建
CREATE STATISTICS addr_full_stats
    ON city, state, zip FROM addresses;

-- ANALYZE 触发收集
ANALYZE addresses;

-- 验证数据已写入
SELECT statistics_name,
       attnames,
       kinds,
       n_distinct,
       dependencies
FROM pg_stats_ext
WHERE tablename = 'addresses';

-- 期望看到:
-- n_distinct:
--   {"2,3":550, "2,4":45000, "3,4":40000, "2,3,4":45000}
-- dependencies:
--   {"2 => 3":0.99, "3 => 2":0.02, "4 => 2":1.0, "4 => 3":1.0, ...}
-- mcv: (较大, 数据略)
```

### 验证：同样的查询，全新的计划

```sql
-- 查询 1 重新执行
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM addresses
WHERE city = 'Beijing' AND zip = '100084';

-- Index Scan using idx_zip on addresses
--   Planner estimate: 250 rows       <<< 修正准确！
--   Actual rows: 250

-- 查询 2 重新执行
EXPLAIN (ANALYZE)
SELECT city, state, zip, COUNT(*) FROM addresses GROUP BY 1, 2, 3;

-- HashAggregate
--   Planner estimate: 45000 rows     <<< 准确
--   Actual: 45000 rows
--   Memory: 16MB (from ndistinct)

-- 查询 3 重新执行
EXPLAIN (ANALYZE)
SELECT ...;

-- Hash Join                 <<< 现在选对算法了
--   Actual: 30 sec (从 5min 降到 30sec)
```

### 关键观察

1. **一次 CREATE STATISTICS 能同时修复多种查询模式**：WHERE 选择性、GROUP BY 基数、JOIN 顺序都得到修正
2. **ANALYZE 成本并未显著增加**：多列统计的 ANALYZE 开销约为单列的 2-3 倍，可接受
3. **修复是静态的，不是自适应的**：数据分布若剧变（比如新增城市），需要重新 ANALYZE
4. **扩展统计不自动创建**：必须 DBA 主动识别出哪些列组合有问题

## 扩展统计在 OLAP 与 OLTP 场景的差异

### OLTP 场景

- 事务性查询多为点查或小范围扫描
- 多列相关性对**索引选择**影响大：`WHERE a=va AND b=vb` 走哪个索引、是否回表
- MCV 类型价值高：热点组合（如订单的高频状态组合）需要精确频率
- 推荐：高频 AND 谓词的列组建 dependencies + mcv

### OLAP 场景

- 分析查询多为大表聚合和多表 JOIN
- 多列相关性对 **JOIN 顺序、聚合代价、并行度**影响大
- ndistinct 类型价值最高：GROUP BY 多列、JOIN 基数估计
- 推荐：常见 GROUP BY 和 JOIN key 组合建 ndistinct

### 混合负载

- 电商、SaaS 应用通常混合：订单状态 + 支付状态 + 地区 + 品类
- 推荐：对热点组合三种类型全建

## 扩展统计的局限

### 1. 无法取代良好的数据建模

如果 `city` 和 `zip` 本身就有严重冗余，更好的方案是规范化（normalize）成 `zip_codes` 表 + FK。扩展统计只是应急补丁。

### 2. 收集成本

```
扩展统计的 ANALYZE 代价:
  ndistinct:    O(sample × columns²)  估算所有子集组合 NDV
  dependencies: O(sample × columns²)  计算两两依赖系数
  mcv:          O(sample × columns × target)  构建多列 MCV

大表 + 多列组合 + 高 statistics_target → ANALYZE 时间显著增加
```

### 3. 并非所有查询都受益

- **纯单列谓词**：`WHERE zip = ?` 只用单列统计，扩展统计无效
- **函数依赖微弱**：如果系数 < 0.5，修正效果不明显
- **极度倾斜**：依赖系数的平均化可能掩盖关键异常值（这时用 MCV）

### 4. 优化器能否利用

PostgreSQL 14 之前，扩展统计在 **JOIN** 中的利用非常有限。PG 15+ 开始改善多表 JOIN 中的扩展统计使用，但仍不如 Oracle 那样深入。

### 5. 跨引擎不可移植

PostgreSQL 的扩展统计定义（CREATE STATISTICS）在其他 PG 兼容系统（CockroachDB、YugabyteDB、Greenplum）上语法类似，但**数据结构和算法不同**——同样的定义在不同引擎产生不同效果。

### 6. 数据分布剧变需要重收

```sql
-- 坏例子: 半年前 ANALYZE, 期间新增 100 个城市
-- 旧统计中: NDV(city, zip) = 45000
-- 现实中:   NDV(city, zip) = 58000
-- 优化器依然使用旧值, 再次走错计划
```

定期 ANALYZE 是必要的。PostgreSQL 的 autovacuum 默认会触发 ANALYZE，但大批量导入后最好手动 ANALYZE。

## 关键发现

经过对 45+ 数据库的横向对比，多列 / 相关性统计信息呈现如下格局：

1. **SQL 标准完全缺席**：ISO/IEC 9075 从未规定统计收集语法，扩展统计更是各家私有方言。任何涉及扩展统计的代码都不可移植。

2. **商业数据库领先**：Oracle（11g，2007）、SQL Server（2000+）、DB2（9.5，2007）、Teradata（V2R5+）早早实现多列统计。开源方面 PostgreSQL 10（2017）追上后成为事实标准。

3. **PostgreSQL 的 CREATE STATISTICS 是开源最完整方案**：三种类型（ndistinct、dependencies、mcv）+ 表达式统计（PG 14+）。CockroachDB、YugabyteDB、Greenplum、TimescaleDB 大量继承。

4. **MySQL 依然是 CBO 多列统计的空白区**：到 9.x 仍只支持单列直方图，对相关列谓词完全依赖 AVI 假设。这是 MySQL 复杂查询上显著弱于 PostgreSQL/Oracle/SQL Server 的根本原因之一。MariaDB 也未实现。

5. **Oracle 的扩展统计最早、路径独特**：通过虚拟列实现，并内建工作负载监控自动推荐（SEED_COL_USAGE）——这是其他引擎都没有的能力。但虚拟列带来 DDL 副作用。

6. **SQL Server 的多列统计最简陋**：只对第一列建直方图，其余列仅存密度向量（density vector），对函数依赖建模能力远不如 PostgreSQL 的 dependencies 类型。

7. **分析引擎集体缺位**：Trino、Presto、Spark SQL、Hive、Flink、Databricks、StarRocks、Doris、DuckDB、Impala——这些 OLAP 主力引擎**全部没有多列扩展统计**。这是它们在复杂 OLAP 查询上（多列 GROUP BY、多条件 WHERE、多表 JOIN）优化器质量长期落后 PostgreSQL/Oracle 的关键原因。

8. **云托管服务变相实现**：Snowflake 的 clustering key、BigQuery 的 partitioning + clustering、Spanner 的 adaptive optimizer，用数据布局和运行时反馈替代了显式扩展统计。用户完全失去控制但通常得到可接受的性能。

9. **函数依赖是最有杠杆的类型**：在实际生产中，函数依赖（zip→city、product_id→brand）比一般联合分布更常见也更严重。PostgreSQL 的 dependencies 类型，以极小的存储代价修复了 AND 谓词最严重的低估问题。

10. **多列 NDV 对 GROUP BY 至关重要**：AVI 对 GROUP BY 多列的高估往往是千倍以上，引发 work_mem 溢出、错误的并行度、不必要的磁盘排序。ndistinct 统计以 JSON 形式存储所有子集组合 NDV，几乎零开销但效果立竿见影。

11. **多列 MCV 是最精确但最昂贵的类型**：PG 12+ 的 MCV 类型能处理任意联合频率倾斜，包括函数依赖无法覆盖的不均匀相关性。但存储和计算成本较高，应仅用于热点组合。

12. **表达式统计填补了最后的盲区**：PG 14+ 对 `lower(email)`、`extract(year from ts)` 这类表达式的选择性估算，从"写死 0.005"升级到真实统计，是日常应用最容易感知的改进。

13. **收集需要智慧**：扩展统计不会自动创建（除了 CockroachDB），DBA 必须识别"哪些列组合有问题"。经验法则：频繁出现的多列 AND 谓词、多列 GROUP BY、多列 JOIN 键——都是候选。

14. **扩展统计是应急补丁，不是银弹**：最好的多列相关性消除办法是**数据建模**——规范化冗余列。扩展统计适合那些无法规范化（或规范化代价太高）的遗留系统。

15. **列与物理顺序的相关性（correlation）是另一个维度**：PostgreSQL `pg_stats.correlation` 字段描述列值与物理行顺序的相关度（-1 到 1），决定了索引扫描的 I/O 代价（随机 vs 顺序）。这不属于"多列相关性"但同样是 CBO 的关键输入。Oracle 的 clustering factor 是等价概念。

扩展统计信息是 CBO 成熟度的试金石：能不能识别 zip→city 的函数依赖，能不能正确估算 `GROUP BY city, zip` 的分组数，能不能让 JOIN 顺序在多列相关时依然选对——这些都直接决定了优化器在真实业务数据上的表现。没有扩展统计的 CBO，充其量是个"教科书优化器"；加上扩展统计，才有机会接近"生产级优化器"。

## 参考资料

- PostgreSQL: [CREATE STATISTICS](https://www.postgresql.org/docs/current/sql-createstatistics.html)
- PostgreSQL: [Extended Statistics](https://www.postgresql.org/docs/current/planner-stats.html#PLANNER-STATS-EXTENDED)
- PostgreSQL: [pg_statistic_ext](https://www.postgresql.org/docs/current/catalog-pg-statistic-ext.html)
- Oracle: [DBMS_STATS.CREATE_EXTENDED_STATS](https://docs.oracle.com/en/database/oracle/oracle-database/19/arpls/DBMS_STATS.html)
- Oracle: [Extended Statistics Concepts](https://docs.oracle.com/en/database/oracle/oracle-database/19/tgsql/optimizer-statistics-concepts.html#GUID-3BEB9C4B-5F1C-4F79-A9A8-6A63E43F8AFE)
- SQL Server: [CREATE STATISTICS](https://learn.microsoft.com/en-us/sql/t-sql/statements/create-statistics-transact-sql)
- SQL Server: [Statistics Concepts](https://learn.microsoft.com/en-us/sql/relational-databases/statistics/statistics)
- DB2 LUW: [RUNSTATS Command](https://www.ibm.com/docs/en/db2/11.5?topic=commands-runstats)
- DB2 LUW: [Column Group Statistics](https://www.ibm.com/docs/en/db2/11.5?topic=statistics-collecting-distribution)
- CockroachDB: [CREATE STATISTICS](https://www.cockroachlabs.com/docs/stable/create-statistics.html)
- Teradata: [COLLECT STATISTICS](https://docs.teradata.com/r/Teradata-VantageTM-SQL-Data-Definition-Language-Syntax-and-Examples)
- SAP HANA: [Data Statistics](https://help.sap.com/docs/SAP_HANA_PLATFORM/4fe29514fd584807ac9f2a04f6754767/20d8c17575191014b98fa76b9eada7b7.html)
- OceanBase: [DBMS_STATS](https://en.oceanbase.com/docs/enterprise-oceanbase-database-en)
- Greenplum: [CREATE STATISTICS](https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/ref_guide-sql_commands-CREATE_STATISTICS.html)
- Yuri Ismailov et al. "Multi-Column Optimizer Statistics", VLDB 2017
- Selinger et al. "Access Path Selection in a Relational Database Management System", SIGMOD 1979（AVI 假设的源头）
- Getoor et al. "Selectivity Estimation using Probabilistic Models", SIGMOD 2001
