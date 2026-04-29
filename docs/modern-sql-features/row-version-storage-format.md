# 行版本存储格式 (Row Version Storage Format)

每一笔 UPDATE 都不只是"修改一行"——它是在制造一个新的行版本，并决定旧版本去往何处。是原地修改 + UNDO 回滚段（Oracle、MySQL InnoDB），还是追加新元组 + 老元组打 xmax 标记（PostgreSQL），还是全部追加成 LSM key/value（CockroachDB、TiKV）？这一选择决定了 bloat 的多少、热点行的争用程度、vacuum/purge 的复杂度，以及 long-running transaction 能撑多久。本文系统对比 45+ 数据库引擎的行版本存储格式，深入剖析 PostgreSQL 24 字节元组头、MySQL undo log 链、Oracle ITL 槽位、CockroachDB MVCC key 这四种最具代表性的实现。

## 没有 SQL 标准

ANSI/ISO SQL 标准定义了 ACID 语义和隔离级别（READ UNCOMMITTED、READ COMMITTED、REPEATABLE READ、SERIALIZABLE），但完全没有规定行版本如何存储：

- 旧版本存储在哪里？标准未定义。
- 行头如何记录可见性信息（xmin/xmax/SCN/ts）？标准未定义。
- 是否允许 in-place update？标准未定义。
- 删除时是物理移除还是只打 tombstone？标准未定义。
- vacuum / purge / compaction 何时进行？标准未定义。

这种"标准沉默"造成了行版本存储的实现近乎完全分化。粗略可以把所有 OLTP 引擎分成四个流派：

- **In-place update + UNDO 段**：MySQL InnoDB、Oracle、MariaDB、TiDB 的 Percolator 模型（部分）、SAP HANA（行存）。当前行原地修改，旧版本写入 UNDO（rollback segment）。回滚和读取旧快照都从 UNDO 重建。
- **Append-only + tombstone**：PostgreSQL、Greenplum、Yellowbrick、CockroachDB（逻辑层）。每次 UPDATE 都生成新元组（new tuple），老元组打 xmax 表示"在某个 xid 之后被删"。通过 vacuum 清理。
- **LSM-based MVCC**：RocksDB-backed 的 CockroachDB Pebble、TiKV、YugabyteDB DocDB、ScyllaDB、Cassandra。行版本是 LSM 中的 key/value，key 后缀是 timestamp，compaction 时清理过期版本。
- **No-MVCC append-only**：ClickHouse、Doris、StarRocks、Druid。完全不维护行版本，UPDATE 通过 mutation 重写整列；DELETE 通过 ALTER TABLE 标记。读取永远走最新 part。

下文用 7 张支持矩阵覆盖 45+ 引擎的核心维度。

## 支持矩阵

### 1. 总体存储模型

| 引擎 | 存储模型 | 旧版本去向 | UPDATE 路径 | DELETE 处理 |
|------|---------|-----------|------------|------------|
| PostgreSQL | append-only heap | 同表内的旧元组 | 新元组 + 老元组 xmax | 老元组 xmax |
| MySQL InnoDB | in-place + undo | undo log（系统表空间或 undo TS） | 原地改 + undo record | 标记删除 + purge |
| MariaDB InnoDB | 同 InnoDB | 同 | 同 | 同 |
| MariaDB Aria | undo + redo | undo file | 原地改 + undo | 标记删除 |
| Oracle | in-place + UNDO TS | UNDO tablespace | 原地改 + UNDO 记录 | 删除 + UNDO 副本 |
| SQL Server (RCSI/SI) | in-place + version store | tempdb version store | 原地改 + 版本副本 | 标记 + 版本副本 |
| SQL Server (默认) | in-place 加锁 | 不保留版本 | 原地改 + 锁 | 原地删除 |
| DB2 | in-place + log + CC | 日志 + currently committed cache | 原地改 + log | 原地删除 + log |
| SQLite | in-place + journal | rollback journal / WAL | 原地改 + journal | 标记 + journal |
| SAP HANA (Row) | in-place + version vector | 内存 version vector | 原地改 + 旧值副本 | 标记 + 副本 |
| SAP HANA (Column) | append + delta | delta store + main | 标记老行 + 写新行到 delta | 标记位 |
| Informix | in-place + log + version | logical log | 原地改 | 原地删除 |
| Firebird | append-only | 同表内的 back-version | 写新版本 + 链接旧版本 | 删除 stub |
| H2 | in-place + undo | 内存 undo log | 原地改 + undo | 标记 |
| HSQLDB | in-place（部分 MVCC） | 内存版本 | 原地改 | 原地删除 |
| Derby | in-place + log | 事务日志 | 原地改 | 原地删除 |
| CockroachDB | LSM (Pebble) | 同 LSM 不同 ts | 写新 (key, ts) | 写 tombstone (key, ts) |
| TiDB / TiKV | LSM (RocksDB) | 同 LSM 不同 ts | 写新 (key, ts) | 写 tombstone |
| YugabyteDB | LSM (DocDB) | 同 LSM 不同 hybrid_time | 写新 (key, ht) | 写 tombstone |
| Spanner | LSM-like (Colossus) | 同存储不同 ts | 写新 (key, ts) | 写 tombstone |
| OceanBase | LSM-tree (memtable + sstable) | redo + sstable 多版本 | 行级 redo + 多版本 | tombstone |
| ClickHouse | append-only parts | 不保留版本 | mutation 重写 part | mutation / lightweight delete |
| Doris / StarRocks | append-only segments + delta | 不保留版本 | 整 batch 重写或写 delete bitmap | delete bitmap |
| Snowflake | immutable micro-partitions | 旧 micro-partition（Time Travel） | 写新 micro-partition | 同 |
| BigQuery | columnar capacitor | 不可变 storage block | streaming buffer + DML batch | 同 |
| Redshift | columnar + RA3 | 不保留行版本（block 级） | DELETE+INSERT | 软删除标记 |
| Greenplum | append-only / heap | 同 PG（heap 表） | 同 PG | 同 PG |
| Vertica | columnar projections | WOS + ROS | 删除向量（Delete Vector） | DV bitmap |
| Teradata | row store + Transient Journal | TJ | 原地改 + TJ | 删除 + TJ |
| DuckDB | 块式列存 + 行级标记 | 内存 undo 块 | 内存 undo + 写 | 标记 |
| MonetDB | 列存 + delta | delta 表 | 写新 | tombstone |
| Crate DB | Lucene 段（不可变） | 段不可变 | 写新文档 + 删旧 | 软删除 |
| Materialize | 流式 (key, ts, diff) | 物化视图增量保留 | (key, +1) + (key, -1) | (key, -1) |
| RisingWave | 流式 state | state store 多版本 | 写新 state | tombstone |

