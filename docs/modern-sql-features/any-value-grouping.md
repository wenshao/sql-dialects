# ANY_VALUE / GROUPING SETS / CUBE / ROLLUP

分组聚合的扩展——从 ANY_VALUE 逃生阀到多维聚合。

## 一、ANY_VALUE

### 支持矩阵

| 引擎 | 支持 | 版本 | 备注 |
|------|------|------|------|
| MySQL | 支持 | 5.7+ | **解决 ONLY_FULL_GROUP_BY 的逃生阀** |
| BigQuery | 支持 | GA | `ANY_VALUE(expr)` |
| DuckDB | 支持 | GA | `any_value(expr)` / `arbitrary(expr)` |
| Snowflake | 支持 | GA | `ANY_VALUE(expr)` |
| Trino | 支持 | GA | `arbitrary(expr)` |
| ClickHouse | 支持 | GA | `any(expr)` |
| Databricks | 支持 | GA | `any_value(expr)` / `any(expr)` |
| SQL Server | 不支持 | - | 用 `MAX` 或子查询替代 |
| PostgreSQL | 不支持 | - | 有社区讨论但未实现 |
| Oracle | 不支持 | - | `ANY_VALUE` 在 23c 中引入 |
| SQLite | 不支持 | - | 但 SQLite 的 GROUP BY 本身就是非严格模式 |

### 设计动机

MySQL 5.7.5 开始默认启用 `ONLY_FULL_GROUP_BY`，要求 SELECT 中的非聚合列必须出现在 GROUP BY 中。这破坏了大量存量 SQL：

```sql
-- MySQL 5.6 可以执行，5.7+ 默认报错
SELECT customer_id, customer_name, SUM(amount)
FROM orders
GROUP BY customer_id;
-- ERROR: customer_name is not in GROUP BY and not aggregated
```

问题是: `customer_name` 由 `customer_id` 函数依赖决定（1:1 关系），逻辑上不需要 GROUP BY。但引擎无法（或不愿）做函数依赖分析。

ANY_VALUE 是显式的"逃生阀"——告诉引擎"这列的值不重要，取任意一个"：

```sql
-- ANY_VALUE: 明确告诉引擎取任意值即可
SELECT customer_id, ANY_VALUE(customer_name) AS name, SUM(amount)
FROM orders
GROUP BY customer_id;
-- customer_name 在每个 customer_id 分组内都相同，ANY_VALUE 取任意一个
```

### 语法对比

```sql
-- MySQL
SELECT dept_id, ANY_VALUE(dept_name), COUNT(*)
FROM employees GROUP BY dept_id;

-- BigQuery
SELECT dept_id, ANY_VALUE(dept_name), COUNT(*)
FROM employees GROUP BY dept_id;

-- ClickHouse（函数名为 any）
SELECT dept_id, any(dept_name), count()
FROM employees GROUP BY dept_id;

-- Trino（函数名为 arbitrary）
SELECT dept_id, arbitrary(dept_name), count(*)
FROM employees GROUP BY dept_id;

-- DuckDB（两个别名都支持）
SELECT dept_id, any_value(dept_name), count(*)
FROM employees GROUP BY dept_id;

-- PostgreSQL 替代方案
SELECT dept_id, MAX(dept_name), COUNT(*)
FROM employees GROUP BY dept_id;
-- 用 MAX/MIN 代替——当值唯一时结果相同
-- 但语义不同: MAX 承诺返回最大值，ANY_VALUE 承诺返回任意值

-- SQL Server 替代方案
SELECT dept_id, MAX(dept_name), COUNT(*)
FROM employees GROUP BY dept_id;
```

### ANY_VALUE 的语义

ANY_VALUE 返回分组中**任意一行**的值。关键语义：

- **不确定性**: 同一查询多次执行可能返回不同值
- **NULL 处理**: 如果分组中有 NULL 和非 NULL，可能返回 NULL
- **性能**: 引擎可以在第一次遇到时直接返回，不需要比较——比 MAX/MIN 快

### 对引擎开发者的实现

ANY_VALUE 是最简单的聚合函数：

```
AnyValueAccumulator<T> {
    value: T
    has_value: bool

    fn update(val: T):
        if !has_value:
            value = val
            has_value = true
        // 后续值直接忽略

    fn merge(other: AnyValueAccumulator):
        if !has_value && other.has_value:
            value = other.value
            has_value = true

    fn result() -> T:
        return value
}
```

优化: 在分布式聚合中，ANY_VALUE 可以直接取第一个 partial 的值，不需要比较。

## 二、GROUPING SETS / CUBE / ROLLUP

### 支持矩阵

