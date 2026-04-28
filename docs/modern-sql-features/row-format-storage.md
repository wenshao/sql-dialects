# 行格式与物理存储 (Row Format and Physical Storage)

同一张表，存储到磁盘上之后，每一行长什么样？是固定长度的紧密数组，还是带 NULL 位图、变长字段偏移和溢出指针的复杂结构？这个看似底层的细节，决定了一张表在磁盘上的体积、缓冲池命中率、UPDATE 的写放大、宽表的 LOB 性能，甚至决定了 `ALTER TABLE ADD COLUMN` 是否能秒级完成。

## 没有 SQL 标准

SQL:92 到 SQL:2023 从未对"行在数据页内如何编码"做出任何规定。标准只关心三件事：

1. 列的逻辑顺序（用于 `SELECT *` 输出和位置访问）
2. NULL 的逻辑语义（三值逻辑）
3. 数据类型的最大长度

而以下问题统统是实现相关的：

- 行的物理布局是 fixed-length array、TLV (tag-length-value)、还是分段的 (header + null-bitmap + offsets + payload)？
- NULL 用 1 bit 位图表示，还是占用完整列宽并加一个标志位？
- 变长列存内嵌长度前缀，还是放偏移数组在行头？
- 超过页大小的字段如何溢出（TOAST、LOB tablespace、blob page）？
- 列的物理顺序是否与逻辑顺序一致？引擎是否会重排以减少对齐填充？
- DROP COLUMN 是物理删除还是仅元数据标记？

这些选择共同构成了一个数据库引擎的"行格式 (row format)"。Antelope vs Barracuda、PLAIN vs EXTENDED、FIXED vs DYNAMIC——名称千差万别，背后的工程权衡却高度一致：**用元数据换密度、用密度换访问速度**。

## 核心概念

### 行头 (Row Header)

```
通用行头组成（不同引擎位段不同）:
  - 事务/MVCC 元数据 (xmin/xmax, trx_id, undo pointer)
  - 长度字段 (整行长度 / 列数量)
  - NULL 位图 (1 bit per nullable column)
  - 变长偏移数组 (offset to each variable-length column)
  - 标志位 (deleted, migrated, redirected)
  - 校验和 (optional checksum)
```

不同引擎的行头开销差异巨大：

- PostgreSQL heap tuple header 固定 23 字节 (HeapTupleHeaderData)，外加 NULL 位图
- MySQL InnoDB COMPACT 行头 5 字节 + 变长长度数组 + NULL 位图
- MySQL InnoDB REDUNDANT 行头 6 字节，无 NULL 位图（NULL 列也占空间）
- Oracle 行头 3 字节 + 列数 + 列长度数组 (每列 1-3 字节)
- SQL Server 行头 4 字节 + NULL 位图 + 变长列计数 + 变长偏移数组

### NULL 位图 (Null Bitmap)

```
高密度 NULL 表示:
  对于 N 个可空列, 用 ceil(N/8) 字节存储位图
  bit i = 1 表示第 i 列为 NULL, 列内容不占空间

不使用 NULL 位图的代价:
  - InnoDB REDUNDANT: NULL 列占完整列宽
  - 一些早期引擎: NULL 用特殊魔数 (-1, 0xFF) 表示, 类型有限
```

### 变长字段编码 (Variable-Length Encoding)

```
方案 A: 长度前缀 (length-prefixed)
  [len][data][len][data]...
  优点: 顺序解析简单
  缺点: 随机访问第 N 列需扫描前 N-1 列

方案 B: 偏移数组 (offset array in header)
  Header: [offset1][offset2]...[offsetN]
  Data:   [col1_data][col2_data]...
  优点: O(1) 随机列访问
  缺点: 行头开销随列数线性增长

方案 C: 混合 (短长度内嵌, 长长度溢出)
  - InnoDB COMPACT: 长度 ≤ 127 用 1 字节, > 127 用 2 字节
  - PostgreSQL varlena: 短串 1 字节头, 长串 4 字节头 + TOAST 标志
```

### 行外存储 (Off-Page / Overflow / TOAST / LOB)

```
触发条件:
  - 单行无法放入单页 (8KB / 16KB)
  - 单列超过阈值 (PG TOAST: ~2KB; InnoDB DYNAMIC: 全行外)

实现方式:
  - PostgreSQL: pg_toast_<reloid> 关联表, 1996 字节 chunk
  - InnoDB DYNAMIC: 主页存 20 字节指针, 数据全部移到溢出页
  - InnoDB COMPACT: 主页存前 768 字节 + 20 字节指针, 剩余溢出
  - Oracle: LOB segment (CLOB/BLOB) 或 SecureFile LOB
  - SQL Server: in-row LOB (默认), text/image off-row, FILESTREAM 文件系统
```

### 列重排 (Column Reordering)

```
逻辑顺序: CREATE TABLE 中声明的顺序
物理顺序: 引擎实际存储的顺序

PostgreSQL: 完全按声明顺序存储, 不重排 (导致对齐填充浪费)
SQL Server: 不重排, 但 SPARSE 列单独处理
InnoDB: 不重排, 但 NULL 列从行内"消失"
Oracle: 按声明顺序; 长 NULL 尾列可省略
DuckDB / ClickHouse: 列存, 物理顺序无意义
```

## 支持矩阵

### 行格式选项 (45+ 引擎)

