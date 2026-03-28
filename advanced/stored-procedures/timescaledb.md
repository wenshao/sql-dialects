# TimescaleDB: 存储过程

TimescaleDB 继承 PostgreSQL 的存储过程和函数
创建函数

```sql
CREATE OR REPLACE FUNCTION get_latest_reading(p_sensor_id INT)
RETURNS TABLE(time TIMESTAMPTZ, temperature DOUBLE PRECISION) AS $$
    SELECT time, temperature
    FROM sensor_data
    WHERE sensor_id = p_sensor_id
    ORDER BY time DESC
    LIMIT 1;
$$ LANGUAGE SQL;

SELECT * FROM get_latest_reading(1);
```

## PL/pgSQL 函数

```sql
CREATE OR REPLACE FUNCTION get_avg_temp(p_sensor_id INT, p_hours INT DEFAULT 24)
RETURNS NUMERIC AS $$
DECLARE
    v_avg NUMERIC;
BEGIN
    SELECT AVG(temperature) INTO v_avg
    FROM sensor_data
    WHERE sensor_id = p_sensor_id
      AND time > NOW() - (p_hours || ' hours')::INTERVAL;
    RETURN COALESCE(v_avg, 0);
END;
$$ LANGUAGE plpgsql;
```

## 存储过程（PostgreSQL 11+）

```sql
CREATE OR REPLACE PROCEDURE archive_old_data(p_days INT)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO sensor_data_archive
    SELECT * FROM sensor_data WHERE time < NOW() - (p_days || ' days')::INTERVAL;

    SELECT drop_chunks('sensor_data', INTERVAL (p_days || ' days'));

    COMMIT;
END;
$$;

CALL archive_old_data(90);
```

## 带异常处理

```sql
CREATE OR REPLACE FUNCTION safe_insert_reading(
    p_time TIMESTAMPTZ, p_sensor_id INT, p_temp DOUBLE PRECISION
) RETURNS BOOLEAN AS $$
BEGIN
    INSERT INTO sensor_data (time, sensor_id, temperature)
    VALUES (p_time, p_sensor_id, p_temp);
    RETURN TRUE;
EXCEPTION
    WHEN unique_violation THEN
        RETURN FALSE;
    WHEN OTHERS THEN
        RAISE WARNING 'Error: %', SQLERRM;
        RETURN FALSE;
END;
$$ LANGUAGE plpgsql;
```

## 删除

```sql
DROP FUNCTION IF EXISTS get_latest_reading(INT);
DROP PROCEDURE IF EXISTS archive_old_data(INT);
```

## TimescaleDB 特有：用户定义操作（User-Defined Actions）

```sql
CREATE OR REPLACE FUNCTION custom_retention(job_id INT, config JSONB)
RETURNS VOID AS $$
BEGIN
    PERFORM drop_chunks('sensor_data', INTERVAL '90 days');
END;
$$ LANGUAGE plpgsql;

SELECT add_job('custom_retention', '1 day');
```

注意：完全兼容 PostgreSQL 存储过程和函数
注意：用户定义操作（add_job）是 TimescaleDB 特有的定时任务
注意：支持 PL/pgSQL、SQL、PL/Python 等多种语言
