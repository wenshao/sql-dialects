# TimescaleDB: 约束

> 参考资料:
> - [TimescaleDB API Reference](https://docs.timescale.com/api/latest/)
> - [TimescaleDB Hyperfunctions](https://docs.timescale.com/api/latest/hyperfunctions/)


## TimescaleDB 继承 PostgreSQL 全部约束功能

超级表（hypertable）对约束有额外限制

## PRIMARY KEY（必须包含时间列）


```sql
CREATE TABLE sensor_data (
    time        TIMESTAMPTZ NOT NULL,
    sensor_id   INT NOT NULL,
    value       DOUBLE PRECISION,
    PRIMARY KEY (time, sensor_id)
);
SELECT create_hypertable('sensor_data', 'time');
```

## 注意：超级表的主键必须包含分区列（时间列）

## UNIQUE（必须包含时间列）


```sql
CREATE TABLE readings (
    time        TIMESTAMPTZ NOT NULL,
    device_id   INT NOT NULL,
    value       DOUBLE PRECISION,
    UNIQUE (time, device_id)
);
SELECT create_hypertable('readings', 'time');

ALTER TABLE readings ADD CONSTRAINT uq_reading UNIQUE (time, device_id);
```

## NOT NULL


```sql
CREATE TABLE metrics (
    time        TIMESTAMPTZ NOT NULL,    -- 时间列建议 NOT NULL
    device_id   INT NOT NULL,
    cpu_usage   DOUBLE PRECISION NOT NULL
);

ALTER TABLE metrics ALTER COLUMN cpu_usage SET NOT NULL;
ALTER TABLE metrics ALTER COLUMN cpu_usage DROP NOT NULL;
```

## CHECK


```sql
CREATE TABLE temperatures (
    time        TIMESTAMPTZ NOT NULL,
    sensor_id   INT NOT NULL,
    temp_c      DOUBLE PRECISION CHECK (temp_c BETWEEN -273.15 AND 1000)
);

ALTER TABLE temperatures ADD CONSTRAINT chk_temp
    CHECK (temp_c BETWEEN -273.15 AND 1000);
ALTER TABLE temperatures DROP CONSTRAINT chk_temp;
```

## FOREIGN KEY（维度表关联）


## 维度表（普通表）

```sql
CREATE TABLE devices (
    id      SERIAL PRIMARY KEY,
    name    TEXT NOT NULL
);
```

## 超级表引用维度表

```sql
CREATE TABLE device_data (
    time       TIMESTAMPTZ NOT NULL,
    device_id  INT NOT NULL REFERENCES devices(id),
    value      DOUBLE PRECISION
);
SELECT create_hypertable('device_data', 'time');
```

## DEFAULT


```sql
CREATE TABLE events (
    time       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    type       TEXT NOT NULL DEFAULT 'unknown',
    data       JSONB DEFAULT '{}'::JSONB
);

ALTER TABLE events ALTER COLUMN type SET DEFAULT 'info';
ALTER TABLE events ALTER COLUMN type DROP DEFAULT;
```

## EXCLUSION（排他约束）


## 超级表不支持排他约束

普通表支持

```sql
CREATE TABLE reservations (
    room_id    INT,
    during     TSTZRANGE,
    EXCLUDE USING GIST (room_id WITH =, during WITH &&)
);
```

注意：超级表的 UNIQUE 和 PRIMARY KEY 必须包含所有分区列
注意：超级表不支持 EXCLUSION 约束
注意：CHECK、NOT NULL、DEFAULT、FOREIGN KEY 正常工作
注意：约束在每个 chunk 上独立执行
