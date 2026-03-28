# TimescaleDB: 集合操作

> 参考资料:
> - [TimescaleDB Documentation](https://docs.timescale.com/)
> - [PostgreSQL Documentation - UNION, INTERSECT, EXCEPT](https://www.postgresql.org/docs/current/queries-union.html)
> - ============================================================
> - UNION / UNION ALL（继承 PostgreSQL）
> - ============================================================

```sql
SELECT time, device_id, temperature FROM sensor_data_2023
UNION
SELECT time, device_id, temperature FROM sensor_data_2024;

SELECT time, device_id, temperature FROM sensor_data_2023
UNION ALL
SELECT time, device_id, temperature FROM sensor_data_2024;
```

## INTERSECT / INTERSECT ALL

```sql
SELECT device_id FROM sensor_data
INTERSECT
SELECT device_id FROM active_devices;

SELECT device_id FROM sensor_data
INTERSECT ALL
SELECT device_id FROM active_devices;
```

## EXCEPT / EXCEPT ALL

```sql
SELECT device_id FROM sensor_data
EXCEPT
SELECT device_id FROM decommissioned_devices;

SELECT device_id FROM sensor_data
EXCEPT ALL
SELECT device_id FROM decommissioned_devices;
```

## 时序数据常见用法：合并不同时间范围的数据

## 合并多个 hypertable 的数据

```sql
SELECT time, value FROM metrics_hot
WHERE time > NOW() - INTERVAL '7 days'
UNION ALL
SELECT time, value FROM metrics_cold
WHERE time BETWEEN '2024-01-01' AND '2024-06-30'
ORDER BY time;
```

## ORDER BY 与集合操作

```sql
SELECT time, device_id, temperature FROM sensor_data_2023
UNION ALL
SELECT time, device_id, temperature FROM sensor_data_2024
ORDER BY time DESC;
```

## LIMIT 与集合操作

```sql
SELECT time, value FROM metrics_a
UNION ALL
SELECT time, value FROM metrics_b
ORDER BY time DESC
LIMIT 100;
```

## 注意事项

TimescaleDB 完全继承 PostgreSQL 的集合操作能力
支持所有 ALL 变体
跨 hypertable 的集合操作可能涉及大量 chunk 扫描
建议对时序数据使用 WHERE 时间条件限制范围后再做集合操作
