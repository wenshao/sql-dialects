# MATCH_RECOGNIZE 模式匹配

在事件序列中用正则模式寻找复杂趋势——SQL:2016 引入的最具野心的特性，将行为分析从过程式代码拉回声明式 SQL。

## 支持矩阵

| 引擎 | 支持 | 版本 | 备注 |
|------|------|------|------|
| Oracle | 完整支持 | 12c (2013) | **最早实现者**，SQL:2016 标准的主要推动者 |
| Snowflake | 完整支持 | GA | 完整 SQL:2016 语义 |
| Trino | 完整支持 | 356+ | 2021 年加入 |
| Flink SQL | 完整支持 | 1.7+ | 流处理场景的核心功能 |
| Databricks | 完整支持 | Runtime 13.0+ | Spark 内核不支持，仅 Databricks SQL |
| MySQL | 不支持 | - | 无计划 |
| PostgreSQL | 不支持 | - | 无计划 |
| SQL Server | 不支持 | - | 无计划 |
| ClickHouse | 不支持 | - | 有 windowFunnel，但不是 MATCH_RECOGNIZE |
| DuckDB | 不支持 | - | 无计划 |
| BigQuery | 不支持 | - | 无计划 |

## 设计动机: 为什么需要行模式匹配

### 问题场景

股票分析师的日常需求："找出过去一年中所有 V 型反转走势——先连续下跌至少 3 天，再连续上涨至少 3 天。"

在没有 MATCH_RECOGNIZE 的时代，这个需求需要：

```sql
-- 传统写法: 窗口函数 + CASE + 自连接（极其复杂）
WITH daily AS (
    SELECT ticker, trade_date, close_price,
           LAG(close_price) OVER (PARTITION BY ticker ORDER BY trade_date) AS prev_price,
           CASE
               WHEN close_price < LAG(close_price) OVER (PARTITION BY ticker ORDER BY trade_date) THEN 'DOWN'
               WHEN close_price > LAG(close_price) OVER (PARTITION BY ticker ORDER BY trade_date) THEN 'UP'
               ELSE 'FLAT'
           END AS direction
    FROM stock_prices
),
groups AS (
    SELECT *, SUM(CASE WHEN direction != LAG(direction) OVER (PARTITION BY ticker ORDER BY trade_date)
                       THEN 1 ELSE 0 END) OVER (PARTITION BY ticker ORDER BY trade_date) AS grp
    FROM daily
)
-- 还需要继续嵌套多层来识别"下跌段后紧跟上涨段"...
-- 代码量通常超过 50 行，且难以维护
```

核心困难在于: SQL 是面向集合的语言，天然不擅长描述"行与行之间的顺序关系"。

### MATCH_RECOGNIZE 的解决方案

```sql
SELECT *
FROM stock_prices
MATCH_RECOGNIZE (
    PARTITION BY ticker
    ORDER BY trade_date
    MEASURES
        FIRST(DOWN.trade_date) AS start_date,
        LAST(UP.trade_date)    AS end_date,
        FIRST(DOWN.close_price) AS start_price,
        LAST(DOWN.close_price)  AS bottom_price,
        LAST(UP.close_price)    AS end_price
    ONE ROW PER MATCH
    PATTERN (DOWN{3,} UP{3,})
    DEFINE
        DOWN AS close_price < PREV(close_price),
        UP   AS close_price > PREV(close_price)
);
```

用类似正则表达式的语法声明模式，由引擎自动匹配——这是 SQL 向"事件处理语言"扩展的重大一步。

## 核心概念

### 1. PATTERN —— 模式定义

PATTERN 子句使用类似正则表达式的语法来描述行序列：

```sql
PATTERN (A B+ C* D?)
-- A    : 恰好一行
-- B+   : 一行或多行（贪婪匹配）
-- C*   : 零行或多行
-- D?   : 零行或一行
-- {3,} : 至少 3 行
-- {2,5}: 2 到 5 行
-- |    : 或（交替匹配）
-- ()   : 分组
```

### 2. DEFINE —— 条件定义

DEFINE 为 PATTERN 中的每个变量指定匹配条件：

```sql
DEFINE
    DOWN AS close_price < PREV(close_price),     -- 下跌: 比前一天低
    UP   AS close_price > PREV(close_price),      -- 上涨: 比前一天高
    FLAT AS close_price = PREV(close_price)       -- 持平
```

未在 DEFINE 中出现的变量默认匹配所有行（如 PATTERN 中的起始锚点）。

### 3. MEASURES —— 输出列

MEASURES 定义匹配成功后输出哪些值：

```sql
MEASURES
    MATCH_NUMBER()         AS match_num,    -- 第几次匹配
    CLASSIFIER()           AS var_name,     -- 当前行匹配了哪个变量
    FIRST(DOWN.trade_date) AS start_date,   -- 下跌段第一天
    LAST(UP.trade_date)    AS end_date,     -- 上涨段最后一天
    COUNT(DOWN.*)          AS down_days,    -- 下跌了几天
    COUNT(UP.*)            AS up_days       -- 上涨了几天
```