### 2. UNDO 段类型与定位

| 引擎 | UNDO 形式 | 存储位置 | 大小可调 | 后台清理 |
|------|----------|---------|---------|---------|
| MySQL InnoDB | undo log | 系统表空间 / undo tablespace | `innodb_max_undo_log_size`、5.6+ 独立 undo TS | purge 线程 |
| MariaDB InnoDB | 同 | 同 | 同 | 同 |
| Oracle | UNDO segment | UNDO tablespace（专用） | `UNDO_RETENTION`、autoextend | SMON / 自动管理 |
| SQL Server | version store | tempdb（共享） | tempdb 大小 | 后台 ghost cleanup |
| DB2 | currently committed | 内存中的"已提交"快照 | 不需显式管理 | -- |
| Informix | logical log | log buffers | log size | -- |
| H2 | 事务回滚日志 | 内存 | -- | 提交时丢弃 |
| HSQLDB | 内存 undo | 内存 | -- | 提交时丢弃 |
| SAP HANA | UndoFile | 持久化文件 | 可配置 | 后台 |
| TiDB | undo（在 TiKV 中） | RocksDB 默认 CF | 同 RocksDB | compaction |
| OceanBase | 多版本 row | memtable + sstable | -- | 合并 (merge) |
| PostgreSQL | 无独立 UNDO | 同 heap 文件 | -- | autovacuum |
| Firebird | 无 UNDO | 同表的 back-version | -- | sweep |
| CockroachDB | 无 UNDO | LSM 中的旧 (key, ts) | -- | GC + compaction |
| ClickHouse | 无 UNDO | -- | -- | -- |

### 3. PostgreSQL append-only 与 HOT update

| 维度 | 实现 | 说明 |
|------|------|------|
| 元组头大小 | 23 字节 + null bitmap | `HeapTupleHeaderData` 结构体 |
| xmin | 32 位 | 创建版本的事务 ID |
| xmax | 32 位 | 删除该版本的事务 ID（0 表示未删） |
| ctid | 6 字节 (block, offset) | 当前元组在文件中的位置 |
| t_cid | 32 位 (复用空间) | command id 用于自身可见性 |
| t_infomask / t_infomask2 | 16 + 16 位 | 一堆位标志（HOT、frozen、null bitmap 等） |
| HOT update | 8.3+ (2008) | 索引列未变 + 同页空间足够 → 链接 ctid |
| HOT chain | 同 page 内的 ctid 链 | 每个版本的 t_ctid 指向下一个版本 |
| Heap Only Tuple 标志 | t_infomask2 高位 | 区分 HOT 元组 |
| Index | 仅指向最早 (root) 元组 | HOT 链通过 root 走到最新 |
| Vacuum 清理 | dead tuple 标记空闲空间 | autovacuum / VACUUM |
| FREEZE | 32 位 xid 防 wraparound | xmin/xmax 替换为 FrozenXid |

### 4. MySQL InnoDB 行格式与 undo log

| 维度 | 实现 | 说明 |
|------|------|------|
| 行格式 | COMPACT / DYNAMIC / COMPRESSED / REDUNDANT | 默认 DYNAMIC（5.7+） |
| 隐藏列 1 | DB_TRX_ID (6 字节) | 最近修改该行的 trx_id |
| 隐藏列 2 | DB_ROLL_PTR (7 字节) | 指向 undo log 中前一版本 |
| 隐藏列 3 | DB_ROW_ID (6 字节) | 无 PK 时自动生成 |
| 聚集索引 | 主键 → 完整行 | 非主键索引存"二级索引 → PK"两段查找 |
| 行内更新 | in-place（同长度时） | 长度变化 → 写新行 + 旧行标记 |
| 行版本链 | DB_ROLL_PTR → undo record → 更早 undo record | 单向链表，每读旧版本回溯 N 跳 |
| Insert undo | undo log | 提交后立即丢弃（无需保留） |
| Update undo | undo log | 保留到所有旧 read view 关闭 |
| Delete undo | undo log + delete mark | purge 之前不能复用 |
| Purge 线程 | innodb_purge_threads | 4 默认（5.7+） |
| Undo TS | 独立 undo tablespace | 8.0+ 默认；支持 truncate |

### 5. Oracle ITL 与行格式

| 维度 | 实现 | 说明 |
|------|------|------|
| Block 头部 | block header + ITL 数组 | ITL = Interested Transaction List |
| ITL 槽位 | INITRANS / MAXTRANS | 每槽 24 字节，记录一笔事务的 lock + UBA |
| INITRANS 默认 | 1（数据块）/ 2（索引块） | 表示初始预留的并发槽数 |
| MAXTRANS | 现代版本固定 255 | 老版本可调 |
| UBA (Undo Byte Address) | 4 字节 | 指向 UNDO 段中的回滚记录 |
| Lock byte | 行 directory 中每行 1 字节 | 指向 ITL 槽位（0 = 不锁） |
| 行 directory | 块尾的偏移数组 | 每行 2 字节，指向行头 |
| Row piece | 链式行（chained / migrated） | 跨 block 时存 forward pointer |
| SCN | 每个 block / 行可携带 | block-level SCN + cleanout |
| Delayed Block Cleanout | 提交后不立刻清理 ITL | 下一次访问时清理 |
| UNDO segment | 自动 / 手动 (OUM/AUM) | 11g+ 强制 AUM (Automatic Undo Management) |

### 6. CockroachDB / TiKV LSM MVCC key 格式

