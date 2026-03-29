# GROUPING SETS / CUBE / ROLLUP

多维聚合的标准语法——SQL:1999 引入的分组集合框架，让一条查询同时产出多个聚合粒度的结果，替代笨重的 UNION ALL 拼接。

## 支持矩阵

### GROUPING SETS / CUBE / ROLLUP 基本支持

| 引擎 | GROUPING SETS | CUBE | ROLLUP | 版本 | 备注 |
|------|:---:|:---:|:---:|------|------|
| Oracle | 支持 | 支持 | 支持 | 9i+ (2001) | **最早的完整实现** |
| SQL Server | 支持 | 支持 | 支持 | 2008+ | 2008 前仅 WITH ROLLUP/CUBE |
| PostgreSQL | 支持 | 支持 | 支持 | 9.5+ (2016) | 标准语法 |
| DB2 | 支持 | 支持 | 支持 | 7.1+ | 标准语法 |
| Snowflake | 支持 | 支持 | 支持 | GA | 标准语法 |
| BigQuery | 支持 | 支持 | 支持 | GA | 标准语法 |
| Trino | 支持 | 支持 | 支持 | 早期版本 | 标准语法 |
| DuckDB | 支持 | 支持 | 支持 | 0.8.0+ | 标准语法 |
| Spark SQL | 支持 | 支持 | 支持 | 2.0+ | 标准语法 |
| Databricks | 支持 | 支持 | 支持 | Runtime 7.0+ | 标准语法 |
| Hive | 支持 | 支持 | 支持 | 0.10+ | 部分使用 WITH CUBE/ROLLUP |
| ClickHouse | 支持 | 支持 | 支持 | 19.13+ | 同时支持 WITH ROLLUP/CUBE |
| MySQL | 支持 (8.0.31+) | 支持 (8.0.1+) | 支持 | 8.0.1+ | 8.0.1 起支持 CUBE/ROLLUP 标准语法；8.0.31 起支持 GROUPING SETS |
| MariaDB | 不支持 | 不支持 | 仅 ROLLUP | 10.0+ | 仅 WITH ROLLUP 语法 |
| SQLite | 不支持 | 不支持 | 不支持 | - | 需 UNION ALL 模拟 |
| Redshift | 支持 | 支持 | 支持 | GA | 标准语法 |
| Teradata | 支持 | 支持 | 支持 | 14+ | 标准语法 |
| Vertica | 支持 | 支持 | 支持 | 7.0+ | 标准语法 |
| Greenplum | 支持 | 支持 | 支持 | 5.0+ | 继承 PostgreSQL |
| CockroachDB | 不支持 | 不支持 | 不支持 | - | 计划中 |
| Impala | 支持 | 不支持 | 支持 | 2.0+ | 无 CUBE 支持 |
| Doris | 支持 | 支持 | 支持 | 1.1+ | 标准语法 |
| StarRocks | 支持 | 支持 | 支持 | 2.0+ | 标准语法 |
| Flink SQL | 支持 | 支持 | 支持 | 1.12+ | 标准语法 |
| Presto | 支持 | 支持 | 支持 | 0.98+ | 标准语法 |
| SAP HANA | 支持 | 支持 | 支持 | 1.0+ | 标准语法 |
| OceanBase | 支持 | 支持 | 支持 | 3.x+ | MySQL/Oracle 双模式 |
| TiDB | 不支持 | 不支持 | 仅 ROLLUP | 5.0+ | 仅 WITH ROLLUP |
| PolarDB | 不支持 | 不支持 | 仅 ROLLUP | - | 继承 MySQL 限制 |
| openGauss | 支持 | 支持 | 支持 | 2.0+ | 兼容 PostgreSQL |
| KingBase | 支持 | 支持 | 支持 | V8+ | 兼容 Oracle/PostgreSQL |
| 达梦 (DM) | 支持 | 支持 | 支持 | DM8 | 兼容 Oracle |
| GaussDB | 支持 | 支持 | 支持 | - | 兼容 PostgreSQL |
| MaxCompute | 支持 | 支持 | 支持 | - | 标准语法 |
| Hologres | 支持 | 支持 | 支持 | - | 兼容 PostgreSQL |
| TDSQL | 支持 | 支持 | 支持 | - | 兼容 MySQL/PostgreSQL |
| YugabyteDB | 支持 | 支持 | 支持 | 2.6+ | 兼容 PostgreSQL |
| Materialize | 不支持 | 不支持 | 不支持 | - | 流式引擎暂不支持 |
| ksqlDB | 不支持 | 不支持 | 不支持 | - | 流式引擎不支持 |
| TDengine | 不支持 | 不支持 | 不支持 | - | 时序引擎不支持 |
| TimescaleDB | 支持 | 支持 | 支持 | - | 继承 PostgreSQL |
| H2 | 支持 | 支持 | 支持 | 1.4+ | 标准语法 |
| Derby | 不支持 | 不支持 | 不支持 | - | - |
| Firebird | 不支持 | 不支持 | 不支持 | - | - |
| Synapse | 支持 | 支持 | 支持 | GA | 继承 SQL Server |

