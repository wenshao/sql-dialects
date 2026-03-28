# ASOF JOIN 时序近似匹配

在时间轴上"找到最近的那条记录"——金融领域诞生的 JOIN 变体，正在成为时序数据处理的标准操作。

## 支持矩阵

| 引擎 | 支持 | 版本 | 语法 | 备注 |
|------|------|------|------|------|
| kdb+/q | 完整支持 | 早期版本 | `aj[...]` | **起源引擎**，金融行业标准 |
| ClickHouse | 完整支持 | 18.6+ | `ASOF JOIN ... ON ... AND ts >= ts` | 需要 AND 条件 |
| DuckDB | 完整支持 | 0.6.0+ | `ASOF JOIN ... ON ... AND ts >= ts` | 语法类 ClickHouse |
| Snowflake | 完整支持 | 2024 | `ASOF JOIN ... MATCH_CONDITION(>=)` | 专用 MATCH_CONDITION 语法 |
| Spark/Databricks | 部分支持 | 3.4+ | DataFrame API `asof_join` | SQL 语法不直接支持 |
| QuestDB | 完整支持 | GA | `ASOF JOIN` / `LT JOIN` / `SPLICE JOIN` | 时序数据库，多种变体 |
| TimescaleDB | 不支持 | - | 需 LATERAL JOIN 模拟 | PostgreSQL 扩展 |
| PostgreSQL | 不支持 | - | 需 LATERAL JOIN 模拟 | - |
| MySQL | 不支持 | - | 需子查询模拟 | - |
| Oracle | 不支持 | - | 需 LATERAL/子查询 | - |
| SQL Server | 不支持 | - | 需 CROSS APPLY | - |
| BigQuery | 不支持 | - | 需窗口函数模拟 | - |

## 设计动机: 时序数据的 JOIN 困境

### 经典场景

交易所的股票交易数据（trades）和报价数据（quotes）分别记录，时间戳不对齐：

```
trades 表:                    quotes 表:
| time     | symbol | price | | time     | symbol | bid  | ask  |
|----------|--------|-------|  |----------|--------|------|------|
| 10:00:01 | AAPL   | 150.5 | | 10:00:00 | AAPL   | 150.3| 150.7|
| 10:00:03 | AAPL   | 150.8 | | 10:00:02 | AAPL   | 150.5| 150.9|
| 10:00:05 | AAPL   | 151.0 | | 10:00:04 | AAPL   | 150.8| 151.2|
```

需求：为每笔交易匹配成交时最近的报价。交易时间 10:00:01 应匹配报价 10:00:00（而非 10:00:02）。

### 等值 JOIN 无法解决

```sql
-- 等值 JOIN: 时间戳不精确匹配，结果为空
SELECT * FROM trades t JOIN quotes q
ON t.symbol = q.symbol AND t.time = q.time;  -- 几乎没有匹配行
```

### 传统替代方案的代价

```sql
-- 方案 1: LATERAL JOIN + ORDER BY + LIMIT 1（PostgreSQL）
-- 正确但性能极差——对每笔交易执行一次子查询
SELECT t.*, q.bid, q.ask
FROM trades t
LEFT JOIN LATERAL (
    SELECT bid, ask FROM quotes q
    WHERE q.symbol = t.symbol AND q.time <= t.time
    ORDER BY q.time DESC
    LIMIT 1
) q ON true;

-- 方案 2: 窗口函数（需要 UNION 后重排序）
WITH combined AS (
    SELECT time, symbol, price, NULL AS bid, NULL AS ask, 'trade' AS src FROM trades
    UNION ALL
    SELECT time, symbol, NULL, bid, ask, 'quote' FROM quotes
),
filled AS (
    SELECT *,
           LAST_VALUE(bid IGNORE NULLS) OVER (PARTITION BY symbol ORDER BY time) AS latest_bid,
           LAST_VALUE(ask IGNORE NULLS) OVER (PARTITION BY symbol ORDER BY time) AS latest_ask
    FROM combined
)
SELECT * FROM filled WHERE src = 'trade';
```

两种方案要么 O(N*M) 性能灾难，要么需要复杂的 UNION + 窗口函数改写。

## ASOF JOIN 的语义

核心语义：对于左表的每一行，在右表中找到**时间戳 <= 左表时间戳的最近一行**。

```
左表 t.time = 10:00:03
右表候选:  10:00:00 (bid=150.3)  ← 满足 <= 条件
           10:00:02 (bid=150.5)  ← 满足 <= 条件，且更近 ✓
           10:00:04 (bid=150.8)  ← 不满足 <= 条件
结果: 匹配 10:00:02 的行
```

### 变体

| 变体 | 语义 | 应用场景 |
|------|------|---------|
| ASOF JOIN (<=) | 找 <= 当前时间的最近行 | 最常见——用历史最近数据 |
| ASOF JOIN (>=) | 找 >= 当前时间的最近行 | 向前看——下一个事件 |
| ASOF JOIN (<) | 严格小于 | 排除同时刻数据 |
| ASOF JOIN (>) | 严格大于 | 排除同时刻数据 |