### 4. 输出模式

```sql
ONE ROW PER MATCH          -- 每次匹配输出一行汇总
ALL ROWS PER MATCH         -- 每次匹配输出所有行（带分类标记）
```

### 5. 匹配后行为

```sql
AFTER MATCH SKIP PAST LAST ROW       -- 默认: 从匹配结尾的下一行继续
AFTER MATCH SKIP TO NEXT ROW         -- 从匹配开头的下一行继续（允许重叠匹配）
AFTER MATCH SKIP TO FIRST var        -- 跳到指定变量的第一次出现
AFTER MATCH SKIP TO LAST var         -- 跳到指定变量的最后一次出现
```

## 语法对比

### Oracle 12c+

```sql
SELECT * FROM stock_prices
MATCH_RECOGNIZE (
    PARTITION BY ticker
    ORDER BY trade_date
    MEASURES
        FIRST(DOWN.trade_date) AS start_date,
        LAST(UP.trade_date) AS end_date
    ONE ROW PER MATCH
    AFTER MATCH SKIP PAST LAST ROW
    PATTERN (DOWN{3,} UP{3,})
    DEFINE
        DOWN AS close_price < PREV(close_price),
        UP   AS close_price > PREV(close_price)
) mr;
```

### Snowflake

```sql
-- 语法与 Oracle 基本一致
SELECT * FROM stock_prices
MATCH_RECOGNIZE (
    PARTITION BY ticker
    ORDER BY trade_date
    MEASURES
        FIRST(DOWN.trade_date) AS start_date,
        LAST(UP.trade_date) AS end_date
    ONE ROW PER MATCH
    PATTERN (DOWN{3,} UP{3,})
    DEFINE
        DOWN AS close_price < PREV(close_price),
        UP   AS close_price > PREV(close_price)
);
```

### Flink SQL（流处理特化）

```sql
-- Flink 的 MATCH_RECOGNIZE 主要用于流处理中的 CEP（复杂事件处理）
SELECT * FROM user_clicks
MATCH_RECOGNIZE (
    PARTITION BY user_id
    ORDER BY click_time
    MEASURES
        FIRST(A.page) AS entry_page,
        LAST(C.page)  AS exit_page,
        COUNT(B.*)     AS browse_count
    ONE ROW PER MATCH
    AFTER MATCH SKIP PAST LAST ROW
    PATTERN (A B* C)
    DEFINE
        A AS page = '/home',
        B AS page NOT IN ('/home', '/checkout'),
        C AS page = '/checkout'
) AS funnel;
```

## 经典用例

### 用例 1: 用户连续登录天数

```sql
SELECT user_id, login_streak
FROM user_logins
MATCH_RECOGNIZE (
    PARTITION BY user_id
    ORDER BY login_date
    MEASURES COUNT(CONSECUTIVE.*) AS login_streak
    ONE ROW PER MATCH
    PATTERN (CONSECUTIVE{3,})
    DEFINE
        CONSECUTIVE AS login_date = PREV(login_date) + INTERVAL '1' DAY
);
```

### 用例 2: 行为漏斗分析

```sql
SELECT user_id, view_time, cart_time, pay_time
FROM user_events
MATCH_RECOGNIZE (
    PARTITION BY user_id
    ORDER BY event_time
    MEASURES
        FIRST(V.event_time) AS view_time,
        FIRST(C.event_time) AS cart_time,
        FIRST(P.event_time) AS pay_time
    ONE ROW PER MATCH
    PATTERN (V W* C W* P)
    DEFINE
        V AS event_type = 'view_product',
        C AS event_type = 'add_to_cart',
        P AS event_type = 'payment',
        W AS event_type NOT IN ('view_product', 'add_to_cart', 'payment')
);
```

### 用例 3: 异常检测——连续超阈值

```sql
SELECT sensor_id, start_time, end_time, max_temp
FROM sensor_readings
MATCH_RECOGNIZE (
    PARTITION BY sensor_id
    ORDER BY reading_time
    MEASURES
        FIRST(HIGH.reading_time) AS start_time,
        LAST(HIGH.reading_time)  AS end_time,
        MAX(HIGH.temperature)    AS max_temp
    ONE ROW PER MATCH
    PATTERN (HIGH{5,})
    DEFINE
        HIGH AS temperature > 100.0
);
```

## 对引擎开发者的实现分析

### 1. 状态机模型: NFA vs DFA

MATCH_RECOGNIZE 的模式匹配本质上是在行序列上运行正则引擎：

- **NFA（非确定性有限自动机）**: Oracle 的实现方式。支持回溯，能处理所有正则特性（贪婪/懒惰量词、交替匹配）。缺点是最坏情况下指数级时间复杂度。
- **DFA（确定性有限自动机）**: 某些引擎优化后采用。无回溯，线性时间，但无法支持所有正则特性（如反向引用）。

实际实现中通常选择 NFA + 优化剪枝，原因是 SQL 模式通常较短且回溯有限。

### 2. 内存管理