> 注意: MariaDB/TiDB/PolarDB 只支持 ROLLUP（且仅支持 WITH ROLLUP 语法），不支持 GROUPING SETS 和 CUBE。MySQL 8.0.1 起支持 CUBE 和标准 ROLLUP 语法，8.0.31 起补齐了 GROUPING SETS。

## 设计动机: 多粒度聚合的问题

### 业务需求

报表场景经常需要同时展示不同聚合粒度的数据——明细、分类小计、总计：

```
| region | city     | SUM(revenue) |
|--------|----------|--------------|
| East   | Beijing  | 500          |  ← 城市级明细
| East   | Shanghai | 300          |  ← 城市级明细
| East   | NULL     | 800          |  ← 区域小计
| West   | Chengdu  | 200          |  ← 城市级明细
| West   | NULL     | 200          |  ← 区域小计
| NULL   | NULL     | 1000         |  ← 全局总计
```

### 没有 ROLLUP 时的写法

```sql
-- 三条查询 UNION ALL: 冗长、低效、难维护
SELECT region, city, SUM(revenue) FROM sales GROUP BY region, city
UNION ALL
SELECT region, NULL, SUM(revenue) FROM sales GROUP BY region
UNION ALL
SELECT NULL, NULL, SUM(revenue) FROM sales;
```

问题：
1. **性能差**: 表被扫描三次
2. **冗余**: 聚合函数写了三遍
3. **维护成本**: 每增加一个维度，UNION ALL 数量指数增长

### ROLLUP 的解决方案

```sql
SELECT region, city, SUM(revenue)
FROM sales
GROUP BY ROLLUP(region, city);
-- 一条查询产出三个粒度: (region, city)、(region)、()
-- 一次表扫描，引擎内部完成多粒度聚合
```

## 核心语法详解

### GROUPING SETS: 显式指定分组集合

```sql
-- 指定需要哪些分组组合
SELECT region, city, SUM(revenue)
FROM sales
GROUP BY GROUPING SETS (
    (region, city),   -- 按 region + city 分组
    (region),         -- 按 region 分组（city 为 NULL）
    ()                -- 全局总计（region 和 city 都为 NULL）
);
```

GROUPING SETS 是最通用的语法，CUBE 和 ROLLUP 都是它的简写形式。

### ROLLUP: 层级聚合的简写

ROLLUP 按参数从右向左逐级去除，产出层级结构的小计：

```sql
GROUP BY ROLLUP(a, b, c)
-- 等价于:
GROUP BY GROUPING SETS (
    (a, b, c),
    (a, b),
    (a),
    ()
)
-- 产出 N+1 个分组集合（N = 参数数量）
```

适用场景: 有层级关系的维度（年 > 季度 > 月、国家 > 省 > 市）。

### CUBE: 全组合的简写

CUBE 产出所有参数的所有子集组合：

```sql
GROUP BY CUBE(a, b, c)
-- 等价于:
GROUP BY GROUPING SETS (
    (a, b, c),
    (a, b), (a, c), (b, c),
    (a), (b), (c),
    ()
)
-- 产出 2^N 个分组集合
```

适用场景: 数据立方体分析（OLAP），需要从各个维度角度查看汇总。

## ROLLUP 参数语法: 标准语法 vs WITH ROLLUP

这是方言之间最常见的语法分歧之一。

### 两种语法

```sql
-- 标准语法 (SQL:1999): ROLLUP 在 GROUP BY 内作为函数调用
SELECT region, city, SUM(revenue)
FROM sales
GROUP BY ROLLUP(region, city);

-- WITH ROLLUP 语法 (MySQL/MariaDB 传统): 后缀修饰符
SELECT region, city, SUM(revenue)
FROM sales
GROUP BY region, city WITH ROLLUP;
```

### 各引擎支持情况