| 引擎 | 行格式选项 | 默认格式 | NULL 位图 | 变长编码 | 溢出存储 | 备注 |
|------|-----------|---------|----------|---------|---------|------|
| PostgreSQL | 无显式选项 | heap tuple | 是 (位图) | varlena 1/4 字节头 | TOAST | 仅 STORAGE 子句控制 |
| MySQL (InnoDB) | REDUNDANT/COMPACT/DYNAMIC/COMPRESSED | DYNAMIC (5.7.9+) | 是 (COMPACT+) | 1-2 字节长度 | 溢出页 | 5.7.9 GA |
| MySQL (MyISAM) | FIXED/DYNAMIC/COMPRESSED | DYNAMIC | -- | -- | 链式记录 | 已过时 |
| MariaDB (InnoDB) | 同 MySQL | DYNAMIC | 是 | 同 MySQL | 同 MySQL | 同步 InnoDB |
| MariaDB (Aria) | PAGE/DYNAMIC/FIXED | PAGE | -- | -- | -- | MyISAM 继任者 |
| SQLite | 无显式选项 | record format | 是 (类型码) | varint | 溢出页链表 | cell payload |
| Oracle | BASIC / OLTP / Hybrid Columnar | 默认非压缩 | 1 bit/列 | 1-3 字节长度 | LOB segment | OLTP 需 ACO 选件 |
| SQL Server | 默认 / SPARSE / vardecimal | 默认 | 是 (位图) | 偏移数组 | in-row / off-row | 行最大 8060 字节 |
| DB2 (LUW) | VALUE COMPRESSION / ADAPTIVE | 默认 | 是 (位图) | 长度前缀 | LOB tablespace | ROW FORMAT 已废弃 |
| DB2 (z/OS) | BASIC / RES (Reordered) | RES (V9+) | 是 | 长度前缀 | LOB | RES 重排变长列到尾部 |
| Snowflake | 无 (列存微分区) | 列存 | 自动 | 自动 | 自动 | 完全透明 |
| BigQuery | 无 (Capacitor 列存) | 列存 | 自动 | 自动 | 自动 | 完全透明 |
| Redshift | 无 (列存 block) | 列存 | -- | -- | -- | 1MB block |
| DuckDB | 无 (列存 vector) | 列存 | 自动 | 自动 | 自动 | 行组织仅查询时 |
| ClickHouse | 无 (列存 part) | 列存 | -- | -- | -- | MergeTree 列文件 |
| Trino | 取决于连接器 | 取决于连接器 | -- | -- | -- | 引擎层无行格式 |
| Presto | 取决于连接器 | 取决于连接器 | -- | -- | -- | 同 Trino |
| Spark SQL | 取决于文件格式 | 取决于文件格式 | -- | -- | -- | Parquet/ORC |
| Hive | 取决于文件格式 (TextFile/ORC/Parquet) | TextFile | -- | -- | -- | SerDe 控制 |
| Flink SQL | 取决于连接器 | -- | -- | -- | -- | 流处理无静态格式 |
| Databricks | Delta (Parquet) | Delta | 自动 | 自动 | 自动 | -- |
| Teradata | 无显式选项 | row + V/C 编码 | 是 (presence bits) | 长度前缀 | LOB | 64KB 行限制 |
| Greenplum | 堆 (PG 同源) / AO row / AO column | 堆 | 是 | varlena | TOAST | AOCO 列存 |
| CockroachDB | 无显式选项 | KV 编码 | 是 | varint | 单列拆分 KV | 每列一个 KV |
| TiDB | v1 / v2 (5.0 默认 v2) | v2 (5.0+) | 是 | 长度前缀 | -- | encoded row format |
| OceanBase | FLAT / DYNAMIC / SELECTIVE | FLAT | 是 | 长度前缀 | -- | 行格式属性 |
| YugabyteDB | DocDB KV 编码 | DocDB | 是 | varint | -- | 同 CockroachDB 思路 |
| SingleStore | rowstore (skiplist) / columnstore | rowstore | 是 | 长度前缀 | -- | 行存内存格式 |
| Vertica | Projection (列存) | 列存 | -- | -- | -- | -- |
| Impala | 取决于文件 (Parquet 默认) | -- | -- | -- | -- | -- |
| StarRocks | 列存 segment | 列存 | -- | -- | -- | -- |
| Doris | 列存 segment | 列存 | -- | -- | -- | -- |
| MonetDB | BAT (列向量) | 列存 | -- | -- | -- | nullable BAT 单独存 |
| CrateDB | Lucene 文档 (JSON-like) | -- | -- | -- | -- | 继承 Elasticsearch |
| TimescaleDB | 继承 PG heap; chunks | heap | 是 | varlena | TOAST | hypertable 分块 |
| QuestDB | 列文件 (mmap) | 列存 | -- | -- | -- | 时序列存 |
| Exasol | 列存 (专有) | 列存 | -- | -- | -- | -- |
| SAP HANA | 行存 / 列存 | 列存 | -- | -- | -- | 双存储 |
| Informix | 标准 / SE / 压缩 | 标准 | 是 | 长度前缀 | smart blob | -- |
| Firebird | 无显式选项 | RLE 行 | 是 | RLE | blob page | RLE 默认行级 |
| H2 | 无 (MVStore 默认) | MVStore | 是 | 长度前缀 | -- | -- |
| HSQLDB | 无 | -- | 是 | -- | -- | 内存优先 |
| Derby | 无 | -- | 是 | -- | -- | -- |
| Amazon Athena | 取决于 S3 文件 | -- | -- | -- | -- | 同 Trino |
| Azure Synapse | 行存 / 列存 (CCI) | CCI | 是 | -- | -- | 同 SQL Server |
| Google Spanner | KV 编码 | -- | 是 | -- | -- | 同 CockroachDB 思路 |
| Materialize | 内部 Row 编码 | -- | -- | -- | -- | -- |
| RisingWave | 行存状态表 | -- | -- | -- | -- | -- |
| InfluxDB | TSM 列文件 | 列存 | -- | -- | -- | 时序专用 |
| Databend | Parquet | -- | 自动 | 自动 | 自动 | -- |
| Yellowbrick | 列存 | -- | -- | -- | -- | -- |
| Firebolt | 列存 (F3 segment) | -- | -- | -- | -- | -- |

> 统计：约 14 个传统行存引擎提供显式行格式选项 (`ROW_FORMAT` 或类似 DDL)，约 22 个云数仓 / 列存引擎完全透明、用户无需关心，其余通过文件格式间接控制。

### 压缩行格式 (Compressed Row Format)

| 引擎 | 压缩行格式 | DDL | 压缩单位 | 算法 | 备注 |
|------|----------|-----|---------|------|------|
| MySQL InnoDB | COMPRESSED | `ROW_FORMAT=COMPRESSED` | 页 | zlib | 需 Barracuda + file_per_table |
| MySQL InnoDB | DYNAMIC + 透明页压缩 | `COMPRESSION='zlib\|lz4\|none'` | 页 | zlib / LZ4 | 5.7+, 需稀疏文件 |
| MySQL MyISAM | COMPRESSED | `myisampack` 工具 | 表 | 静态字典 | 只读表 |
| MariaDB InnoDB | 同 MySQL | 同 | 同 | 同 | -- |
| MariaDB Aria | 同 MyISAM | `aria_pack` | 表 | 静态字典 | 只读 |
| Oracle | BASIC | `COMPRESS [BASIC]` | 块 | 符号表 | EE only, 仅批量加载 |
| Oracle | OLTP | `COMPRESS FOR OLTP` | 块 | 符号表 | ACO 选件 |
| Oracle | HCC | `COMPRESS FOR QUERY/ARCHIVE` | CU | 列编码 | Exadata only |
| SQL Server | ROW / PAGE | `DATA_COMPRESSION=ROW\|PAGE` | 行 / 页 | 字典+RLE | 2008+ |
| DB2 | Adaptive Compression | `COMPRESS YES` | 行 / 页 | 字典 | 9.7+ |
| PostgreSQL | -- (TOAST 自动压缩) | `STORAGE EXTENDED/EXTERNAL` | 字段 | PGLZ / LZ4 | 14+ 支持 LZ4 |
| SQLite | -- | -- | -- | -- | 需 ZIPVFS 商业扩展 |
| Teradata | Multi-Value / Block-Level | `COMPRESS (...)` / `BLOCKCOMPRESSION` | 列值 / 块 | 字典 / ALC | -- |
| OceanBase | macro block 压缩 | `COMPRESSION='lz4\|zstd\|...'` | macro block | 多算法 | -- |
| TiDB | RocksDB SSTable 压缩 | (引擎级配置) | SSTable | LZ4 / ZSTD | 行格式不直接压缩 |

