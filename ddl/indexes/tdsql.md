# TDSQL: 索引 (Indexes)

TDSQL distributed MySQL-compatible database (Tencent Cloud).

> 参考资料:
> - [TDSQL-C MySQL 版文档](https://cloud.tencent.com/document/product/1003)
> - [TDSQL MySQL 版文档](https://cloud.tencent.com/document/product/557)
> - [TDSQL 分布式架构指南](https://cloud.tencent.com/document/product/557/43296)
> - [MySQL 8.0 Reference Manual - CREATE INDEX](https://dev.mysql.com/doc/refman/8.0/en/create-index.html)


## 基本索引语法（MySQL 兼容）


## 普通索引

```sql
CREATE INDEX idx_age ON users (age);
```

## 唯一索引

```sql
CREATE UNIQUE INDEX uk_email ON users (email);
```

## 复合索引

```sql
CREATE INDEX idx_city_age ON users (city, age);
```

## 前缀索引（适用于长字符串列）

```sql
CREATE INDEX idx_email_prefix ON users (email(20));
```

## 降序索引（MySQL 8.0+）

```sql
CREATE INDEX idx_age_desc ON users (age DESC);
```

## 函数索引 / 表达式索引（MySQL 8.0+）

```sql
CREATE INDEX idx_upper_name ON users ((UPPER(username)));
```

## 不可见索引（用于安全测试索引删除的影响）

```sql
CREATE INDEX idx_test ON users (age) INVISIBLE;
ALTER TABLE users ALTER INDEX idx_test VISIBLE;
```

## 指定索引算法

```sql
CREATE INDEX idx_age ON users (age) USING BTREE;
```

## 删除索引

```sql
DROP INDEX idx_age ON users;
DROP INDEX IF EXISTS idx_age ON users;
```

## 查看索引

```sql
SHOW INDEX FROM users;
```

## Shardkey 与索引的交互（TDSQL 核心概念）

TDSQL 是分布式 MySQL 兼容数据库，数据按 shardkey 分布到不同分片。
shardkey 决定了数据行位于哪个物理分片（Set），类似于 TiDB 的分区键。
Shardkey 定义语法:

```sql
CREATE TABLE orders (
    order_id    BIGINT NOT NULL,
    user_id     BIGINT NOT NULL,
    order_time  DATETIME NOT NULL,
    amount      DECIMAL(10,2),
    PRIMARY KEY (order_id, user_id)
) SHARDKEY=user_id;
```

Shardkey 对索引的限制:
1. 所有唯一索引（含主键）必须包含 shardkey 列
原因: 分布式环境下唯一性需要定位到特定分片才能验证
不包含 shardkey 的唯一索引 → TDSQL 拒绝创建
2. 非 shardkey 上的普通索引可以创建，但查询时可能需要扫描所有分片
3. shardkey 上的索引查询可精确路由到目标分片（最高效）
4. 广播表（小表）不受 shardkey 限制，所有分片都有完整数据
正确: 唯一索引包含 shardkey (user_id)

```sql
CREATE UNIQUE INDEX uk_user_order ON orders (user_id, order_id);
```

## 错误: 唯一索引不包含 shardkey → 创建失败

CREATE UNIQUE INDEX uk_order_id ON orders (order_id);  -- 会被拒绝

## 全局二级索引（Global Secondary Index, GSI）

TDSQL 支持全局二级索引，允许在非 shardkey 列上创建索引
并提供跨分片的查询能力。
GSI 特点:
索引数据独立于主表分片，有自己的分片策略
查询利用 GSI 可以避免全分片扫描
GSI 的维护有额外写入开销（需要跨分片同步）
GSI 上的唯一性可以保证全局唯一
全局二级索引语法（TDSQL 扩展）:
CREATE GLOBAL INDEX idx_global_city ON users (city) SHARDKEY=city;
注意: GSI 会创建独立的索引表，按指定的 shardkey 分布
GSI 与本地索引的对比:
本地索引: 只在分片内有效，查询非 shardkey 列可能全分片扫描
全局索引: 跨分片有效，支持在非 shardkey 列上的高效查询
代价: 全局索引增加写入延迟（需跨分片更新）和存储开销

## 分布式索引行为与限制


4.1 索引创建在所有分片上同步执行
CREATE INDEX 语句会被 TDSQL 调度层分解为每个分片上的本地 CREATE INDEX
任一分片失败则整个操作回滚
4.2 索引只保证分片内的数据有序
范围查询如果是非 shardkey 列，需要合并排序所有分片的结果
4.3 不支持的索引类型
不支持 FULLTEXT 索引（分布式全文检索建议使用 Elasticsearch）
不支持 SPATIAL 索引（空间索引需要专业地理数据库）
4.4 索引与分片路由
查询条件包含 shardkey → 精确路由到单个分片（最快）
查询条件包含 GSI 列 → 先查 GSI 定位分片，再回主表（较慢）
查询条件不含 shardkey/GSI → 全分片扫描（最慢）

## 设计分析（对 SQL 引擎开发者）

TDSQL 的索引设计体现了分布式数据库索引的经典 trade-off:
5.1 唯一性约束与分布式的矛盾:
集中式数据库: 唯一索引通过 B+树或 Hash 直接验证，O(log n)
分布式数据库: 跨分片唯一性需要分布式协议（2PC 或异步校验）
TDSQL 的方案: 要求唯一索引包含 shardkey → 将全局唯一退化为分片内唯一
对比 TiDB: 通过全局索引 + 2PC 保证全局唯一（代价更高但更通用）
对比 CockroachDB: 通过分布式事务 + range 分裂保证唯一性
5.2 索引路由效率:
shardkey 是最高效的路由键（O(1) 定位分片）
GSI 需要额外查询索引表再回查主表（两跳）
非 shardkey 非 GSI 的索引只能做分片内优化（减少分片内扫描量）
5.3 跨方言对比:
TDSQL:    SHARDKEY 必须在唯一索引中，GSI 可扩展
TiDB:     无强制要求，但推荐 AUTO_RANDOM 避免热点
PolarDB-X: 类似 TDSQL，使用 DRDS 分区策略
CockroachDB: 自动分片（基于 range），无需显式指定 shardkey
Spanner:   INTERLEAVE 提供物理邻近，二级索引是独立表
Vitess:    Vindex 概念类似 shardkey，支持多种分片算法
5.4 版本演进:
TDSQL 早期: 只支持 shardkey 上的唯一约束
TDSQL 新版本: 支持 GSI，允许非 shardkey 列上的全局索引
趋势: 从"限制用户"转向"提供能力"，但性能和一致性需要用户权衡

## 最佳实践

## shardkey 选择: 选择高基数、均匀分布、查询频率高的列

## 避免在低基数列上建 shardkey（如 status 只有几个值 → 数据倾斜）

## 高频查询条件包含 shardkey 可以大幅减少扫描范围

## GSI 用于需要跨分片查询但又不频繁更新的场景

## 广播表适合小维度表（如配置表），全分片冗余避免跨分片 JOIN
