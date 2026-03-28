# TDengine: Views

> 参考资料:
> - [TDengine Documentation - SQL Manual](https://docs.tdengine.com/reference/sql/)
> - [TDengine Documentation - Views (3.2.1+)](https://docs.tdengine.com/reference/sql/view/)
> - [TDengine Documentation - Continuous Query](https://docs.tdengine.com/develop/continuous-query/)


## 基本视图（TDengine 3.2.1+）

```sql
CREATE VIEW active_devices AS
SELECT device_id, temperature, ts
FROM sensor_data
WHERE temperature > 25;
```

## 物化视图

TDengine 不支持传统物化视图

替代方案 1：连续查询 (Continuous Query, 2.x)
注意：3.x 已废弃连续查询，改用流计算
CREATE TABLE avg_temp AS
SELECT AVG(temperature) AS avg_temp, FIRST(ts) AS ts
FROM sensor_data
INTERVAL(10m);
替代方案 2：流计算 (Stream, 3.0+)

```sql
CREATE STREAM stream_avg_temp
INTO avg_temp_table
AS SELECT
    _wstart AS window_start,
    AVG(temperature) AS avg_temp,
    COUNT(*) AS cnt
FROM sensor_data
INTERVAL(10m);
```

## 替代方案 3：超级表 + 标签查询

TDengine 的标签（TAG）查询本身就是一种"物化"的元数据

## 可更新视图

TDengine 视图不可更新


## 删除视图

```sql
DROP VIEW active_devices;
```

限制：
视图功能需要 TDengine 3.2.1+
不支持物化视图（使用流计算替代）
不支持 WITH CHECK OPTION
不支持 CREATE OR REPLACE VIEW
TDengine 是时序数据库，设计理念与 OLTP 不同
流计算（STREAM）是 TDengine 推荐的实时聚合方案
