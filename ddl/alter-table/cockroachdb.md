# CockroachDB: ALTER TABLE

> 参考资料:
> - [CockroachDB ALTER TABLE](https://www.cockroachlabs.com/docs/stable/alter-table)
> - [CockroachDB Online Schema Changes](https://www.cockroachlabs.com/docs/stable/online-schema-changes)

**引擎定位**: 分布式 SQL 数据库，兼容 PostgreSQL 协议。基于 Pebble (RocksDB) 存储，Raft 共识，支持 Geo-Partitioning。

## 基本语法（PostgreSQL 兼容）

```sql
ALTER TABLE users ADD COLUMN phone VARCHAR(20);
ALTER TABLE users ADD COLUMN IF NOT EXISTS phone VARCHAR(20);
ALTER TABLE users ADD COLUMN status INT NOT NULL DEFAULT 1;
ALTER TABLE users ALTER COLUMN age TYPE BIGINT;
ALTER TABLE users ALTER COLUMN email SET NOT NULL;
ALTER TABLE users ALTER COLUMN phone DROP NOT NULL;
ALTER TABLE users ALTER COLUMN status SET DEFAULT 0;
ALTER TABLE users ALTER COLUMN status DROP DEFAULT;
ALTER TABLE users DROP COLUMN phone;
ALTER TABLE users DROP COLUMN IF EXISTS phone;
ALTER TABLE users RENAME COLUMN username TO user_name;
ALTER TABLE users RENAME TO members;

```

## 语法设计分析（对 SQL 引擎开发者）


### 异步 Schema 变更: CockroachDB 的核心 DDL 设计

CockroachDB 的 schema 变更基于 Google F1 论文（与 TiDB 类似），
但实现上有重要差异:

状态机: absent → delete-only → delete-and-write-only → backfill → public
协调: 不需要中心化协调器（不同于 TiDB 的 PD），而是通过 schema lease 机制
每个节点定期刷新 schema（默认 5 分钟），任何时刻最多两个相邻版本共存

关键设计决策:
  DDL 是事务性的: BEGIN; ALTER TABLE ...; CREATE TABLE ...; COMMIT;
  这与 PostgreSQL 一致，但在分布式环境中实现难度更大。
  MySQL/Oracle DDL 隐式提交，无法在事务中 rollback DDL。

**对比:**
  TiDB:       F1 协议 + PD 协调（中心化），DDL 隐式提交
  OceanBase:  RootService 协调 DDL，DDL 隐式提交
  Spanner:    DDL 不在用户事务中，是独立的 schema update 操作
  PostgreSQL: DDL 是事务性的（与 CockroachDB 一致）

### ALTER PRIMARY KEY: CockroachDB 独有能力

```sql
ALTER TABLE users ALTER PRIMARY KEY USING COLUMNS (id, region);
```

背后执行: 创建新主键索引 → 回填数据 → 原子切换 → 清理旧索引
**对比:** MySQL/PostgreSQL/TiDB/Spanner/OceanBase 都不支持直接修改主键

## CockroachDB 特有操作


### Locality 修改（多区域控制）

```sql
ALTER TABLE users SET LOCALITY REGIONAL BY ROW;
ALTER TABLE users SET LOCALITY GLOBAL;
ALTER TABLE users SET LOCALITY REGIONAL BY TABLE IN 'us-east1';

```

### 行级 TTL（v22.1+）

```sql
ALTER TABLE events SET (ttl_expiration_expression = 'created_at + INTERVAL ''90 days''');
ALTER TABLE events SET (ttl_job_cron = '@daily');
ALTER TABLE events RESET (ttl);

```

### Column Family 修改

```sql
ALTER TABLE wide_table ADD COLUMN extra BYTES CREATE FAMILY f_extra;
ALTER TABLE wide_table ADD COLUMN more TEXT CREATE IF NOT EXISTS FAMILY f_extra;

```

### Zone 配置（副本和 GC）

```sql
ALTER TABLE users CONFIGURE ZONE USING num_replicas = 5;
ALTER TABLE users CONFIGURE ZONE USING num_replicas = 5, gc.ttlseconds = 86400;

```

### Hash-sharded index via ALTER

```sql
ALTER TABLE events ADD INDEX idx_ts (ts) USING HASH;

```

### Schema 修改

```sql
ALTER TABLE users SET SCHEMA myschema;

```

## 约束管理

```sql
ALTER TABLE orders ADD CONSTRAINT fk_orders_user
    FOREIGN KEY (user_id) REFERENCES users (id);
ALTER TABLE users ADD CONSTRAINT chk_age CHECK (age >= 0 AND age <= 150);
ALTER TABLE users ADD CONSTRAINT uq_email UNIQUE (email);

```

NOT VALID: 添加约束但不验证现有数据（PostgreSQL 兼容）
```sql
ALTER TABLE orders ADD CONSTRAINT fk_user
    FOREIGN KEY (user_id) REFERENCES users (id) NOT VALID;
ALTER TABLE orders VALIDATE CONSTRAINT fk_user;

```

Partial unique constraint
```sql
ALTER TABLE users ADD CONSTRAINT uq_active_email
    UNIQUE (email) WHERE (status = 'active');

ALTER TABLE orders DROP CONSTRAINT fk_orders_user;
ALTER TABLE users DROP CONSTRAINT IF EXISTS chk_age;

```

## 限制与注意事项

不支持 ADD COLUMN ... AFTER/FIRST（PostgreSQL 语法不支持列顺序指定）
部分列类型转换支持（如 INT → BIGINT），不支持部分（如 STRING → INT with data）
同一表上的 DDL 串行执行
SHOW JOBS 查看 schema 变更进度
大表 ADD INDEX 可能影响读写性能
不支持 ADD COLUMN 带 GENERATED ALWAYS AS（必须在 CREATE TABLE 中定义）

## 横向对比

## ALTER PRIMARY KEY:

   CockroachDB: 支持在线修改（独有优势）
   TiDB/MySQL/PostgreSQL/OceanBase/Spanner: 不支持直接修改

## DDL 事务性:

   CockroachDB + PostgreSQL: DDL 是事务性的（可以 ROLLBACK）
   MySQL + OceanBase + TiDB: DDL 隐式提交
   Spanner: DDL 不在事务中

## NOT VALID 约束:

   CockroachDB + PostgreSQL: 支持（先添加再异步验证，对大表友好）
   MySQL/TiDB/OceanBase: 不支持（添加约束时必须验证所有现有数据）
