# TDSQL: 约束 (Constraints)

TDSQL distributed MySQL-compatible database (Tencent Cloud).

> 参考资料:
> - [TDSQL-C MySQL 版文档](https://cloud.tencent.com/document/product/1003)
> - [TDSQL MySQL 版文档](https://cloud.tencent.com/document/product/557)
> - [TDSQL 分布式架构指南](https://cloud.tencent.com/document/product/557/43296)
> - [MySQL 8.0 Reference Manual - Constraints](https://dev.mysql.com/doc/refman/8.0/en/create-table-foreign-keys.html)


## PRIMARY KEY（主键约束）

## 主键必须包含 shardkey 列（TDSQL 核心限制）

单列主键 + shardkey

```sql
CREATE TABLE users (
    id         BIGINT       NOT NULL AUTO_INCREMENT,
    username   VARCHAR(64)  NOT NULL,
    email      VARCHAR(255) NOT NULL,
    age        INT,
    PRIMARY KEY (id)
) SHARDKEY=id;
```

## 复合主键（包含 shardkey）

```sql
CREATE TABLE order_items (
    order_id BIGINT NOT NULL,
    item_id  BIGINT NOT NULL,
    user_id  BIGINT NOT NULL,
    quantity INT    NOT NULL DEFAULT 1,
    PRIMARY KEY (order_id, item_id, user_id)
) SHARDKEY=user_id;
```

## UNIQUE 约束（唯一性约束）

## 唯一约束必须包含 shardkey 列，否则无法保证全局唯一性

正确: 唯一约束包含 shardkey

```sql
ALTER TABLE users ADD CONSTRAINT uk_email UNIQUE (email, id);
```

## 复合唯一约束

```sql
ALTER TABLE users ADD CONSTRAINT uk_name_email UNIQUE (username, email, id);
```

## 通过 CREATE TABLE 内联定义

```sql
CREATE TABLE products (
    id    BIGINT       NOT NULL,
    sku   VARCHAR(64)  NOT NULL,
    name  VARCHAR(255) NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uk_sku (sku, id)
) SHARDKEY=id;
```

## NOT NULL 约束

```sql
ALTER TABLE users MODIFY COLUMN email VARCHAR(255) NOT NULL;
```

## DEFAULT 约束

```sql
ALTER TABLE users ALTER COLUMN status SET DEFAULT 1;
```

## CHECK 约束（MySQL 8.0 兼容模式）

```sql
ALTER TABLE users ADD CONSTRAINT chk_age CHECK (age >= 0 AND age <= 200);
ALTER TABLE orders ADD CONSTRAINT chk_amount CHECK (amount > 0);
```

## FOREIGN KEY 约束（不支持）

TDSQL 不支持外键约束，原因:
1. 跨分片外键验证需要分布式事务，性能代价极高
2. 父子表可能分布在不同分片，无法做引用完整性检查
3. 外键级联操作在分布式环境下难以保证原子性
替代方案:
a. 应用层保证引用完整性（推荐）
b. 使用广播表（小表冗余到所有分片，模拟同分片外键）
c. 使用事务 + 显式校验

## 约束管理操作


## 删除唯一约束（通过 DROP INDEX）

```sql
ALTER TABLE users DROP INDEX uk_email;
```

## 删除 CHECK 约束

```sql
ALTER TABLE users DROP CHECK chk_age;
```

## 查看约束元数据

```sql
SELECT * FROM information_schema.TABLE_CONSTRAINTS
WHERE TABLE_SCHEMA = 'mydb' AND TABLE_NAME = 'users';

SELECT * FROM information_schema.KEY_COLUMN_USAGE
WHERE TABLE_SCHEMA = 'mydb' AND TABLE_NAME = 'users';

SELECT * FROM information_schema.CHECK_CONSTRAINTS
WHERE CONSTRAINT_SCHEMA = 'mydb' AND TABLE_NAME = 'users';
```

## 广播表的约束行为

广播表（通过特定语法创建）在所有分片上存储完整副本:
约束在每个分片独立执行
不受 shardkey 限制（广播表无 shardkey）
唯一约束可建立在任意列上（因为每个分片有完整数据）
适合小型维度表（配置、字典等）

## 分布式约束行为分析（对 SQL 引擎开发者）

TDSQL 的约束设计体现了分布式数据库约束的核心矛盾:
9.1 唯一性约束的分布式挑战:
集中式:  B+树插入时自动检查唯一性，O(log n)，单机事务保证
分布式:  需要跨分片检查，可能涉及多节点分布式事务
TDSQL 方案: 强制唯一约束包含 shardkey → 退化为分片内唯一性检查
优点: 零额外开销，与单机 MySQL 行为一致
缺点: 无法在非 shardkey 列上保证全局唯一（除非用 GSI）
9.2 与其他分布式数据库对比:
TDSQL:     唯一约束必须含 shardkey，无外键
TiDB:      支持全局唯一约束（通过 Percolator 2PC），6.6+ 支持外键
PolarDB-X: 类似 TDSQL，但 GSI 可扩展唯一约束
CockroachDB: 完整支持外键（通过分布式事务）
Spanner:   不支持外键的强制执行（仅声明性）
OceanBase: 支持外键（通过分布式事务），性能有一定代价
9.3 对引擎开发者的启示:
分布式约束是 "功能完备性" 与 "性能" 的权衡
TDSQL 选择了性能优先: 限制约束范围换取零额外开销
如果目标用户从 MySQL 迁移，需要评估外键缺失的影响
GSI 是解决 "非 shardkey 唯一约束" 的方向，但写入代价高
9.4 版本演进:
TDSQL 早期: 只支持 shardkey 内唯一约束，无外键
TDSQL 新版本: GSI 支持非 shardkey 唯一约束
未来: 可能支持有限形式的跨分片约束

## 最佳实践

## shardkey 选择应优先考虑唯一约束的需求

## 业务上需要全局唯一的列，要么包含在 shardkey 中，要么使用 GSI

## 用应用层逻辑替代外键（先查后插/删，或用事务）

## 广播表适合有约束需求的小型维度表

## CHECK 约束对分布式透明，可自由使用