| 维度 | CockroachDB (Pebble) | TiKV (RocksDB) |
|------|---------------------|----------------|
| Key 格式 | `/Table/<id>/<pk>/<ts>` | `<region_prefix>/<table>/<pk>` + ts 后缀 |
| Timestamp | HLC (96 位：64 位物理 + 32 位逻辑) | TSO (64 位：46ms + 18 logical) |
| 编码 | proto + key encoding | mvcc.Encode (memcomparable) |
| 行版本 | 同 key 不同 ts | 同 key 不同 ts |
| Tombstone | (key, ts) value 为空 | (key, ts) 标记 PUT 类型为 DELETE |
| Intent 写 | 单独的 intent record | Lock CF（独立列族） |
| GC | TTL + GC threshold | safe point + compaction filter |
| Compaction | Pebble L0~L6 | RocksDB L0~Lmax |
| 列族 | 单列族（Pebble） | 三列族：Default / Lock / Write |
| 编码细节 | crdb keys 包含 family id | TiKV write CF 存提交点指针 |

### 7. 其他引擎要点

| 引擎 | 关键事实 |
|------|----------|
| Spanner | 单元格 (row, column, ts) 三维数据；TrueTime 提交 ts |
| Snowflake | micro-partition (50–500MB) 不可变；Time Travel 1–90 天 |
| BigQuery | 列存 capacitor；DML 批量重写或 streaming buffer |
| Redshift | block-level（1MB）；DELETE 标记 + VACUUM 重排 |
| Vertica | ROS (Read Optimized Store) + WOS (Write)；Delete Vector 标记 |
| ClickHouse | MergeTree parts 不可变；UPDATE = mutation 重写 |
| Doris / StarRocks | rowset segment + delete bitmap |
| Iceberg | snapshot + manifest；equality / position delete files |
| Hudi | Copy-on-Write vs Merge-on-Read |
| Delta Lake | parquet + delta log；Z-order |
| ScyllaDB / Cassandra | LSM + tombstone + GC grace |
| Materialize | (key, value, ts, diff) 元组；arrangement |
| RisingWave | 状态后端 LSM + barrier |
| SAP HANA Column | delta store（行式）+ main store（列式压缩）|

## PostgreSQL：append-only 与 24 字节元组头

PostgreSQL 是"完全没有 UNDO"的代表。它的 MVCC 哲学很激进：每一笔 UPDATE 都生成一个新的 heap tuple，老 tuple 不动，只是把 xmax 设成当前 xid。读旧快照？沿着同一 page 上的旧 tuple 读就行。

### 元组头结构

```c
/* src/include/access/htup_details.h */
typedef struct HeapTupleHeaderData {
    union {
        HeapTupleFields t_heap;
        DatumTupleFields t_datum;
    } t_choice;            /* 12 字节 */
    ItemPointerData t_ctid; /* 6 字节：当前 tuple 的 (block, offset) */
    uint16 t_infomask2;     /* 2 字节：列数 + flags */
    uint16 t_infomask;      /* 2 字节：null/varlen/HOT 等 flags */
    uint8  t_hoff;          /* 1 字节：用户数据偏移 */
    /* 后接 null bitmap（可选）+ 用户数据 */
} HeapTupleHeaderData;

typedef struct HeapTupleFields {
    TransactionId t_xmin;   /* 4 字节：插入该 tuple 的 xid */
    TransactionId t_xmax;   /* 4 字节：删除该 tuple 的 xid（0 = 未删） */
    union {
        CommandId t_cid;    /* 4 字节：cmin/cmax，用于自身可见性 */
        TransactionId t_xvac; /* 4 字节：早期 VACUUM FULL 用 */
    } t_field3;
} HeapTupleFields;
```

合计 23 字节固定 + null bitmap，按 MAXALIGN（8）对齐到 24 字节。这就是 PG 经典文献中常说的"24-byte tuple header"。

### xmin / xmax 的可见性判断

```sql
-- 查询元组的 xmin/xmax 内部列（系统列）
SELECT xmin, xmax, ctid, * FROM users WHERE id = 1;
-- xmin=12345 xmax=0  ctid=(0,1)  id=1 ...

-- 更新一行
UPDATE users SET name = 'Alice' WHERE id = 1;

-- 现在能看到两个 tuple（不同 xmin）
SELECT xmin, xmax, ctid, * FROM users WHERE id = 1;
-- 当前事务能看到的是新 tuple：xmin=12346 xmax=0 ctid=(0,2) id=1 name=Alice

-- 老 tuple 还在 page 上：xmin=12345 xmax=12346 ctid=(0,1)
-- 但对当前快照不可见（xmax 在快照之前）

-- 可见性规则（极简化）:
--   visible(t) = (xmin committed AND xmin <= snapshot.xmax)
--                AND (xmax == 0 OR xmax > snapshot.xmin OR xmax aborted)
```

### HOT update（自 8.3，2008 年）

经典 PG 模型有个痛点：每次 UPDATE 都要写新 tuple，连**所有**索引都要写新 entry（即使列值没变），index bloat 极快。

8.3 引入 HOT (Heap Only Tuple)：

```
HOT 触发条件:
1. UPDATE 不修改任何索引列
2. 同一 page 上有空闲空间足够放新 tuple

HOT 行为:
1. 新 tuple 写在同一 page，标记 HEAP_ONLY_TUPLE
2. 老 tuple 的 t_ctid 指向新 tuple，标记 HEAP_HOT_UPDATED
3. 索引仍指向老 tuple（root tuple）
4. 读取时索引找到 root → 沿 t_ctid 链走到最新可见 tuple

效果:
- 索引完全不变（避免 index bloat）
- 老 tuple 在 vacuum 时可被回收（不需要重建索引）
- 同 page 内的 HOT chain 形成短链表
```

```
Page layout（HOT chain 示例）:

   +-------+-------+-------+-------+
   | tup1  | tup2  | tup3  | free  |
   |       |       |       |       |
   +-------+-------+-------+-------+

   tup1: xmin=100 xmax=200 t_ctid=(this, 2)  HEAP_HOT_UPDATED
   tup2: xmin=200 xmax=300 t_ctid=(this, 3)  HEAP_ONLY_TUPLE | HOT_UPDATED
   tup3: xmin=300 xmax=0   t_ctid=(this, 3)  HEAP_ONLY_TUPLE  (最新)

   索引项: id=1 → ctid=(page, 1)  (始终指向 root)
   读取流程: 索引 → tup1 → tup2 → tup3 (找到可见版本)
```

### page header 与 line pointer

