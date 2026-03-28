# TDengine: UPSERT

> 参考资料:
> - [TDengine SQL Reference](https://docs.taosdata.com/taos-sql/)
> - [TDengine Function Reference](https://docs.taosdata.com/taos-sql/function/)
> - TDengine 内置 UPSERT 语义
> - 相同时间戳的 INSERT 自动覆盖旧数据
> - ============================================================
> - 隐式 UPSERT（通过时间戳覆盖）
> - ============================================================
> - 第一次插入

```sql
INSERT INTO d1001 VALUES ('2024-01-15 10:00:00.000', 10.3, 219, 0.31);
```

## 相同时间戳再次插入 → 自动覆盖（UPSERT 语义）

```sql
INSERT INTO d1001 VALUES ('2024-01-15 10:00:00.000', 11.5, 220, 0.32);
```

## 批量 UPSERT


## 批量插入/更新

```sql
INSERT INTO d1001 VALUES
    ('2024-01-15 10:00:00.000', 11.5, 220, 0.32)     -- 覆盖已有
    ('2024-01-15 10:01:00.000', 10.5, 220, 0.32)     -- 覆盖已有
    ('2024-01-15 10:03:00.000', 10.8, 219, 0.31);    -- 新插入
```

## 多表 UPSERT

```sql
INSERT INTO
    d1001 VALUES ('2024-01-15 10:00:00.000', 11.5, 220, 0.32)
    d1002 VALUES ('2024-01-15 10:00:00.000', 12.6, 221, 0.33);
```

## 自动建表 + UPSERT


## 如果子表不存在则创建，如果时间戳重复则覆盖

```sql
INSERT INTO d3001 USING meters TAGS ('Wuhan.Wuchang', 7)
    VALUES ('2024-01-15 10:00:00.000', 10.3, 219, 0.31);
```

## 再次插入相同时间戳

```sql
INSERT INTO d3001 USING meters TAGS ('Wuhan.Wuchang', 7)
    VALUES ('2024-01-15 10:00:00.000', 11.5, 220, 0.32);
```

## 标签更新（非数据 UPSERT）


## 标签值通过 ALTER TABLE 修改

```sql
ALTER TABLE d1001 SET TAG location = 'Beijing.Dongcheng';
```

注意：TDengine 的 INSERT 天然具有 UPSERT 语义
注意：相同时间戳的数据自动覆盖旧值
注意：不需要特殊的 UPSERT 语法（ON CONFLICT 等）
注意：不支持部分列更新（覆盖时必须提供所有列）
注意：这种设计非常适合时序数据场景（数据修正/回填）