### 行外/LOB 存储

| 引擎 | 行外触发条件 | 存储位置 | 默认行内阈值 | 显式控制 |
|------|------------|---------|------------|---------|
| PostgreSQL | 整行 > TOAST_TUPLE_THRESHOLD (~2KB) | pg_toast.pg_toast_<oid> | ~2KB | `STORAGE PLAIN/EXTENDED/EXTERNAL/MAIN` |
| MySQL InnoDB DYNAMIC | 列长 > BLOB 阈值 | 溢出页 | ~768 字节 | -- |
| MySQL InnoDB COMPACT | 同上, 但前 768 字节存行内 | 溢出页 | 768 字节 | -- |
| MySQL InnoDB REDUNDANT | 同上 | 溢出页 | 768 字节 | -- |
| Oracle | LOB > 4KB (默认) | LOB segment | `ENABLE STORAGE IN ROW` 时 ~4KB | `LOB ... STORE AS` |
| SQL Server | text/image/varchar(max) | LOB_DATA / ROW_OVERFLOW | 8060 字节 | `large value types out of row` |
| SQL Server FILESTREAM | varbinary(max) FILESTREAM | NTFS 文件 | -- | `FILESTREAM` 属性 |
| DB2 | LOB > inline length | LOB tablespace | `INLINE LENGTH` 控制 | `INLINE LENGTH n` |
| SQLite | 单 cell > 页大小 | 溢出页链表 | varies (页大小决定) | -- |
| Teradata | LOB | LOB subtable | 64KB 行限制 | 强制行外 |

### 列重排优化

| 引擎 | 是否重排 | 优化目标 | 备注 |
|------|---------|---------|------|
| PostgreSQL | 否 | -- | 严格按声明顺序; pg_attribute.attnum 即物理位置 |
| MySQL InnoDB | 否 | -- | 严格按声明顺序 |
| Oracle | 部分 | NULL 尾列省略 | 末尾 NULL 列不存储任何字节 |
| SQL Server | 否 (SPARSE 例外) | -- | SPARSE 列特殊编码 |
| DB2 z/OS RES | 是 | 变长列移到尾部 | Reordered Row Format (RES) 自 V9 |
| DB2 LUW | 否 | -- | -- |
| Snowflake | N/A | -- | 列存自然按列分文件 |
| ClickHouse | N/A | -- | 列存 |
| TiDB | 否 | -- | encoded row 按 column_id 编码 |
| OceanBase | SELECTIVE 模式 | 高频列前置 | SELECTIVE row format 优化 |

## 各引擎详解

### MySQL InnoDB：四种行格式的演进史

InnoDB 的行格式是关系数据库领域最完整的"演进式"案例：从 MySQL 4.x 的 REDUNDANT，到 5.0 的 COMPACT，再到 5.5 的 Barracuda 引入 DYNAMIC 和 COMPRESSED，最后在 5.7.9 (2015 年 10 月) 将 DYNAMIC 设为默认。

#### REDUNDANT（最古老）

```sql
CREATE TABLE t_redundant (
    id   INT PRIMARY KEY,
    name VARCHAR(100),
    note TEXT
) ROW_FORMAT=REDUNDANT;

-- 行布局:
--   [字段长度偏移列表 (倒序)]
--   [行头 6 字节: info bits + n_owned + heap_no + record_type + next_ptr]
--   [事务列: trx_id 6B + roll_ptr 7B (仅聚簇索引)]
--   [列1] [列2] ... [列N]
--
-- 关键特点:
--   - 字段长度偏移: 每列 1 或 2 字节 (取决于行总长)
--   - 无 NULL 位图: NULL 列存储 SQL_NULL (固定字节数)
--   - VARCHAR(255) 即使 NULL 也占 255 字节
--   - 兼容 MySQL 4.0/4.1 客户端
```

REDUNDANT 的最大问题是 NULL 列不节省空间，宽 NULL 表非常浪费。

#### COMPACT（5.0.3 起默认，2005 年 3 月）

```sql
CREATE TABLE t_compact (
    id   INT PRIMARY KEY,
    name VARCHAR(100),
    note TEXT
) ROW_FORMAT=COMPACT;

-- 行布局:
--   [变长字段长度列表 (倒序, 仅变长非 NULL 列)]
--   [NULL 位图 (倒序, ceil(可空列数 / 8) 字节)]
--   [行头 5 字节]
--   [事务列: trx_id 6B + roll_ptr 7B]
--   [列1] [列2] ...  (NULL 列不占空间)
--
-- 关键改进:
--   - NULL 位图: NULL 列彻底从行内消失
--   - 变长长度: 长度 ≤ 127 用 1 字节, > 127 用 2 字节
--   - 行头从 6 字节缩到 5 字节
--   - 大字段处理: 前 768 字节存行内, 超出部分溢出到 BLOB 页
```

COMPACT 是 MySQL 5.0 至 5.6 的默认行格式，在 5.5+ 也能用 Antelope 文件格式存储。

#### DYNAMIC（5.7.9 起默认，2015 年 10 月）

```sql
CREATE TABLE t_dynamic (
    id   INT PRIMARY KEY,
    name VARCHAR(100),
    huge BLOB
) ROW_FORMAT=DYNAMIC;

-- 行布局:
--   与 COMPACT 类似, 但大字段处理不同
--
-- 关键差异:
--   - 大字段完全溢出: 行内仅存 20 字节指针 (no inline 768)
--   - 节省聚簇 B+ 树空间, 改善缓冲池命中率
--   - 配合 innodb_large_prefix=ON 支持 3072 字节索引前缀
--   - 5.7.9 GA 起作为 innodb_default_row_format 的默认值
```

DYNAMIC 解决了 COMPACT 在宽 BLOB 表上聚簇页"撑爆"的问题：把大字段彻底搬走，主页只剩薄薄一层，B+ 树高度降低。

#### COMPRESSED（5.5+，需 Barracuda）

```sql
CREATE TABLE t_compressed (
    id   INT PRIMARY KEY,
    text MEDIUMTEXT
) ROW_FORMAT=COMPRESSED KEY_BLOCK_SIZE=8;

-- 关键点:
--   - 物理页大小压缩到 KEY_BLOCK_SIZE (1/2/4/8/16 KB)
--   - 算法: zlib (deflate)
--   - 缓冲池中维护两份: 原始压缩页 + 解压后页 (LRU 双链)
--   - 写入时压缩失败会重做整页 (compression failure)
--   - 配合 innodb_compression_failure_threshold_pct 容错
--   - DDL 要求: ROW_FORMAT=COMPRESSED 必须 file_per_table=ON
```

