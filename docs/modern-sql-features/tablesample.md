# TABLESAMPLE 数据采样

从大表中随机抽取一部分数据——SQL:2003 标准定义，大数据场景下的核心能力。

## 支持矩阵

| 引擎 | 语法 | 方法 | 版本 | 备注 |
|------|------|------|------|------|
| PostgreSQL | `TABLESAMPLE` | BERNOULLI, SYSTEM | 9.5+ | 完全符合标准 |
| SQL Server | `TABLESAMPLE` | SYSTEM | 2005+ | 仅块级采样 |
| Oracle | `SAMPLE` / `SAMPLE BLOCK` | 行级, 块级 | 8i+ | 非标准语法 |
| Hive | `TABLESAMPLE` | BUCKET, 行数, 百分比 | 0.11+ | 扩展语法丰富 |
| BigQuery | `TABLESAMPLE SYSTEM` | SYSTEM | GA | 仅块级采样 |
| Snowflake | `SAMPLE` / `TABLESAMPLE` | BERNOULLI, SYSTEM (BLOCK) | GA | 两种关键字等价 |
| DuckDB | `TABLESAMPLE` / `USING SAMPLE` | BERNOULLI, SYSTEM, RESERVOIR | 0.3.0+ | 额外支持 RESERVOIR |
| Trino | `TABLESAMPLE` | BERNOULLI, SYSTEM | 早期版本 | 符合标准 |
| ClickHouse | `SAMPLE` | 自有实现 | 早期版本 | 需表引擎支持采样键 |
| MySQL | 不支持 | - | - | 需 `ORDER BY RAND() LIMIT N` 模拟 |
| SQLite | 不支持 | - | - | 需应用层模拟 |

## SQL:2003 标准定义

SQL:2003 标准引入 `TABLESAMPLE` 子句，定义了两种采样方法：

```sql
-- 标准语法
SELECT * FROM table_name TABLESAMPLE method (percentage) [REPEATABLE (seed)];

-- method 可以是:
-- BERNOULLI: 行级随机采样
-- SYSTEM:    系统实现相关的采样（通常是块级）
```

关键语义：

1. **百分比参数**: 0 到 100 之间的值，表示期望采样比例
2. **结果是近似的**: 10% 采样不保证恰好返回总行数的 10%
3. **REPEATABLE**: 可选子句，给定相同的种子值，在数据不变时返回相同结果

## BERNOULLI vs SYSTEM: 两种采样方法

### BERNOULLI（行级随机）

```sql
-- PostgreSQL / Trino / DuckDB / Snowflake
SELECT * FROM orders TABLESAMPLE BERNOULLI(10);
```

实现原理：逐行扫描，每行独立地以给定概率（如 10%）决定是否保留。

```
行1: random() < 0.10 → 保留
行2: random() < 0.10 → 丢弃
行3: random() < 0.10 → 保留
...（每行独立判断）
```

特点：

- **随机性好**: 真正的行级随机，样本分布均匀
- **性能差**: 必须扫描全表（每行都要判断），I/O 量与全表扫描相同
- **适用场景**: 对随机性要求高的统计分析

### SYSTEM（块级随机）

```sql
-- PostgreSQL / SQL Server / BigQuery
SELECT * FROM orders TABLESAMPLE SYSTEM(10);
```

实现原理：随机选择数据块（page/block），被选中的块中所有行都返回。

```
Block 1 (1000 行): random() < 0.10 → 整块保留
Block 2 (1000 行): random() < 0.10 → 整块丢弃
Block 3 (1000 行): random() < 0.10 → 整块保留
...（按块判断）
```

特点：

- **性能好**: 只读取被选中的块，I/O 大幅减少
- **随机性差**: 同一块中的行通常是相邻插入的，可能有聚集偏差
- **适用场景**: 快速粗略估计、数据探索

## 各引擎语法对比

### PostgreSQL（最标准）

