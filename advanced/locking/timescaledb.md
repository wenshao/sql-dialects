# TimescaleDB: 锁机制 (Locking)

> 参考资料:
> - [TimescaleDB Documentation - FAQ: Concurrency](https://docs.timescale.com/timescaledb/latest/overview/)
> - [PostgreSQL Documentation - Explicit Locking](https://www.postgresql.org/docs/current/explicit-locking.html)
> - (TimescaleDB 作为 PostgreSQL 扩展，继承 PostgreSQL 锁机制)
> - ============================================================
> - TimescaleDB 继承 PostgreSQL 的完整锁机制
> - ============================================================
> - 行级锁

```sql
SELECT * FROM metrics WHERE time > NOW() - INTERVAL '1 hour'
  AND device_id = 'sensor_1'
FOR UPDATE;

SELECT * FROM metrics WHERE time > NOW() - INTERVAL '1 hour'
FOR SHARE;

SELECT * FROM metrics WHERE time > NOW() - INTERVAL '1 hour'
FOR NO KEY UPDATE;

SELECT * FROM metrics WHERE time > NOW() - INTERVAL '1 hour'
FOR KEY SHARE;
```

## NOWAIT / SKIP LOCKED

```sql
SELECT * FROM metrics WHERE device_id = 'sensor_1'
FOR UPDATE NOWAIT;

SELECT * FROM tasks WHERE status = 'pending'
ORDER BY created_at LIMIT 5
FOR UPDATE SKIP LOCKED;
```

## 表级锁


## 注意: hypertable 上的锁会影响所有 chunk

```sql
LOCK TABLE metrics IN ACCESS SHARE MODE;
LOCK TABLE metrics IN ROW EXCLUSIVE MODE;
LOCK TABLE metrics IN SHARE MODE;
LOCK TABLE metrics IN EXCLUSIVE MODE;
LOCK TABLE metrics IN ACCESS EXCLUSIVE MODE;
```

## Chunk 级别并发


TimescaleDB 将数据分为 chunk（按时间分区）
不同 chunk 的写入可以并发执行
这比普通 PostgreSQL 表有更好的写入并发性
压缩操作获取 chunk 级别的排他锁

```sql
SELECT compress_chunk('_timescaledb_internal._hyper_1_1_chunk');
```

## 查看 chunk 信息

```sql
SELECT * FROM timescaledb_information.chunks
WHERE hypertable_name = 'metrics';
```

## 咨询锁


```sql
SELECT pg_advisory_lock(12345);
SELECT pg_advisory_unlock(12345);
SELECT pg_try_advisory_lock(12345);
SELECT pg_advisory_xact_lock(12345);
```

## 乐观锁


```sql
ALTER TABLE devices ADD COLUMN version INTEGER NOT NULL DEFAULT 1;

UPDATE devices SET config = '{"threshold": 100}', version = version + 1
WHERE id = 'sensor_1' AND version = 5;
```

## 锁监控


```sql
SELECT * FROM pg_locks;

SELECT pid, pg_blocking_pids(pid), query
FROM pg_stat_activity
WHERE cardinality(pg_blocking_pids(pid)) > 0;
```

## 连续聚合与锁


## 刷新连续聚合时会获取相关 chunk 的锁

```sql
CALL refresh_continuous_aggregate('hourly_metrics', '2024-01-01', '2024-01-02');
```

## 注意事项


## 完全继承 PostgreSQL 锁机制

## Chunk 分区提供更好的写入并发性

## 压缩操作需要 chunk 级排他锁

## 连续聚合刷新获取读锁

## 支持所有 PostgreSQL 锁功能（advisory locks 等）