## 语法对比

### DuckDB

```sql
-- ASOF JOIN: 找到 quotes.time <= trades.time 的最近匹配
SELECT t.time, t.symbol, t.price, q.bid, q.ask
FROM trades t
ASOF JOIN quotes q
    ON t.symbol = q.symbol
    AND t.time >= q.time;

-- ASOF LEFT JOIN: 无匹配时保留左表行（NULL 填充）
SELECT t.time, t.symbol, t.price, q.bid, q.ask
FROM trades t
ASOF LEFT JOIN quotes q
    ON t.symbol = q.symbol
    AND t.time >= q.time;
```

### ClickHouse

```sql
-- ClickHouse 的 ASOF JOIN 语法
-- 注意: ON 子句中最后一个条件必须是不等式（ASOF 条件）
SELECT t.time, t.symbol, t.price, q.bid, q.ask
FROM trades t
ASOF LEFT JOIN quotes q
    ON t.symbol = q.symbol
    AND t.time >= q.time;

-- 也支持 USING 语法
SELECT *
FROM trades t
ASOF JOIN quotes q
    USING (symbol, time);
-- USING 时默认为 >= 语义
```

### Snowflake

```sql
-- Snowflake 使用 MATCH_CONDITION 关键字
SELECT t.time, t.symbol, t.price, q.bid, q.ask
FROM trades t
ASOF JOIN quotes q
    MATCH_CONDITION (t.time >= q.time)
    ON t.symbol = q.symbol;
```

### kdb+/q（起源）

```
/ kdb+ 的 aj 函数——ASOF JOIN 的鼻祖
/ aj[匹配列; 左表; 右表]
result: aj[`symbol`time; trades; quotes]
```

kdb+/q 在 1990 年代就将 ASOF JOIN 作为核心操作，因为金融时序数据的按时间近似匹配是最基本的需求。SQL 世界用了 20 多年才追上这个概念。

### QuestDB

```sql
-- QuestDB 提供最丰富的时序 JOIN 变体
-- ASOF JOIN: 找 <= 的最近行（标准 ASOF）
SELECT * FROM trades ASOF JOIN quotes ON (symbol);

-- LT JOIN: 找严格 < 的最近行
SELECT * FROM trades LT JOIN quotes ON (symbol);

-- SPLICE JOIN: 双向合并（类似 FULL OUTER ASOF）
SELECT * FROM trades SPLICE JOIN quotes ON (symbol);
```

## 经典用例

### 用例 1: 交易匹配最近报价

```sql
-- DuckDB 语法
SELECT
    t.trade_id, t.symbol, t.trade_time, t.price, t.qty,
    q.bid, q.ask,
    t.price - q.bid AS spread_to_bid
FROM trades t
ASOF LEFT JOIN quotes q
    ON t.symbol = q.symbol
    AND t.trade_time >= q.quote_time;
```

### 用例 2: IoT 传感器数据对齐

```sql
-- 温度传感器和湿度传感器采样频率不同，需要对齐
SELECT
    temp.sensor_location,
    temp.reading_time,
    temp.temperature,
    humid.humidity
FROM temperature_readings temp
ASOF LEFT JOIN humidity_readings humid
    ON temp.sensor_location = humid.sensor_location
    AND temp.reading_time >= humid.reading_time;
```

### 用例 3: 汇率转换

```sql
-- 将交易金额按当时汇率转换
SELECT
    t.transaction_id,
    t.amount_usd,
    r.rate AS usd_to_eur_rate,
    t.amount_usd * r.rate AS amount_eur
FROM transactions t
ASOF LEFT JOIN exchange_rates r
    ON t.currency_pair = r.currency_pair
    AND t.txn_time >= r.effective_time;
```

## 对引擎开发者的实现分析

1. 排序合并算法（Sort-Merge）

最直观的实现方式，适用于两表都已按时间排序的情况：

```
算法: SortMerge ASOF JOIN (左表 L, 右表 R, 等值键 EQ, 时间键 T)
1. 按 EQ 分组（如 symbol）
2. 对每个分组，L 和 R 都按 T 排序
3. 双指针遍历:
   - l_ptr 指向 L 的当前行
   - r_ptr 指向 R 中 T <= L[l_ptr].T 的最大行
4. 输出 (L[l_ptr], R[r_ptr])，l_ptr 前进
5. r_ptr 只需前进（不回退），因为 L 也有序

时间复杂度: O(N + M)（排序后）
空间复杂度: O(1)（不含排序）
```

这是 kdb+/q 的经典实现方式，在时序数据库中极为高效。

2. 二分查找算法

当右表已排序但左表未排序时：

```
算法: BinarySearch ASOF JOIN
1. 按 EQ 分组
2. 对每个分组，R 按 T 排序（或建索引）
3. 对 L 的每一行，在 R 中二分查找 T <= L.T 的最大行

时间复杂度: O(N * log M)
空间复杂度: O(M)（右表索引）
```