```c
/* src/include/storage/bufpage.h */
typedef struct PageHeaderData {
    PageXLogRecPtr pd_lsn;         /* 8 字节：last LSN */
    uint16  pd_checksum;            /* 2 字节 */
    uint16  pd_flags;               /* 2 字节 */
    LocationIndex pd_lower;         /* 2 字节：line pointer 末尾 */
    LocationIndex pd_upper;         /* 2 字节：tuple 起始（向下增长） */
    LocationIndex pd_special;       /* 2 字节：特殊空间 */
    uint16  pd_pagesize_version;    /* 2 字节 */
    TransactionId pd_prune_xid;     /* 4 字节：HOT prune 用 */
    ItemIdData pd_linp[FLEXIBLE];   /* line pointer 数组 */
} PageHeaderData;
/* 24 字节 page header */

typedef struct ItemIdData {
    uint32 lp_off:15,    /* tuple 在 page 内偏移 */
           lp_flags:2,   /* UNUSED / NORMAL / REDIRECT / DEAD */
           lp_len:15;    /* tuple 长度 */
} ItemIdData;            /* 4 字节 line pointer */
```

`lp_flags` 的四种状态对 HOT 关键：

- `LP_NORMAL`: 正常 tuple
- `LP_REDIRECT`: 指向 HOT chain 内的下一个 line pointer（HOT prune 后留下的"重定向"）
- `LP_DEAD`: 已知死亡，等 vacuum 回收
- `LP_UNUSED`: 已回收，可复用

```sql
-- 查 page 内部
SELECT * FROM heap_page_items(get_raw_page('users', 0));
--  lp | lp_off | lp_flags | lp_len | t_xmin | t_xmax | t_ctid | t_data
--  1  | 8160   | 1        | 32     | 100    | 200    | (0,2)  | ...
--  2  | 8128   | 1        | 32     | 200    | 0      | (0,2)  | ...
```

## MySQL InnoDB：聚集索引 in-place + undo log

InnoDB 是"经典 in-place + UNDO"流派的代表。它的哲学是：当前版本永远是 page 上的那一行，旧版本通过 undo log 链回溯。

### 行格式概述

```
DYNAMIC 行格式 (InnoDB 5.7+ 默认):

  [variable-length 字段长度数组]   <- 变长字段长度（1 或 2 字节每列）
  [NULL bitmap]                    <- 每列 1 bit
  [Record header (5 字节)]
    info_flags(4 bit)              <- delete mark / min rec
    n_owned(4 bit)                 <- 跳跃记录数
    heap_no(13 bit)                <- 在 page 内的位置
    record_type(3 bit)             <- conventional / node / supremum / infimum
    next_record(2 bytes)           <- 同 page 内下一记录偏移
  [DB_TRX_ID (6 字节)]             <- 最近修改该行的 trx_id
  [DB_ROLL_PTR (7 字节)]           <- 指向 undo log
  [DB_ROW_ID (6 字节, 可选)]       <- 无 PK 时的内部行 ID
  [用户列数据]
```

DB_ROLL_PTR 7 字节内部结构：

```
[is_insert(1 bit) | rseg_id(7 bit) | page_no(4 字节) | offset(2 字节)]

  is_insert: 1 表示 insert undo（可立即丢弃），0 表示 update undo
  rseg_id:   rollback segment 编号（默认 128 个，5.7+）
  page_no:   undo log 所在的 page
  offset:    undo log record 在 page 内的偏移
```

### Undo log 链

```
Page 上当前行（最新版本）:
  trx_id=300, roll_ptr=Undo[100, 16] -> 用户列: id=1 name='Charlie' age=30

Undo log:
  Undo[100, 16] (update_undo, type_cmpl):
    trx_id=200            <- 上一版本的 trx_id
    roll_ptr=Undo[99, 32] <- 上一版本的 roll_ptr
    被修改的列旧值:
      name='Bob'          <- diff 编码（仅记录变化的列）
    主键: id=1

  Undo[99, 32] (update_undo):
    trx_id=100
    roll_ptr=Undo[NULL]   <- 链尾
    被修改的列旧值:
      name='Alice', age=29
    主键: id=1

读取旧版本流程:
1. 取当前行 (trx_id=300)
2. 不可见 -> 沿 roll_ptr 跳到 Undo[100, 16]
3. 重建版本 = 当前行 - Undo 记录的 diff
4. 检查可见性 (trx_id=200) -> 不可见
5. 继续沿 Undo[99, 32] 重建
6. 直到找到可见版本或链尾
```

### Update 的 in-place vs 写新行

```
in-place update:
  - 长度不变（如 INT, CHAR, 同长度 VARCHAR）
  - 直接在 page 上修改字节
  - 写 update_undo 记录旧值
  - delete + insert 两个 undo 不需要

非 in-place（必须新行 + 标记旧行）:
  - 长度变化（短 VARCHAR -> 长 VARCHAR）
  - 主键变化（极少）
  - 可变长溢出（off-page BLOB）

非 in-place 路径:
  1. 把旧行标记 delete-mark（info_flags |= REC_DELETED）
  2. 在合适位置插入新行
  3. 写两条 undo（delete-mark undo + insert undo）
```

### Purge 线程

```
purge 的工作:
1. 真正删除 delete-mark 的行
2. 回收 undo log 空间
3. 维护 history list 长度（trx_rseg->history_size）

purge 不能动什么:
  仍被某个活跃 read view 引用的 undo
  (history list 长度暴涨 -> long-running transaction 警告)

innodb_max_purge_lag:
  限制 history list 长度，超过时延迟新事务（保护 vacuum 不堆积）

innodb_purge_threads:
  4 默认（5.7+），多线程并行 purge
```

## Oracle：ITL 槽位 + UNDO tablespace

Oracle 的实现是三大商业引擎中最精致的。它把"行级锁信息"塞进了每个数据 block 头部的 **ITL (Interested Transaction List)** 槽位，而旧版本走独立的 UNDO 表空间。

### Block header 与 ITL

