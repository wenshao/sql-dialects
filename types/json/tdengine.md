# TDengine: JSON 类型

> 参考资料:
> - [TDengine SQL Reference](https://docs.taosdata.com/taos-sql/)
> - [TDengine Function Reference](https://docs.taosdata.com/taos-sql/function/)
> - TDengine 3.0+ 支持 JSON 类型（仅用于标签列）
> - 数据列不支持 JSON 类型
> - ============================================================
> - JSON 标签
> - ============================================================
> - 创建带 JSON 标签的超级表

```sql
CREATE STABLE devices (
    ts     TIMESTAMP,
    value  FLOAT
) TAGS (
    info   JSON                           -- JSON 类型标签
);
```

## 创建子表（使用 JSON 标签）

```sql
CREATE TABLE dev001 USING devices TAGS ('{"name": "sensor1", "location": "Beijing", "type": 1}');
CREATE TABLE dev002 USING devices TAGS ('{"name": "sensor2", "location": "Shanghai", "type": 2}');
```

## JSON 查询


## 按 JSON 字段过滤

```sql
SELECT * FROM devices WHERE info->'location' = 'Beijing';
SELECT * FROM devices WHERE info->'type' = 1;
```

## 提取 JSON 字段

```sql
SELECT info->'name', info->'location' FROM devices;
```

## JSON 包含匹配

```sql
SELECT * FROM devices WHERE info CONTAINS 'Beijing';
```

## 修改 JSON 标签


```sql
ALTER TABLE dev001 SET TAG info = '{"name": "sensor1", "location": "Guangzhou", "type": 1}';
```

## 数据列的 JSON 替代方案


## 数据列不支持 JSON，使用 NCHAR 存储 JSON 字符串

```sql
CREATE STABLE logs (
    ts      TIMESTAMP,
    payload NCHAR(1000)                   -- JSON 作为字符串存储
) TAGS (
    source  NCHAR(64)
);

INSERT INTO log001 USING logs TAGS ('app')
    VALUES (NOW, '{"level": "error", "msg": "timeout"}');
```

## 查询时需要手动解析字符串（应用层处理）

## 不支持的 JSON 功能


不支持数据列的 JSON 类型
不支持 JSON 路径表达式（JSONPath）
不支持 JSON 聚合函数
不支持 JSON 修改函数（jsonb_set 等）
不支持 JSON 索引
注意：JSON 仅能用于标签（TAG）列
注意：数据列使用 NCHAR 存储 JSON 字符串
注意：JSON 标签支持基本的字段提取和过滤
注意：复杂 JSON 处理需要在应用层完成