| 引擎 | GROUPING SETS | CUBE | ROLLUP | GROUPING() | 版本 |
|------|--------------|------|--------|------------|------|
| Oracle | 支持 | 支持 | 支持 | 支持 | 8i+ |
| SQL Server | 支持 | 支持 | 支持 | 支持 | 2008+ |
| PostgreSQL | 支持 | 支持 | 支持 | 支持 | 9.5+ (2016) |
| BigQuery | 支持 | 支持 | 支持 | 支持 | GA |
| Snowflake | 支持 | 支持 | 支持 | 支持 | GA |
| Databricks | 支持 | 支持 | 支持 | 支持 | GA |
| DuckDB | 支持 | 支持 | 支持 | 支持 | 0.8.0+ |
| Trino | 支持 | 支持 | 支持 | 支持 | GA |
| ClickHouse | 支持 | 支持 | 支持 | 支持 | 19.13+ |
| Hive | 支持 | 支持 | 支持 | 支持 | 0.10+ |
| MySQL | **不支持** | **不支持** | **仅 WITH ROLLUP** | 部分 | - |
| MariaDB | 支持 | 不支持 | 支持 | 支持 | 10.5+ |
| SQLite | 不支持 | 不支持 | 不支持 | - | - |

### 设计动机

报表场景中经常需要同时看"明细 + 小计 + 合计"：

```
| region | product  | revenue |
|--------|----------|---------|
| East   | Widget   | 100     |
| East   | Gadget   | 150     |
| East   | (小计)   | 250     |  ← ROLLUP
| West   | Widget   | 200     |
| West   | Gadget   | 120     |
| West   | (小计)   | 320     |  ← ROLLUP
| (合计) | (合计)   | 570     |  ← ROLLUP
```

没有 GROUPING SETS 时，需要 UNION ALL 多个 GROUP BY 查询——扫描表多次。

### 三者关系

```sql
-- ROLLUP = 层级聚合（从明细到合计）
GROUP BY ROLLUP (a, b, c)
-- 等效于
GROUP BY GROUPING SETS ((a, b, c), (a, b), (a), ())

-- CUBE = 所有组合的聚合
GROUP BY CUBE (a, b)
-- 等效于
GROUP BY GROUPING SETS ((a, b), (a), (b), ())

-- GROUPING SETS = 显式指定哪些分组组合
GROUP BY GROUPING SETS ((a, b), (a), ())
```

| 特性 | ROLLUP(a,b,c) | CUBE(a,b,c) | GROUPING SETS |
|------|--------------|-------------|---------------|
| 分组数 | N+1 (4) | 2^N (8) | 自定义 |
| 适用场景 | 层级报表 | 多维分析 | 灵活定制 |

### 语法对比

#### PostgreSQL / SQL Server / Oracle / BigQuery（标准语法）

```sql
-- ROLLUP: 层级小计
SELECT
    region,
    product,
    SUM(revenue) AS total_revenue
FROM sales
GROUP BY ROLLUP (region, product);
-- 输出:
-- (East, Widget, 100)
-- (East, Gadget, 150)
-- (East, NULL,   250)    ← region 小计
-- (West, Widget, 200)
-- (West, Gadget, 120)
-- (West, NULL,   320)    ← region 小计
-- (NULL, NULL,   570)    ← 总计

-- CUBE: 所有维度组合
SELECT region, product, SUM(revenue)
FROM sales
GROUP BY CUBE (region, product);
-- 比 ROLLUP 多出: (NULL, Widget), (NULL, Gadget) 等按 product 的汇总

-- GROUPING SETS: 自定义组合
SELECT region, product, SUM(revenue)
FROM sales
GROUP BY GROUPING SETS (
    (region, product),   -- 明细
    (region),            -- 按地区汇总
    ()                   -- 总计
);

-- GROUPING() 函数: 区分 NULL 是"汇总行"还是"数据就是 NULL"
SELECT
    region,
    product,
    SUM(revenue) AS total,
    GROUPING(region) AS is_region_total,     -- 1 = 汇总行, 0 = 明细行
    GROUPING(product) AS is_product_total
FROM sales
GROUP BY ROLLUP (region, product);
```

#### MySQL（仅 WITH ROLLUP）

