# TimescaleDB: JSON 展平为关系行 (JSON Flatten)

> 参考资料:
> - [TimescaleDB Documentation](https://docs.timescale.com/)
> - [PostgreSQL Documentation - JSON Functions（TimescaleDB 完全兼容）](https://www.postgresql.org/docs/current/functions-json.html)
> - [TimescaleDB Hypertable 概念](https://docs.timescale.com/use-timescale/latest/hypertables/)


## 示例数据（时序场景：传感器 JSON 事件）


```sql
CREATE TABLE sensor_events (
    ts      TIMESTAMPTZ  NOT NULL,
    device  TEXT          NOT NULL,
    data    JSONB         NOT NULL
);
SELECT create_hypertable('sensor_events', 'ts');

INSERT INTO sensor_events (ts, device, data) VALUES
    ('2024-01-01 08:00:00+00', 'sensor-1',
     '{"sensor_id": "T-001", "temperature": 22.5,
       "readings": [{"type": "temp", "value": 22.5}, {"type": "humidity", "value": 45.0}]}'),
    ('2024-01-01 08:05:00+00', 'sensor-2',
     '{"sensor_id": "T-002", "temperature": 19.8,
       "readings": [{"type": "temp", "value": 19.8}, {"type": "humidity", "value": 62.3},
                     {"type": "pressure", "value": 1013.2}]}'),
    ('2024-01-01 08:10:00+00', 'sensor-1',
     '{"sensor_id": "T-001", "temperature": 23.1,
       "readings": [{"type": "temp", "value": 23.1}, {"type": "humidity", "value": 44.7}]}');
```

## 提取 JSON 字段为列


```sql
SELECT ts, device,
       data->>'sensor_id'                        AS sensor_id,
       (data->>'temperature')::DOUBLE PRECISION  AS temperature
FROM   sensor_events
ORDER  BY ts;
```

设计分析: TimescaleDB 继承了 PostgreSQL 完整的 JSONB 功能
>> 运算符提取文本值，:: 进行类型转换
JSONB 存储为二进制格式，查询时不需要重新解析

## jsonb_array_elements 展开嵌套数组


```sql
SELECT ts, device,
       reading->>'type'                  AS reading_type,
       (reading->>'value')::NUMERIC      AS reading_value
FROM   sensor_events,
       LATERAL jsonb_array_elements(data->'readings') AS reading
ORDER  BY ts, reading_type;
```

设计分析: LATERAL + jsonb_array_elements
jsonb_array_elements 是 Set-Returning Function（SRF），返回多行
LATERAL 允许它引用外表列（data->'readings'）
这是 TimescaleDB/PostgreSQL 展开 JSON 数组的标准模式

## jsonb_to_recordset 直接转为关系记录


```sql
SELECT ts, device, r.*
FROM   sensor_events,
       LATERAL jsonb_to_recordset(data->'readings')
              AS r(type TEXT, value NUMERIC)
ORDER  BY ts;
```

设计分析: jsonb_to_recordset vs jsonb_array_elements
jsonb_to_recordset 直接定义列名和类型，一步到位
jsonb_array_elements 需要逐字段 ->> 提取，但更灵活
推荐在列结构固定时使用 jsonb_to_recordset

## 时间范围查询 + JSON 展平（TimescaleDB 特有优势）


```sql
SELECT time_bucket('5 minutes', ts) AS bucket, device,
       AVG((reading->>'value')::NUMERIC) AS avg_value
FROM   sensor_events,
       LATERAL jsonb_array_elements(data->'readings') AS reading
WHERE  ts >= '2024-01-01 08:00:00+00'
  AND  ts <  '2024-01-01 09:00:00+00'
  AND  reading->>'type' = 'temp'
GROUP  BY bucket, device
ORDER  BY bucket, device;
```

## time_bucket 是 TimescaleDB 的核心函数，将时间戳按任意间隔分组

与 JSON 展平结合，可以实现对嵌套指标的时间聚合

## jsonb_each 展开对象键值对


```sql
SELECT ts, device, kv.key, kv.value
FROM   sensor_events,
       LATERAL jsonb_each(data - 'readings') AS kv
ORDER  BY ts, kv.key;
```

## 排除 readings 数组后，展开其余键值对

## 连续聚合 + JSON 提取（TimescaleDB 高级用法）


CREATE MATERIALIZED VIEW sensor_hourly
WITH (timescaledb.continuous) AS
SELECT time_bucket('1 hour', ts) AS bucket,
device,
(data->>'temperature')::DOUBLE PRECISION AS temp,
AVG((data->>'temperature')::DOUBLE PRECISION) AS avg_temp
FROM sensor_events
GROUP BY bucket, device;
连续聚合自动刷新，适合实时仪表盘场景

## 横向对比与对引擎开发者的启示


## TimescaleDB JSON 处理能力:

完全继承 PostgreSQL 的 JSONB 生态
所有 PostgreSQL JSON 函数（->>, jsonb_array_elements 等）均可使用
额外优势: time_bucket + 连续聚合 + JSON 组合
2. 时序数据中的 JSON 展平模式:
(a) 传感器数据: JSON 字段 + JSON 数组展平 + 时间聚合
(b) 日志分析:   JSON 字段提取 + 时间范围过滤
(c) IoT 设备:   JSON 标签 + JSON 指标数组展平
对引擎开发者:
时序数据库若支持 JSON，应关注 JSON + 时间聚合的组合场景
LATERAL + SRF 的组合式设计在时序场景中同样有效
连续聚合（Materialized Continuous Aggregate）是时序数据库独有的优化
