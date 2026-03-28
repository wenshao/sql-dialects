# TiDB: ALTER TABLE

> 参考资料:
> - [TiDB ALTER TABLE](https://docs.pingcap.com/tidb/stable/sql-statement-alter-table)
> - [TiDB Online DDL](https://docs.pingcap.com/tidb/stable/ddl-introduction)
> - [TiDB Multi-Schema Change](https://docs.pingcap.com/tidb/stable/sql-statement-alter-table)

**引擎定位**: 分布式 HTAP 数据库，兼容 MySQL 协议。基于 TiKV 行存 + TiFlash 列存，Raft 共识。

## 基本语法（MySQL 兼容）

```sql
ALTER TABLE users ADD COLUMN phone VARCHAR(20) AFTER email;
ALTER TABLE users MODIFY COLUMN phone VARCHAR(32) NOT NULL;
ALTER TABLE users CHANGE COLUMN phone mobile VARCHAR(32);
ALTER TABLE users DROP COLUMN phone;
ALTER TABLE users RENAME COLUMN phone TO mobile;

```

## 语法设计分析（对 SQL 引擎开发者）


### TiDB Online DDL: 分布式环境下的 Schema 变更

TiDB 所有 ALTER TABLE 操作默认都是 Online（非阻塞）的。
但实现机制与 MySQL 的 Online DDL 完全不同:

MySQL Online DDL:  COPY / INPLACE / INSTANT 三种算法
TiDB Online DDL:   基于 Google F1 论文的异步 Schema 变更协议
  核心流程: absent → delete-only → write-only → reorganization → public
  每个状态转换通过 PD 协调所有 TiDB Server 的 schema lease
  所有 TiDB 节点在同一时刻看到一致的 schema 版本

**设计 trade-off:**
  优点: 不锁表，不阻塞 DML，适合分布式环境
  缺点: DDL 速度比 MySQL INSTANT 慢（需要多轮状态转换），
        大表 ADD INDEX 可能需要数小时（需要回填数据）

**对比:**
  MySQL:      ALGORITHM=INSTANT（8.0.12+，ADD COLUMN 瞬间完成）
  PostgreSQL: ADD COLUMN + DEFAULT 在 11+ 是即时的
  CockroachDB: 也是异步 Schema 变更（类似 F1 协议）
  OceanBase:  Online DDL + LSM-Tree Schema Evolution
  Spanner:    DDL 是长事务 schema update（后台滚动执行）

**对引擎开发者的启示:**
  分布式引擎的 DDL 是最难的问题之一。核心挑战是:
  多个节点在不同时刻执行不同 schema 版本的 DML，如何保证一致性？
  F1 协议用多阶段状态机解决了这个问题，但代价是 DDL 变慢。

Multi-schema change（6.2+）: 一条语句执行多个 DDL 操作
```sql
ALTER TABLE users
    ADD COLUMN city VARCHAR(64),
    ADD COLUMN country VARCHAR(64),
    DROP COLUMN bio;
```

**对比:** MySQL 8.0 也支持，但 TiDB 的实现更高效（一轮状态转换）

### ALGORITHM/LOCK 子句: 解析但忽略

TiDB 解析 MySQL 的 ALGORITHM 和 LOCK 子句但不执行:
  ALGORITHM=INSTANT/INPLACE/COPY: 忽略（TiDB 总是用自己的 Online DDL）
  LOCK=NONE/SHARED/EXCLUSIVE: 忽略（TiDB DDL 总是非阻塞的）
这是 MySQL 兼容性的常见模式: 接受语法 → 不执行 → 避免迁移报错

## TiDB 特有的 ALTER TABLE 操作


### 设置 TiFlash 副本（HTAP 核心操作）

```sql
ALTER TABLE users SET TIFLASH REPLICA 1;   -- 添加 1 个 TiFlash 列存副本
ALTER TABLE users SET TIFLASH REPLICA 0;   -- 移除 TiFlash 副本
```

副本通过 Raft Learner 异步同步，通常 < 1 秒延迟

### 修改 Placement Rules（数据放置策略）

```sql
ALTER TABLE users PLACEMENT POLICY = region_policy;
ALTER TABLE users PLACEMENT POLICY = DEFAULT;

```

### 修改分片参数

```sql
ALTER TABLE logs SHARD_ROW_ID_BITS = 6;
```

不能将 AUTO_INCREMENT 改为 AUTO_RANDOM（或反向），必须重建表

### 分区管理（MySQL 兼容语法）

```sql
ALTER TABLE events ADD PARTITION (
    PARTITION p2025 VALUES LESS THAN (2026)
);
ALTER TABLE events DROP PARTITION p2023;
ALTER TABLE events TRUNCATE PARTITION p2024;

```

非分区表转分区表（6.1+）
```sql
ALTER TABLE users PARTITION BY HASH(id) PARTITIONS 16;
```

分区表转非分区表
```sql
ALTER TABLE users REMOVE PARTITIONING;

```

### 字符集转换

```sql
ALTER TABLE users CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

```

## DDL 并发控制与加速

tidb_ddl_reorg_worker_cnt: 控制 DDL 回填并发数（默认 4）
tidb_ddl_reorg_batch_size: 每批回填的行数（默认 256）
tidb_ddl_reorg_priority: DDL 优先级（PRIORITY_LOW/NORMAL/HIGH）
tidb_enable_fast_create_table: 快速建表（8.0+）

查看 DDL 任务状态
ADMIN SHOW DDL JOBS;
ADMIN CANCEL DDL JOBS job_id;

## 限制与注意事项

ALTER TABLE ... ORDER BY: 不支持
某些列类型转换需要全表重写（如 INT → VARCHAR）
并发 DDL 可能排队（同一表上的 DDL 是串行的）
ADD INDEX 是在线的但大表可能需要较长时间
RENAME TABLE 跨数据库: 支持（MySQL 也支持）
列默认值修改: 即时生效（不需要回填）
NOT NULL 添加: 需要验证现有数据

## 横向对比: ALTER TABLE 行为

## ADD COLUMN 速度:

   MySQL 8.0:   INSTANT（末尾添加，瞬间完成）
   TiDB:        Online（需要状态转换，秒级到分钟级）
   CockroachDB: 异步 schema 变更（分钟级）
   Spanner:     后台 schema update（分钟级）
   OceanBase:   LSM-Tree 友好（较快）

## ADD INDEX 阻塞性:

   MySQL:      不阻塞 DML（Online DDL），但可能阻塞 DDL
   TiDB:       不阻塞 DML，可能很慢（需要扫描全表）
   PostgreSQL: CREATE INDEX CONCURRENTLY（不锁表但需要两次扫描）
   CockroachDB: 后台异步创建，不阻塞
   Spanner:    后台滚动创建，对大表需要数小时

## DDL 事务性:

   TiDB:       DDL 隐式提交（与 MySQL 一致）
   CockroachDB: DDL 是事务性的（可以 ROLLBACK）
   PostgreSQL: DDL 是事务性的
   MySQL:      DDL 隐式提交
   Spanner:    DDL 不在事务中
