# TDengine: INSERT

> 参考资料:
> - [TDengine SQL Reference](https://docs.taosdata.com/taos-sql/)
> - [TDengine Function Reference](https://docs.taosdata.com/taos-sql/function/)


## TDengine 的 INSERT 针对时序数据优化

单行插入

```sql
INSERT INTO d1001 VALUES (NOW, 10.3, 219, 0.31);
```

## 指定列插入

```sql
INSERT INTO d1001 (ts, current, voltage) VALUES (NOW, 10.3, 219);
```

## 指定时间戳

```sql
INSERT INTO d1001 VALUES ('2024-01-15 10:00:00.000', 10.3, 219, 0.31);
```

## 多行插入（同一子表）

```sql
INSERT INTO d1001 VALUES
    ('2024-01-15 10:00:00.000', 10.3, 219, 0.31)
    ('2024-01-15 10:01:00.000', 10.5, 220, 0.32)
    ('2024-01-15 10:02:00.000', 10.2, 218, 0.30);
```

## 多表插入（不同子表，一条语句）

```sql
INSERT INTO
    d1001 VALUES ('2024-01-15 10:00:00.000', 10.3, 219, 0.31)
    d1002 VALUES ('2024-01-15 10:00:00.000', 12.6, 220, 0.33)
    d1003 VALUES ('2024-01-15 10:00:00.000', 11.8, 221, 0.29);
```

## 自动建表插入（子表不存在则自动创建）

```sql
INSERT INTO d2001 USING meters TAGS ('Guangzhou.Tianhe', 5)
    VALUES (NOW, 10.3, 219, 0.31);
```

## 自动建表批量插入

```sql
INSERT INTO
    d2001 USING meters TAGS ('Guangzhou.Tianhe', 5) VALUES (NOW, 10.3, 219, 0.31)
    d2002 USING meters TAGS ('Guangzhou.Haizhu', 6) VALUES (NOW, 12.1, 220, 0.33);
```

## 自动建表多行插入

```sql
INSERT INTO d2001 USING meters TAGS ('Guangzhou.Tianhe', 5)
    VALUES ('2024-01-15 10:00:00.000', 10.3, 219, 0.31)
    ('2024-01-15 10:01:00.000', 10.5, 220, 0.32);
```

## NOW 函数（当前时间戳）

```sql
INSERT INTO d1001 VALUES (NOW, 10.3, 219, 0.31);
```

## NOW + 偏移

```sql
INSERT INTO d1001 VALUES (NOW + 1s, 10.3, 219, 0.31);    -- 1 秒后
INSERT INTO d1001 VALUES (NOW - 1m, 10.3, 219, 0.31);    -- 1 分钟前
```

## NULL 值

```sql
INSERT INTO d1001 VALUES (NOW, NULL, 219, NULL);
```

从文件导入（使用 taosdump 或 CSV 导入工具）
taosdump -i /path/to/data
注意：第一列必须是时间戳
注意：多行插入不使用逗号分隔（与标准 SQL 不同）
注意：重复时间戳的数据会覆盖旧值（更新语义）
注意：自动建表（USING ... TAGS）是常用的插入模式
注意：不支持 INSERT INTO ... SELECT
注意：不支持 RETURNING 子句
