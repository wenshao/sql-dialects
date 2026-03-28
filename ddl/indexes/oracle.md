# Oracle: 索引

> 参考资料:
> - [Oracle SQL Language Reference - CREATE INDEX](https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/CREATE-INDEX.html)
> - [Oracle Database Concepts - Indexes and Index-Organized Tables](https://docs.oracle.com/en/database/oracle/oracle-database/23/cncpt/indexes-and-index-organized-tables.html)

## 基本索引类型

B-tree 索引（默认，所有版本）
```sql
CREATE INDEX idx_age ON users (age);
```

唯一索引
```sql
CREATE UNIQUE INDEX uk_email ON users (email);
```

复合索引
```sql
CREATE INDEX idx_city_age ON users (city, age);
```

降序索引
```sql
CREATE INDEX idx_age_desc ON users (age DESC);
```

函数索引（8i+，Oracle 比其他数据库更早支持）
```sql
CREATE INDEX idx_upper_name ON users (UPPER(username));
```

## Oracle 独有索引类型（对引擎开发者的核心价值）

### 位图索引（Bitmap Index）

Oracle 在 OLAP 优化中的杀手级特性
```sql
CREATE BITMAP INDEX idx_status ON users (status);
```

设计决策分析:
  位图索引为每个不同值维护一个位向量（bit vector），
  每一位对应表中的一行。适合低基数列（如性别、状态、国家）。

位图索引的优势:
  1. 多个位图索引可以高效组合（AND/OR 位运算）
  2. 存储紧凑（位向量比 B-tree 叶节点小得多）
  3. COUNT/EXISTS 等查询极快（直接在位图上计算）

位图索引的致命缺陷（OLTP 禁用！）:
  位图按数据块粒度锁定 → 一个 UPDATE 可能锁住上千行
  高并发 DML 场景下会导致严重的锁争用和死锁

横向对比:
  Oracle:     原生 BITMAP INDEX，优化器自动识别使用
  PostgreSQL: 无位图索引，但优化器可动态构建 Bitmap Heap Scan
              （运行时创建临时位图，不持久化）
  MySQL:      不支持位图索引
  SQL Server: 不支持位图索引（但有列存储索引实现类似 OLAP 优化）
  ClickHouse: 使用跳数索引（Skip Index）+ 布隆过滤器

对引擎开发者的启示:
  如果引擎面向 OLAP 或混合负载，位图索引值得实现。
  关键设计点: 位图压缩算法（Oracle 使用专有压缩）、
  位图锁粒度（影响 OLTP 并发）、位图与 B-tree 的优化器切换。

### 反向键索引（Reverse Key Index）

```sql
CREATE INDEX idx_id_rev ON users (id) REVERSE;
```

设计动机:
  自增 ID 的 B-tree 索引会导致所有插入集中在最右叶子节点（热点问题）。
  RAC 环境下多实例争用同一个叶块更为严重。
  反向键索引将字节序反转，分散插入到不同叶节点。

代价:
  不能用于范围查询（WHERE id BETWEEN 1 AND 100），
  因为反转后相邻值分散到了不同位置。

对比:
  PostgreSQL: 无反向键索引（BRIN 索引用于不同场景）
  MySQL/InnoDB: 无反向键（使用 AUTO_INCREMENT 时热点是已知问题）
  Spanner:    bit-reversed sequence 是类似思想

### 不可见索引（Invisible Index，11g+）

```sql
CREATE INDEX idx_test ON users (age) INVISIBLE;
ALTER INDEX idx_test VISIBLE;
```

优化器忽略该索引，但仍然维护更新。
用途: 安全地测试"删除索引的影响"而不实际删除。
对比: MySQL 8.0+ 也支持 INVISIBLE INDEX（受 Oracle 启发）

## 压缩索引与在线操作

压缩索引（前缀压缩，减少重复值存储）
```sql
CREATE INDEX idx_city_age ON users (city, age) COMPRESS 1;
```

COMPRESS 1 表示压缩前 1 列的重复值

高级索引压缩（12c+）
```sql
CREATE INDEX idx_city_age ON users (city, age) COMPRESS ADVANCED LOW;
```

在线创建（不阻塞 DML）
```sql
CREATE INDEX idx_age ON users (age) ONLINE;
```

在线重建
```sql
ALTER INDEX idx_age REBUILD ONLINE;
```

## 分区索引（对引擎开发者：分布式索引的参考）

本地分区索引（与表分区对齐，每个表分区一个索引段）
```sql
CREATE INDEX idx_date ON orders (order_date) LOCAL;
```

全局分区索引（独立于表分区）
```sql
CREATE INDEX idx_amount ON orders (amount) GLOBAL
    PARTITION BY RANGE (amount) (
        PARTITION p1 VALUES LESS THAN (1000),
        PARTITION p2 VALUES LESS THAN (MAXVALUE)
    );
```

设计权衡:
  LOCAL 索引: 分区维护方便（DROP PARTITION 不影响索引），但全局查询需扫描多个索引段
  GLOBAL 索引: 全局查询高效，但分区 DDL 需要 REBUILD

横向对比:
  PostgreSQL: 11+ 支持分区索引，类似 Oracle LOCAL
  MySQL:      分区表索引必须包含分区键（强制 LOCAL 语义）

对引擎开发者的启示:
  分布式引擎中"全局索引"等价于跨节点索引，实现代价极高。
  大多数分布式数据库选择只支持 LOCAL 索引（索引与数据同分布）。

## '' = NULL 对索引的影响

Oracle B-tree 索引不存储全 NULL 的索引键:
对单列索引: WHERE col IS NULL 不能使用 B-tree 索引
对复合索引: 至少一个列非 NULL 才会被索引

由于 '' = NULL:
VARCHAR2 列包含空字符串的行也不会被索引!
WHERE name = '' 和 WHERE name IS NULL 都无法使用单列 B-tree 索引

解决方案 1: 复合索引加一个常量列
```sql
CREATE INDEX idx_name_nn ON users (name, 0);  -- 0 保证索引键不全为 NULL

-- 解决方案 2: 位图索引（位图索引包含 NULL）
CREATE BITMAP INDEX idx_name_bm ON users (name);
```

对比:
  PostgreSQL: NULL 值被索引，IS NULL 可以走索引
  MySQL:      NULL 值被索引
  SQL Server: NULL 值被索引

## 数据字典查询

```sql
SELECT index_name, index_type, uniqueness, visibility, compression
FROM user_indexes WHERE table_name = 'USERS';

SELECT index_name, column_name, column_position, descend
FROM user_ind_columns WHERE table_name = 'USERS'
ORDER BY index_name, column_position;
```

查看函数索引的表达式
```sql
SELECT index_name, column_expression
FROM user_ind_expressions WHERE table_name = 'USERS';
```

索引统计
```sql
SELECT index_name, blevel, leaf_blocks, distinct_keys, num_rows
FROM user_indexes WHERE table_name = 'USERS';
```

## 对引擎开发者的总结

Oracle 的索引体系是最丰富的:
  B-tree (默认) → 通用场景
  Bitmap → OLAP 低基数列（杀手级特性）
  Reverse Key → RAC 热点消除
  Function-based → 表达式查询优化
  Compressed → 减少存储和 I/O
  Invisible → 安全测试索引变更
  Local/Global → 分区场景灵活控制

最小可行索引系统: B-tree + 函数索引 + 在线创建
进阶: 位图索引（OLAP 场景显著提升）
高级: 分区索引（大数据量必备）
