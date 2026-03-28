# TimescaleDB: 复合/复杂类型 (Array, Map, Struct)

> 参考资料:
> - [TimescaleDB Documentation - Data Types](https://docs.timescale.com/timescaledb/latest/overview/)
> - [PostgreSQL Documentation - Arrays](https://www.postgresql.org/docs/current/arrays.html)

## (TimescaleDB 完全继承 PostgreSQL 的数据类型)

## TimescaleDB 完全继承 PostgreSQL 的复杂类型


## ARRAY

```sql
CREATE TABLE sensor_data (
    time       TIMESTAMPTZ NOT NULL,
    device_id  TEXT NOT NULL,
    readings   DOUBLE PRECISION[],             -- 多个传感器读数
    tags       TEXT[]
);

SELECT create_hypertable('sensor_data', 'time');

INSERT INTO sensor_data VALUES
    (NOW(), 'sensor_1', ARRAY[23.5, 45.2, 67.8], ARRAY['temp', 'humidity', 'pressure']);
```

## 数组操作

```sql
SELECT readings[1] FROM sensor_data;
SELECT ARRAY_LENGTH(readings, 1) FROM sensor_data;
SELECT * FROM sensor_data WHERE tags @> ARRAY['temp'];
SELECT device_id, UNNEST(readings) AS reading FROM sensor_data;
```

## 复合类型

```sql
CREATE TYPE geo_point AS (lat DOUBLE PRECISION, lng DOUBLE PRECISION);

CREATE TABLE locations (
    time      TIMESTAMPTZ NOT NULL,
    device_id TEXT NOT NULL,
    position  geo_point
);

SELECT create_hypertable('locations', 'time');
INSERT INTO locations VALUES (NOW(), 'device_1', ROW(37.7749, -122.4194));
SELECT (position).lat, (position).lng FROM locations;
```

## JSONB

```sql
CREATE TABLE events (
    time TIMESTAMPTZ NOT NULL,
    data JSONB
);

SELECT create_hypertable('events', 'time');
INSERT INTO events VALUES (NOW(), '{"type": "click", "tags": ["web"]}');
SELECT data->'tags' FROM events;
```

## GIN 索引

```sql
CREATE INDEX idx_tags ON sensor_data USING GIN (tags);
CREATE INDEX idx_data ON events USING GIN (data);
```

## 注意事项


## 完全继承 PostgreSQL 的 ARRAY / 复合类型 / JSONB / hstore

## 复杂类型列可以在 hypertable 中使用

## GIN 索引在 hypertable 上正常工作

## 连续聚合中可以使用 ARRAY_AGG
