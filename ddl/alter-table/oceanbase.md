# OceanBase: ALTER TABLE

> 参考资料:
> - [OceanBase ALTER TABLE (MySQL Mode)](https://www.oceanbase.com/docs/common-oceanbase-database-cn)
> - [OceanBase Online DDL](https://www.oceanbase.com/docs/common-oceanbase-database-cn)

**引擎定位**: 分布式关系型数据库，兼容 MySQL/Oracle 双模式。基于 LSM-Tree 存储，Paxos 共识。

## 基本语法 — MySQL 模式

```sql
ALTER TABLE users ADD COLUMN phone VARCHAR(20) AFTER email;
ALTER TABLE users MODIFY COLUMN phone VARCHAR(32) NOT NULL;
ALTER TABLE users CHANGE COLUMN phone mobile VARCHAR(32);
ALTER TABLE users DROP COLUMN phone;

```

## 语法设计分析（对 SQL 引擎开发者）


### LSM-Tree 对 ALTER TABLE 的天然优势

OceanBase 使用 LSM-Tree 存储引擎，这使得某些 DDL 操作更高效:

ADD COLUMN: LSM-Tree 的 append-only 特性意味着不需要重写现有数据文件。
  新 Schema 只影响后续写入的 MemTable，旧 SSTable 在 Compaction 时适配新 Schema。
  对比 B+Tree (InnoDB): 添加非末尾列可能需要重写数据页。

DROP COLUMN: 标记删除，在下次 Major Compaction 时物理清除。
  优点: 瞬间完成（只修改元数据）
  缺点: 空间不会立即释放

**设计 trade-off:**
  LSM-Tree DDL 快但 Compaction 开销后置 → 需要合理调度 Compaction
  B+Tree DDL 慢但不需要后台 Compaction → 空间回收即时

**对比:**
  TiDB (RocksDB):  也是 LSM-Tree，DDL 特性类似
  CockroachDB (Pebble): LSM-Tree，异步 schema 变更
  MySQL (InnoDB):   B+Tree，INSTANT/INPLACE/COPY 三种模式
  PostgreSQL:       Heap + MVCC，ADD COLUMN+DEFAULT 在 11+ 是即时的

### 双模式 DDL 差异

MySQL 模式和 Oracle 模式的 ALTER TABLE 语法差异很大:
MySQL 模式:  ALTER TABLE t ADD COLUMN c INT AFTER x;
Oracle 模式: ALTER TABLE t ADD (c NUMBER);
引擎内部必须维护两套 DDL 解析器，但存储层操作相同。

Online DDL 支持
```sql
ALTER TABLE users ADD COLUMN city VARCHAR(64), ALGORITHM=INPLACE;
```

ALGORITHM=INSTANT: 不支持（OceanBase 有自己的 Online DDL 机制）

## OceanBase 特有操作


### 修改 Locality（副本分布）

```sql
ALTER TABLE users LOCALITY = 'F@zone1, F@zone2, R@zone3';
```

F = Full replica (参与 Paxos 投票), R = ReadOnly replica, L = LogOnly

### 修改 Primary Zone（Leader 放置）

```sql
ALTER TABLE users PRIMARY_ZONE = 'zone1';

```

### 修改 Tablegroup

```sql
ALTER TABLE orders TABLEGROUP = tg_new;

```

### 分区管理

```sql
ALTER TABLE logs ADD PARTITION (
    PARTITION p2026 VALUES LESS THAN (2027)
);
ALTER TABLE logs DROP PARTITION p2023;
ALTER TABLE logs TRUNCATE PARTITION p2024;

```

分区重组
```sql
ALTER TABLE sales REORGANIZE PARTITION p2024 INTO (
    PARTITION p2024_h1 VALUES LESS THAN ('2024-07-01'),
    PARTITION p2024_h2 VALUES LESS THAN ('2025-01-01')
);

```

非分区表转分区表（4.0+）
```sql
ALTER TABLE users PARTITION BY HASH(id) PARTITIONS 8;

```

### 列组 (Column Group, 4.2+)

OceanBase 列存引擎（HTAP）通过列组实现混合存储
ALTER TABLE users ADD COLUMN GROUP (all_columns EACH COLUMN);

## Oracle 模式

ALTER TABLE t ADD (col1 NUMBER, col2 VARCHAR2(100));
ALTER TABLE t MODIFY (col1 NUMBER(10,2));
ALTER TABLE t DROP (col1, col2);
ALTER TABLE t RENAME COLUMN old_name TO new_name;

分区管理 (Oracle 模式)
ALTER TABLE events ADD PARTITION p2025 VALUES LESS THAN (TO_DATE('2026-01-01','YYYY-MM-DD'));
ALTER TABLE events DROP PARTITION p2023;

## 其他通用操作

```sql
ALTER TABLE users RENAME TO members;
RENAME TABLE users TO members;
ALTER TABLE users ALTER COLUMN status SET DEFAULT 0;
ALTER TABLE users CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

```

## 限制与注意事项

ALGORITHM=INSTANT: 不支持
不能修改主键列的类型（主键决定数据分布）
分区键列的修改受限
并发 DDL 可能排队（由 RootService 协调）
ALTER TABLE ... ORDER BY: 不支持
某些列类型转换需要重建表

## 横向对比

## Online DDL 支持度:

   OceanBase: 大部分操作 Online（LSM-Tree 优势）
   TiDB:      全部 Online（F1 协议）
   MySQL:     大部分 Online（5.6+），部分 INSTANT（8.0.12+）
   CockroachDB: 全部异步 schema 变更
   Spanner:   全部后台 schema update

## 双模式的 DDL 挑战:

   OceanBase 需要同时维护 MySQL 和 Oracle 两套 DDL 解析器。
   ALTER TABLE 的语法差异（AFTER/FIRST 是 MySQL 独有，Oracle 不支持列顺序指定）。
   这意味着 OceanBase 的 DDL 测试矩阵是其他引擎的 2 倍。
