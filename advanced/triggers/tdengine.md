# TDengine: 触发器

## TDengine 不支持触发器

使用 Stream 计算和订阅替代

## Stream 计算（替代 AFTER INSERT 触发器）


## 当数据插入时自动计算聚合

```sql
CREATE STREAM hourly_avg INTO hourly_avg_results AS
SELECT _WSTART, location, AVG(current) AS avg_current, MAX(current) AS max_current
FROM meters
INTERVAL(1h);
```

## 插入 meters 时自动触发 stream 计算并写入 hourly_avg_results

带过滤的 Stream（类似条件触发器）

```sql
CREATE STREAM alert_stream INTO alerts AS
SELECT ts, location, current
FROM meters
WHERE current > 15;
```

## 订阅（Topic/Subscription）


## 创建主题

```sql
CREATE TOPIC topic_meters AS SELECT * FROM meters;
CREATE TOPIC topic_alerts AS SELECT * FROM meters WHERE current > 15;
```

在应用层订阅并处理（类似触发器的回调）
使用 TDengine Consumer API:
consumer = TaosConsumer(topic='topic_alerts')
while True:
msg = consumer.poll()
process_alert(msg)  -- 应用层处理逻辑
删除

```sql
DROP STREAM hourly_avg;
DROP TOPIC topic_meters;
```

注意：TDengine 不支持触发器
注意：Stream 计算是实时数据处理的替代方案
注意：Topic/Subscription 用于异步事件处理
注意：应用层订阅 + 回调 = 类似触发器效果