```sql
-- MySQL 只支持 WITH ROLLUP（注意语法位置不同!）
SELECT region, product, SUM(revenue)
FROM sales
GROUP BY region, product WITH ROLLUP;
-- 注意: WITH ROLLUP 在 GROUP BY 列表之后
-- 不是 GROUP BY ROLLUP(region, product)

-- MySQL 8.0+ 支持 GROUPING() 函数
SELECT
    region, product, SUM(revenue),
    GROUPING(region) AS is_total
FROM sales
GROUP BY region, product WITH ROLLUP;

-- MySQL 不支持 GROUPING SETS 和 CUBE
-- 替代方案: UNION ALL
SELECT region, product, SUM(revenue) FROM sales GROUP BY region, product
UNION ALL
SELECT region, NULL, SUM(revenue) FROM sales GROUP BY region
UNION ALL
SELECT NULL, NULL, SUM(revenue) FROM sales;
-- 缺点: 扫描表 3 次
```

#### 复合用法

```sql
-- ROLLUP 和 CUBE 可以组合
GROUP BY a, ROLLUP (b, c), CUBE (d, e)
-- 等效于 a × ROLLUP(b,c) × CUBE(d,e) 的笛卡尔积

-- 部分 ROLLUP
GROUP BY a, ROLLUP (b, c)
-- = GROUPING SETS ((a, b, c), (a, b), (a))
-- 注意: a 始终在分组中，不参与 ROLLUP
```

### 等价改写: 不支持 GROUPING SETS 的引擎

```sql
-- UNION ALL 模拟（MySQL / SQLite）
-- GROUP BY GROUPING SETS ((a, b), (a), ())

SELECT a, b, SUM(x) AS total, 0 AS grp FROM t GROUP BY a, b
UNION ALL
SELECT a, NULL, SUM(x), 1 FROM t GROUP BY a
UNION ALL
SELECT NULL, NULL, SUM(x), 2 FROM t;

-- 用 grp 列区分汇总级别（模拟 GROUPING 函数）
```

### 对引擎开发者的实现建议

#### 1. 实现方案选择

| 方案 | 描述 | 优劣 |
|------|------|------|
| 多次聚合 | 对每个 grouping set 做独立聚合，UNION ALL 结果 | 简单但扫描多次 |
| 单次扫描 + 多路输出 | 一次扫描数据，同时维护多组 accumulator | 高效但内存大 |
| 单次扫描 + 位图 | 用位图标记每行属于哪些 grouping set | 最优实现 |

#### 2. 位图实现

每行数据对于不同的 grouping set 有不同的 GROUP BY 键。用位图标记：

```
GROUPING SETS ((a, b), (a), ())
位图:
  Set 0: (a, b)  → key = (a_value, b_value)
  Set 1: (a)     → key = (a_value, NULL)
  Set 2: ()      → key = (NULL, NULL)

对每一行输入，生成 3 个虚拟行（每个 grouping set 一个），
用不同的 key 发送到 hash aggregate。
```

#### 3. GROUPING() 函数实现

GROUPING() 需要在输出行中附加元信息——标记每列是"真实值"还是"因 ROLLUP/CUBE 而置 NULL"：

```
每行输出附加一个 grouping_id 位图:
  bit[i] = 1 表示第 i 列在当前 grouping set 中不参与分组（是汇总列）
  bit[i] = 0 表示第 i 列参与分组（是明细列）

GROUPING(col_i) = bit[i]
```

#### 4. 内存优化

CUBE(a, b, c) 产生 2^3 = 8 个 grouping set，CUBE(a, b, c, d, e) 产生 32 个。每个 set 都需要独立的 hash table。优化策略：

- **共享前缀**: ROLLUP(a, b, c) 中，(a, b, c) 的结果可以先聚合，再对 (a, b) 做二次聚合
- **限制 CUBE 维度**: 建议限制最大维度数（如 12），超过时报错
- **spill to disk**: 当 hash table 总大小超过内存限制时，溢写到磁盘

#### 5. 分布式执行

GROUPING SETS 在分布式环境中的执行：

```
阶段 1: 每个节点对本地数据做 partial aggregate（每个 grouping set 独立）
阶段 2: 按 grouping set 的 key shuffle（不同 set 的 key 结构不同）
阶段 3: 合并 partial 结果，输出最终结果
```

挑战: 不同 grouping set 的 shuffle key 不同，需要多轮 shuffle 或统一 key 格式。

## 参考资料

- MySQL: [ANY_VALUE](https://dev.mysql.com/doc/refman/8.0/en/miscellaneous-functions.html#function_any-value)
- PostgreSQL: [GROUPING SETS](https://www.postgresql.org/docs/current/queries-table-expressions.html#QUERIES-GROUPING-SETS)
- SQL Server: [GROUP BY with ROLLUP, CUBE, and GROUPING SETS](https://learn.microsoft.com/en-us/sql/t-sql/queries/select-group-by-transact-sql)
- Oracle: [GROUP BY Extensions](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/SELECT.html)
- BigQuery: [GROUPING SETS](https://cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#group_by_grouping_sets)
