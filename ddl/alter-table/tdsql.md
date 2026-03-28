# TDSQL: ALTER TABLE

TDSQL distributed MySQL-compatible database (Tencent Cloud).

> 参考资料:
> - [TDSQL-C MySQL 版文档](https://cloud.tencent.com/document/product/1003)
> - [TDSQL MySQL 版文档](https://cloud.tencent.com/document/product/557)
> - [TDSQL 分布式架构指南](https://cloud.tencent.com/document/product/557/43296)
> - [MySQL 8.0 Reference Manual - ALTER TABLE](https://dev.mysql.com/doc/refman/8.0/en/alter-table.html)
> - ============================================================
> - 1. 基本列操作（MySQL 兼容语法）
> - ============================================================
> - 添加列

```sql
ALTER TABLE users ADD COLUMN phone VARCHAR(20) AFTER email;
ALTER TABLE users ADD COLUMN status TINYINT NOT NULL DEFAULT 1 FIRST;
```

## 一次添加多列

```sql
ALTER TABLE users
    ADD COLUMN city VARCHAR(64),
    ADD COLUMN country VARCHAR(64);
```

## 修改列类型

```sql
ALTER TABLE users MODIFY COLUMN phone VARCHAR(32) NOT NULL;
```

## 重命名列

```sql
ALTER TABLE users CHANGE COLUMN phone mobile VARCHAR(32);
ALTER TABLE users RENAME COLUMN mobile TO phone;
```

## 删除列

```sql
ALTER TABLE users DROP COLUMN phone;
ALTER TABLE users ADD COLUMN IF NOT EXISTS phone VARCHAR(20);
ALTER TABLE users DROP COLUMN IF EXISTS phone;
```

## 修改默认值

```sql
ALTER TABLE users ALTER COLUMN status SET DEFAULT 0;
ALTER TABLE users ALTER COLUMN status DROP DEFAULT;
```

## 表级操作


## 重命名表

```sql
ALTER TABLE users RENAME TO members;
RENAME TABLE users TO members;
```

## 修改表引擎 / 字符集

```sql
ALTER TABLE users ENGINE = InnoDB;
ALTER TABLE users CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
```

## 即时列添加（MySQL 8.0.12+ ALGORITHM=INSTANT）

```sql
ALTER TABLE users ADD COLUMN tag VARCHAR(32), ALGORITHM=INSTANT;
```

## 指定 ALTER 算法

```sql
ALTER TABLE users ADD COLUMN bio TEXT, ALGORITHM=INPLACE;
ALTER TABLE users ADD COLUMN nickname VARCHAR(64), ALGORITHM=INSTANT;
```

## 分区管理（节点内分区）


## 添加分区

```sql
ALTER TABLE logs ADD PARTITION (
    PARTITION p2026 VALUES LESS THAN (2027)
);
```

## 删除分区

```sql
ALTER TABLE logs DROP PARTITION p2023;
```

## 注意: 这里是单节点内的分区管理（RANGE/LIST 分区）

分布式分片（shardkey）的分区由 TDSQL 自动管理

## Shardkey 列变更限制（TDSQL 核心限制）

Shardkey（分片键）一旦设定，变更受到严格限制:
这是 TDSQL 分布式架构的根本约束。
4.1 不能修改 shardkey 列的类型
假设 users 表的 shardkey 是 user_id (BIGINT):
ALTER TABLE users MODIFY COLUMN user_id INT;  -- 会被拒绝
原因: shardkey 类型的改变会影响所有分片的数据路由规则
4.2 不能删除 shardkey 列
ALTER TABLE users DROP COLUMN user_id;  -- 会被拒绝
原因: 删除 shardkey 会导致数据无法路由
4.3 不能重命名 shardkey 列
ALTER TABLE users RENAME COLUMN user_id TO uid;  -- 会被拒绝
原因: 重命名会影响路由映射
4.4 不能在已有表上添加 shardkey
ALTER TABLE users ADD SHARDKEY=user_id;  -- 不支持
原因: 需要重新分布所有数据（需要数据迁移）
替代方案: 创建新表 → 数据迁移 → 删除旧表 → 重命名
4.5 shardkey 变更的正确流程:
Step 1: 创建新 shardkey 的表

```sql
CREATE TABLE users_new (
    id      BIGINT       NOT NULL AUTO_INCREMENT,
    user_id BIGINT       NOT NULL,
    email   VARCHAR(255) NOT NULL,
    PRIMARY KEY (id, user_id)
) SHARDKEY=user_id;
```

Step 2: 迁移数据（使用 TDSQL 提供的数据迁移工具）
INSERT INTO users_new SELECT * FROM users;
Step 3: 验证数据一致性后切换
DROP TABLE users;
ALTER TABLE users_new RENAME TO users;

## 分布式 DDL 执行行为

TDSQL 的 ALTER TABLE 在分布式环境下的执行机制:
5.1 DDL 分发到所有分片
ALTER TABLE users ADD COLUMN phone VARCHAR(20);
TDSQL 调度层会将此 DDL 分发到每个分片（Set）执行
任一分片失败 → 全部回滚
5.2 广播表的 ALTER 行为
广播表（所有分片完整冗余）的 ALTER 会同步到所有节点
确保每个分片的 schema 一致
5.3 跨分片一致性保证
ALTER TABLE 是 DDL 操作，在 TDSQL 中是同步执行的
所有分片完成 ALTER 后才返回成功
期间可能有短暂的写阻塞（取决于 ALTER 的类型）
5.4 Online DDL 支持
支持 MySQL 8.0 的 Online DDL（ALGORITHM=INPLACE / INSTANT）
ALGORITHM=INSTANT: 只修改元数据，不锁表（最快）
ALGORITHM=INPLACE: 原地修改，允许并发 DML
ALGORITHM=COPY: 全表复制，阻塞 DML（最慢）

## 设计分析（对 SQL 引擎开发者）

TDSQL 的 ALTER TABLE 设计体现了分布式 DDL 的核心挑战:
6.1 Shardkey 不可变更的深层原因:
Shardkey 决定了数据 → 分片的映射关系（hash(shardkey) → Set ID）
修改 shardkey 等于重新分布所有数据 → 等价于全表迁移
这不是 TDSQL 的独特限制，所有基于 hash 分片的分布式数据库都有此限制:
TiDB:      可以修改主键但代价极高（需要 region 分裂合并）
CockroachDB: 自动分片，但修改主键同样需要数据迁移
Spanner:   INTERLEAVE 的父键不可修改
Cassandra: partition key 不可修改
6.2 分布式 DDL 的原子性:
集中式: DDL 是单机操作，天然原子
分布式: DDL 需要在多个分片上执行，需要协调:
方案 A: 2PC（两阶段提交）→ TDSQL 使用此方案
方案 B: 异步执行 + 最终一致性 → 会导致 schema 不一致窗口
方案 C: DDL 只修改元数据中心 → 分片 lazy apply
TDSQL 选择方案 A（最安全但可能有性能影响）
6.3 跨方言对比:
TDSQL:     shardkey 不可变更, DDL 同步分发, MySQL 兼容
TiDB:      Online DDL (异步), 允许修改但需要重写
PolarDB-X: 类似 TDSQL, DDL 同步到所有分片
OceanBase: DDL 通过 Leader 统一调度, Follower 异步同步
CockroachDB: DDL 是分布式事务（自动协调）
6.4 版本演进:
TDSQL 早期: 只支持基础 ALTER（ADD/DROP/RENAME 列）
TDSQL MySQL 8.0 兼容: Online DDL, ALGORITHM=INSTANT
TDSQL 新版本: IF EXISTS / IF NOT EXISTS 支持
未来: 可能支持 shardkey 变更（通过在线数据迁移）

## 最佳实践

## shardkey 在建表时确定，后续不可变更 → 谨慎选择

## 使用 ALGORITHM=INSTANT 避免锁表（适用于末尾 ADD COLUMN）

## 批量 DDL 操作在低峰期执行（减少对在线业务的影响）

## 需要 shardkey 变更时，使用 "创建新表 → 迁移 → 切换" 流程

## 广播表适合频繁 ALTER 的小表（维度表等）

## MODIFY COLUMN 操作确保所有分片的数据与新类型兼容
