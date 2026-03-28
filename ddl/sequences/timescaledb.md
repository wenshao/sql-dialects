# TimescaleDB: Sequences & Auto-Increment

> 参考资料:
> - [PostgreSQL Documentation - CREATE SEQUENCE](https://www.postgresql.org/docs/current/sql-createsequence.html)
> - [TimescaleDB Documentation - CREATE TABLE / Hypertable](https://docs.timescale.com/api/latest/hypertable/create_hypertable/)


## TimescaleDB 完全兼容 PostgreSQL 的序列功能


## SEQUENCE

```sql
CREATE SEQUENCE sensor_id_seq START WITH 1 INCREMENT BY 1 CACHE 20;

SELECT nextval('sensor_id_seq');
SELECT currval('sensor_id_seq');
SELECT setval('sensor_id_seq', 1000);

ALTER SEQUENCE sensor_id_seq RESTART WITH 5000;

DROP SEQUENCE sensor_id_seq;
```

## SERIAL / BIGSERIAL

```sql
CREATE TABLE devices (
    id       BIGSERIAL PRIMARY KEY,
    name     VARCHAR(64) NOT NULL,
    location VARCHAR(255)
);
```

## GENERATED AS IDENTITY（推荐）

```sql
CREATE TABLE users (
    id       BIGINT GENERATED ALWAYS AS IDENTITY,
    username VARCHAR(64) NOT NULL,
    email    VARCHAR(255) NOT NULL
);
```

## 超表 (Hypertable) 中的序列

时序数据通常以时间戳为主要标识

```sql
CREATE TABLE sensor_data (
    ts          TIMESTAMPTZ NOT NULL,
    device_id   BIGINT NOT NULL,
    temperature DOUBLE PRECISION,
    humidity    DOUBLE PRECISION
);

SELECT create_hypertable('sensor_data', 'ts');
```

## 如果超表需要唯一 ID

```sql
CREATE TABLE events (
    id       BIGINT GENERATED ALWAYS AS IDENTITY,
    ts       TIMESTAMPTZ NOT NULL,
    data     JSONB
);
SELECT create_hypertable('events', 'ts');
```

## UUID 生成

```sql
SELECT gen_random_uuid();                    -- PostgreSQL 13+ 内置

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
SELECT uuid_generate_v4();
```

## 序列 vs 自增 权衡

## 时序数据通常以时间戳为主键，不需要自增 ID

## GENERATED AS IDENTITY：需要数值 ID 时的推荐方式

## SERIAL/BIGSERIAL：兼容旧 PostgreSQL 代码

## UUID：适合分布式场景

## TimescaleDB 完全继承 PostgreSQL 的序列功能
