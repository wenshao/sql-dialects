# TDengine: 复合/复杂类型 (Array, Map, Struct)

> 参考资料:
> - [TDengine Documentation - Data Types](https://docs.tdengine.com/taos-sql/data-type/)
> - [TDengine Documentation - JSON Type](https://docs.tdengine.com/taos-sql/json/)


## TDengine 没有原生 ARRAY / MAP / STRUCT 类型

使用 JSON 标签（Tag）存储复杂结构


## JSON 类型标签（TDengine 3.0+）

注意：JSON 只能用于超级表的标签，不能用于普通列

```sql
CREATE STABLE sensors (
    ts       TIMESTAMP,
    value    DOUBLE,
    status   INT
) TAGS (
    device_info JSON                           -- JSON 标签
);
```

## 创建子表并设置 JSON 标签

```sql
CREATE TABLE sensor_001 USING sensors TAGS (
    '{"type": "temperature", "location": {"building": "A", "floor": 3}, "tags": ["indoor", "hvac"]}'
);
```

## 查询 JSON 标签

```sql
SELECT * FROM sensors WHERE device_info->'type' = 'temperature';
SELECT * FROM sensors WHERE device_info->'location'->'floor' = 3;
```

## JSON 函数

```sql
SELECT device_info->'type' FROM sensors;
SELECT device_info->'tags' FROM sensors;      -- 获取数组
```

## 包含检查

```sql
SELECT * FROM sensors WHERE device_info CONTAINS 'type';
```

## NCHAR 列存储 JSON 字符串


## 普通列只能使用标量类型

如需存储复杂数据，使用 NCHAR/BINARY 存储 JSON 字符串

```sql
CREATE STABLE logs (
    ts       TIMESTAMP,
    msg      NCHAR(1000),                      -- 可存储 JSON 字符串
    level    INT
) TAGS (
    source   NCHAR(100)
);
```

## 注意事项


## 不支持原生 ARRAY / MAP / STRUCT 列类型

## JSON 类型只能用于超级表的标签（Tag），不能用于普通列

## 普通列只支持标量类型

## 时序数据通常不需要复杂类型（每个度量点是标量值）

## 使用超级表 + 标签的架构来组织元数据