```sql
-- BERNOULLI: 行级采样，约 5% 的行
SELECT * FROM large_table TABLESAMPLE BERNOULLI(5);

-- SYSTEM: 块级采样，约 5% 的块
SELECT * FROM large_table TABLESAMPLE SYSTEM(5);

-- REPEATABLE: 可重复的采样
SELECT * FROM large_table TABLESAMPLE BERNOULLI(10) REPEATABLE(42);

-- 结合其他子句
SELECT count(*), avg(amount)
FROM orders TABLESAMPLE BERNOULLI(1)
WHERE status = 'completed';

-- 扩展采样方法（通过扩展安装）
-- tsm_system_rows: 精确返回 N 行
-- tsm_system_time: 在指定毫秒内返回尽可能多的行
CREATE EXTENSION tsm_system_rows;
SELECT * FROM large_table TABLESAMPLE SYSTEM_ROWS(1000);
```

### SQL Server（仅 SYSTEM）

```sql
-- 块级采样（百分比）
SELECT * FROM Sales.SalesOrderDetail TABLESAMPLE (10 PERCENT);

-- 指定行数（近似）
SELECT * FROM Sales.SalesOrderDetail TABLESAMPLE (1000 ROWS);

-- REPEATABLE
SELECT * FROM Sales.SalesOrderDetail
    TABLESAMPLE (10 PERCENT) REPEATABLE(42);

-- 注意: SQL Server 不支持 BERNOULLI 方法
-- 实际返回的行数可能与指定值有较大偏差
```

### Snowflake

```sql
-- SAMPLE 和 TABLESAMPLE 等价
SELECT * FROM large_table SAMPLE (10);
SELECT * FROM large_table TABLESAMPLE (10);

-- 指定方法
SELECT * FROM large_table SAMPLE BERNOULLI (10);
SELECT * FROM large_table SAMPLE BLOCK (10);     -- 等价于 SYSTEM

-- 指定行数（Snowflake 扩展）
SELECT * FROM large_table SAMPLE (100 ROWS);

-- REPEATABLE / SEED
SELECT * FROM large_table SAMPLE (10) SEED (42);
SELECT * FROM large_table SAMPLE (10) REPEATABLE (42);
```

### ClickHouse（SAMPLE 子句）

```sql
-- ClickHouse 使用自有的 SAMPLE 语法
-- 前提: 表必须有采样键（SAMPLE BY 子句）
CREATE TABLE events (
    event_id UInt64,
    user_id UInt64,
    event_time DateTime
) ENGINE = MergeTree()
ORDER BY (user_id, event_time)
SAMPLE BY user_id;       -- 声明采样键

-- 按比例采样
SELECT count() FROM events SAMPLE 0.1;            -- 约 10%

-- 按行数采样
SELECT count() FROM events SAMPLE 10000;           -- 约 10000 行

-- 带偏移的采样（不同分片取不同样本）
SELECT count() FROM events SAMPLE 1/10 OFFSET 3/10;

-- 注意: 没有采样键的表不能使用 SAMPLE
-- 采样基于采样键的哈希值范围，不是真正的随机
```

### Hive（最丰富的采样方式）

```sql
-- 分桶采样: 从 10 个桶中取第 1 个
SELECT * FROM large_table TABLESAMPLE(BUCKET 1 OUT OF 10 ON user_id);

-- 按百分比采样
SELECT * FROM large_table TABLESAMPLE(10 PERCENT);

-- 按行数采样
SELECT * FROM large_table TABLESAMPLE(1000 ROWS);

-- 按数据量采样
SELECT * FROM large_table TABLESAMPLE(100M);       -- 约 100MB

-- 分桶采样在 JOIN 时特别有用: 两表用相同的桶策略
SELECT a.*, b.*
FROM table_a TABLESAMPLE(BUCKET 1 OUT OF 10 ON id) a
JOIN table_b TABLESAMPLE(BUCKET 1 OUT OF 10 ON id) b ON a.id = b.id;
```