COMPRESSED 在 SSD 时代逐渐被透明页压缩 (`COMPRESSION='lz4'`) 替代，后者无需双缓冲池，CPU 开销更低。

#### InnoDB 行格式时间线

```
2001 - MySQL 4.0  REDUNDANT (唯一选项)
2005 - MySQL 5.0.3 COMPACT 引入并设为默认
2010 - MySQL 5.5  Barracuda 文件格式发布
                  Barracuda 包含 DYNAMIC 和 COMPRESSED
                  Antelope 兼容 REDUNDANT/COMPACT
                  innodb_file_format=Antelope (默认)
2013 - MySQL 5.6  innodb_file_format=Antelope (仍默认)
                  innodb_file_per_table=ON (默认)
2015 - MySQL 5.7.9 (Oct) innodb_default_row_format=DYNAMIC
                  innodb_file_format=Barracuda (默认)
2018 - MySQL 8.0  innodb_file_format 参数废弃
                  Barracuda 成为唯一格式, Antelope 移除
                  REDUNDANT/COMPACT 仍可创建, 但无单独格式标志
```

#### Antelope vs Barracuda 对比

| 文件格式 | 行格式 | 大字段处理 | 引入版本 |
|---------|-------|-----------|---------|
| Antelope | REDUNDANT, COMPACT | 前 768 字节内联 | 4.0 / 5.0 |
| Barracuda | DYNAMIC, COMPRESSED | 完全溢出 (20 字节指针) | 5.5 (2010) |

> 5.7.9 后 Barracuda 默认；8.0 后 Antelope 移除，但 REDUNDANT 和 COMPACT 仍可作为 ROW_FORMAT 创建。

### MySQL MyISAM：FIXED / DYNAMIC / COMPRESSED

MyISAM 在 MySQL 5.5 之前是默认存储引擎，自 5.5 起被 InnoDB 取代，但其行格式仍有研究价值。

```sql
-- FIXED: 所有列定长, 无变长字段
CREATE TABLE t_fixed (
    id   INT,
    code CHAR(10),
    val  INT
) ENGINE=MyISAM ROW_FORMAT=FIXED;
-- 行长 = 列长之和 + 删除标记
-- 优点: 行 ID = 偏移 / 行长, 随机访问 O(1)
-- 缺点: 表中不能有 VARCHAR/BLOB

-- DYNAMIC: 包含变长列时自动选择
CREATE TABLE t_dyn (
    id    INT,
    title VARCHAR(200),
    note  TEXT
) ENGINE=MyISAM ROW_FORMAT=DYNAMIC;
-- 行可拆分: 头部记录 + 链式扩展记录
-- 优点: 节省空间
-- 缺点: 行 ID 不再线性, 删除留下碎片

-- COMPRESSED: 只读压缩
CREATE TABLE t_packed (
    id    INT,
    title VARCHAR(200)
) ENGINE=MyISAM ROW_FORMAT=COMPRESSED;
-- 用 myisampack 工具压缩, 静态字典编码
-- 表变为只读, 后续 INSERT 报错
```

### PostgreSQL：TOAST 与 STORAGE 子句

PostgreSQL 没有显式的 `ROW_FORMAT` 选项，所有表都使用统一的 heap tuple 格式。但 PostgreSQL 通过 TOAST (The Oversized-Attribute Storage Technique) 提供了灵活的字段级溢出控制。

#### TOAST 历史与基本概念

TOAST 自 PostgreSQL 7.1 (2001 年发布) 引入，是 PostgreSQL 早期最重要的存储创新之一。它解决的核心问题是：PostgreSQL 数据页固定 8KB，单行不能跨页，但用户经常需要存储几 MB 甚至几 GB 的字段（长文本、JSON、几何数据、tsvector 等）。

```
TOAST 触发流程 (默认 8KB 页):
  1. INSERT/UPDATE 时计算行大小
  2. 如果行 > TOAST_TUPLE_THRESHOLD (默认 ~2KB):
     a. 找到所有可 TOAST 的列 (varlena 类型)
     b. 按列长度降序排列
     c. 依次压缩 (PGLZ 或 LZ4) 直到行 ≤ 阈值
     d. 仍超过则将最长列移到 pg_toast 表
  3. 主表行内: 18 字节 TOAST 指针 (varatt_external)
  4. pg_toast.pg_toast_<reloid>: 按 1996 字节 chunk 切分
```

TOAST 关联表的命名规则：

```sql
-- 创建表时自动创建 TOAST 关联表
CREATE TABLE articles (
    id      SERIAL PRIMARY KEY,
    title   TEXT,
    content TEXT
);
-- 系统创建: pg_toast.pg_toast_<articles_oid>

-- 查看 TOAST 表
SELECT relname, reltoastrelid::regclass
FROM   pg_class
WHERE  relname = 'articles';
--   relname  |        reltoastrelid
-- -----------+------------------------------
--   articles | pg_toast.pg_toast_16384

-- TOAST 表结构 (固定):
--   chunk_id   OID,           -- 标识同一字段的多个块
--   chunk_seq  INTEGER,        -- 块序号 (0, 1, 2, ...)
--   chunk_data BYTEA           -- 1996 字节
```

#### STORAGE 子句的四种模式

```sql
-- 1. PLAIN: 不压缩、不行外存储 (仅适用定长类型如 INT/BIGINT)
ALTER TABLE articles ALTER COLUMN id SET STORAGE PLAIN;

-- 2. EXTENDED: 默认值, 可压缩 + 可行外 (TEXT/BYTEA/JSON 等默认)
ALTER TABLE articles ALTER COLUMN content SET STORAGE EXTENDED;

-- 3. EXTERNAL: 可行外但不压缩 (适合已经压缩的数据如 JPG)
ALTER TABLE articles ALTER COLUMN avatar SET STORAGE EXTERNAL;
-- 优势: 子串/SUBSTRING 操作可以只读取需要的 chunk, 不必解压

-- 4. MAIN: 优先行内压缩, 必要时才行外
ALTER TABLE articles ALTER COLUMN title SET STORAGE MAIN;
-- 适合不想触发 TOAST 但希望压缩的中等长度字段
```

#### TOAST 算法选择 (PostgreSQL 14+)

PostgreSQL 14 (2021) 引入 LZ4 压缩选项，14+ 用户可以选择更快的算法。

```sql
-- 设置默认 TOAST 压缩
SET default_toast_compression = 'lz4';   -- 14+

-- 列级指定
ALTER TABLE articles ALTER COLUMN content SET COMPRESSION lz4;

-- 查看当前压缩
SELECT pg_column_compression(content) FROM articles LIMIT 1;
-- 'pglz' / 'lz4' / NULL (未压缩)
```

#### TOAST 内部结构