3. Hash + 排序混合

ClickHouse 的实现采用 hash 分桶 + 排序合并：
- 先按等值键（symbol）hash 分桶
- 每个桶内按时间排序
- 桶内执行排序合并

4. 执行计划

```
TableScan(trades) → Sort(time)
                               ↘
                                 AsofJoin(symbol, time >=)  → Project
                               ↗
TableScan(quotes) → Sort(time)
```

ASOF JOIN 在计划中作为一种特殊的 JOIN 算子，要求输入已排序。如果输入来自索引或分区且天然有序，可以省去排序步骤。

5. NULL 和边界处理

关键设计决策：

| 场景 | 推荐行为 |
|------|---------|
| 左表时间为 NULL | 不匹配任何右表行 |
| 右表时间为 NULL | 跳过该右表行 |
| 左表时间早于所有右表行 | LEFT JOIN 返回 NULL，INNER JOIN 不输出 |
| 右表为空 | LEFT JOIN 全部返回 NULL |

6. 分布式执行

在分布式环境中 ASOF JOIN 的挑战：
- 两表需要按相同的等值键分片（co-partition）
- 每个分片内独立执行排序合并
- 如果分片不对齐，需要 shuffle——代价高昂

## 等价改写: 不支持 ASOF JOIN 的引擎

### PostgreSQL: LATERAL JOIN

```sql
SELECT t.*, q.bid, q.ask
FROM trades t
LEFT JOIN LATERAL (
    SELECT bid, ask
    FROM quotes q
    WHERE q.symbol = t.symbol AND q.time <= t.time
    ORDER BY q.time DESC
    LIMIT 1
) q ON true;
```

### SQL Server: CROSS APPLY

```sql
SELECT t.*, q.bid, q.ask
FROM trades t
CROSS APPLY (
    SELECT TOP 1 bid, ask
    FROM quotes q
    WHERE q.symbol = t.symbol AND q.time <= t.time
    ORDER BY q.time DESC
) q;
```

### MySQL: 相关子查询

```sql
SELECT t.*,
    (SELECT q.bid FROM quotes q
     WHERE q.symbol = t.symbol AND q.time <= t.time
     ORDER BY q.time DESC LIMIT 1) AS bid,
    (SELECT q.ask FROM quotes q
     WHERE q.symbol = t.symbol AND q.time <= t.time
     ORDER BY q.time DESC LIMIT 1) AS ask
FROM trades t;
```

### 通用: 窗口函数方案

```sql
WITH combined AS (
    SELECT time, symbol, price, NULL AS bid, NULL AS ask, 'T' AS src FROM trades
    UNION ALL
    SELECT time, symbol, NULL, bid, ask, 'Q' FROM quotes
),
filled AS (
    SELECT *,
        LAST_VALUE(bid IGNORE NULLS) OVER w AS latest_bid,
        LAST_VALUE(ask IGNORE NULLS) OVER w AS latest_ask
    FROM combined
    WINDOW w AS (PARTITION BY symbol ORDER BY time
                 ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
)
SELECT time, symbol, price, latest_bid, latest_ask
FROM filled WHERE src = 'T';
```

## 设计观点

### 为什么 ASOF JOIN 不在 SQL 标准中？

截至 SQL:2023，ASOF JOIN 仍未进入 ISO SQL 标准。原因可能是：

1. **应用领域窄**: 主要需求来自金融和 IoT，通用数据库厂商推动动力不足
2. **语义争议**: `<=` 还是 `<`？默认方向是什么？各引擎的答案不同
3. **LATERAL JOIN 可替代**: SQL 标准中 LATERAL JOIN 已能表达相同语义

但随着 DuckDB、ClickHouse 等引擎的普及，ASOF JOIN 正在成为事实标准。预计未来标准有可能将其纳入。

### 性能差距

ASOF JOIN 相对于 LATERAL JOIN 模拟的性能优势：

| 数据规模 | LATERAL JOIN | ASOF JOIN | 加速比 |
|---------|-------------|-----------|--------|
| 1K x 1K | ~10ms | ~2ms | 5x |
| 100K x 100K | ~30s | ~200ms | 150x |
| 10M x 10M | 超时 | ~10s | - |

在大规模时序数据上，原生 ASOF JOIN 的优势是压倒性的。

## 参考资料

- kdb+: [aj (asof join)](https://code.kx.com/q/ref/aj/)
- ClickHouse: [JOIN clause - ASOF](https://clickhouse.com/docs/en/sql-reference/statements/select/join#asof-join)
- DuckDB: [ASOF Joins](https://duckdb.org/docs/guides/sql_features/asof_join)
- Snowflake: [ASOF JOIN](https://docs.snowflake.com/en/sql-reference/constructs/asof-join)
- QuestDB: [JOIN types](https://questdb.io/docs/reference/sql/join/)