| 引擎 | `ROLLUP(a, b)` 标准语法 | `GROUP BY a, b WITH ROLLUP` | 备注 |
|------|:---:|:---:|------|
| Oracle | 支持 | 不支持 | 仅标准语法 |
| SQL Server | 支持 (2008+) | 不支持 (已废弃) | 2008 前使用 WITH ROLLUP |
| PostgreSQL | 支持 | 不支持 | 仅标准语法 |
| MySQL | 支持 (8.0.1+) | 支持 | 8.0.1 起两种都支持 |
| MariaDB | 不支持 | 支持 | 仅 WITH ROLLUP |
| ClickHouse | 支持 | 支持 | 两种都支持 |
| Hive | 支持 | 支持 | 两种都支持 |
| Spark SQL | 支持 | 支持 | 两种都支持 |
| TiDB | 不支持 | 支持 | 仅 WITH ROLLUP |
| Snowflake | 支持 | 不支持 | 仅标准语法 |
| BigQuery | 支持 | 不支持 | 仅标准语法 |
| DB2 | 支持 | 不支持 | 仅标准语法 |

> SQL Server 2005 及更早版本使用 `WITH ROLLUP` / `WITH CUBE`，2008 起改为标准的 `ROLLUP()` / `CUBE()` 语法，旧语法已标记为废弃。这是一个值得参考的迁移路径。

### 语义差异

两种语法在简单用法下等价，但 WITH ROLLUP 无法表达复杂的分组组合：

```sql
-- 标准语法: 可以与其他 GROUP BY 列混合
GROUP BY a, ROLLUP(b, c)
-- 等价于 GROUPING SETS ((a, b, c), (a, b), (a))

-- WITH ROLLUP: 只能对所有 GROUP BY 列整体生效
GROUP BY a, b, c WITH ROLLUP
-- 等价于 GROUPING SETS ((a, b, c), (a, b), (a), ())
-- 无法只对 b, c 做 ROLLUP 而 a 保持不变
```

这正是标准语法更强大的原因——它支持部分 ROLLUP 和串联分组（后文详述）。

## GROUPING() 和 GROUPING_ID() 函数

### 为什么需要 GROUPING()

ROLLUP/CUBE 产出的汇总行中，被"聚合掉"的维度列显示为 NULL。但如果原始数据中该列本身就有 NULL 值，就会产生歧义：

```sql
-- city 列包含 NULL 值的数据
INSERT INTO sales VALUES ('East', NULL, 100);  -- 真实的 NULL（未知城市）

SELECT region, city, SUM(revenue)
FROM sales
GROUP BY ROLLUP(region, city);

-- 结果中这两行无法区分:
-- | East | NULL | 100  |  ← 真实数据中 city=NULL 的行
-- | East | NULL | 800  |  ← ROLLUP 产生的区域小计
```

### GROUPING() 函数

GROUPING() 返回 0 或 1，标识某列在当前行是否因分组聚合而产生了 NULL：

```sql
SELECT
    region,
    city,
    SUM(revenue),
    GROUPING(region) AS g_region,  -- 0=正常分组列, 1=被聚合掉（小计/总计行）
    GROUPING(city)   AS g_city
FROM sales
GROUP BY ROLLUP(region, city);

-- 结果:
-- | East | Beijing  | 500  | 0 | 0 |  ← 明细行
-- | East | NULL     | 100  | 0 | 0 |  ← 真实 NULL (g_city=0)
-- | East | NULL     | 800  | 0 | 1 |  ← 区域小计 (g_city=1) ← 可区分!
-- | NULL | NULL     | 1000 | 1 | 1 |  ← 全局总计
```

### GROUPING_ID() / GROUPING() 多参数形式

将多个列的 GROUPING 值合并为一个位掩码整数：

```sql
-- Oracle / SQL Server: GROUPING_ID()
SELECT region, city, SUM(revenue),
    GROUPING_ID(region, city) AS gid
FROM sales
GROUP BY ROLLUP(region, city);

-- gid = GROUPING(region) * 2 + GROUPING(city) * 1
-- gid=0: (region, city) 明细行
-- gid=1: (region) 区域小计
-- gid=3: () 全局总计

-- PostgreSQL / Snowflake / BigQuery: GROUPING() 接受多参数
SELECT region, city, SUM(revenue),
    GROUPING(region, city) AS gid
FROM sales
GROUP BY ROLLUP(region, city);
-- 语义与 GROUPING_ID 相同，只是函数名不同
```

### 各引擎函数名对照

