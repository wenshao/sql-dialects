# Materialize: 聚合函数 (Aggregate Functions)

> 参考资料:
> - [Materialize Documentation - Aggregate Functions](https://materialize.com/docs/sql/functions/)
> - [Materialize Documentation - CREATE MATERIALIZED VIEW](https://materialize.com/docs/sql/create-materialized-view/)
> - [PostgreSQL Documentation - Aggregate Functions](https://www.postgresql.org/docs/current/functions-aggregate.html)


## 说明: Materialize 基于 PostgreSQL 语法，聚合函数与 PostgreSQL 高度兼容。

核心差异: 聚合在物化视图中可增量维护，提供实时计算能力。

## 基本聚合函数


```sql
SELECT COUNT(*) FROM users;                           -- 总行数
SELECT COUNT(DISTINCT city) FROM users;               -- 去重计数
SELECT SUM(age), AVG(age), MIN(age), MAX(age) FROM users;
```

## 聚合函数忽略 NULL（COUNT(*) 除外）

```sql
SELECT SUM(NULL);                                     -- NULL
SELECT COUNT(col_with_nulls) FROM users;              -- 仅计算非 NULL
```

## GROUP BY 分组聚合


## 单列分组

```sql
SELECT city, COUNT(*) AS cnt, AVG(age) AS avg_age
FROM users GROUP BY city;
```

## 多列分组

```sql
SELECT city, status, COUNT(*) AS cnt
FROM users GROUP BY city, status;
```

## HAVING: 分组后过滤

```sql
SELECT city, COUNT(*) AS cnt
FROM users GROUP BY city HAVING COUNT(*) > 10;
```

## FILTER 子句: 条件聚合 (PostgreSQL 风格)


## FILTER 是 SQL:2003 标准，比 CASE WHEN 更简洁

```sql
SELECT
    COUNT(*) AS total,
    COUNT(*) FILTER (WHERE age > 30) AS over_30,
    COUNT(*) FILTER (WHERE age <= 30) AS under_30,
    SUM(amount) FILTER (WHERE status = 'completed') AS completed_total
FROM orders;
```

对比 CASE WHEN 写法:
SUM(CASE WHEN status = 'completed' THEN amount ELSE 0 END) -- 旧方式
SUM(amount) FILTER (WHERE status = 'completed')              -- FILTER 方式
优势:
1. 语义更清晰（条件与聚合分离）
2. 内部实现可能更高效（不满足条件的行直接跳过）
3. 在 Materialize 中 FILTER 可增量维护

## 字符串聚合: STRING_AGG


```sql
SELECT STRING_AGG(username, ', ') FROM users;                         -- 基本用法
SELECT STRING_AGG(username, ', ' ORDER BY username) FROM users;       -- 带排序
SELECT STRING_AGG(DISTINCT city, ', ') FROM users;                    -- 去重
```

## 分组聚合

```sql
SELECT department,
    STRING_AGG(name, '; ' ORDER BY name) AS member_list
FROM employees GROUP BY department;
```

## JSON 聚合函数


## JSONB_AGG: 聚合为 JSONB 数组

```sql
SELECT JSONB_AGG(username) FROM users;
```

## JSONB_OBJECT_AGG: 聚合为 JSONB 对象

```sql
SELECT JSONB_OBJECT_AGG(username, age) FROM users;
```

## 分组 JSON 聚合

```sql
SELECT department, JSONB_AGG(JSONB_BUILD_OBJECT('name', name, 'age', age))
FROM employees GROUP BY department;
```

## 数组聚合: ARRAY_AGG


```sql
SELECT ARRAY_AGG(username ORDER BY id) FROM users;                    -- 聚合为数组
SELECT department, ARRAY_AGG(DISTINCT name) FROM employees
GROUP BY department;
```

## 统计聚合函数


```sql
SELECT STDDEV(age) FROM users;                        -- 样本标准差
SELECT STDDEV_POP(age) FROM users;                    -- 总体标准差
SELECT VARIANCE(age) FROM users;                      -- 样本方差
SELECT VAR_POP(age) FROM users;                       -- 总体方差
```

## 布尔聚合


```sql
SELECT BOOL_AND(active) FROM users;                   -- 所有 active 为 TRUE 则 TRUE
SELECT BOOL_OR(verified) FROM users;                  -- 任一 verified 为 TRUE 则 TRUE
SELECT EVERY(active) FROM users;                      -- SQL 标准的 BOOL_AND 别名
```

## 物化视图中的聚合: 增量维护


## Materialize 的核心能力: 聚合结果随源数据自动更新

```sql
CREATE MATERIALIZED VIEW city_stats AS
SELECT city, COUNT(*) AS cnt, AVG(age) AS avg_age
FROM users GROUP BY city;
```

## 复杂聚合物化视图

```sql
CREATE MATERIALIZED VIEW realtime_metrics AS
SELECT
    DATE_TRUNC('hour', event_time) AS hour_bucket,
    COUNT(*) AS total_events,
    COUNT(DISTINCT user_id) AS unique_users,
    COUNT(*) FILTER (WHERE event_type = 'click') AS clicks,
    COUNT(*) FILTER (WHERE event_type = 'purchase') AS purchases
FROM events
GROUP BY DATE_TRUNC('hour', event_time);
```

增量维护原理:
新数据到达时，只更新受影响的聚合分组（而非重新计算全部）
这使得 Materialize 可以高效维护实时聚合

## 不支持的功能


不支持 GROUPING SETS / ROLLUP / CUBE
PostgreSQL 的多维聚合在 Materialize 中不可用
替代方案: 创建多个物化视图或在应用层组合结果
不支持自定义聚合函数 (CREATE AGGREGATE)
PostgreSQL 的自定义聚合在 Materialize 中不可用
不支持有序集聚合 (PERCENTILE_CONT / MODE WITHIN GROUP)
百分位数等需要单独处理

## 横向对比: Materialize vs PostgreSQL


功能对比:
COUNT/SUM/AVG/MIN/MAX:  Materialize ✓    PostgreSQL ✓
FILTER 子句:            Materialize ✓    PostgreSQL ✓
STRING_AGG:             Materialize ✓    PostgreSQL ✓
JSONB_AGG:              Materialize ✓    PostgreSQL ✓
ARRAY_AGG:              Materialize ✓    PostgreSQL ✓
GROUPING SETS/ROLLUP:   Materialize ✗    PostgreSQL ✓
PERCENTILE_CONT:        Materialize ✗    PostgreSQL ✓
CREATE AGGREGATE:       Materialize ✗    PostgreSQL ✓
增量维护:               Materialize ✓    PostgreSQL ✗（需手动刷新）

## 版本演进与注意事项

Materialize 0.x: 基础聚合函数
Materialize 0.7+: FILTER 子句, JSONB_AGG
Materialize 0.9+: 增量维护优化
注意事项:
1. 聚合函数与 PostgreSQL 语法高度兼容
2. 物化视图中聚合会增量维护（核心优势）
3. 不支持 GROUPING SETS / ROLLUP / CUBE
4. 不支持自定义聚合函数
5. COUNT(DISTINCT) 在流式场景中有特殊近似实现