```
Oracle Data Block (默认 8KB) 布局:

+----------------------------------+
| block header (公共头, ~30 字节)    |
| flag, format, type, RDBA, SCN    |
+----------------------------------+
| ITL 数组 (INITRANS 个槽, 每槽 24 字节) |
|   slot 0: xid, UBA, lock flags, fsc, scn |
|   slot 1: ...                    |
|   ...                            |
+----------------------------------+
| 表头 (table dir, ~4 字节)         |
+----------------------------------+
| 行 directory (每行 2 字节)        |
|   row 0 offset                   |
|   row 1 offset                   |
|   ...                            |
+----------------------------------+
| 空闲空间                         |
| (可双向增长)                      |
+----------------------------------+
| 行数据 (从底部向上增长)            |
|   row N: lock byte | flag | ncols | col data... |
|   ...                            |
+----------------------------------+
| tail (校验, 4 字节)               |
+----------------------------------+
```

每个 ITL 槽 24 字节，包含：

- **Xid (10 字节)**: 事务 ID（usn + slot + wrap）
- **Uba (8 字节)**: Undo Block Address，指向该事务的最近一笔 UNDO 记录
- **Flag/lck (2 字节)**: 标志位 + 该 ITL 占有的行锁数量
- **scn/fsc (4 字节)**: SCN（已提交）或 free space credit（未提交）

### 行的 lock byte

```
每行的 row header 第一字节是 lock byte:
  lock byte = 0     -> 该行未被锁
  lock byte = N     -> 该行被 ITL 槽 N 持有的事务锁住

读取一行时:
1. 解析行 directory 找到行偏移
2. 读 row header 的 lock byte
3. 如果非 0，找到对应 ITL 槽
4. 槽中 xid 表示锁主，UBA 指向回滚段
5. 通过 UBA 读 UNDO 重建旧版本（如果需要）
```

INITRANS 与 MAXTRANS：

```sql
-- 建表时指定
CREATE TABLE t (...) INITRANS 4 MAXTRANS 255;
-- INITRANS 4: 每个 block 预留 4 个 ITL 槽
-- 多于 4 个并发事务想锁同 block 的行时:
--   block 还有空闲空间 -> 新增 ITL 槽（消耗空闲空间）
--   block 已无空闲 -> ITL contention（事务等待）
```

### Delayed Block Cleanout

```
Oracle 提交时的"懒清理":

提交时:
1. 写 commit redo
2. 释放锁、清理 ITL 槽... 但是！如果 block 当前不在 buffer cache：
   不写回那个 block
   ITL 仍然指向已提交事务的 UBA

下次有人访问该 block:
1. 读 block 进 buffer
2. 发现 ITL 槽中事务已不存在（active TX list 中查不到）
3. 通过 UBA 读 UNDO 头部确认提交 + SCN
4. 修正 ITL 中的 SCN（写脏页）
5. 释放锁

好处: commit 不需要等待 block 刷盘
代价: 第一次访问的查询会触发"延迟块清理"（产生 redo!）
```

### UNDO segment 与 UNDO_RETENTION

```sql
-- AUM (Automatic Undo Management) 默认开启 (11g+)
ALTER SYSTEM SET UNDO_RETENTION = 900;  -- 秒，旧版本保留下限

-- 报错 ORA-01555 "snapshot too old":
-- 当 UNDO 被覆盖、旧版本无法重建时抛出
-- 修复: 增大 UNDO_RETENTION 或 UNDO 表空间

-- UNDO 内部组织:
--   UNDO segment header
--     transaction table（活跃 + 最近已提交事务的列表）
--   UNDO data blocks
--     每个 block 包含若干 undo records
--     按 SCN 反向链接
```

## CockroachDB Pebble：MVCC key 直接编码 timestamp

CockroachDB（以及 TiKV、YugabyteDB）走的是"LSM 中嵌入 MVCC"路线：每个行版本是 LSM 的 key/value，key 后缀编码 timestamp，compaction 时清理过期版本。

### MVCC key 格式

```
CockroachDB MVCC key（简化）:
  /Table/<id>/<index_id>/<pk_columns>/<timestamp>

  Table id:        4 字节（或 varint）
  Index id:        通常 1（主索引）
  PK columns:      memcomparable 编码
  Timestamp:       12 字节（HLC: 8 wall + 4 logical）

实际 key 示例（pk=1, ts=100.0）:
  /Table/53/1/1/100.0

不同 timestamp 的同一行版本是不同 LSM key:
  /Table/53/1/1/200.0  -> {name: "Charlie"}  最新
  /Table/53/1/1/150.0  -> {name: "Bob"}
  /Table/53/1/1/100.0  -> {name: "Alice"}    最旧

读取 ts=180 的快照:
  Pebble seek 到 /Table/53/1/1/180.0
  迭代器返回第一个 ts <= 180 的 key（即 ts=150 的 Bob）
  完美 ts-based MVCC，不需要 UNDO
```

### Tombstone

```
DELETE 时:
  写一个 (key, ts) 的空 value（或 metadata-only key）
  GC 之前读快照仍能看到旧版本
  GC 后所有 ts <= GC threshold 的 key 都被 compaction 丢弃
```

### Intent 与提交

```
Pending write（事务未提交）:
  写 intent record（包含 transaction record 引用）
  其他事务读到 intent 时，去查 transaction record 是否提交

提交时:
  把 intent 转成正式的 (key, ts) 行版本
  CockroachDB: parallel commit + commit intent resolve

GC threshold:
  默认 25 小时
  老于 threshold 的所有版本被 compaction 丢弃
```

### TiKV 的三列族

```
TiKV 在 RocksDB 上分了三个 Column Family:

Default CF:
  长 value 存这里
  key = encoded_key + ts

Lock CF:
  pending lock 写这里
  事务两阶段提交期间持有

Write CF:
  提交点存这里
  key = encoded_key + commit_ts
  value = (start_ts, write_type, short_value?)
  其中 short_value 可以放小 value 内联（避免一次 default CF 访问）

读取流程:
1. 在 Lock CF 检查 pending lock（resolve if blocking）
2. 在 Write CF 找 commit_ts <= read_ts 的最新 entry
3. 通过 entry 中的 start_ts 反查 Default CF（如果不是 short_value）
```

## SQL Server：in-place + tempdb version store

SQL Server 是商业引擎中"两个时代"的代表：默认仍是悲观锁 + 当前版本（无 MVCC），但启用 RCSI（Read Committed Snapshot Isolation）或 SI（Snapshot Isolation）后才提供 MVCC。

### Version store

