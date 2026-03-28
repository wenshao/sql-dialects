# TDengine: 存储过程

TDengine 不支持存储过程
所有业务逻辑在应用层实现
============================================================
替代方案
============================================================
方案 1：使用 UDF（用户定义函数，3.0+）
创建 UDF（C 语言实现）
CREATE FUNCTION my_func AS '/path/to/libmyfunc.so' OUTPUTTYPE FLOAT;
CREATE AGGREGATE FUNCTION my_agg AS '/path/to/libmyagg.so' OUTPUTTYPE FLOAT BUFSIZE 64;
使用 UDF
SELECT my_func(current) FROM d1001;
SELECT my_agg(current) FROM d1001 INTERVAL(1h);
删除 UDF
DROP FUNCTION my_func;
方案 2：使用 Stream 计算（3.0+）
创建流计算

```sql
CREATE STREAM avg_stream INTO avg_results AS
SELECT _WSTART, sensor_id, AVG(current) AS avg_current
FROM meters
INTERVAL(1h);
```

## 方案 3：使用订阅（Topic/Subscription）

创建主题

```sql
CREATE TOPIC topic_meters AS SELECT * FROM meters;
```

在应用层订阅并处理
使用 TDengine 客户端 API 消费主题数据
方案 4：应用层实现存储过程逻辑
使用 Python/Java/Go 等语言连接 TDengine 执行复杂逻辑
注意：TDengine 不支持存储过程
注意：3.0+ 支持 UDF（C 语言实现）
注意：Stream 计算可替代部分存储过程功能
注意：复杂业务逻辑在应用层实现
