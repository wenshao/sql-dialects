# TDengine: 集合操作（有限支持）

> 参考资料:
> - [TDengine Documentation - SELECT](https://docs.tdengine.com/reference/sql/select/)
> - [TDengine Documentation - SQL Reference](https://docs.tdengine.com/reference/sql/)


## UNION / UNION ALL（3.0+）

```sql
SELECT ts, value FROM meters.d1001
UNION ALL
SELECT ts, value FROM meters.d1002;

SELECT ts, value FROM meters.d1001
UNION
SELECT ts, value FROM meters.d1002;
```

## INTERSECT / EXCEPT

注意：TDengine 不支持 INTERSECT 和 EXCEPT
替代方案：使用 JOIN 或子查询
模拟 INTERSECT

```sql
SELECT DISTINCT a.device_id FROM (
    SELECT device_id FROM sensor_data WHERE temperature > 30
) a INNER JOIN (
    SELECT device_id FROM sensor_data WHERE humidity > 80
) b ON a.device_id = b.device_id;
```

## 模拟 EXCEPT

```sql
SELECT a.device_id FROM (
    SELECT DISTINCT device_id FROM sensor_data
) a LEFT JOIN (
    SELECT DISTINCT device_id FROM decommissioned_devices
) b ON a.device_id = b.device_id
WHERE b.device_id IS NULL;
```

## ORDER BY 与集合操作

```sql
SELECT ts, value FROM meters.d1001
UNION ALL
SELECT ts, value FROM meters.d1002
ORDER BY ts DESC;
```

## LIMIT 与集合操作

```sql
SELECT ts, value FROM meters.d1001
UNION ALL
SELECT ts, value FROM meters.d1002
ORDER BY ts DESC
LIMIT 100;
```

## LIMIT + OFFSET

```sql
SELECT ts, value FROM meters.d1001
UNION ALL
SELECT ts, value FROM meters.d1002
ORDER BY ts DESC
LIMIT 100 OFFSET 200;
```

## 注意事项

TDengine 3.0 开始支持 UNION / UNION ALL
不支持 INTERSECT 和 EXCEPT
主要用于合并多个子表或超级表的查询结果
时序数据场景下，UNION ALL 用于跨时间分区查询
每个子查询需要查询相同数量的列