```
启用 RCSI/SI 后:

每行追加 14 字节 versioning info:
  XSN (Transaction Sequence Number, 6 字节)
  Pointer to row version in tempdb (8 字节)

UPDATE 时:
1. 把当前行复制到 tempdb 的版本存储
2. 在 page 上原地改
3. 把 versioning info 指向 tempdb 中的副本
4. 老版本指向更老版本（链表）

读取（在 SNAPSHOT 隔离）:
1. 找到行
2. 检查 XSN 与当前事务时间戳
3. 如果版本不可见，沿链表跳到 tempdb 中的旧版本
```

注意：

- tempdb 是全实例共享的，长事务可能撑爆 tempdb
- ghost cleanup 后台任务回收过期版本
- 14 字节 versioning info 会让每行变大（启用 RCSI 后初次重建表才生效）

## SAP HANA：列存 main + 行式 delta

HANA 列存的版本组织是独特的两层模型：

```
Main store（列式，压缩）:
  按列分块，pdict（字典）+ pcol（数值）+ visibility flag
  不可变，新版本不写这里

Delta store（行式，未压缩）:
  最近修改的行
  支持 in-place update + undo

UPDATE:
1. 在 main store 中标记老行不可见（visibility bitmap = 0）
2. 在 delta store 中插入新行
3. 写一份 undo 用于回滚

Merge 任务（后台）:
  把 delta store 合并进 main store
  重新构建字典 + 压缩
```

## ClickHouse：append-only + mutation

ClickHouse 没有 row-level MVCC：

```
MergeTree 引擎:
  数据按 part 组织（不可变文件夹）
  INSERT 写新 part
  Background merge 把多个 part 合成大 part

UPDATE 不是行级:
  ALTER TABLE ... UPDATE ... WHERE ... 是 mutation
  整个 part 的相关列被重写
  原 part 标记为 outdated -> 后台删除

DELETE:
  ALTER TABLE ... DELETE WHERE ... 同样是 mutation
  Lightweight DELETE（22.8+）写 delete bitmap，读时跳过

后果:
  没有"小批量 UPDATE"的低成本路径
  适合 append-heavy + 偶尔 mutation 的负载
```

## TiDB Percolator + TiKV write CF

```
TiDB 的事务模型基于 Percolator (Google):
  Two-phase commit (Prewrite + Commit)
  使用 TSO (PD 集中分配) 作为时间戳

行版本存储在 TiKV 的 Write CF:
  key = encode(key) + commit_ts
  value = (write_type, start_ts, short_value)

write_type:
  PUT     -> 提交一个 PUT
  DELETE  -> 提交一个 DELETE (tombstone)
  LOCK    -> 锁的 commit 标记
  ROLLBACK -> 回滚标记

读取流程 (start_ts):
1. seek 到 (key, start_ts) 之前最大的 commit_ts
2. 解析 entry 拿到 start_ts
3. 通过 (key, start_ts) 找 default CF 中的实际 value
```

## YugabyteDB DocDB

```
YugabyteDB 的 DocDB 在 RocksDB 上:
  每个文档（行）是若干 SubDocKey
  SubDocKey = doc_key + subkey_path + hybrid_time

文档的列变成多个 KV 对:
  (doc_key/col1, ht=100) -> "Alice"
  (doc_key/col2, ht=100) -> 30
  (doc_key/col1, ht=200) -> "Bob"   <- col1 更新

读取 ht=150 的快照:
  对每个 SubDocKey seek 到 ht <= 150 的最新 entry
  组装成完整文档
```

## 设计争议

### append-only 的两难

PostgreSQL 选择 append-only 的代价：

- bloat：UPDATE 留下死元组，需要 vacuum
- 索引仍可能 bloat（HOT 不命中时）
- vacuum 本身是负担（IO + CPU + 锁）

收益：

- UPDATE 简单，rollback 等于"不做事"
- 没有 UNDO 段管理负担
- 长事务对其他写不构成阻塞（不会撑爆 UNDO）

### in-place + UNDO 的两难

InnoDB / Oracle 选择 in-place + UNDO 的代价：

- UNDO 表空间需要管理大小
- 长事务会撑爆 UNDO（ORA-01555、history list 暴涨）
- rollback 需要重放 UNDO（慢）

收益：

- UPDATE 不留死元组（page 紧凑）
- 索引列未变时索引完全不动
- 当前版本读取无需追链（首读最快）

### LSM + ts 的两难

CockroachDB / TiKV 的 LSM + ts 设计：

- compaction 取代 vacuum/purge
- 没有 UNDO，rollback 通过 abort 状态隐式解决
- read amplification（同 key 多版本）
- 大量历史版本时 LSM 高度增加

### HOT 的局限

HOT 是 PG bloat 的关键缓解，但有两个硬限制：

1. 只对"非索引列 UPDATE"有效
2. 同 page 必须有空闲（fillfactor 太满 → HOT 失败）

工程实践常用 `WITH (fillfactor=70)` 给 HOT 留空间，代价是 30% 空间浪费。

### tempdb version store 的脆弱

SQL Server 的 RCSI 把版本扔到全实例共享 tempdb：

- 一个长事务能拖垮整个实例
- tempdb 故障 = 所有 RCSI 数据库不可用
- ghost cleanup 是后台单线程

### Oracle ITL 槽位的隐式成本

INITRANS 设置过低 + 高并发更新：

- 新事务尝试加锁 → 没有 ITL 槽 → 申请新槽（消耗 free space）
- 如果 free space 也不够 → enq: TX - allocate ITL entry 等待
- 老 OLTP 系统经常需要把 INITRANS 调到 8 或 16

### CockroachDB GC threshold 与 Long-running query

```
GC threshold 默认 25 小时:
  老版本超过 25 小时被 compaction 丢
  但是！如果有 30 小时的 long-running 分析查询正在跑:
    需要的旧版本已被 GC -> "transaction retry" 错误
    需要把 gc.ttlseconds 调高（代价：bloat）
```

## 对引擎开发者的实现建议

### 1. 选哪种存储模型

```
负载特征 -> 推荐:
  OLTP，UPDATE 多、行短、热点行 -> in-place + UNDO (InnoDB / Oracle)
  分析为主、长事务、读多 -> append-only (PG) 或 LSM (Cockroach)
  写多、几乎只 INSERT、列存 -> append-only parts (ClickHouse / Doris)
  分布式、一致性优先 -> LSM + global timestamp (TiKV / YugabyteDB)
```