```
主表行 (heap tuple):
  ┌──────────────────────────────────────┐
  │ HeapTupleHeader (23 字节)              │
  │   xmin, xmax, ctid, infomask, ...     │
  ├──────────────────────────────────────┤
  │ NULL 位图 (ceil(N/8) 字节, 对齐)        │
  ├──────────────────────────────────────┤
  │ 列数据 (按声明顺序, 含对齐填充)         │
  │   id: 4 字节                          │
  │   title: 短串则内联, 长串为 TOAST 指针 │
  │   content: 4MB → TOAST 指针 18 字节    │
  └──────────────────────────────────────┘

TOAST 指针 (varatt_external, 18 字节):
  ┌─────────────────────────────────────┐
  │ va_header  (1 字节, 0x80 标志)       │
  │ va_rawsize (4 字节, 解压后总长)      │
  │ va_extinfo (4 字节, 含算法位 + 长度) │
  │ va_valueid (4 字节, chunk_id)        │
  │ va_toastrelid (4 字节, TOAST 表 OID) │
  └─────────────────────────────────────┘

TOAST 关联表 (pg_toast.pg_toast_<oid>):
  ┌────────────┬────────────┬────────────────────────┐
  │ chunk_id   │ chunk_seq  │ chunk_data (1996 字节)  │
  ├────────────┼────────────┼────────────────────────┤
  │ 12345      │ 0          │ <bytes 0..1995>        │
  │ 12345      │ 1          │ <bytes 1996..3991>     │
  │ 12345      │ 2          │ <bytes 3992..5987>     │
  │ ...        │ ...        │ ...                    │
  └────────────┴────────────┴────────────────────────┘
  PRIMARY KEY (chunk_id, chunk_seq)
```

#### TOAST 与 MVCC 的交互

```sql
-- TOAST 行也受 MVCC 影响, 但优化点:
--   1. UPDATE 不修改 TOAST 列时, TOAST 行不复制 (HOT update path)
--   2. UPDATE 修改 TOAST 列时, 整个 TOAST 链必须重写
--   3. VACUUM 同时清理主表死元组和孤立的 TOAST chunks

UPDATE articles SET title = 'new' WHERE id = 1;
-- 不影响 content (TOAST), 仅主表更新

UPDATE articles SET content = content || 'x' WHERE id = 1;
-- 整个 content 重新 TOAST, 旧 TOAST 行变死元组
-- 大字段频繁追加是 PG 性能反模式
```

#### TOAST 阈值调优

```sql
-- 默认阈值: 约 2KB (TOAST_TUPLE_THRESHOLD = MaximumBytesPerTuple(4) = 2032)
-- 通过表选项调整 (10+):
ALTER TABLE articles SET (toast_tuple_target = 4096);
-- 行不超过 4KB 时不触发 TOAST, 减少索引扫描时的 TOAST 关联

-- 查看当前阈值:
SELECT reltoastrelid, reloptions FROM pg_class WHERE relname = 'articles';
```

### Oracle：BASIC、OLTP 压缩与 LOB

Oracle 的"行格式"概念更接近"块级压缩"和"LOB 存储"，而非显式的 ROW_FORMAT 关键字。

```sql
-- 1. 默认未压缩
CREATE TABLE orders (
    order_id    NUMBER PRIMARY KEY,
    customer_id NUMBER,
    note        VARCHAR2(4000)
);
-- 行格式: 行头 3 字节 + 列数 1-2 字节 + 列长度数组 (每列 1-3 字节) + 列数据
-- NULL 位图: 1 bit/列, 末尾 NULL 列省略 (trailing NULL elimination)

-- 2. 基本压缩 (BASIC, EE only) - 仅批量加载有效
CREATE TABLE orders_basic (
    order_id    NUMBER PRIMARY KEY,
    region      VARCHAR2(50),
    product     VARCHAR2(100)
) COMPRESS BASIC;
-- 仅 INSERT /*+ APPEND */, CREATE TABLE AS SELECT, 直接路径加载会压缩
-- 普通 DML INSERT/UPDATE 不压缩
-- 块内字典 (symbol table) 在块头, 重复值用符号引用
-- BASIC 是 Oracle EE 的内置功能, 无需额外选件

-- 3. OLTP 压缩 (Advanced Compression Option, 收费选件)
CREATE TABLE orders_oltp (
    order_id    NUMBER PRIMARY KEY,
    region      VARCHAR2(50),
    product     VARCHAR2(100)
) COMPRESS FOR OLTP;
-- INSERT/UPDATE 也压缩
-- 块达到 PCTFREE 阈值时触发压缩
-- 需要 Advanced Compression Option (ACO) 许可证

-- 4. Hybrid Columnar Compression (HCC, 仅 Exadata)
CREATE TABLE orders_hcc (...) COMPRESS FOR QUERY HIGH;
-- COMPRESSION 类型: QUERY LOW/HIGH, ARCHIVE LOW/HIGH
-- 列式存储, 仅 Exadata / ZFS Storage / Pillar Axiom

-- 5. LOB 存储
CREATE TABLE documents (
    doc_id  NUMBER PRIMARY KEY,
    content CLOB
)
LOB (content) STORE AS SECUREFILE (
    ENABLE STORAGE IN ROW       -- 小 LOB 行内
    CHUNK 8192                   -- 8KB chunk
    NOCACHE
    LOGGING
    COMPRESS HIGH                -- LOB 数据压缩 (需 ACO)
    DEDUPLICATE                  -- 跨行去重 (需 ACO)
);
-- SecureFile LOB (11g+) 全面替代旧的 BasicFile LOB
-- ENABLE STORAGE IN ROW: ≤4KB 内联, > 4KB 行外
```

Oracle 行内布局示例：

```
未压缩行:
  [行头 3B: lock byte + flag + cols]
  [列数 1-2B]
  [列1: 长度 1-3B + 数据]
  [列2: 长度 1-3B + 数据]
  ...
  [列N (末尾 NULL 可省略)]

压缩块 (BASIC/OLTP):
  [块头]
  [符号表 (块内字典): 高频值 → 短符号]
  [行1: 列引用符号或字面量]
  [行2: ...]
```

### SQL Server：FILESTREAM、in-row LOB、off-row

SQL Server 的行格式核心约束是 **8060 字节的最大行长**（页大小 8KB 减去开销）。超过的列必须移到行外。

