# TDengine: UPDATE

> 参考资料:
> - [TDengine SQL Reference](https://docs.taosdata.com/taos-sql/)
> - [TDengine Function Reference](https://docs.taosdata.com/taos-sql/function/)


## TDengine 没有传统的 UPDATE 语句

通过插入相同时间戳的数据来实现更新（覆盖语义）

## 覆盖更新（通过重复时间戳 INSERT）


## 原始数据

```sql
INSERT INTO d1001 VALUES ('2024-01-15 10:00:00.000', 10.3, 219, 0.31);
```

## 更新：插入相同时间戳的新数据（覆盖旧值）

```sql
INSERT INTO d1001 VALUES ('2024-01-15 10:00:00.000', 11.5, 220, 0.32);
```

## 部分列更新：需要先读取旧值，然后整行覆盖

TDengine 不支持只更新某一列

## 修改标签值（唯一的"UPDATE"操作）


## 标签（TAG）值可以直接修改

```sql
ALTER TABLE d1001 SET TAG location = 'Beijing.Dongcheng';
ALTER TABLE d1001 SET TAG group_id = 5;
```

## 批量覆盖更新


## 批量重新插入覆盖

```sql
INSERT INTO d1001 VALUES
    ('2024-01-15 10:00:00.000', 11.5, 220, 0.32)
    ('2024-01-15 10:01:00.000', 11.8, 221, 0.33)
    ('2024-01-15 10:02:00.000', 12.0, 222, 0.34);
```

## UPDATE 的替代模式


需要更新的场景：
1. 数据修正：重新插入正确的时间戳和值
2. 标签更新：使用 ALTER TABLE SET TAG
3. 数据回填：插入历史时间戳的数据
回填示例

```sql
INSERT INTO d1001 VALUES
    ('2024-01-10 08:00:00.000', 9.5, 218, 0.30)
    ('2024-01-10 08:01:00.000', 9.6, 218, 0.31);
```

注意：TDengine 没有 UPDATE 语句
注意：相同时间戳的 INSERT 会覆盖旧数据（更新语义）
注意：不能只更新某一列，必须整行覆盖
注意：标签值使用 ALTER TABLE SET TAG 修改
注意：这种设计符合时序数据"一次写入"的特点
