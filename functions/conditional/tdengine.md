# TDengine: 条件函数

CASE WHEN（3.0+）

```sql
SELECT ts, current,
    CASE
        WHEN current > 15 THEN 'high'
        WHEN current > 10 THEN 'medium'
        ELSE 'low'
    END AS level
FROM d1001;
```

## 简单 CASE

```sql
SELECT ts,
    CASE voltage
        WHEN 219 THEN 'low'
        WHEN 220 THEN 'normal'
        WHEN 221 THEN 'high'
        ELSE 'unknown'
    END AS v_status
FROM d1001;
```

IF（3.0+）
TDengine 不支持 IF 函数，使用 CASE WHEN 替代
CAST 类型转换

```sql
SELECT CAST(current AS INT) FROM d1001;
SELECT CAST(current AS NCHAR(20)) FROM d1001;
SELECT CAST('10.5' AS FLOAT);
```

## ISNULL（判断空值）

```sql
SELECT ts, ISNULL(current) FROM d1001;
```

## 条件查询

```sql
SELECT * FROM d1001 WHERE current IS NOT NULL;
SELECT * FROM d1001 WHERE current IS NULL;
```

## 不支持的条件函数


不支持 COALESCE
不支持 NULLIF
不支持 GREATEST / LEAST
不支持 IF / IIF
不支持 NVL / NVL2
不支持 DECODE
注意：条件函数支持有限
注意：CASE WHEN 是主要的条件表达式
注意：COALESCE 需要用 CASE WHEN IS NULL 替代
注意：复杂条件逻辑建议在应用层实现