| 引擎 | GROUPING(col) | 多列位掩码 | 备注 |
|------|:---:|------|------|
| Oracle | 支持 | `GROUPING_ID(a, b)` | 两个函数 |
| SQL Server | 支持 | `GROUPING_ID(a, b)` | 两个函数 |
| PostgreSQL | 支持 | `GROUPING(a, b)` — 多参数 | 单一函数 |
| MySQL | 支持 (8.0.1+) | 不支持 | 仅单列 GROUPING() |
| Snowflake | 支持 | `GROUPING(a, b)` — 多参数 | - |
| BigQuery | 支持 | `GROUPING(a, b)` — 多参数 | - |
| DB2 | 支持 | `GROUPING_ID(a, b)` | 与 Oracle 兼容 |
| Hive | 支持 | `GROUPING__ID` — 内置特殊列 | 注意双下划线 |
| Spark SQL | 支持 | `GROUPING_ID(a, b)` | - |
| ClickHouse | 不支持 | 不支持 | 无 GROUPING 函数 |
| DuckDB | 支持 | `GROUPING_ID(a, b)` | - |
| Trino | 支持 | `GROUPING(a, b)` — 多参数 | - |
| MariaDB | 不支持 | 不支持 | 无 GROUPING 函数 |

> Hive 的 `GROUPING__ID` (双下划线) 是一个历史遗留问题。它是系统自动附加的隐式列，位掩码的位序与其他引擎相反（低位在左），使用时需特别注意。

## 复合列 (Composite Columns)

复合列是 GROUPING SETS 中用括号将多个列捆绑为一个逻辑单元的功能：

```sql
-- Oracle / PostgreSQL / SQL Server / Snowflake 等标准实现
GROUP BY ROLLUP((region, city), year)
-- 注意 (region, city) 有额外括号——它们是一个复合列

-- 等价于:
GROUP BY GROUPING SETS (
    ((region, city), year),   -- region + city + year
    ((region, city)),         -- region + city（year 被聚合掉）
    ()                        -- 全局总计
)
-- 只有 3 个分组集合，而非 ROLLUP(region, city, year) 的 4 个

-- 对比不使用复合列:
GROUP BY ROLLUP(region, city, year)
-- 等价于 4 个分组集合:
-- (region, city, year), (region, city), (region), ()
```

复合列的含义是"这几列要么一起参与分组，要么一起被聚合掉，不会单独拆开"。

### 支持情况

| 引擎 | 复合列支持 | 备注 |
|------|:---:|------|
| Oracle | 支持 | 完整支持 |
| SQL Server | 支持 | 完整支持 |
| PostgreSQL | 支持 | 完整支持 |
| Snowflake | 支持 | 完整支持 |
| BigQuery | 支持 | 完整支持 |
| DB2 | 支持 | 完整支持 |
| DuckDB | 支持 | 完整支持 |
| Trino | 支持 | 完整支持 |
| Spark SQL | 支持 | 完整支持 |
| MySQL | 支持 (8.0.31+) | 8.0.31 起支持 GROUPING SETS |
| ClickHouse | 不支持 | 不支持复合列 |
| Hive | 部分支持 | 取决于版本 |

## 串联分组 (Concatenated Groupings)

在 GROUP BY 中混合使用多个 GROUPING SETS / CUBE / ROLLUP，引擎会对它们做笛卡尔积：

```sql
GROUP BY ROLLUP(a, b), ROLLUP(c, d)

-- ROLLUP(a, b) 产出: {(a,b), (a), ()}  — 3 个集合
-- ROLLUP(c, d) 产出: {(c,d), (c), ()}  — 3 个集合
-- 笛卡尔积: 3 × 3 = 9 个分组集合:
-- (a,b,c,d), (a,b,c), (a,b), (a,c,d), (a,c), (a), (c,d), (c), ()
```

串联分组是构建复杂报表的强大工具，可以精确控制需要的分组组合，避免 CUBE 产出过多不需要的组合。

### 实际用例

```sql
-- 需求: 产品维度做完整 ROLLUP，时间维度只做年和总计
SELECT
    category, product,
    year,
    SUM(revenue)
FROM sales
GROUP BY ROLLUP(category, product), GROUPING SETS ((year), ());

-- ROLLUP(category, product): {(cat,prod), (cat), ()}
-- GROUPING SETS ((year), ()): {(year), ()}
-- 笛卡尔积: 3 × 2 = 6 个组合
-- 比 CUBE(category, product, year) 的 8 个组合更精确
```

### 支持情况

大部分支持 GROUPING SETS 的引擎都支持串联分组，因为它只是多个分组子句的笛卡尔积——语义清晰，实现直接。MariaDB 不支持（因为不支持 GROUPING SETS）。MySQL 8.0.31+ 支持。

## CUBE/ROLLUP 作为 GROUPING SETS 的简写

理解三者关系的关键是看 CUBE 和 ROLLUP 如何展开为 GROUPING SETS：

