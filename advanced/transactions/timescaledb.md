# TimescaleDB: 事务

TimescaleDB 继承 PostgreSQL 全部事务功能
基本事务

```sql
BEGIN;
INSERT INTO sensor_data (time, sensor_id, temperature) VALUES (NOW(), 1, 25.0);
INSERT INTO sensor_data (time, sensor_id, temperature) VALUES (NOW(), 2, 30.0);
COMMIT;
```

## 回滚

```sql
BEGIN;
DELETE FROM sensor_data WHERE sensor_id = 1;
ROLLBACK;
```

## 保存点

```sql
BEGIN;
INSERT INTO sensor_data VALUES (NOW(), 1, 25.0);
SAVEPOINT sp1;
INSERT INTO sensor_data VALUES (NOW(), 2, 30.0);
ROLLBACK TO SAVEPOINT sp1;
COMMIT;
```

## 隔离级别

```sql
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;        -- 默认
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
```

## 只读事务

```sql
SET TRANSACTION READ ONLY;
BEGIN READ ONLY;
```

## 锁

```sql
SELECT * FROM devices WHERE id = 1 FOR UPDATE;
SELECT * FROM devices WHERE id = 1 FOR SHARE;
SELECT * FROM devices WHERE id = 1 FOR UPDATE NOWAIT;
SELECT * FROM devices WHERE id = 1 FOR UPDATE SKIP LOCKED;
```

## 查看事务状态

```sql
SELECT txid_current();
```

## 咨询锁

```sql
SELECT pg_advisory_lock(1);
SELECT pg_advisory_unlock(1);
```

## TimescaleDB 特有注意事项


压缩的 chunk 在事务中不可修改
需要先解压才能在事务中操作
SELECT decompress_chunk(c) FROM show_chunks('sensor_data', older_than => INTERVAL '7 days') c;
DDL 操作（create_hypertable 等）会获取排他锁
大表的 DDL 操作需注意锁等待
注意：完全兼容 PostgreSQL 事务语法
注意：压缩 chunk 不能在事务中修改
注意：默认隔离级别为 READ COMMITTED
注意：支持 SAVEPOINT、FOR UPDATE、咨询锁
