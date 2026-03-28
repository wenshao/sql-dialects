# ksqlDB: 累计/滚动合计（Running Total）

> 参考资料:
> - [ksqlDB Reference - Aggregate Functions](https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/aggregate-functions/)
> - ============================================================
> - 示例数据上下文
> - ============================================================
> - 假设 STREAM:
> - transactions_stream(txn_id INT KEY, account_id INT, amount DOUBLE, txn_time BIGINT)
> - ============================================================
> - 注意：ksqlDB 不支持传统窗口函数（SUM OVER）
> - ============================================================
> - 以下是 ksqlDB 中可实现的近似方案：
> - ============================================================
> - 1. 使用窗口聚合模拟累计
> - ============================================================
> - TUMBLING 窗口内的累计

```sql
SELECT account_id,
       SUM(amount) AS window_total,
       COUNT(*) AS window_count,
       WINDOWSTART AS window_start,
       WINDOWEND AS window_end
FROM transactions_stream
WINDOW TUMBLING (SIZE 1 HOUR)
GROUP BY account_id
EMIT CHANGES;
```

## 持续聚合（全局累计）


```sql
CREATE TABLE account_running_totals AS
SELECT account_id,
       SUM(amount) AS total_amount,
       COUNT(*) AS total_count,
       AVG(amount) AS avg_amount
FROM transactions_stream
GROUP BY account_id
EMIT CHANGES;
```

## 查询当前状态

```sql
SELECT * FROM account_running_totals WHERE account_id = 1001;
```

## 性能考量


ksqlDB 不支持 SUM OVER / ROW_NUMBER 等窗口函数
使用窗口聚合和持续聚合实现近似累计
建议：需要精确累计时，导入到批处理引擎
