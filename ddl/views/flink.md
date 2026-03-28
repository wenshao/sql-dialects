# Flink SQL: 视图

> 参考资料:
> - [Flink Documentation - CREATE VIEW](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/create/#create-view)
> - [Flink Documentation - SQL Statements](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/overview/)

**引擎定位**: 流批一体计算引擎。表是外部系统的映射，支持 Changelog 语义和 Watermark 机制。

## 基本视图

Flink SQL 视图是逻辑视图，定义在 Catalog 中
```sql
SELECT id, username, email, event_time
FROM users
WHERE age >= 18;

```

CREATE OR REPLACE（Flink 1.17+）
早期版本需要 DROP + CREATE

临时视图（仅当前会话可见）
```sql
CREATE TEMPORARY VIEW temp_active_users AS
SELECT id, username, email
FROM users
WHERE age >= 18;

```

## 流式视图

Flink SQL 的核心场景是流处理
```sql
SELECT
    user_id,
    TUMBLE_START(event_time, INTERVAL '1' HOUR) AS window_start,
    TUMBLE_END(event_time, INTERVAL '1' HOUR) AS window_end,
    COUNT(*) AS order_count,
    SUM(amount) AS total_amount
FROM orders
GROUP BY user_id, TUMBLE(event_time, INTERVAL '1' HOUR);

```

基于处理时间的视图
```sql
CREATE VIEW recent_events AS
SELECT id, event_type, proctime
FROM events
WHERE event_type = 'click';

```

## 物化视图

Flink SQL 不支持物化视图
## 替代方案：

## 使用 CREATE TABLE ... AS SELECT (CTAS) 将结果写入外部存储

## 使用 INSERT INTO ... SELECT 持续写入 sink 表

## 使用 Flink Materialized Table（1.20+，实验性功能）


写入 sink 表（类似物化视图的效果）
INSERT INTO order_summary_sink
SELECT user_id, COUNT(*), SUM(amount)
FROM orders
GROUP BY user_id;

## 可更新视图

Flink SQL 视图不可更新
删除视图
```sql
DROP VIEW IF EXISTS active_users;
DROP TEMPORARY VIEW temp_active_users;
DROP TEMPORARY VIEW IF EXISTS temp_active_users;

```

**限制:**
不支持物化视图（使用 sink 表替代）
不支持 WITH CHECK OPTION
不支持可更新视图
视图是流计算管道的逻辑定义
Catalog 中的视图在 Session 间持久化
