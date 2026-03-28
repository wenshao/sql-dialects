# TDengine: CTE（公共表表达式）

> 参考资料:
> - [TDengine SQL Reference](https://docs.taosdata.com/taos-sql/)
> - [TDengine Function Reference](https://docs.taosdata.com/taos-sql/function/)
> - TDengine 不支持 CTE（WITH 子句）
> - 使用子查询和多次查询替代
> - ============================================================
> - 子查询替代 CTE
> - ============================================================
> - CTE 方式（不支持）：
> - WITH hourly AS (
> - SELECT _WSTART AS bucket, AVG(current) AS avg_current FROM d1001 INTERVAL(1h)
> - )
> - SELECT * FROM hourly WHERE avg_current > 10;
> - 子查询替代：

```sql
SELECT * FROM (
    SELECT _WSTART AS bucket, AVG(current) AS avg_current
    FROM d1001
    INTERVAL(1h)
) WHERE avg_current > 10;
```

## 多步查询替代 CTE 链


CTE 链方式（不支持）：
WITH step1 AS (...), step2 AS (... FROM step1) SELECT * FROM step2;
替代方案 1：嵌套子查询（仅支持一层）

```sql
SELECT AVG(avg_current) FROM (
    SELECT AVG(current) AS avg_current
    FROM meters
    WHERE location = 'Beijing.Chaoyang'
    INTERVAL(1h)
);
```

替代方案 2：在应用层分步执行
步骤 1：查询小时聚合
SELECT _WSTART, AVG(current) AS avg_current FROM d1001 INTERVAL(1h);
步骤 2：在应用层过滤和处理结果

## 递归查询替代（不支持）


## TDengine 不支持递归 CTE

层级结构查询需要在应用层实现

## 常用查询模式（不需要 CTE）


## INTERVAL 已经内置了时间序列降采样

```sql
SELECT _WSTART, AVG(current), MAX(voltage)
FROM meters
WHERE ts >= '2024-01-01'
INTERVAL(1h);
```

## GROUP BY 标签已经内置了分组聚合

```sql
SELECT location, AVG(current), COUNT(*)
FROM meters
WHERE ts >= '2024-01-01'
GROUP BY location;
```

## 嵌套降采样 + 过滤

```sql
SELECT * FROM (
    SELECT _WSTART AS ts, location, AVG(current) AS avg_val
    FROM meters
    INTERVAL(1h)
    GROUP BY location
) WHERE avg_val > 10
ORDER BY ts;
```

注意：TDengine 不支持 CTE（WITH 子句）
注意：使用子查询替代（仅支持一层嵌套）
注意：不支持递归查询
注意：TDengine 内置的 INTERVAL/GROUP BY 已覆盖大部分时序分析需求
注意：复杂分析建议在应用层实现