### DuckDB（额外支持 RESERVOIR）

```sql
-- 标准语法
SELECT * FROM large_table TABLESAMPLE BERNOULLI(10);
SELECT * FROM large_table TABLESAMPLE SYSTEM(10);

-- USING SAMPLE 语法（DuckDB 扩展）
SELECT * FROM large_table USING SAMPLE 10%;
SELECT * FROM large_table USING SAMPLE 1000;
SELECT * FROM large_table USING SAMPLE 10% (BERNOULLI);
SELECT * FROM large_table USING SAMPLE 10% (SYSTEM);

-- RESERVOIR 采样: 精确返回 N 行（Reservoir Sampling 算法）
SELECT * FROM large_table USING SAMPLE 1000 (RESERVOIR);

-- REPEATABLE
SELECT * FROM large_table USING SAMPLE 10% (BERNOULLI, 42);
```

### MySQL 替代方案

```sql
-- MySQL 没有 TABLESAMPLE，常见的替代方案:

-- 方案 1: ORDER BY RAND()（性能极差，全表排序）
SELECT * FROM large_table ORDER BY RAND() LIMIT 1000;

-- 方案 2: 基于主键范围随机（性能好但分布可能不均）
SELECT * FROM large_table
WHERE id >= (SELECT FLOOR(RAND() * (SELECT MAX(id) FROM large_table)))
LIMIT 1000;

-- 方案 3: 基于哈希取模（可重复，分布较均匀）
SELECT * FROM large_table WHERE MOD(id, 10) = 0;  -- 约 10%

-- 方案 4: 使用 information_schema 估算后随机偏移
SET @offset = FLOOR(RAND() * (SELECT TABLE_ROWS FROM information_schema.TABLES
    WHERE TABLE_NAME = 'large_table'));
PREPARE stmt FROM 'SELECT * FROM large_table LIMIT 1000 OFFSET ?';
EXECUTE stmt USING @offset;
```

## REPEATABLE 子句: 可重复的采样

```sql
-- REPEATABLE(seed) 确保相同种子在数据不变时返回相同结果
-- 用途: A/B 测试、可复现的实验、调试

-- PostgreSQL
SELECT * FROM users TABLESAMPLE BERNOULLI(5) REPEATABLE(12345);
-- 相同种子 + 相同数据 → 相同结果

-- 注意事项:
-- 1. 数据变化（INSERT/DELETE/UPDATE）后，相同种子可能返回不同结果
-- 2. 不同引擎的种子算法不同，跨引擎不可复现
-- 3. SYSTEM 方法的 REPEATABLE 粒度是块级的
```

## 用例

### 1. 大表快速统计估算

```sql
-- 1亿行的订单表，精确 COUNT DISTINCT 太慢
-- 采样 1% 后估算，误差可接受
SELECT
    COUNT(DISTINCT customer_id) * 100 AS estimated_unique_customers,
    AVG(amount) AS avg_amount,           -- 均值的采样估计是无偏的
    STDDEV(amount) AS stddev_amount
FROM orders TABLESAMPLE BERNOULLI(1);
```

### 2. 数据探索

```sql
-- 数据分析师快速了解数据分布
SELECT status, count(*) AS cnt
FROM events TABLESAMPLE SYSTEM(5)
GROUP BY status
ORDER BY cnt DESC;
```

### 3. 测试数据集提取

```sql
-- 从生产表提取可重复的测试数据
CREATE TABLE test_orders AS
SELECT * FROM production.orders TABLESAMPLE BERNOULLI(0.1) REPEATABLE(42);
```

## 对引擎开发者的实现建议

### 1. BERNOULLI 实现

行级概率过滤，实现最简单：

```
BernoulliSampleScan {
    child: TableScan
    probability: f64          // 0.0 ~ 1.0
    rng: RandomGenerator      // 可用 seed 初始化

    fn next() -> Option<Row>:
        loop:
            row = child.next()?
            if rng.next_f64() < probability:
                return Some(row)
}
```

