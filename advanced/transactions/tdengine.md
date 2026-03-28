# TDengine: 事务

TDengine 不支持传统的 ACID 事务
每条 SQL 语句是原子的，但不支持多语句事务
============================================================
单语句原子性
============================================================
单条 INSERT 是原子的

```sql
INSERT INTO d1001 VALUES (NOW, 10.3, 219, 0.31);
```

## 多行插入也是原子的（全部成功或全部失败）

```sql
INSERT INTO d1001 VALUES
    ('2024-01-15 10:00:00.000', 10.3, 219, 0.31)
    ('2024-01-15 10:01:00.000', 10.5, 220, 0.32);
```

## 多表插入是原子的

```sql
INSERT INTO
    d1001 VALUES (NOW, 10.3, 219, 0.31)
    d1002 VALUES (NOW, 12.6, 220, 0.33);
```

## 不支持的事务操作


不支持 BEGIN / COMMIT / ROLLBACK
不支持 SAVEPOINT
不支持事务隔离级别
不支持 SELECT ... FOR UPDATE
不支持 LOCK TABLE

## 数据一致性保证


写入保证：
1. 同一子表的写入按时间戳顺序
2. WAL（Write-Ahead Log）保证持久性
3. 副本同步保证高可用
读取一致性：
1. 查询结果反映查询开始时的数据状态
2. 不存在脏读
3. 但可能存在非重复读（no repeatable read）
WAL 配置

```sql
CREATE DATABASE power WAL_LEVEL 2;            -- WAL 级别（0: 无, 1: 写WAL, 2: 写WAL+fsync）
CREATE DATABASE power WAL_FSYNC_PERIOD 3000;  -- fsync 周期（毫秒）
```

注意：TDengine 不支持多语句事务
注意：单条 SQL 是原子的
注意：数据一致性通过 WAL 保证
注意：时序数据场景通常不需要复杂事务
注意：跨表一致性需要在应用层保证
