# PostgreSQL: 索引

> 参考资料:
> - [PostgreSQL Documentation - Indexes](https://www.postgresql.org/docs/current/indexes.html)
> - [PostgreSQL Source - nbtree, gin, gist, brin](https://github.com/postgres/postgres/tree/master/src/backend/access)

## 基本索引操作

```sql
CREATE INDEX idx_age ON users (age);                    -- B-tree 默认
CREATE UNIQUE INDEX uk_email ON users (email);          -- 唯一索引
CREATE INDEX idx_city_age ON users (city, age);         -- 复合索引
CREATE INDEX idx_age_desc ON users (age DESC NULLS LAST); -- 降序+NULL排序
CREATE INDEX CONCURRENTLY idx_name ON users (username); -- 不锁表创建

DROP INDEX idx_age;
DROP INDEX CONCURRENTLY idx_age;       -- 不锁表删除
REINDEX INDEX idx_age;                 -- 12+: REINDEX CONCURRENTLY
```

## PostgreSQL 独有索引特性

### 表达式索引（函数索引）—— 所有版本支持

```sql
CREATE INDEX idx_lower_email ON users (LOWER(email));
CREATE INDEX idx_year ON events (EXTRACT(YEAR FROM created_at));
```

查询时必须匹配表达式: WHERE LOWER(email) = 'alice@example.com'
实现: 索引中存储的是表达式计算结果，INSERT/UPDATE 时自动计算

### 部分索引（Partial Index）—— 只索引满足条件的行

```sql
CREATE INDEX idx_active ON users (username) WHERE status = 1;
```

设计分析:
  只有 status=1 的行被索引，索引体积远小于全表索引。
  查询 WHERE status = 1 AND username = 'alice' 时使用此索引。
  经典场景: 软删除（只索引未删除行）、稀疏数据（只索引非 NULL 行）
对比:
  MySQL:      不支持部分索引
  Oracle:     不支持部分索引（但全 NULL 行不入 B-tree 索引，可模拟）
  SQL Server: CREATE INDEX ... WHERE（2008+ 支持 filtered index）

### INCLUDE 列（11+）—— Index-Only Scan 覆盖列

```sql
CREATE INDEX idx_user_incl ON users (username) INCLUDE (email, age);
```

INCLUDE 列不参与索引排序，但存储在叶子节点中。
查询 SELECT email, age FROM users WHERE username = 'alice' 可走 Index-Only Scan
对比:
  SQL Server: INCLUDE 列（2005+ 就有）
  MySQL:      无 INCLUDE（需要把所有列放入索引键）

## 索引类型: PostgreSQL 的可扩展索引架构

B-tree（默认）: 等值、范围、排序、LIKE 'prefix%'
```sql
CREATE INDEX idx_btree ON users USING btree (age);
```

Hash: 仅等值查询（10+ 才支持 WAL，之前不持久化）
```sql
CREATE INDEX idx_hash ON users USING hash (username);
```

GIN (Generalized Inverted Index): 倒排索引
适用: 数组(@>, &&), JSONB(@>, ?), 全文搜索(@@), 三元组(pg_trgm)
```sql
CREATE INDEX idx_gin ON documents USING gin (tags);
CREATE INDEX idx_jsonb ON events USING gin (data jsonb_path_ops);
CREATE INDEX idx_ft ON articles USING gin (to_tsvector('english', content));
```

GiST (Generalized Search Tree): 通用搜索树
适用: 几何(包含/相交), 范围类型(&&重叠), 全文搜索, ltree
```sql
CREATE INDEX idx_gist ON places USING gist (location);
```

SP-GiST (Space-Partitioned GiST): 空间分区搜索树
适用: 不等长数据（IP地址, 电话号码前缀匹配）
```sql
CREATE INDEX idx_spgist ON logs USING spgist (ip_addr inet_ops);
```

BRIN (Block Range Index, 9.5+): 块范围索引
适用: 物理上有序的大表（时序数据、日志）
```sql
CREATE INDEX idx_brin ON logs USING brin (created_at);
```

BRIN 只存储每个块范围的最小/最大值，索引极小（KB级 vs MB级）
但要求数据物理上有序（correlation 接近 1.0）

可扩展性设计:
  PostgreSQL 的索引类型是可插拔的——任何人都可以用 C 写新的索引访问方法
  (CREATE ACCESS METHOD)。这不是空话: bloom, rum, zombodb 都是社区贡献。
  对比 MySQL 的索引固化在存储引擎中（InnoDB只有B+tree和全文索引）。

## CREATE INDEX CONCURRENTLY 的实现机制

```sql
CREATE INDEX CONCURRENTLY idx_con ON users (email);
```

内部过程（三阶段）:
  阶段 1: 创建索引元数据（pg_class + pg_index），标记为 indisready=false
          只持短暂的 SHARE UPDATE EXCLUSIVE 锁（不阻塞 DML）
  阶段 2: 全表扫描构建索引（此时新的 INSERT/UPDATE 也会维护索引）
  阶段 3: 等待所有并发事务结束，再次扫描填补阶段2期间的变化
          最后标记 indisvalid=true

代价:
  (a) 耗时约为普通 CREATE INDEX 的 2-3 倍
  (b) 如果中途失败，留下 INVALID 索引（需手动 DROP）
  (c) 不能在事务块中执行

检查失败的索引:
```sql
SELECT indexrelid::regclass, indisvalid FROM pg_index WHERE NOT indisvalid;
```

## Index-Only Scan vs Index Scan vs Bitmap Scan

Index-Only Scan: 只读索引，不回表
  条件: 查询所有列都在索引中（含 INCLUDE 列），且 visibility map 标记页面全可见
Index Scan: 读索引 + 回表取行
Bitmap Index Scan: 先扫描索引构建位图，再按页批量回表
  适用: 选择性中等（5%-30%行），减少随机 I/O
```sql
EXPLAIN SELECT id FROM users WHERE id > 100;              -- Index Only Scan
EXPLAIN SELECT * FROM users WHERE id = 1;                 -- Index Scan
EXPLAIN SELECT * FROM users WHERE age IN (25, 30, 35);    -- Bitmap Heap Scan
```

## 横向对比: 索引能力

### 索引类型丰富度

  PostgreSQL: B-tree, Hash, GIN, GiST, SP-GiST, BRIN + 可扩展
  MySQL:      B+tree, Hash(Memory引擎), 全文索引, 空间索引
  Oracle:     B-tree, Bitmap, 函数索引, 反向索引, Domain Index
  SQL Server: B-tree, Columnstore, Full-text, Spatial
  ClickHouse: Primary key(稀疏索引), Skip index(minmax/set/bloom)

### 部分索引

  PostgreSQL: WHERE 子句（最灵活）
  SQL Server: WHERE 子句（Filtered Index, 2008+）
  MySQL/Oracle: 不支持

### 表达式索引

  PostgreSQL: 任意表达式（最早支持）
  MySQL:      8.0+ 函数索引（实际是虚拟生成列+索引）
  Oracle:     函数索引（Function-Based Index）

### CONCURRENTLY 创建

  PostgreSQL: CREATE INDEX CONCURRENTLY（不阻塞写入）
  MySQL:      Online DDL（ALGORITHM=INPLACE，允许并发DML）
  Oracle:     CREATE INDEX ONLINE
  SQL Server: ONLINE = ON（Enterprise only）

## 对引擎开发者的启示

(1) 可扩展索引框架是 PostgreSQL 最有价值的架构设计之一。
    GiST/GIN 不是具体的索引类型，而是"索引框架"——定义了接口，
    具体的数据类型（几何、全文、JSON）只需要实现几个回调函数。
    这种"接口+实现"的分离让 PostgreSQL 能支持任意数据类型的高效索引。

(2) 部分索引 + 表达式索引的组合让 PostgreSQL 索引极其灵活:
```sql
    CREATE INDEX ON orders (customer_id) WHERE status = 'active';
```

    这在 MySQL 中需要冗余索引或覆盖全表。

(3) BRIN 索引适合 IoT/时序场景（索引只有 KB 级），
    但要求数据物理有序——这在 append-only 写入模式下天然满足。

(4) Visibility Map 对 Index-Only Scan 至关重要:
    MVCC 下，索引不知道某行对当前事务是否可见，
    需要回表检查 tuple 的 xmin/xmax。Visibility Map 标记"全可见"的页面
    可以跳过回表——这是 VACUUM 的重要副产品。

## 版本演进

PostgreSQL 8.2:  GIN 索引
PostgreSQL 8.3:  GiST 索引支持 INCLUDE（后续改进）
PostgreSQL 9.2:  Index-Only Scan（依赖 Visibility Map）
PostgreSQL 9.5:  BRIN 索引
PostgreSQL 10:   Hash 索引支持 WAL（终于可以在生产使用）
PostgreSQL 11:   INCLUDE 列, CREATE INDEX 并行构建
PostgreSQL 12:   REINDEX CONCURRENTLY, CREATE STATISTICS（多列统计）
PostgreSQL 13:   B-tree 去重（deduplication，重复键共享entry）
PostgreSQL 14:   BRIN multi-range（同一块范围多个区间）
PostgreSQL 15:   UNIQUE NULLS NOT DISTINCT