```sql
-- 1. 默认行格式
CREATE TABLE products (
    id      INT PRIMARY KEY,
    name    VARCHAR(100),
    desc    VARCHAR(MAX),
    photo   VARBINARY(MAX)
);
-- 行布局:
--   [行头 4B: 状态位 + null bitmap offset]
--   [固定长度列]
--   [列数 2B]
--   [NULL 位图 ceil(N/8) 字节]
--   [变长列计数 2B]
--   [变长列偏移数组 (每个 2B)]
--   [变长列数据]

-- 2. SPARSE 列: 节省 NULL 占用
CREATE TABLE wide_table (
    id  INT PRIMARY KEY,
    col_1024 INT SPARSE,
    col_1025 INT SPARSE,
    -- ... 数千个 SPARSE 列
);
-- SPARSE 列 NULL 时不占空间, 非 NULL 时多 4 字节开销
-- 适合稀疏宽表 (>30% NULL)
-- 配合 column set 可批量访问

-- 3. ROW / PAGE 压缩
ALTER TABLE products REBUILD WITH (DATA_COMPRESSION = ROW);
-- ROW: 整数变长存储, 字符串去尾部空格, NULL 节省
ALTER TABLE products REBUILD WITH (DATA_COMPRESSION = PAGE);
-- PAGE: 在 ROW 基础上 + 页前缀字典 + 页字典

-- 4. in-row LOB (默认行为)
-- VARCHAR(MAX) / VARBINARY(MAX) ≤ 8000 字节: 行内
-- > 8000 字节: 行外 LOB_DATA 单元
-- 选项 'large value types out of row' 可强制行外

-- 5. ROW_OVERFLOW_DATA
-- 当行总长 > 8060 字节时, 选取最长的变长列移出
-- 行内保留 24 字节指针

-- 6. FILESTREAM: 大文件存 NTFS
CREATE TABLE files (
    id      UNIQUEIDENTIFIER ROWGUIDCOL UNIQUE NOT NULL,
    content VARBINARY(MAX) FILESTREAM
);
-- content 不存数据库文件, 而存 NTFS 上的文件
-- 全文索引、备份、事务一致性仍由 SQL Server 管理
-- 适合 > 1MB 的二进制大对象
```

### DB2：ROW FORMAT 与 RES (Reordered Row Format)

DB2 的行格式分两个分支：DB2 LUW（Linux/Unix/Windows）和 DB2 z/OS。

```sql
-- DB2 LUW: VALUE COMPRESSION
CREATE TABLE inventory (
    item_id INT PRIMARY KEY,
    name    VARCHAR(200),
    qty     INT
) VALUE COMPRESSION;
-- NULL 不占空间; 默认值不存储
-- 配合 COMPRESS YES 启用 Adaptive Compression

-- DB2 LUW: Adaptive Compression (10.5+)
ALTER TABLE inventory COMPRESS YES ADAPTIVE;
-- 表级字典 + 页级字典双层

-- DB2 z/OS: BASIC 和 RES (Reordered Row Format)
CREATE TABLE orders (
    order_id INT NOT NULL,
    note     VARCHAR(4000),
    region   CHAR(10),
    PRIMARY KEY (order_id)
);
-- z/OS V9+ 默认 RES:
--   - 固定长度列前置
--   - 变长列移到行尾
--   - 变长列偏移数组前置
--   - 减少 UPDATE VARCHAR 时的整行移动

-- 切换:
ALTER TABLESPACE ts1 ROWFORMAT BRF;  -- BASIC (旧)
ALTER TABLESPACE ts1 ROWFORMAT RRF;  -- Reordered (推荐)

-- LOB inline 控制
CREATE TABLE docs (
    doc_id INT PRIMARY KEY,
    body   CLOB(10M) INLINE LENGTH 4096
);
-- 小于 4KB 的 LOB 直接行内, 节省 LOB tablespace 访问
```

### SQLite：Cell Payload 编码

SQLite 的"行格式"称为 **record format** 或 **cell payload**。它没有显式选项，所有表都使用同一种紧凑的 TLV 编码。

```
SQLite Record Format:
  ┌──────────────────────────────────────────────────────┐
  │ Header Length (varint)                                │
  │ Type Codes (varint × N):                             │
  │   0      = NULL                                       │
  │   1      = INT (1 byte, big-endian)                   │
  │   2..6   = INT (2..8 bytes)                           │
  │   7      = REAL (8 bytes, IEEE 754)                   │
  │   8      = INT 0 (no body)                            │
  │   9      = INT 1 (no body)                            │
  │   10..11 = reserved                                   │
  │   N>=12 (even) = BLOB, length=(N-12)/2                │
  │   N>=13 (odd)  = TEXT, length=(N-13)/2                │
  ├──────────────────────────────────────────────────────┤
  │ Body (拼接所有列的二进制表示)                          │
  └──────────────────────────────────────────────────────┘
```

```sql
-- WITHOUT ROWID 表 (聚簇表)
CREATE TABLE config (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
) WITHOUT ROWID;
-- 行格式相同, 但主键不再是 ROWID 而是声明的 PK

-- 大行处理
CREATE TABLE blobs (id INTEGER PRIMARY KEY, data BLOB);
INSERT INTO blobs VALUES (1, randomblob(1000000));  -- 1MB
-- SQLite 自动溢出: 主 cell 存前 N 字节 + 4 字节首溢出页号
-- 链式溢出页 (overflow page chain), 每页 (page_size - 4) 字节有效负载
-- 默认 page_size = 4096, 1MB BLOB ~ 256 个溢出页
```

### ClickHouse：列存无行格式

ClickHouse 完全摆脱了"行"的概念。MergeTree 引擎将每列单独存为 `<column>.bin` 文件，配合稀疏主键索引和 mark 文件。

```sql
CREATE TABLE events (
    event_time DateTime CODEC(DoubleDelta, LZ4),
    user_id    UInt64    CODEC(Delta, ZSTD),
    event_type LowCardinality(String),
    payload    String    CODEC(ZSTD(3))
) ENGINE = MergeTree()
ORDER BY (event_time, user_id);
-- 物理布局:
--   <part>/event_time.bin   - DateTime 列
--   <part>/event_time.mrk2  - mark 索引
--   <part>/user_id.bin
--   <part>/user_id.mrk2
--   <part>/event_type.bin / event_type.dict.bin (LowCardinality 字典)
--   <part>/payload.bin
--   <part>/primary.idx      - 稀疏主键索引
```

ClickHouse 没有传统行格式选项，但提供了细粒度的 CODEC DSL 控制每列的编码。

### CockroachDB：每列一个 KV

CockroachDB 将每行拆分为多个 KV pair（每列一个），存入底层 RocksDB/Pebble。

```
表 orders (id INT PK, name VARCHAR, amount DECIMAL):

KV 编码:
  /Table/52/1/100/0    -> sentinel value (空 value, 表示行存在)
  /Table/52/1/100/2    -> "Alice"          (列 name)
  /Table/52/1/100/3    -> 99.99            (列 amount)

新格式 (column families): 同一 family 的列合并为一个 value
  /Table/52/1/100/0    -> ProtoBuf{name: "Alice", amount: 99.99}
```

CockroachDB 自 v22+ 默认使用 column family 编码减少 KV 数量。这是**逻辑行存 + 物理 KV 存**的混合模型。

### TiDB：encoded row format v1 vs v2