```sql
-- ROLLUP 展开规则: 从右向左逐级去除
ROLLUP(a, b, c) → GROUPING SETS ((a,b,c), (a,b), (a), ())

-- CUBE 展开规则: 所有子集（幂集）
CUBE(a, b) → GROUPING SETS ((a,b), (a), (b), ())

-- 部分 ROLLUP: ROLLUP 嵌套在 GROUP BY 中
GROUP BY a, ROLLUP(b, c)
→ GROUP BY GROUPING SETS ((a,b,c), (a,b), (a))
-- 注意: a 始终参与分组，没有全局总计
-- 这叫"部分 ROLLUP"，因为 a 不被 ROLLUP

-- 部分 CUBE:
GROUP BY a, CUBE(b, c)
→ GROUP BY GROUPING SETS ((a,b,c), (a,b), (a,c), (a))
```

| 语法 | 分组集合数量 | 特点 |
|------|:---:|------|
| `ROLLUP(a, b, ..., n)` | N+1 | 层级结构，适合有上下级关系的维度 |
| `CUBE(a, b, ..., n)` | 2^N | 全组合，适合 OLAP 多维分析 |
| `GROUPING SETS (...)` | 手动指定 | 最灵活，精确控制 |

## NULL 歧义: 区分"真实 NULL"与"分组 NULL"

这是 GROUPING SETS / ROLLUP / CUBE 实现中最微妙的问题。

### 问题本质

```sql
CREATE TABLE t (a INT, b INT, v INT);
INSERT INTO t VALUES (1, NULL, 10);  -- b 是真实的 NULL
INSERT INTO t VALUES (1, 2, 20);

SELECT a, b, SUM(v), GROUPING(b) AS gb
FROM t
GROUP BY ROLLUP(a, b);

-- 结果:
-- | 1    | NULL | 10 | 0 |  ← b 本来就是 NULL（真实数据）
-- | 1    | 2    | 20 | 0 |  ← 明细行
-- | 1    | NULL | 30 | 1 |  ← ROLLUP 小计（b 被聚合掉）
-- | NULL | NULL | 30 | 1 |  ← 全局总计
```

### 解决方案对比

| 方案 | 描述 | 采用的引擎 |
|------|------|------|
| GROUPING() 函数 | 用函数区分，应用层自行处理 | 所有支持 GROUPING SETS 的引擎 |
| GROUPING_ID() 位掩码 | 多列合并为一个数字 | Oracle, SQL Server, Spark |
| 标记行 | 添加额外标记列 | 应用层方案 |

最佳实践：**始终使用 GROUPING() 函数**。不要依赖 NULL 来判断是否为汇总行。

```sql
-- 推荐写法: 用 GROUPING() 构造展示标签
SELECT
    CASE WHEN GROUPING(region) = 1 THEN '全部区域' ELSE region END AS region,
    CASE WHEN GROUPING(city) = 1   THEN '全部城市' ELSE city   END AS city,
    SUM(revenue) AS total
FROM sales
GROUP BY ROLLUP(region, city);
```

## 各引擎语法差异详解

### Oracle

Oracle 是 GROUPING SETS 系列语法的先驱（9i，2001年），功能最完整：

```sql
-- 基本 ROLLUP
SELECT department, job, SUM(salary)
FROM employees
GROUP BY ROLLUP(department, job);

-- 复合列
SELECT region, country, year, SUM(revenue)
FROM sales
GROUP BY ROLLUP((region, country), year);

-- 串联分组
SELECT region, product, year, SUM(revenue)
FROM sales
GROUP BY ROLLUP(region), CUBE(product, year);

-- GROUPING_ID
SELECT department, job, SUM(salary),
    GROUPING(department) AS gd,
    GROUPING(job) AS gj,
    GROUPING_ID(department, job) AS gid
FROM employees
GROUP BY CUBE(department, job);

-- GROUP_ID(): Oracle 独有——区分重复分组集合
SELECT region, SUM(revenue), GROUP_ID() AS gid
FROM sales
GROUP BY region, ROLLUP(region);
-- region 出现了两次分组，GROUP_ID() 用于去重
```

### SQL Server

```sql
-- 标准语法 (2008+)
SELECT region, city, SUM(revenue)
FROM sales
GROUP BY ROLLUP(region, city);

-- 旧语法 (已废弃，但仍可用)
SELECT region, city, SUM(revenue)
FROM sales
GROUP BY region, city WITH ROLLUP;

-- GROUPING_ID
SELECT region, city, SUM(revenue),
    GROUPING_ID(region, city) AS gid
FROM sales
GROUP BY CUBE(region, city);
```

