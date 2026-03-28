# TimescaleDB: Error Handling

> 参考资料:
> - [TimescaleDB Documentation](https://docs.timescale.com/)
> - [PostgreSQL PL/pgSQL Error Handling](https://www.postgresql.org/docs/current/plpgsql-control-structures.html#PLPGSQL-ERROR-TRAPPING)
> - ============================================================
> - EXCEPTION WHEN (完全兼容 PostgreSQL)
> - ============================================================

```sql
CREATE OR REPLACE FUNCTION safe_insert_reading(
    p_time TIMESTAMPTZ, p_device TEXT, p_value DOUBLE PRECISION
) RETURNS TEXT AS $$
BEGIN
    INSERT INTO sensor_data(time, device_id, value)
    VALUES(p_time, p_device, p_value);
    RETURN 'Success';
EXCEPTION
    WHEN unique_violation THEN
        RETURN 'Duplicate reading ignored';
    WHEN check_violation THEN
        RETURN 'Invalid value';
    WHEN OTHERS THEN
        RETURN 'Error: ' || SQLERRM;
END;
$$ LANGUAGE plpgsql;
```

## RAISE

```sql
CREATE OR REPLACE FUNCTION validate_reading(p_value DOUBLE PRECISION)
RETURNS VOID AS $$
BEGIN
    IF p_value < -273.15 THEN
        RAISE EXCEPTION 'Temperature below absolute zero: %', p_value
            USING ERRCODE = '22003';
    END IF;
END;
$$ LANGUAGE plpgsql;
```

注意：TimescaleDB 完全兼容 PostgreSQL 错误处理
注意：支持 EXCEPTION WHEN, RAISE, GET STACKED DIAGNOSTICS
限制：与 PostgreSQL 相同