```
PARTITION BY ticker ORDER BY trade_date
```

引擎需要在内存中缓存每个分区的行数据，直到匹配完成。对于大分区（如一只股票 10 年的日线数据 = ~2500 行），内存压力可控；但如果分区键选择不当（如不分区），可能需要缓存全表。

实现建议：
- 设置每个分区的最大行数限制（如 Oracle 的隐式限制）
- 支持 spill to disk 机制
- 在 PATTERN 中利用有界量词 `{,100}` 限制搜索范围

### 3. 流处理特殊考量

在 Flink SQL 等流处理引擎中，MATCH_RECOGNIZE 面临额外挑战：
- 数据无界: 不能等所有数据到齐后再匹配
- 需要增量匹配: 每到一行就推进状态机
- 超时处理: 模式匹配多久没完成算放弃？

### 4. 执行计划位置

```
TableScan → Filter (WHERE) → Sort (ORDER BY) → MatchRecognize → Project
```

MATCH_RECOGNIZE 在执行计划中位于排序之后。它消费排好序的行流，输出匹配结果。

### 5. 复杂度评估

实现 MATCH_RECOGNIZE 的工程量极大，这是多数引擎不支持的根本原因：
- Parser 扩展: 新关键字 + 模式语法 + MEASURES 表达式
- 类型推断: MEASURES 中的表达式涉及跨行引用
- 状态机构建: PATTERN → NFA/DFA 编译
- 执行器: 流式行匹配 + 回溯 + 输出
- 优化器: 谓词下推到 DEFINE 条件

保守估计需要资深工程师 3-6 个月的开发周期。

## 替代方案: 不支持 MATCH_RECOGNIZE 的引擎

### 方案 1: 窗口函数 LAG/LEAD + 分组

```sql
-- 识别 V 型反转（简化版，只能识别固定长度）
WITH tagged AS (
    SELECT ticker, trade_date, close_price,
           CASE WHEN close_price < LAG(close_price) OVER w THEN 'D'
                WHEN close_price > LAG(close_price) OVER w THEN 'U'
                ELSE 'F' END AS direction
    FROM stock_prices
    WINDOW w AS (PARTITION BY ticker ORDER BY trade_date)
),
segments AS (
    SELECT *, SUM(CASE WHEN direction != LAG(direction) OVER
        (PARTITION BY ticker ORDER BY trade_date) THEN 1 ELSE 0 END)
        OVER (PARTITION BY ticker ORDER BY trade_date) AS seg_id
    FROM tagged
)
SELECT ticker, seg_id, direction, COUNT(*) AS seg_len,
       MIN(trade_date) AS seg_start, MAX(trade_date) AS seg_end
FROM segments
GROUP BY ticker, seg_id, direction;
-- 后续还需再 JOIN 相邻段来识别 V 型模式
```

### 方案 2: 递归 CTE

```sql
-- 连续登录天数（递归写法）
WITH RECURSIVE consecutive AS (
    SELECT user_id, login_date, 1 AS streak
    FROM user_logins
    UNION ALL
    SELECT c.user_id, l.login_date, c.streak + 1
    FROM consecutive c
    JOIN user_logins l ON c.user_id = l.user_id
        AND l.login_date = c.login_date + INTERVAL '1' DAY
)
SELECT user_id, MAX(streak) AS max_streak
FROM consecutive
GROUP BY user_id;
```

### 方案 3: ClickHouse windowFunnel（部分替代）

```sql
-- ClickHouse 的 windowFunnel 函数处理漏斗场景
SELECT user_id,
       windowFunnel(86400)(event_time, event = 'view', event = 'cart', event = 'pay') AS funnel_level
FROM user_events
GROUP BY user_id;
```

## 设计争议

### 过于复杂？

MATCH_RECOGNIZE 是 SQL 标准中最复杂的单一特性。批评者认为：
- 学习曲线过于陡峭，多数 SQL 用户无法掌握
- 正则模式在行上的语义与字符串正则有微妙差异，容易误用
- 实现成本太高，投入产出比不佳

支持者则认为：
- 事件序列分析是真实且高频的需求
- 声明式方案远优于过程式循环
- 一旦掌握，表达能力远超窗口函数组合

### 为什么不用专用语言？

kdb+/q、Esper（CEP 引擎）等专用系统在事件模式匹配方面更成熟。将此功能引入 SQL 的价值在于：用户不需要离开 SQL 生态，可以在同一查询中组合使用 JOIN、聚合、窗口函数和模式匹配。

## 参考资料

- ISO/IEC 9075-2:2016 (SQL:2016) Row Pattern Recognition
- Oracle: [MATCH_RECOGNIZE](https://docs.oracle.com/en/database/oracle/oracle-database/19/dwhsg/sql-pattern-matching.html)
- Snowflake: [MATCH_RECOGNIZE](https://docs.snowflake.com/en/sql-reference/constructs/match_recognize)
- Trino: [Row Pattern Recognition](https://trino.io/docs/current/sql/match-recognize.html)
- Flink: [Pattern Recognition](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/queries/match_recognize/)
