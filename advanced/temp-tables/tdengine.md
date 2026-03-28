# TDengine: 临时表与临时存储

> 参考资料:
> - [TDengine Documentation](https://docs.taosdata.com/taos-sql/)


## TDengine 不支持 CREATE TEMPORARY TABLE

作为时序数据库，使用子表和 CTE

## 子查询（替代临时表）


```sql
SELECT t.device_id, t.avg_temp
FROM (
    SELECT device_id, AVG(temperature) AS avg_temp
    FROM meters
    WHERE ts > NOW() - 1h
    GROUP BY device_id
) t
WHERE t.avg_temp > 30;
```

## 嵌套查询


```sql
SELECT AVG(total) FROM (
    SELECT device_id, SUM(power) AS total
    FROM meters
    WHERE ts > NOW() - 24h
    INTERVAL(1h)
) sub;
```

## 超级表和子表


## 子表作为数据分组（类似临时视图）

```sql
SELECT * FROM meters WHERE device_id = 'device_001' AND ts > NOW() - 1h;
```

注意：TDengine 不支持临时表
注意：子查询是组织中间结果的主要方式
注意：超级表/子表模型天然提供数据隔离
注意：时序查询通常通过时间窗口和聚合完成