### 2. 元组头大小是核心设计点

```
PG: 24 字节 (+ null bitmap) -> 大但功能完整
InnoDB: 5 + 6 + 7 = 18 字节 (+ DB_ROW_ID 6 字节如果无 PK) -> 紧凑
SQL Server (RCSI): 14 字节附加（仅启用版本时）

决策点:
  xmin/xmax 都直接存 -> 简单但占空间（PG 路径）
  只存 trx_id + roll_ptr -> 紧凑但读旧版本要追链（InnoDB 路径）
  存 ts + LSM 嵌入 -> 不需要元组头扩展（LSM 路径）
```

### 3. UNDO 段大小管理

```
设计要点:
1. 独立表空间（不要混在系统表空间，否则爆炸）
2. UNDO_RETENTION 与 history list 配套
3. 必须有"老 read view 找不到 UNDO" 的明确报错（ORA-01555）
4. 不能让 UNDO 无限增长 -> 监控 + 告警 + 自动 truncate
```

### 4. HOT-style 优化的实现要点

```
触发判断（每次 UPDATE 时）:
  if 没有索引列变化:
    if 同 page 有空闲 >= 新 tuple 大小:
      做 HOT
    else:
      普通 UPDATE
  else:
    普通 UPDATE

prune 时机:
  page 第一次被访问时
  vacuum 时
  HOT prune 把 dead chain 折叠成 redirect

测试:
  长链测试: 同行连续 UPDATE 100 次 -> 链不应无限增长
  prune 后 ctid 重定向是否正确
```

### 5. ITL 风格行级锁的开销

```
优势:
  锁信息内嵌在 page 中 -> 锁查询不需要全局锁表
  并发度高（一个 page 可同时被 N 个事务持有不同行的锁）

代价:
  每个 page 多 INITRANS * 24 字节
  ITL 不够时阻塞（INITRANS 调优很关键）
  delayed block cleanout 在大量提交后会有延迟成本

决策:
  短事务、高并发热点页 -> ITL 风格
  长事务、批量更新 -> 全局锁表更简单
```

### 6. LSM MVCC key 的设计

```
key 格式选择:
  table_id + pk + ts (CockroachDB 风格)
    优点: 简单
    缺点: 行级 (整行一个 KV)，update 任何列都要写完整行

  table_id + pk + col + ts (YugabyteDB 风格)
    优点: 列级 update 只写一个 KV
    缺点: read 时需多次 seek（每列）

ts 编码:
  反向编码（大 ts 排在前）-> seek to <= ts 是单次 seek
  正向编码 -> 需要 reverse iterator

intent / lock 处理:
  独立 CF (TiKV) -> 隔离干扰
  intent 嵌入主 CF (CockroachDB) -> 单 CF 管理
```

### 7. tombstone 与 GC 的协同

```
tombstone 不能立即删:
  需要保证读快照看到"已删除"
  (老版本 + tombstone 都还在时，读取看到 tombstone 然后跳过)

GC threshold 设计:
  全局最小 read ts -> 该 ts 之前的版本都可丢
  TiKV: safe point（PD 维护）
  CockroachDB: closed timestamp + GC ttl

陷阱:
  长事务持有老 read ts -> GC 卡住
  推荐: 监控 + 报警 + 长事务自动 abort
```

### 8. 行版本可见性判断的优化

```
PostgreSQL HeapTupleSatisfiesMVCC 流程:
  XidInMVCCSnapshot -> 检查 xid 是否在 snapshot.xip 中
  TransactionIdDidCommit -> 查 CLOG（commit log）
  TransactionIdDidAbort  -> 同上

性能关键:
  CLOG 命中率（buffered page）
  visibility map（页级"全可见"标志，跳过 row 检查）
  hint bits（首读时缓存提交状态在 t_infomask）

InnoDB Read View 流程:
  对比 trx_id 与 view.up_limit / low_limit
  在 m_ids 中查找（小表 binary search）
  追链（最多 N 跳）

LSM 流程:
  seek to (key, ts <= read_ts)
  iterator next（同 key 不同 ts）
  resolve intent（如果撞到 lock CF）
```

### 9. 长事务保护机制

```
所有 MVCC 引擎的共同问题: 长事务卡 GC

防御:
1. 监控 oldest_active_xid / oldest_read_ts
2. 设置 statement_timeout / idle_in_transaction_session_timeout
3. 报警：history list 长度 / undo segment 占用 / GC backlog
4. 自动 abort（PG 14+ idle_session_timeout）
5. 慢 vacuum / purge 单独监控
```

### 10. 索引可见性的两条路径

```
路径 A: 索引仅指向最早 (root) 元组（PG / HOT）
  + 索引列未变时索引不需更新
  - 读取需追链找最新版本

路径 B: 索引指向每个版本（InnoDB 二级索引早期）
  + 读取直接命中
  - 每次 UPDATE 都更新索引（即使列未变）

InnoDB 二级索引的折中:
  二级索引存"二级 key + PK"
  通过 PK 回聚集索引找最新（多一次 IO，但避免索引每次都改）
```

## 总结对比矩阵

### 行版本存储模型一览

| 引擎 | 存储模型 | 元组头 | UNDO 形式 | HOT-like | 维护机制 |
|------|---------|--------|----------|----------|---------|
| PostgreSQL | append-only heap | 24 字节 | 无 | HOT (8.3+) | autovacuum |
| MySQL InnoDB | in-place + undo | 18+ 字节 | undo log | -- | purge thread |
| Oracle | in-place + ITL + UNDO | 24 字节 ITL/槽 | UNDO TS | -- | SMON / AUM |
| SQL Server (RCSI) | in-place + version store | 14 字节附加 | tempdb | -- | ghost cleanup |
| DB2 | in-place + log + CC | 平坦 | currently committed | -- | -- |
| SQLite | in-place + journal | 平坦 | rollback journal | -- | 提交丢弃 |
| SAP HANA Row | in-place + version vector | 平坦 | 内存 | -- | -- |
| SAP HANA Column | append + delta | bitmap visibility | delta | -- | merge |
| Firebird | append (back-version) | 平坦 | 同表 | -- | sweep |
| CockroachDB | LSM (Pebble) | 由 ts 编码 | 无 | -- | GC + compaction |
| TiKV | LSM (RocksDB) | 三 CF 编码 | 无 | -- | safe point |
| YugabyteDB | LSM (DocDB) | SubDocKey | 无 | -- | compaction |
| Spanner | LSM-like | (row, col, ts) | 无 | -- | -- |
| OceanBase | LSM (memtable+sstable) | 多版本 row | redo + sstable | -- | merge |
| ClickHouse | append-only parts | 无 MVCC | -- | -- | mutation merge |
| Doris/StarRocks | rowset + delete bmap | -- | -- | -- | compaction |
| Vertica | ROS + WOS + DV | -- | -- | -- | merge-out |
| Snowflake | immutable micro-part | -- | Time Travel | -- | -- |
| Materialize | (key, ts, diff) | -- | -- | -- | logical compaction |

