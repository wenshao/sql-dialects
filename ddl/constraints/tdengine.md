# TDengine: 约束

> 参考资料:
> - [TDengine SQL Reference](https://docs.taosdata.com/taos-sql/)
> - [TDengine Function Reference](https://docs.taosdata.com/taos-sql/function/)
> - TDengine 约束支持非常有限
> - 主要通过数据模型（超级表/子表/标签）来组织数据
> - ============================================================
> - 时间戳列约束（隐式）
> - ============================================================
> - 第一列必须是 TIMESTAMP，这是强制约束

```sql
CREATE STABLE meters (
    ts       TIMESTAMP,              -- 必须是第一列，不可为空
    current  FLOAT,
    voltage  INT
) TAGS (
    location NCHAR(64)
);
```

## 时间戳列隐式 NOT NULL，不能为空值

## NOT NULL（有限支持）


TDengine 中只有第一列（TIMESTAMP）是隐式 NOT NULL
其他列允许 NULL 值，无法显式设置 NOT NULL 约束
插入时可以传 NULL

```sql
INSERT INTO d1001 VALUES (NOW, NULL, 220, 0.31);
```

## 标签约束（通过数据模型实现）


## 标签值在创建子表时指定，确保每个子表有唯一标识

```sql
CREATE TABLE d1001 USING meters TAGS ('Beijing.Chaoyang', 2);
CREATE TABLE d1002 USING meters TAGS ('Beijing.Haidian', 3);
```

## 修改标签值

```sql
ALTER TABLE d1001 SET TAG location = 'Beijing.Dongcheng';
```

## 标签不允许为 NULL（3.0+）

## 唯一性（通过时间戳 + 子表实现）


## 同一子表中不允许重复时间戳

相同时间戳的数据会覆盖旧值（更新语义）

```sql
INSERT INTO d1001 VALUES ('2024-01-15 10:00:00', 10.3, 219, 0.31);
INSERT INTO d1001 VALUES ('2024-01-15 10:00:00', 11.5, 220, 0.32);  -- 覆盖前一条
```

## 数据保留策略（类似过期约束）


## 创建数据库时设置数据保留天数

```sql
CREATE DATABASE power KEEP 365;
```

## 修改保留天数

```sql
ALTER DATABASE power KEEP 730;
```

## 不支持的约束


不支持 PRIMARY KEY（时间戳列隐式为主键）
不支持 UNIQUE（时间戳在同一子表内隐式唯一）
不支持 FOREIGN KEY
不支持 CHECK
不支持 DEFAULT（除时间戳外）
注意：TDengine 通过数据模型而非约束来保证数据完整性
注意：时间戳列是隐式主键，同一子表内时间戳唯一
注意：重复时间戳的数据会覆盖旧值
注意：数据完整性主要在应用层保证
