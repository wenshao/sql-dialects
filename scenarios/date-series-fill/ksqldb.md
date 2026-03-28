# ksqlDB: 日期序列生成与间隙填充 (Date Series Fill)

> 参考资料:
> - [ksqlDB Documentation - Windowing](https://docs.ksqldb.io/en/latest/concepts/time-and-windows-in-ksqldb-queries/)
> - [ksqlDB Documentation - Scalar Functions](https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/scalar-functions/)
> - [ksqlDB Documentation - Aggregate Functions](https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/aggregate-functions/)


## 示例数据（流和表）


## 每日销售流: 从 Kafka 持续消费

```sql
CREATE STREAM sales_stream (
    sale_date  VARCHAR,
    amount     DECIMAL(10,2)
) WITH (
    KAFKA_TOPIC  = 'daily_sales_topic',
    VALUE_FORMAT = 'JSON',
    TIMESTAMP    = 'sale_date'
);
```

## 创建物化聚合表

```sql
CREATE TABLE daily_sales WITH (
    KAFKA_TOPIC  = 'daily_sales_agg',
    VALUE_FORMAT = 'JSON'
) AS
SELECT sale_date, SUM(amount) AS amount
FROM   sales_stream
GROUP  BY sale_date
EMIT CHANGES;
```

## ksqlDB 日期序列的挑战


ksqlDB 是流处理引擎，不支持:
generate_series（PostgreSQL 特有）
递归 CTE（WITH RECURSIVE）
辅助数字表（无静态表数据）
替代方案:
使用 Kafka Connect 生成日期维度数据
使用 TUMBLING/HOPPING 窗口自动生成时间桶
使用 AS OF JOIN 进行时间点关联

## 窗口聚合: 时间桶自动填充（推荐）


## 使用 TUMBLING 窗口按天聚合

```sql
SELECT WINDOW_START AS sale_date,
       COALESCE(SUM(amount), 0) AS daily_total
FROM   sales_stream
WINDOW TUMBLING (SIZE 1 DAY)
GROUP  BY WINDOW_START
EMIT CHANGES;
```

设计分析: TUMBLING 窗口自动生成连续的时间桶
每天一个桶，即使没有数据也会有对应的窗口
这在流处理场景中等价于"日期序列"
窗口边界由 Kafka 消息的时间戳决定

## HOPPING 窗口: 滑动聚合


```sql
SELECT WINDOW_START AS window_start,
       WINDOW_END   AS window_end,
       COALESCE(SUM(amount), 0) AS rolling_total
FROM   sales_stream
WINDOW HOPPING (SIZE 7 DAY, ADVANCE BY 1 DAY)
GROUP  BY WINDOW_START, WINDOW_END
EMIT CHANGES;
```

## HOPPING 窗口: 7 天窗口，每天滑动一次

等价于"7 天滚动合计"

## AS OF JOIN: 时间点关联（流表关联）


## 将销售数据与最新汇率关联

```sql
CREATE TABLE exchange_rates (
    currency   VARCHAR PRIMARY KEY,
    rate       DECIMAL(10,6),
    rate_date  VARCHAR
) WITH (
    KAFKA_TOPIC  = 'exchange_rates',
    VALUE_FORMAT = 'JSON'
);

SELECT s.sale_date, s.amount,
       e.rate,
       s.amount * e.rate AS amount_usd
FROM   sales_stream s
LEFT   JOIN exchange_rates e
       ON s.sale_date >= e.rate_date
EMIT CHANGES;
```

## AS OF JOIN 使用流的时间戳关联表中最近的记录

类似于"用最近已知值填充"的语义

## 累计和（Running Total）


## 使用表查询实现累计和

```sql
SELECT sale_date, amount,
       SUM(amount) OVER (ORDER BY sale_date) AS running_total
FROM   daily_sales
EMIT CHANGES;
```

## 窗口函数 SUM() OVER (ORDER BY ...) 在 ksqlDB 中可用

注意: 流查询中 running_total 会持续更新

## 使用日期维度流（Kafka 主题预填充）


## 创建日期维度流（由外部系统预填充）

例如使用 Kafka Connect 从数据库导入日期维度

```sql
CREATE STREAM date_dimension (
    date_key    VARCHAR KEY,
    date_value  VARCHAR,
    year        INT,
    month       INT,
    day         INT,
    weekday     INT
) WITH (
    KAFKA_TOPIC  = 'date_dimension',
    VALUE_FORMAT = 'JSON'
);
```

使用 LEFT JOIN 填充（流 + 维度流关联）
SELECT d.date_value AS sale_date,
COALESCE(s.amount, 0) AS amount
FROM   date_dimension d
LEFT   JOIN sales_stream s WITHIN 1 DAY
ON d.date_key = s.sale_date
EMIT CHANGES;

## 用最近已知值填充（LOCF 模式）


ksqlDB 不支持 IGNORE NULLS
但可以使用 LAST_VALUE 或 LAST_VALUE_OFFSET 函数
方法: 聚合表中使用 COALESCE 链

```sql
SELECT sale_date,
       COALESCE(amount,
            LAST_VALUE(amount) OVER (
                ORDER BY sale_date
                ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
            )
       ) AS filled_amount
FROM   daily_sales
EMIT CHANGES;
```

## 注意: 实际行为取决于 ksqlDB 版本对窗口函数的支持程度

如果 LAST_VALUE 不支持忽略 NULL，需要使用应用层逻辑

## ksqlDB 时间语义说明


ksqlDB 有两种时间语义:
Event Time:  事件发生时间（如 sale_date 字段）
Processing Time: 消息被处理的时间
日期序列填充在流处理中与传统 SQL 有本质区别:
传统 SQL: 知道完整的时间范围，生成所有日期
ksqlDB:    流是无界的，只能基于窗口和 watermark 处理
实践建议:
(a) 优先使用 TUMBLING 窗口自动生成时间桶
(b) 日期维度数据通过 Kafka 主题提供
(c) 复杂的时间序列操作在外部系统完成

## 横向对比与对引擎开发者的启示


## ksqlDB 日期填充策略:

TUMBLING 窗口: 自动按时间桶聚合（最自然的方式）
HOPPING 窗口:  滑动窗口聚合
AS OF JOIN:    时间点关联
维度流:        外部日期维度 + LEFT JOIN
2. 与其他流处理引擎对比:
ksqlDB:     TUMBLING 窗口 + 维度流
Flink SQL:  TUMBLE/HOP 窗口 + Temporal Join
Materialize: generate_series + LEFT JOIN（PostgreSQL 兼容）
对引擎开发者:
流处理引擎的"日期序列"概念与传统 SQL 完全不同
窗口（Window）是流处理中日期填充的自然替代
支持日期维度流（Temporal Join）是重要能力
物化视图（Materialized View）模式更接近传统 SQL 体验