### 引擎选型建议

| 场景 | 推荐流派 | 代表引擎 | 理由 |
|------|---------|---------|------|
| OLTP 高并发热点行 | in-place + UNDO | InnoDB / Oracle | 行短 + UPDATE 简单 |
| 写少读多 + 长事务报表 | append-only | PostgreSQL | 长读不卡写 |
| 极高写入 + 弱一致性 | LSM | Cassandra / Scylla | 顺序写 + compaction |
| 全球分布 + 强一致性 | LSM + 全局 ts | Spanner / Cockroach | TrueTime / HLC |
| 分析为主 OLAP | append-only parts | ClickHouse / Doris | 不需要行级 MVCC |
| 列存 + 偶尔点更新 | main + delta | SAP HANA | 写小 / 读大 |
| 时序 / append-only | LSM 或 part | TimescaleDB / QuestDB | 时间分区 |

## 关键发现

1. **没有一种存储格式适合所有负载**：append-only 适合长读和复杂事务；in-place + UNDO 适合短事务高并发；LSM 适合写多 + 全局一致；append-only parts 适合列存分析。

2. **元组头大小是隐藏成本**：PostgreSQL 的 24 字节元组头让小表浪费严重（1 行 user 表 = 24 字节头 + 几十字节数据，元数据占比可超 30%）；InnoDB 的 18 字节相对紧凑；LSM 引擎完全没有"元组头"概念，但 key 编码会包含 ts。

3. **HOT 是 append-only 的关键性能优化**：PG 8.3 (2008) 引入后，索引未变的 UPDATE 不再产生索引 bloat。但 HOT 命中率高度依赖 fillfactor 和数据访问模式。

4. **UNDO 表空间管理是 in-place 引擎的运维痛点**：Oracle ORA-01555、MySQL history list 暴涨、长事务拖死 UNDO 是 OLTP 运维的高频问题。

5. **LSM + 全局 timestamp 是分布式 MVCC 的最优解**：CockroachDB / TiKV / YugabyteDB / Spanner 都采用这种架构。代价是 read amplification 和 compaction 写放大。

6. **ITL 槽位是 Oracle 独有的精致设计**：把行级锁信息嵌入 block 头部，避免全局锁表。但 INITRANS 调优对热点页性能至关重要。

7. **没有 MVCC 不等于差**：ClickHouse 这类 OLAP 引擎完全放弃行级 MVCC，UPDATE/DELETE 通过 mutation 重写 part，简化了引擎实现且适合大批量分析负载。

8. **vacuum / purge / compaction 都是同一个问题的不同面**：旧版本何时清理、清理时是否阻塞读写、清理粒度（行 / page / part / row group）的选择决定了引擎的可运维性。

9. **PG 的 append-only 哲学影响深远**：Greenplum、Yellowbrick、Redshift（早期）、CockroachDB（逻辑层）都继承了 PG 的可见性模型，但底层存储各不相同。

10. **HLC vs TSO vs TrueTime 决定了 LSM ts 编码**：CockroachDB 用 HLC（96 位），TiKV 用 TSO（64 位 PD 分配），Spanner 用 TrueTime（带不确定窗口）。这三种全局 ts 设计直接影响 MVCC key 的编码长度和读路径。

## 参考资料

- PostgreSQL: [Storage Page Layout](https://www.postgresql.org/docs/current/storage-page-layout.html)
- PostgreSQL: [Heap-Only Tuples (HOT)](https://github.com/postgres/postgres/blob/master/src/backend/access/heap/README.HOT)
- MySQL: [InnoDB Row Formats](https://dev.mysql.com/doc/refman/8.0/en/innodb-row-format.html)
- MySQL: [InnoDB Undo Log](https://dev.mysql.com/doc/refman/8.0/en/innodb-undo-logs.html)
- Oracle: [Logical Storage Structures - Block Format](https://docs.oracle.com/en/database/oracle/oracle-database/19/cncpt/logical-storage-structures.html)
- Oracle: [Automatic Undo Management](https://docs.oracle.com/en/database/oracle/oracle-database/19/admin/managing-undo.html)
- SQL Server: [Row Versioning Resource Usage](https://learn.microsoft.com/en-us/sql/relational-databases/sql-server-transaction-locking-and-row-versioning-guide)
- CockroachDB: [Architecture - Storage Layer](https://www.cockroachlabs.com/docs/stable/architecture/storage-layer.html)
- TiKV: [MVCC in TiKV](https://docs.pingcap.com/tidb/stable/tidb-storage)
- YugabyteDB: [DocDB - Persistence](https://docs.yugabyte.com/preview/architecture/docdb/persistence/)
- Spanner: [Truetime and External Consistency](https://cloud.google.com/spanner/docs/true-time-external-consistency)
- ClickHouse: [MergeTree Storage Engine](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/mergetree)
- SAP HANA: [Storage Architecture](https://help.sap.com/docs/SAP_HANA_PLATFORM)
- Vertica: [Hybrid Storage Model (WOS+ROS)](https://docs.vertica.com/)
- Hellerstein, Stonebraker, Hamilton. "Architecture of a Database System" (2007)
- Mohan et al. "ARIES: A Transaction Recovery Method" (1992)
- Ports, Grittner. "Serializable Snapshot Isolation in PostgreSQL" (VLDB 2012)
- Corbett et al. "Spanner: Google's Globally-Distributed Database" (OSDI 2012)