TiDB 自 5.0 起默认使用 row format v2，相比 v1 在编码效率和扫描性能上有显著提升。

```
TiDB Row Format v1 (5.0 之前):
  [col1_id][col1_value][col2_id][col2_value]...
  - 列 ID 与值交错
  - NULL 列不出现 (相当于隐式 NULL 位图)
  - 顺序解析需扫描全行

TiDB Row Format v2 (5.0+ 默认):
  Header:
    [version 1B = 0x80][flags 1B][numNotNullCols 2B][numNullCols 2B]
  ColIDs:
    [non_null_col_ids][null_col_ids]   - 排序后存储
  Offsets:
    [non_null_col_offsets]              - 4 字节每列, 大行 8 字节
  Values:
    [non_null_col_values]
  - 列 ID 排序后二分查找, O(log N)
  - 偏移数组直达列, 无需顺序扫描
  - NULL 列 ID 单独存, 显式 NULL 集合
```

启用方式：

```sql
-- 全局开关
SET GLOBAL tidb_row_format_version = 2;  -- 5.0+ 默认
-- 0 = v1, 2 = v2
```

### OceanBase：FLAT、DYNAMIC、SELECTIVE 三种行格式

OceanBase 提供三种 ROW_FORMAT 选项，覆盖不同负载特点。

```sql
-- 1. FLAT (默认, 类似 InnoDB COMPACT)
CREATE TABLE t1 (id INT PRIMARY KEY, name VARCHAR(100))
ROW_FORMAT = FLAT;
-- 紧凑布局: 列长度数组 + NULL 位图 + 列值

-- 2. DYNAMIC (类似 InnoDB DYNAMIC)
CREATE TABLE t2 (id INT PRIMARY KEY, content TEXT)
ROW_FORMAT = DYNAMIC;
-- 大字段完全溢出, 行内 20 字节指针

-- 3. SELECTIVE (高频列前置)
CREATE TABLE t3 (id INT PRIMARY KEY, hot_col INT, cold_col TEXT)
ROW_FORMAT = SELECTIVE;
-- 优化点: 高频访问列存储在行的前部
-- 减少部分列扫描时的 CPU 开销
```

OceanBase 还在 macro block 级别提供压缩 (`COMPRESSION='lz4_1.0'` 等)，与行格式正交。

## PostgreSQL TOAST 内部细节

TOAST 是 PostgreSQL 长达 25 年的存储基石，值得深入剖析。

### TOAST chunk 存储机制

```
pg_toast.pg_toast_<oid> 表结构 (固定):
  CREATE TABLE pg_toast.pg_toast_16384 (
      chunk_id   OID NOT NULL,
      chunk_seq  INTEGER NOT NULL,
      chunk_data BYTEA NOT NULL,
      PRIMARY KEY (chunk_id, chunk_seq)
  );

  - chunk_id: 标识单个 TOASTed 字段的所有 chunks
  - chunk_seq: 0, 1, 2, ... (按顺序)
  - chunk_data: 1996 字节 (TOAST_MAX_CHUNK_SIZE), 最后一块可能更短

读取流程:
  1. 主表 heap tuple 中读出 18 字节 TOAST 指针
  2. 提取 chunk_id (4 字节) 和 toastrelid
  3. 在 pg_toast_<oid> 上按 (chunk_id, chunk_seq) 顺序读取
  4. 拼接 chunk_data
  5. 如果指针标记为压缩, 用 PGLZ/LZ4 解压
  6. 返回完整字段值

部分读取 (substring/octet 操作):
  - PostgreSQL 优化: 如果不需要全部 chunks, 仅读取所需的 chunk_seq 范围
  - 对未压缩的 EXTERNAL 字段尤其有效
  - 对压缩字段必须从头解压 (PGLZ 流式解压)
```

### TOAST 压缩算法

```
PGLZ (默认, 自 7.1):
  - 基于 LZSS, 慢但稳定
  - 压缩比中等, 解压速度中等
  - 仅对 ≥ 32 字节的字段尝试压缩
  - 至少减少 25% 才接受压缩结果, 否则原样存储

LZ4 (PostgreSQL 14+):
  - 解压速度比 PGLZ 快 5-10 倍
  - 压缩比略低于 PGLZ
  - default_toast_compression = 'lz4' 启用
  - 支持列级 SET COMPRESSION lz4

ZSTD: 暂未原生支持, 仅通过文件系统层 (ZFS, btrfs) 间接获得
```

### TOAST 阈值的精确定义

```c
// PostgreSQL 源码 (src/include/access/heaptoast.h)
#define TOAST_TUPLES_PER_PAGE 4
#define MaximumBytesPerTuple(tuplesPerPage) \
    MAXALIGN_DOWN((BLCKSZ - \
                   MAXALIGN(SizeOfPageHeaderData + \
                            (tuplesPerPage) * sizeof(ItemIdData))) / \
                  (tuplesPerPage))

// 默认 8KB 页:
//   MaximumBytesPerTuple(4) = (8192 - 24 - 16) / 4 = ~2032 字节

// TOAST_TUPLE_THRESHOLD = MaximumBytesPerTuple(4) ~ 2032 字节
// TOAST_TUPLE_TARGET = MaximumBytesPerTuple(4) ~ 2032 字节 (压缩目标)
```

### TOAST 与 VACUUM

```
VACUUM 处理 TOAST 表:
  1. 主表 VACUUM 时同时扫描关联 TOAST 表
  2. 死元组的 TOAST 行通过 chunk_id 找到并标记可回收
  3. TOAST 表也有自己的 freespace map (FSM)
  4. autovacuum 可独立触发 TOAST 表

陷阱: 大字段更新引发 TOAST 表膨胀
  -- 反模式
  UPDATE articles SET content = content || 'append' WHERE id = 1;
  -- 每次都重写整个 content 的 TOAST 链
  -- 旧 TOAST chunks 变死元组, 等 VACUUM 清理
  -- 高频追加场景应使用专门的 append-only 设计
```

### TOAST 的特殊场景

```sql
-- 1. 关闭 TOAST (仅适合定长字段)
ALTER TABLE t ALTER COLUMN col SET STORAGE PLAIN;
-- 注意: 如果 col 是 varlena 类型且超过 8KB, INSERT 会报错

-- 2. 强制行外但不压缩 (对随机访问大字段的优化)
ALTER TABLE t ALTER COLUMN avatar SET STORAGE EXTERNAL;
-- 适合 JPG/PNG 等已压缩数据
-- substring(avatar, 100, 50) 可只读 1 个 chunk

-- 3. 鼓励行内压缩 (避免 TOAST 表查找开销)
ALTER TABLE t ALTER COLUMN tags SET STORAGE MAIN;
-- 中等长度字段优先压缩到行内, 必要时才行外

-- 4. 检查字段是否被 TOAST
SELECT pg_column_size(content) AS stored_size,
       octet_length(content)    AS uncompressed_size,
       pg_column_compression(content) AS algo
FROM articles WHERE id = 1;
```