### PostgreSQL

```sql
-- 标准语法 (9.5+)
SELECT region, city, SUM(revenue)
FROM sales
GROUP BY ROLLUP(region, city);

-- GROUPING() 支持多参数（标准行为）
SELECT region, city, SUM(revenue),
    GROUPING(region, city) AS gid
FROM sales
GROUP BY CUBE(region, city);

-- 串联分组
SELECT a, b, c, SUM(v)
FROM t
GROUP BY ROLLUP(a), CUBE(b, c);
```

### MySQL

```sql
-- WITH ROLLUP 语法 (传统)
SELECT region, city, SUM(revenue)
FROM sales
GROUP BY region, city WITH ROLLUP;

-- 标准语法 (8.0.1+)
SELECT region, city, SUM(revenue)
FROM sales
GROUP BY ROLLUP(region, city);

-- GROUPING() 函数 (8.0.1+)
SELECT region, city, SUM(revenue),
    GROUPING(region) AS gr, GROUPING(city) AS gc
FROM sales
GROUP BY ROLLUP(region, city);

-- CUBE (8.0.1+)
SELECT region, city, SUM(revenue)
FROM sales
GROUP BY CUBE(region, city);

-- GROUPING SETS (8.0.31+)
SELECT region, city, SUM(revenue)
FROM sales
GROUP BY GROUPING SETS (
    (region, city),
    (region),
    ()
);
```

### ClickHouse

```sql
-- 标准语法
SELECT region, city, SUM(revenue)
FROM sales
GROUP BY ROLLUP(region, city);

-- WITH ROLLUP / WITH CUBE 后缀语法（也支持）
SELECT region, city, SUM(revenue)
FROM sales
GROUP BY region, city WITH ROLLUP;

SELECT region, city, SUM(revenue)
FROM sales
GROUP BY region, city WITH CUBE;

-- GROUPING SETS
SELECT region, city, SUM(revenue)
FROM sales
GROUP BY GROUPING SETS (
    (region, city),
    (region),
    ()
);

-- 注意: ClickHouse 不支持 GROUPING() 函数
-- 需要用其他方式区分汇总行
```

### Snowflake / BigQuery / Trino / DuckDB

这些引擎都采用标准语法，差异很小：

```sql
-- 标准 ROLLUP / CUBE / GROUPING SETS（所有引擎通用）
SELECT region, city, SUM(revenue)
FROM sales
GROUP BY ROLLUP(region, city);

-- GROUPING() 多参数（Snowflake / BigQuery / Trino）
SELECT region, city, SUM(revenue), GROUPING(region, city) AS gid
FROM sales GROUP BY CUBE(region, city);

-- GROUPING_ID()（DuckDB）
SELECT region, city, SUM(revenue), GROUPING_ID(region, city) AS gid
FROM sales GROUP BY CUBE(region, city);
```

### Spark SQL / Databricks / Hive

```sql
-- 标准语法 + WITH ROLLUP 都支持
SELECT region, city, SUM(revenue)
FROM sales
GROUP BY ROLLUP(region, city);
-- 或: GROUP BY region, city WITH ROLLUP

-- GROUPING_ID (Spark/Databricks)
SELECT region, city, SUM(revenue),
    GROUPING_ID(region, city) AS gid
FROM sales GROUP BY CUBE(region, city);

-- Hive 特殊: GROUPING__ID (双下划线，隐式列，位序与其他引擎相反)
SELECT region, city, SUM(revenue), GROUPING__ID
FROM sales GROUP BY region, city WITH CUBE;

-- Hive 的 GROUPING SETS 要求 GROUP BY 先列出所有列
SELECT region, city, SUM(revenue)
FROM sales
GROUP BY region, city
GROUPING SETS ((region, city), (region), ());
```

## 性能考量: 分组组合数的爆炸

### 组合数量

| 语法 | 维度数 N | 分组集合数 | 示例 |
|------|:---:|:---:|------|
| ROLLUP | 3 | 4 | N+1 线性增长 |
| ROLLUP | 5 | 6 | 可控 |
| ROLLUP | 10 | 11 | 完全可控 |
| CUBE | 3 | 8 | 2^N 指数增长 |
| CUBE | 5 | 32 | 开始有压力 |
| CUBE | 10 | 1024 | **危险** |
| CUBE | 15 | 32768 | **灾难** |
| CUBE | 20 | 1048576 | **系统崩溃** |

### 引擎的保护措施

部分引擎会限制分组集合的数量：