关键点：必须扫描全表，无法跳过 I/O。优化器不应将 BERNOULLI 采样推到存储层做 I/O 裁剪。

### 2. SYSTEM 实现

块级跳过，可大幅减少 I/O：

```
SystemSampleScan {
    child: TableScan
    probability: f64
    rng: RandomGenerator
    current_block_selected: bool

    fn next_block() -> bool:
        current_block_selected = rng.next_f64() < probability
        return current_block_selected

    fn next() -> Option<Row>:
        while !current_block_selected:
            child.skip_block()     // 跳过整个块的 I/O
            if !child.has_next_block(): return None
            next_block()
        return child.next()
}
```

关键点：需要存储层支持块级跳过（skip_block），否则退化为 BERNOULLI。

### 3. 与优化器的交互

```
-- 采样对统计信息的影响
-- 优化器需要知道采样后的预估行数

原始行数: 100,000,000
BERNOULLI(1): 预估 1,000,000 行
SYSTEM(1):    预估 1,000,000 行（但方差更大）

-- 采样不应影响谓词下推
SELECT * FROM t TABLESAMPLE BERNOULLI(10) WHERE x > 100
→ 先做 WHERE 下推（索引/过滤），再在结果上采样
   还是先采样再过滤？

-- SQL 标准定义: TABLESAMPLE 在 FROM 子句中，逻辑上先于 WHERE
-- 但优化器可以选择先做谓词下推再采样（语义等价当采样是行独立的）
```

### 4. REPEATABLE 实现

```
-- 使用 seed 初始化伪随机数生成器
-- 对于 BERNOULLI: seed → RNG → 逐行判断
-- 对于 SYSTEM: seed → RNG → 逐块判断

-- 注意: 要保证相同 seed 的可重复性，需要固定:
-- 1. 随机数算法（如 PCG、Xoshiro）
-- 2. 数据的物理顺序（SYSTEM 方法对物理布局敏感）
-- 3. 块大小（SYSTEM 方法）
```

## 设计争议

### 采样在 SQL 执行管道中的位置

SQL 标准将 TABLESAMPLE 定义在 FROM 子句中，逻辑上在 WHERE 之前执行。但这意味着：

```sql
-- 逻辑执行: 先从 1 亿行中采样 1%（100 万行），再过滤 status = 'A'
SELECT * FROM orders TABLESAMPLE BERNOULLI(1) WHERE status = 'A';

-- 如果 status = 'A' 只占 1%，最终只有约 1 万行
-- 用户可能期望的是: 先过滤 status = 'A'（100 万行），再采样 1%
```

一些引擎允许在子查询上采样来解决这个问题：

```sql
SELECT * FROM (SELECT * FROM orders WHERE status = 'A') t TABLESAMPLE BERNOULLI(1);
```

### 为什么 MySQL 不支持？

MySQL 的存储引擎架构（InnoDB 的 B+ 树聚簇索引）不容易做块级跳过。行级采样（BERNOULLI）虽然不依赖存储布局，但 MySQL 团队一直未优先实现此特性。社区中多次有人提出 feature request，但截至 MySQL 8.x 仍未支持。

## 参考资料

- SQL:2003 标准: ISO/IEC 9075-2, Section 7.6 (table reference - TABLESAMPLE)
- PostgreSQL: [TABLESAMPLE](https://www.postgresql.org/docs/current/sql-select.html#SQL-FROM)
- SQL Server: [TABLESAMPLE](https://learn.microsoft.com/en-us/sql/t-sql/queries/from-transact-sql#tablesample-clause)
- Snowflake: [SAMPLE / TABLESAMPLE](https://docs.snowflake.com/en/sql-reference/constructs/sample)
- DuckDB: [SAMPLE](https://duckdb.org/docs/sql/samples)
- ClickHouse: [SAMPLE](https://clickhouse.com/docs/en/sql-reference/statements/select/sample)