## 关键发现

### 1. 行格式选项数量与年代正相关

老牌的传统数据库（MySQL、Oracle、SQL Server、DB2）都积累了多种行格式，反映 25+ 年的演进历史；2010 年后诞生的引擎（CockroachDB、TiDB、Snowflake、ClickHouse）大多只有一种"原生"行格式（或者根本没有"行"概念），通过 codec / encoding 提供细粒度控制。这印证了一个规律：**显式 ROW_FORMAT 是历史包袱，新引擎更倾向自动化**。

### 2. NULL 位图普及程度

支持 NULL 位图（每列 1 bit）的引擎中 NULL 几乎免费；不支持的（如 InnoDB REDUNDANT、早期 MyISAM、一些教育型嵌入式引擎）NULL 列代价高昂。这导致老应用迁移到新引擎时存储利用率提升明显——**NULL 多的宽表是最大的受益者**。

### 3. 变长字段的两种风格：长度前缀 vs 偏移数组

InnoDB / DB2 / Oracle 使用长度前缀（顺序解析），SQL Server / TiDB v2 使用偏移数组（O(1) 列访问）。两者各有优劣：长度前缀节省行头空间，偏移数组适合宽表的部分列扫描。**TiDB v2 在 5.0 引入偏移数组主要是为了 OLAP 场景的列裁剪优化**。

### 4. 行外存储的两种策略

PostgreSQL TOAST 与 InnoDB DYNAMIC 是两种代表性策略：
- **TOAST 字段级**：每个 varlena 字段独立判断溢出，通过 STORAGE 子句细控
- **InnoDB 整行级**：超过阈值的列整体溢出到一组溢出页，无字段级控制

PostgreSQL 的设计更灵活但实现复杂；InnoDB 简单但缺乏微调能力。**TOAST 的字段级压缩对 JSON/JSONB 字段尤其友好**——对每个 JSON 文档独立压缩、独立解压。

### 5. MySQL InnoDB 的 DYNAMIC 默认化是迟到的修复

DYNAMIC 实质上 2010 年随 Barracuda 引入，但直到 2015 年 (5.7.9 GA, 10 月发布) 才设为默认。这 5 年间默认 COMPACT 导致大量宽 BLOB 表的聚簇 B+ 树膨胀。**新部署应优先确认 innodb_default_row_format=DYNAMIC**。

### 6. Oracle BASIC 压缩需要企业版授权

虽然 Oracle BASIC compression 包含在 EE (Enterprise Edition) 中，但**不能在 Standard Edition 中使用**；OLTP / HCC 进一步需要 Advanced Compression Option (ACO) 或 Exadata 选件。这意味着 Oracle 的"压缩"特性在中小企业部署中常常不可用。

### 7. PostgreSQL TOAST 的 25 年遗产

TOAST 自 7.1 (2001) 引入以来一直是 PostgreSQL 的核心存储机制。直到 14 (2021) 才支持 LZ4 替代 PGLZ——长达 20 年只有一个压缩算法。这种保守的演进策略既是稳定性的体现，也是历史包袱：现代列存引擎的多算法 codec 体系（ClickHouse / DuckDB）已经领先 PostgreSQL 一个时代。

### 8. SQL Server 8060 字节硬限制

SQL Server 至今保留了 8060 字节的最大行长（页大小 8KB - 开销）。超过的列必须移到 LOB_DATA 或 ROW_OVERFLOW_DATA 单元。这与 PostgreSQL 的"任何长度都自动 TOAST"形成鲜明对比。**应用层设计宽表时必须意识到 SQL Server 的物理限制**。

### 9. 列存引擎的"无行格式"

Snowflake / BigQuery / Redshift / DuckDB / ClickHouse 这些列存引擎完全没有"行格式"概念：每列独立存储、独立压缩、独立 NULL 表示。用户连选项都不需要——这是云数仓的"零运维"哲学。从 DBA 视角看，列存的"行格式"反而是查询时由扫描算子重组的瞬时结构。

### 10. CockroachDB / Spanner 的 KV 编码：物理碎片化

将每列拆分为独立 KV 的设计在分布式系统上有天然优势（细粒度 MVCC、按列读取），但带来了 KV 数量爆炸的副作用。CockroachDB 自 v22 引入 column family 默认编码减少 KV 数量。**这是分布式 SQL 与传统行存最深刻的物理差异之一**。

## 参考资料

- MySQL InnoDB Row Formats: https://dev.mysql.com/doc/refman/8.0/en/innodb-row-format.html
- MySQL InnoDB COMPACT: https://dev.mysql.com/doc/refman/8.0/en/innodb-row-format.html#innodb-compact-row-format
- MySQL InnoDB DYNAMIC: https://dev.mysql.com/doc/refman/8.0/en/innodb-row-format.html#innodb-row-format-dynamic
- MySQL Antelope vs Barracuda: https://dev.mysql.com/doc/refman/5.7/en/innodb-file-format.html
- MySQL MyISAM Storage: https://dev.mysql.com/doc/refman/8.0/en/myisam-table-formats.html
- PostgreSQL TOAST: https://www.postgresql.org/docs/current/storage-toast.html
- PostgreSQL Page Layout: https://www.postgresql.org/docs/current/storage-page-layout.html
- PostgreSQL HeapTupleHeader: https://github.com/postgres/postgres/blob/master/src/include/access/htup_details.h
- Oracle Compression: https://docs.oracle.com/en/database/oracle/oracle-database/19/admin/managing-tables.html#GUID-A8F3420F-9B0E-4F2E-A7AF-77D77F37D6C4
- Oracle SecureFile LOBs: https://docs.oracle.com/en/database/oracle/oracle-database/19/adlob/securefiles.html
- SQL Server Row Format: https://learn.microsoft.com/en-us/sql/relational-databases/system-tables/sysrscols-transact-sql
- SQL Server Sparse Columns: https://learn.microsoft.com/en-us/sql/relational-databases/tables/use-sparse-columns
- DB2 Reordered Row Format: https://www.ibm.com/docs/en/db2-for-zos/13?topic=tables-reordered-row-format
- SQLite Record Format: https://www.sqlite.org/fileformat2.html#record_format
- ClickHouse MergeTree: https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/mergetree
- TiDB Row Format v2: https://github.com/pingcap/tidb/blob/master/pkg/tablecodec/rowindexcodec.go
- CockroachDB Encoding: https://www.cockroachlabs.com/docs/stable/architecture/encoding.html
- OceanBase ROW_FORMAT: https://www.oceanbase.com/docs/common-oceanbase-database-cn-1000000000033795
- 相关文章: [可插拔存储引擎](pluggable-storage-engines.md)、[表与列压缩](table-column-compression.md)、[聚簇 vs 堆表存储](clustered-heap-storage.md)