```sql
-- Spark SQL: spark.sql.maxGroupingSetsNum 默认 32
-- 超过限制会报错

-- 实际中，CUBE 列数超过 10 列就应该考虑替代方案
-- 如果只需要部分组合，用 GROUPING SETS 精确指定
```

### 执行策略对比

引擎实现 GROUPING SETS 的两种主要策略：

| 策略 | 描述 | 优势 | 劣势 | 采用引擎 |
|------|------|------|------|------|
| Expand（展开） | 每行数据复制 N 份（N=分组集合数），每份标记所属分组 | 实现简单，可复用现有 GROUP BY | 数据量膨胀 N 倍 | Spark, Hive, Flink |
| 多遍聚合 | 对数据做多次扫描/聚合，每次用不同分组键 | 不膨胀数据 | 多次扫描 | Oracle, SQL Server |
| 共享前缀 | ROLLUP 时利用层级关系，共享部分聚合结果 | 最优性能 | 仅适用于 ROLLUP | 部分高级优化器 |

## 部分 ROLLUP (Partial ROLLUP)

部分 ROLLUP 是指将某些列放在 ROLLUP 之外，使其始终参与分组：

```sql
-- 完整 ROLLUP: a 也会被聚合掉（产出全局总计）
GROUP BY ROLLUP(a, b, c)
→ (a,b,c), (a,b), (a), ()

-- 部分 ROLLUP: a 始终参与分组，不产出全局总计
GROUP BY a, ROLLUP(b, c)
→ (a,b,c), (a,b), (a)

-- 更复杂的部分 ROLLUP
GROUP BY a, b, ROLLUP(c, d)
→ (a,b,c,d), (a,b,c), (a,b)
```

### 典型场景

```sql
-- 需求: 按年份始终分组，在年份内对 region > city 做 ROLLUP
SELECT year, region, city, SUM(revenue)
FROM sales
GROUP BY year, ROLLUP(region, city);

-- 产出:
-- 2024 | East   | Beijing | 500   ← 明细
-- 2024 | East   | NULL    | 800   ← 区域小计
-- 2024 | NULL   | NULL    | 1500  ← 年度总计（而非全局总计）
```

部分 ROLLUP 只在支持标准 `ROLLUP()` 语法的引擎中可用。`WITH ROLLUP` 语法无法实现部分 ROLLUP（因为它对所有 GROUP BY 列整体生效）。

## 对引擎开发者的实现建议

### 1. 语法解析

GROUPING SETS / ROLLUP / CUBE 出现在 GROUP BY 子句中，解析器需要处理嵌套结构：

```
group_by_clause:
    GROUP BY group_by_element (',' group_by_element)*

group_by_element:
    expression                                          -- 普通列
  | ROLLUP '(' column_list ')'                         -- ROLLUP
  | CUBE '(' column_list ')'                           -- CUBE
  | GROUPING SETS '(' grouping_set (',' grouping_set)* ')'  -- GROUPING SETS

grouping_set:
    '(' column_list ')'     -- 多列分组
  | expression              -- 单列分组
  | '(' ')'                 -- 空集（全局总计）
  | ROLLUP '(' column_list ')'  -- 嵌套 ROLLUP（标准允许）
  | CUBE '(' column_list ')'    -- 嵌套 CUBE

column_list:
    column_or_composite (',' column_or_composite)*

column_or_composite:
    expression                              -- 普通列
  | '(' expression (',' expression)+ ')'    -- 复合列
```

注意复合列 `(a, b)` 与单列分组 `(a)` 的歧义——单元素括号不是复合列，需要两个以上元素才构成复合列。

### 2. 语义分析: 展开为分组集合列表

在 binder/analyzer 阶段，将所有 ROLLUP/CUBE 展开为 GROUPING SETS：

```
步骤 1: 展开 ROLLUP(a, b, c) → GROUPING SETS ((a,b,c), (a,b), (a), ())
步骤 2: 展开 CUBE(a, b) → GROUPING SETS ((a,b), (a), (b), ())
步骤 3: 处理串联分组 → 多个 GROUPING SETS 做笛卡尔积
步骤 4: 去重（可选）——消除重复的分组集合
步骤 5: 最终得到一个唯一的分组集合列表
```

### 3. 执行计划生成

推荐的实现路径（从简单到高级）：

**阶段一: Expand 方案（最简单）**

```
Expand 算子:
  输入: 每行原始数据
  输出: 每行复制 N 份（N=分组集合数），附加 grouping_id 列
  下游: 普通 GroupBy 算子，按 (grouping_id, 分组列) 分组

示例: ROLLUP(a, b) 有 3 个分组集合
原始行: (a=1, b=2, v=10)
→ 复制为 3 行:
  (gid=0, a=1,    b=2,    v=10)  ← 分组 (a, b)
  (gid=1, a=1,    b=NULL, v=10)  ← 分组 (a)
  (gid=2, a=NULL, b=NULL, v=10)  ← 分组 ()
```

优势: 可以完全复用现有的 GROUP BY 执行引擎，不需要新的算子类型。

**阶段二: 多遍聚合** — 对每个分组集合分别执行聚合后 UNION ALL。不膨胀数据，但多次扫描。

**阶段三: 共享前缀优化** — 针对 ROLLUP 的层级特性，先做最细粒度聚合 `GROUP BY a, b, c`，然后在其结果上逐级再聚合 `GROUP BY a, b` → `GROUP BY a` → `GROUP BY ()`。粗粒度聚合直接复用细粒度结果，避免重新扫描原始数据。仅适用于 ROLLUP（CUBE 无此层级关系）。

### 4. GROUPING() 函数的实现

```
实现方式:
1. 在 Expand 阶段为每行附加一个 grouping_id 位向量
2. GROUPING(col) 函数在运行时查询该位向量中对应列的位
3. 如果该位为 1，说明该列在当前分组集合中被"聚合掉"

位向量定义:
  N 个分组列 → N 位整数
  第 i 位 = 1 表示第 i 列不在当前分组集合中（被聚合掉）
  第 i 位 = 0 表示第 i 列在当前分组集合中（正常参与分组）

GROUPING_ID(a, b, c) = GROUPING(a) << 2 | GROUPING(b) << 1 | GROUPING(c) << 0
```

### 5. NULL 处理的注意事项

Expand 阶段将"被聚合掉"的列设为 NULL，但原始数据可能已经是 NULL。必须维护 grouping_id 位向量而非依赖值是否为 NULL。Hash 聚合时 `(a=NULL, gid=0)` 和 `(a=NULL, gid=1)` 必须是不同的分组键；排序聚合时排序键必须包含 grouping_id。

### 6. WITH ROLLUP 语法兼容

如果要支持 MySQL 兼容模式，在解析阶段将 `GROUP BY a, b WITH ROLLUP` 转换为 `GROUP BY ROLLUP(a, b)`，`WITH CUBE` 同理。转换在解析器中完成，后续处理统一走标准路径。

### 7. 优化器提示

- **分组集合去重**: `GROUP BY ROLLUP(a, b), GROUPING SETS ((a), ())` 展开后有重复的 `(a)` 和 `()`，应当去重
- **子集消除**: 如果下游查询只需部分分组集合的结果，可消除不需要的分组集合
- **分组列排序**: Expand 方案中，将分组列集合类似的行放在一起，有利于下游 GROUP BY 的局部性
- **共享前缀优化条件**: 仅当分组集合形成严格层级关系时可应用（ROLLUP 满足，CUBE 不满足）

## 参考资料

- SQL:1999 标准: ISO/IEC 9075-2:1999, Section 7.9 (GROUP BY clause)
- Oracle: [GROUP BY Extensions](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/SELECT.html#GUID-CFA006CA-6FF1-4972-821E-6996142A51C6)
- SQL Server: [GROUP BY ROLLUP, CUBE, GROUPING SETS](https://learn.microsoft.com/en-us/sql/t-sql/queries/select-group-by-transact-sql)
- PostgreSQL: [GROUPING SETS, CUBE, ROLLUP](https://www.postgresql.org/docs/current/queries-table-expressions.html#QUERIES-GROUPING-SETS)
- MySQL: [GROUP BY Modifiers](https://dev.mysql.com/doc/refman/8.0/en/group-by-modifiers.html)
- Snowflake: [GROUP BY ROLLUP, CUBE, GROUPING SETS](https://docs.snowflake.com/en/sql-reference/constructs/group-by-rollup)
- BigQuery: [ROLLUP, CUBE, GROUPING SETS](https://cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#group_by_clause)
- ClickHouse: [GROUP BY Modifiers](https://clickhouse.com/docs/en/sql-reference/statements/select/group-by#rollup-modifier)
- Spark SQL: [GROUP BY clause](https://spark.apache.org/docs/latest/sql-ref-syntax-qry-select-groupby.html)
- Hive: [Enhanced Aggregation](https://cwiki.apache.org/confluence/display/Hive/Enhanced+Aggregation,+Cube,+Grouping+and+Rollup)
- DuckDB: [GROUPING SETS](https://duckdb.org/docs/sql/query_syntax/groupby#grouping-sets)
- Trino: [GROUPING SETS](https://trino.io/docs/current/sql/select.html#grouping-sets)
