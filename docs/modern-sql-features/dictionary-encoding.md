# 字典编码 (Dictionary Encoding)

一张事实表里的国家代码列只有 200 个不同值，却被当成 8 字节字符串重复存储 100 亿次——这就是字典编码（Dictionary Encoding）要解决的核心问题。把 distinct value 抽出建表，然后只存"第几条"的 ID，列存数据库立刻获得 5-50 倍的压缩比，并在不解压的情况下完成 `WHERE country = 'CN'` 这样的谓词。字典编码不是某种"压缩算法"，而是列存引擎的物理基础——没有它，列存的扫描性能会瞬间退化到行存水平。

字典编码本身的概念可以追溯到 1970 年代的统计数据库，但真正使它成为现代数据库标准实践的是 2000 年代的列存浪潮：C-Store / Vertica 把字典编码与 RLE / bit-packing 视为列存的"基本三件套"；Power Pivot / VertiPaq 把它带进了 SQL Server Columnstore；Parquet / ORC 把它写进了文件格式规范；ClickHouse 的 `LowCardinality(String)` 把它做成了用户可见的列类型。

本文系统对比 45+ 个数据库引擎在字典编码上的能力差异，深入剖析 Parquet `PLAIN_DICTIONARY` / `RLE_DICTIONARY` 的双页模型、ORC 的字典阈值、ClickHouse `LowCardinality` 的语义、Vertica 自动 LF/HF 选择、SAP HANA 的 N-bit value-id 编码，并讨论字典编码与谓词下推、Bloom filter、压缩域 join 的协同。

> 注: 字典编码完全是 vendor-specific / 文件格式 specific 的特性，SQL 标准从未定义任何与之相关的语法。所有在 DDL 中可见的字典编码暴露面（`LowCardinality`, `ENCODE BYTEDICT`, `BLOCK_DICT` 等）都来自厂商扩展。

## 字典编码的基本原理

### 三个核心概念

```
原始列 (8 字节字符串 × 10 行):
  ['China', 'USA', 'China', 'India', 'USA', 'China', 'Japan', 'USA', 'China', 'India']

字典 (4 entry × ~5 字节):
  0 -> 'China'
  1 -> 'USA'
  2 -> 'India'
  3 -> 'Japan'

编码后的列 (1 字节 × 10 行 或 2-bit × 10 行):
  [0, 1, 0, 2, 1, 0, 3, 1, 0, 2]

存储节省: 80 字节 -> 20 字节 (字典) + 10 字节 (ID 序列) = ~62% 节省
```

字典编码有三个关键设计决策，决定了实现差异：

1. **字典作用域**：每个 page / row group / file / table / database 单独建字典？作用域越大字典越大、命中率越高，但局部访问代价越大。
2. **ID 编码方式**：定长字节、bit-packing、RLE 与字典 ID 序列叠加？
3. **回退策略**：字典超过某个阈值（如 1MB / 10000 entry）时，换回 PLAIN 编码还是放弃压缩？

### 为什么字典编码对列存如此重要？

```
列存 + 字典编码的协同效应：
  1. 字典 ID 通常 1-4 字节 → 单列扫描带宽降到原来的 1/2-1/8
  2. 字典 ID 序列高度可压缩 (RLE / bit-packing) → 再叠加 5-10 倍
  3. 谓词可在压缩域执行：WHERE country = 'CN'
     → 查字典 'CN' -> id 7
     → 在 ID 序列上做 == 7，无需解压字符串
  4. 字典 ID 是 group by / join 的天然 hash key，跳过字符串哈希
```

字典编码与列存的关系类似页缓存与 OLTP 引擎——理论上可以分离，实际上不可分离。

## 没有 SQL 标准

SQL:2003 / SQL:2016 / SQL:2023 都没有任何与字典编码相关的语法或语义规范。所有在 DDL 中能看到的字典控制（`ENCODE BYTEDICT`、`LowCardinality(String)`、`BLOCK_DICT` 等）都是厂商扩展。Parquet / ORC 的字典编码规范属于文件格式标准（Apache 软件基金会），与 SQL 标准无关。

> 注：SQL 标准定义的是"逻辑上字符串列"的语义，物理上是否使用字典是优化器与存储引擎自由发挥的范畴。

## 支持矩阵

### 原生字典编码支持

| 引擎 | 行/列存 | 原生字典编码 | 用户可见控制 | 自动选择 | 字典作用域 |
|------|--------|-------------|------------|---------|-----------|
| PostgreSQL | 行 | -- | -- | -- | -- |
| MySQL | 行 | -- | -- | -- | -- |
| MariaDB | 行 | -- | -- | -- | -- |
| SQLite | 行 | -- | -- | -- | -- |
| Oracle | 行+列(IMC/HCC) | 是 (IM/HCC) | -- | 是 | CU / IMCU |
| SQL Server | 行+列存 | 是 (Columnstore) | -- | 是 | row group (~1M 行) |
| DB2 | 行+列(BLU) | 是 (BLU) | -- | 是 | 表级 + 页级 |
| Snowflake | 列（micropartition） | 是 | -- | 是 | micropartition |
| BigQuery | 列（Capacitor） | 是 | -- | 是 | 文件级 |
| Redshift | 列 | 是 | `ENCODE BYTEDICT/TEXT255/TEXT32K` | 是 (ANALYZE) | 1 MB 块 |
| DuckDB | 列 | 是 (`Dictionary` + FSST) | -- | 是 | row group |
| ClickHouse | 列（MergeTree） | 是 (`LowCardinality`) | 是 (类型) | 部分 | part |
| Trino | 取决文件 | 取决 Parquet/ORC | 取决文件 | 取决文件 | 取决文件 |
| Presto | 取决文件 | 取决 Parquet/ORC | 取决文件 | 取决文件 | 取决文件 |
| Spark SQL | 取决文件 | 是 (读 Parquet/ORC dict) | -- | 是 | row group |
| Hive | 取决文件 | 是 (读 Parquet/ORC dict) | -- | 是 | row group |
| Flink SQL | 取决文件 | 是 (读 Parquet/ORC dict) | -- | 是 | row group |
| Databricks | 列 (Delta) | 是 | -- | 是 | row group |
| Teradata | 行+列(Columnar) | 是 (MVC) | `MULTIVALUE COMPRESS` | 半自动 | 列级 |
| Greenplum | 行+列(AOCO) | 是 (AOCO) | `compresstype=rle_type` | 是 | block |
| CockroachDB | 行(KV) | -- | -- | -- | -- |
| TiDB | 行+列(TiFlash) | 是 (TiFlash) | -- | 是 | DMFile pack |
| OceanBase | 行+列 4.x | 是 (列存模式) | -- | 是 | 微块 |
| YugabyteDB | 行(DocDB) | -- | -- | -- | -- |
| SingleStore | 行+列存 | 是 (Columnstore) | -- | 是 | segment (~1M 行) |
| Vertica | 列（projection） | 是 (LF/HF/BLOCK_DICT) | `ENCODING` | 是 (auto) | block / projection |
| Impala | 取决格式 | 是 (读 Parquet/ORC dict) | -- | 是 | row group |
| StarRocks | 列 | 是 (低基数全局字典) | -- | 是 | segment + 全局 |
| Doris | 列 | 是 | -- | 是 | segment |
| MonetDB | 列 | 隐式 | -- | -- | -- |
| CrateDB | 列 (Lucene) | 是 (DocValues) | -- | 是 | Lucene segment |
| TimescaleDB | 行+列（压缩块） | 部分 | -- | 部分 | chunk |
| QuestDB | 列 | 是 (Symbol type) | 是 (`SYMBOL`) | 是 | 全表字典 |
| Exasol | 列 | 自动 | -- | 是 | -- |
| SAP HANA | 列 | 是 (value-id) | -- | 是 | 表级（main） |
| Informix | 行 | -- | -- | -- | -- |
| Firebird | 行 | -- | -- | -- | -- |
| H2 | 行 | -- | -- | -- | -- |
| HSQLDB | 行 | -- | -- | -- | -- |
| Derby | 行 | -- | -- | -- | -- |
| Amazon Athena | 取决格式 | 是 (读 Parquet/ORC dict) | -- | 是 | 取决文件 |
| Azure Synapse | 行+列存 | 是 (Columnstore) | -- | 是 | row group |
| Google Spanner | 行(Ressi 列式) | 部分 | -- | 部分 | -- |
| Materialize | 增量视图 | -- | -- | -- | -- |
| RisingWave | 流+状态 | -- | -- | -- | -- |
| InfluxDB (IOx) | 列 (Parquet) | 是 (Parquet 默认) | -- | 是 | row group |
| Apache Pinot | 列 | 是 (StringColumn 默认) | `noDictionaryColumns` | 是 | segment |
| Apache Druid | 列 | 是 (维度默认 dict) | -- | 是 | segment |
| Databend | 列 (Parquet) | 是 (继承 Parquet) | -- | 是 | row group |
| Yellowbrick | 列 | 是 | -- | 是 | shard |
| Firebolt | 列 (F3) | 是 | -- | 是 | F3 segment |

> 统计：48 个引擎中，约 35 个具备某种形式的"原生字典编码"。其中 **行存数据库（PostgreSQL/MySQL/MariaDB/SQLite/Informix/Firebird/H2/HSQLDB/Derby/CockroachDB/YugabyteDB）几乎全部不支持**，这与"是否是列存"基本是镜像关系。

### 字典作用域：per-column-chunk vs file-level vs table-level

| 引擎 / 格式 | 字典粒度 | 典型大小 | 跨多大数据共享 | 备注 |
|------------|---------|---------|---------------|------|
| Parquet | column chunk (per row group, per column) | 1 MB 上限 | row group (≈1M 行) | 超阈值回退 PLAIN |
| ORC | stripe (per column) | ~64 MB stripe | stripe (~10K-1M 行) | dict 阈值 0.8 |
| ClickHouse `LowCardinality` | part (per column) | 灵活 | 单 part（10M-100M 行） | merge 时全局重映射 |
| ClickHouse 全局字典 | 表级 | 不限 | 整表 | 24.x 实验性 |
| SAP HANA | 表级（main fragment） | 整列字典 | 整列 | delta 单独 |
| SQL Server Columnstore | row group dict + 全局字典 | 1M 行 row group | row group + 全局共享串字典 | "Bulk Loaded" 模式可全表 |
| Vertica BLOCK_DICT | block (~64KB) | 一个 block | block | 适合局部低基数 |
| Vertica BLOCKDICT_COMP | block + LZO | 同上 | block | 字典再 LZO |
| Snowflake | micropartition | 16 MB 压缩 | micropartition | 完全透明 |
| BigQuery Capacitor | 列 chunk | -- | 启发式 record reorder + chunk | 完全透明 |
| Redshift `BYTEDICT` | 1 MB 块 | 256 entry 上限 | block | 超 256 直接回退 |
| Redshift `TEXT255` | block | 245 个 word（每 word ≤14 byte） | block | "word-level" 而非整列 |
| Redshift `TEXT32K` | block | 32 KB 字典 | block | 大字典版本 |
| DuckDB | row group (~120K 行) | 灵活 | row group | 与 FSST 互补 |
| StarRocks | segment + 全局 | 全局字典存 FE | 整表多 segment | 低基数列优化 |
| QuestDB SYMBOL | 全表 | 不限 | 全表 | 字符串映射到 int32 |
| Apache Druid | segment | -- | segment | dimension 默认 dict |
| Apache Pinot | segment | -- | segment | StringColumn 默认 |

### 字典回退策略

字典编码并非总是最优——当 distinct count 接近行数（高基数列）时，字典会大到失去意义。各引擎的回退策略：

| 引擎 / 格式 | 回退触发条件 | 回退后编码 | 是否可手动禁用字典 |
|------------|------------|----------|------------------|
| Parquet (parquet-mr / parquet-cpp) | 字典 > **1 MB** | PLAIN | `parquet.enable.dictionary=false` |
| ORC | distinct/total > **0.8** (默认 threshold) | DIRECT (PLAIN) | `orc.dictionary.key.threshold=0.0` |
| ClickHouse `LowCardinality` | 默认无硬限制；超 ~10000 distinct 性能下降 | -- | 改用 `String` |
| Apache Druid | 维度始终 dict（无回退） | -- | -- |
| Apache Pinot | distinct > segment 行数阈值 | RAW | `noDictionaryColumns` 显式 |
| Redshift `BYTEDICT` | distinct > **256** | RAW | `ENCODE RAW` |
| Redshift `TEXT255` | word 数 > 245 / word > 14 字节 | LZO | `ENCODE LZO/ZSTD` |
| DuckDB | row group 内 distinct > **2/3 行数** | FSST 或其他 | -- |
| Vertica | 自动选 LF/HF/BLOCK_DICT/None | -- | `ENCODING NONE` |
| SQL Server Columnstore | 总是 dict（VertiPaq 内部） | -- | 不可禁用 |
| Snowflake | 自动启发式 | -- | 不可禁用 |
| TiDB TiFlash | distinct > pack 行数阈值 | DIRECT | -- |

### 字典共享 / 字典重用跨文件

Parquet 与 ORC 的字典默认 **不跨 row group / stripe 共享**，因为这会让局部访问需要额外读字典 page。但部分引擎实现了"全局字典"以提升 join / group by 性能：

| 引擎 | 全局字典 | 实现方式 | 用途 |
|------|---------|---------|------|
| StarRocks | 是 | FE 维护表级 string-to-id 映射 | 低基数列谓词 / aggregation 加速 |
| ClickHouse | 实验 | 24.x `dictionaries` 全局表（不同概念） | 字典表 join |
| SAP HANA | 是 | 表级 main fragment 全列字典 | 压缩域 join |
| TiDB TiFlash | 部分 | 列级合并字典（同 segment） | 压缩域谓词 |
| Apache Druid | 部分 | segment 级字典（不跨 segment） | -- |
| Apache Pinot | 部分 | segment 级 + Cluster 维度 lookup | -- |
| QuestDB | 是（SYMBOL） | 整表唯一字典 | 字符串 → int32 |
| Vertica | 否 | 仅 block 级 | -- |
| Parquet 标准 | 否 | row group 内独立 | -- |
| Snowflake | 否 | micropartition 内独立 | -- |

全局字典的代价：写入路径需要协调（CAS 或集中式分配 ID），并且字典本身随表增长。StarRocks 的实现选择了"最大字典大小阈值，超过则放弃全局优化"。

## Parquet 字典编码深入

Parquet 是字典编码最重要的开放规范。它定义了两种字典页编码与一种字典数据页编码的组合，被几乎所有 Lakehouse 查询引擎（Spark / Trino / Hive / Impala / Athena / DuckDB / ClickHouse / BigQuery 外部表 / Snowflake 外部表）共同使用。

### Parquet 编码类型与字典模型

```
parquet 文件结构：
  Row Group
    Column Chunk (per column)
      [可选] Dictionary Page    <-- PLAIN_DICTIONARY 编码的字典
      Data Page 1               <-- RLE_DICTIONARY 编码的 ID 序列
      Data Page 2
      ...
```

| 编码值 | 含义 | 用途 |
|--------|------|------|
| `PLAIN` (0) | 无编码（直接二进制） | 数据页与字典页 |
| `PLAIN_DICTIONARY` (2) | 字典页编码（已弃用，用 PLAIN 替代） | 仅历史兼容 |
| `RLE` (3) | RLE + bit-packing | bool / 定长整数 |
| `BIT_PACKED` (4) | bit-packing | 已弃用 |
| `DELTA_BINARY_PACKED` (5) | delta 编码 | 整数 |
| `DELTA_LENGTH_BYTE_ARRAY` (6) | 长度 delta | 字符串前缀 |
| `DELTA_BYTE_ARRAY` (7) | 增量字符串 | 排序字符串 |
| `RLE_DICTIONARY` (8) | RLE 编码的字典 ID | 字典数据页 |
| `BYTE_STREAM_SPLIT` (9) | 浮点比特位重排 | float / double |

字典编码的实际工作流程：

```
写入第一个数据页时：
  1. 创建一个 dictionary page（PLAIN 编码所有 distinct value）
  2. 数据页用 RLE_DICTIONARY 编码：每个 value 替换为字典 ID

如果 dictionary page 大小超过 1 MB：
  1. 停止往字典加新 value
  2. 之后的数据页改用 PLAIN（或 DELTA_*）编码原始 value
  3. 已写入的 dictionary 仍然有效，但只用于现有 page

读取时：
  1. 解析 column chunk metadata 获取 dictionary page offset
  2. 加载并解码 dictionary（一次）
  3. 对每个数据页：
     - 如果是 RLE_DICTIONARY，按 ID 查字典
     - 如果是 PLAIN，直接解码
```

### 1 MB 字典阈值的依据

```
Parquet 默认 parquet.dictionary.page.size.bytes = 1 MB
原因：
  1. 字典本身存在每个 row group → 不能太大
  2. 内存中需要 hash map (string -> id) → 1 MB 字典对应 ~10K-100K entry
  3. 1 MB 字典 + 1M 行数据页 = 字典开销 / 数据 ≈ 1%（可接受）
  4. 若 distinct 超过此阈值，字典编码已无收益（ID 与原值差不多大）
```

阈值是**写时**触发的："字典大小是否会超过 1 MB"是写入器的运行时决策，可通过 `parquet.dictionary.page.size.bytes` 调整（一些社区引擎默认调到 2 MB 或 4 MB 以提升列存表的字典命中率）。

### Parquet RLE_DICTIONARY 数据页布局

```
RLE_DICTIONARY 数据页：
  +--------------------+
  | Bit Width (1 byte) |  <-- ID 编码所需位宽（log2(dict size)）
  +--------------------+
  | RLE/bit-packed     |
  | hybrid encoding    |  <-- run-length 与 bit-packing 自动切换
  | of dictionary IDs  |
  +--------------------+
```

RLE/Bit-Packing Hybrid 是 Parquet 的二阶段编码：
- 当连续相同 ID >= 8 个时切到 RLE 模式
- 否则用 bit-packing（每 8 个 ID 一个 group）
- 编码器在写入时维护 buffer，根据当前模式决定是否切换

这种自适应编码使得"低基数 + 局部聚集"的字符串列（如有序日期、客户区域）能获得极高压缩比——不仅字典本身压缩，连字典 ID 序列也能被 RLE 进一步压。

### Parquet 字典回退示例

```python
# pyarrow 写入示例（伪代码）
import pyarrow.parquet as pq

# 默认开启字典编码
writer = pq.ParquetWriter(
    'out.parquet', schema,
    use_dictionary=True,                       # 默认 True
    dictionary_pagesize_limit=1024 * 1024,     # 1 MB
)

# 高基数列示例：UUID 列基本无重复
# 第一个 row group 写入 100 万个 UUID：
#   字典在写到 ~50K-70K UUID 时超过 1 MB → 触发回退
#   后续 page 改用 PLAIN（或 DELTA_BYTE_ARRAY）

# 低基数列示例：country code（200 distinct）
# 字典稳定在 ~3-4 KB → 永远使用 RLE_DICTIONARY
```

实战中，约 70% 的列存表字符串列受益于 Parquet 字典（业务标识、状态码、枚举类、地区编码、用户分类等都是低基数）；只有真正的高基数列（UUID、URL、Email、自由文本）才会触发回退。

### Parquet 字典与谓词下推

```
查询：SELECT count(*) FROM events WHERE country = 'CN'

字典下推流程：
  1. Reader 加载 column chunk 的 dictionary page
  2. 在字典中查 'CN' 是否存在，得到 dict_id = 7
  3. （或返回 0 → 跳过整个 row group，使用 statistics）
  4. 解码 RLE_DICTIONARY 数据页，对每个 ID 比较 == 7
  5. 永远不需要解码 'CN' 字符串本身

收益：
  1. 字符串比较 → 整数比较（快 5-10x）
  2. 字典级 NULL 检测（min/max statistics + dict 范围）
  3. IN 列表谓词：先在字典中找出所有匹配 ID，再扫描
```

Trino、Spark、Impala、DuckDB、ClickHouse 都实现了这一优化路径。

## ORC 字典编码

ORC 比 Parquet 更早采用字典编码（Hortonworks 在 2013 年的 Stinger Initiative 中把 ORC 作为 Hive 的列存默认格式）。其字典模型与 Parquet 类似但有几点不同：

### ORC 编码类型

| 编码 | 适用 | 说明 |
|------|------|------|
| `DIRECT` | 数值 | 通用编码 |
| `RLE_v1 / v2` | 整数 | run-length |
| `DICTIONARY` | string | 字符串字典 |
| `DICTIONARY_v2` | string | 优化后的字典编码 |
| `DELTA` | 整数 | delta |
| `PATCHED_BASE` | 整数 | patched delta |

### ORC 字典阈值

```
orc.dictionary.key.threshold = 0.8 (默认)
含义：如果 distinct values / total values > 0.8，禁用字典编码

控制：
  - 0.0 = 完全禁用字典
  - 1.0 = 总是使用字典
  - 默认 0.8 是 Hortonworks 实测的"字典通常仍有收益"边界
```

ORC 的阈值是 **基于行数比例**，而非字典大小。这意味着 ORC 在小 stripe 上更倾向回退，在大 stripe 上更倾向保留字典。这比 Parquet 的"绝对字典大小"决策略粗糙——但 ORC 的 stripe 通常远大于 Parquet 的 row group（256MB vs 128MB），所以相对效果接近。

### ORC stripe 字典布局

```
ORC stripe layout:
  +------------------------------+
  | Index Streams                |  <-- statistics, row index, bloom filter
  +------------------------------+
  | Data Streams                 |
  |   - PRESENT (null bitmap)    |
  |   - DATA (字典 ID 序列, RLE) |
  |   - DICTIONARY_DATA (UTF-8)  |
  |   - LENGTH (字典字符串长度)   |
  +------------------------------+
  | Stripe Footer                |
  +------------------------------+
```

ORC 把字典字符串本身（DICTIONARY_DATA）与字符串长度（LENGTH）拆分成两个独立 stream，便于压缩 codec（ZLIB/SNAPPY/ZSTD）针对不同分布单独压缩。这是 ORC 的"细粒度 stream"特色。

## ClickHouse `LowCardinality` 类型

ClickHouse 是少数把字典编码作为**用户可见的列类型**而非透明优化的引擎。`LowCardinality(String)` 在 19.0（2019）GA，自此成为 ClickHouse 表设计的关键工具。

### 基本用法

```sql
CREATE TABLE events (
    event_time   DateTime,
    user_id      UInt64,
    country      LowCardinality(String),    -- 200-300 distinct
    device_type  LowCardinality(String),    -- 5-10 distinct
    browser      LowCardinality(String),    -- 50-100 distinct
    page_url     String                       -- 高基数，不用 LC
)
ENGINE = MergeTree
ORDER BY (event_time, user_id);
```

`LowCardinality` 是一个**包装类型**：其底层结构是 `(dict, indices)`，其中 dict 是去重值数组，indices 是字典 ID（自动选择 UInt8/UInt16/UInt32 位宽）。

### LowCardinality vs String 性能对比

```
1 亿行 country 列（200 distinct）：

String:
  存储：~800 MB（每行平均 8 字节，加 LZ4 压缩到 ~100 MB）
  GROUP BY：字符串哈希
  WHERE：字符串比较

LowCardinality(String):
  存储：~100 MB ID 序列（UInt8）+ ~5 KB 字典 + LZ4 ≈ 30 MB
  GROUP BY：UInt8 哈希（10x 快）
  WHERE：UInt8 比较 + 字典查找一次（10-20x 快）
```

### LowCardinality 工作机制

```
插入 'China' 'USA' 'China' 'India':
  Part-level dictionary:
    {0: 'China', 1: 'USA', 2: 'India'}
  Indices:
    [0, 1, 0, 2]

不同 part 字典独立。merge 时合并字典：
  Part1 dict: {0: 'A', 1: 'B'}
  Part2 dict: {0: 'B', 1: 'C'}
  Merged dict: {0: 'A', 1: 'B', 2: 'C'}
  Part1 indices remap: 0->0, 1->1
  Part2 indices remap: 0->1, 1->2
```

### LowCardinality 设置项

```sql
-- 全局阈值（默认 8192）：
-- 字典超过此 distinct count 时性能下降，但不会自动回退
SETTINGS low_cardinality_max_dictionary_size = 8192;

-- 共享字典：跨 part 共享字典（实验）
SETTINGS low_cardinality_use_single_dictionary_for_part = 0;

-- LowCardinality(Nullable(String))：支持 NULL，字典中保留 NULL slot
CREATE TABLE t (city LowCardinality(Nullable(String))) ENGINE = MergeTree;
```

### LowCardinality 谓词下推

```sql
-- 物化视图与谓词下推都受益于 LowCardinality:
SELECT count() FROM events WHERE country = 'CN';
-- ClickHouse 内部:
--   1. 在每个 part 字典中查 'CN' 的 ID
--   2. 如果不存在，跳过整个 part
--   3. 如果存在，比较 ID（UInt8）

-- 与 Bloom filter 的协同
ALTER TABLE events ADD INDEX idx_country country TYPE bloom_filter GRANULARITY 4;
-- Bloom filter 直接对字典原始字符串建立，跳过整个 granule
```

### LowCardinality 使用陷阱

```sql
-- 反模式 1：高基数列用 LC
ALTER TABLE events MODIFY COLUMN url LowCardinality(String);
-- url 通常 distinct count 接近行数，字典本身比数据还大

-- 反模式 2：常变列用 LC
ALTER TABLE sessions MODIFY COLUMN session_token LowCardinality(String);
-- session_token 几乎每行不同，字典 merge 代价过高

-- 推荐：distinct < 10000 且重复率高的列
-- 国家、地区、城市、状态码、user_agent 类别等
```

`LowCardinality` 在 19.0（2019 年初）正式 GA，21.x 增加 `low_cardinality_allow_in_native_format` 改进客户端兼容，22.x 持续优化 merge 性能。

## Vertica：自动 LF/HF 字典选择

Vertica 是最早采用字典编码作为列存基础的商业数据库（C-Store 学术原型 2005，Vertica 商业产品 2010）。Vertica 的特色是**自动判断 LF 或 HF**：

| 编码 | 含义 | 适用 |
|------|------|------|
| `AUTO` | 自动选择 | 默认 |
| `RLE` | run-length | 排序后高度重复 |
| `BLOCK_DICT` | block 级字典 | 局部低基数 |
| `BLOCKDICT_COMP` | block 字典 + LZO | 局部低基数 + 通用压缩 |
| `COMMONDELTA_COMP` | 公共 delta | 等差数列 |
| `DELTAVAL` | delta 编码 | 单调整数 |
| `DELTARANGE_COMP` | delta + LZO | 类似 DELTA 加压缩 |
| `GCDDELTA` | GCD + delta | 倍数关系数据 |
| `GZIP_COMP` | GZIP 块压缩 | 不可预测高熵 |
| `RLE` | RLE | 高度重复 |
| `ZSTD_COMP/FAST/HIGH` | ZSTD 块压缩 | 通用 |

```sql
-- 显式指定字典编码
CREATE TABLE events (
    user_id INT,
    country VARCHAR(2) ENCODING BLOCK_DICT,      -- 局部字典
    region  VARCHAR(20) ENCODING BLOCKDICT_COMP, -- 字典 + LZO
    status  CHAR(8) ENCODING RLE                 -- 排序后高度重复
);

-- 让 Vertica 自动选编码（基于样本数据）
SELECT ANALYZE_STATISTICS('events');
-- 之后查看 Database Designer 推荐
SELECT DESIGNER_DESIGN_PROJECTION_ENCODINGS('events');
```

Vertica 的 `BLOCK_DICT` 是 **block 级字典**（每个 64KB block 独立字典），适合"局部聚集低基数"的列。这与 SQL Server columnstore 的 row group 字典思路一致。

### Vertica LF/HF 概念

Vertica 内部将字典编码列分成两类：
- **LF (Low-Frequency)**：column 内 distinct count 较低，适合 RLE / BLOCK_DICT
- **HF (High-Frequency)**：column 内 distinct count 较高但 < 行数，适合直接 BLOCK_DICT 或 ZSTD_COMP

Vertica 在 projection 创建后会做一次 **encoding tuning**：扫描真实数据，对每列尝试多种编码，选取压缩率最高且 CPU 代价可接受的方案。这是商业列存最早的"自动选编码"实现。

## Snowflake：透明的字典编码

Snowflake 把字典编码完全隐藏在 micropartition 内部：

```
Snowflake micropartition (compressed ~16 MB):
  +-----------------------------+
  | Header / metadata           |
  +-----------------------------+
  | Column 1: dict + RLE IDs    |
  +-----------------------------+
  | Column 2: dict + RLE IDs    |
  +-----------------------------+
  | ... (per column)            |
  +-----------------------------+
  | Footer: column statistics   |
  +-----------------------------+
```

用户没有任何 DDL 控制点，连"是否使用字典"都不可见——只能通过查询性能反推。Snowflake 的设计哲学：用户应该思考业务逻辑，不应该思考 codec 与编码。

```sql
-- Snowflake 完全无字典 DDL
CREATE TABLE events (
    event_id BIGINT,
    user_id BIGINT,
    country STRING,           -- 自动判断字典是否合适
    device_type STRING,       -- 自动选择
    payload VARIANT
);
```

实战中 Snowflake 对 distinct < 1000 的字符串列几乎总是采用字典；distinct > 100 万的列回退为 PLAIN + LZ4/ZSTD。但用户无法看到这个决策，也无法手动覆盖。

## Redshift：暴露多种字典编码

Redshift 是少数允许用户显式指定字典编码类型的引擎：

```sql
CREATE TABLE events (
    event_id    BIGINT     ENCODE az64,
    country_2   VARCHAR(2) ENCODE bytedict,    -- 1 字节字典，最多 256 entry
    region_20   VARCHAR(20) ENCODE text255,    -- word-level 字典 (245 word)
    description VARCHAR(500) ENCODE text32k,   -- 32 KB 字典
    notes       VARCHAR(1000) ENCODE zstd      -- 高基数，回退 ZSTD
)
DISTKEY(event_id);
```

| 编码 | 字典大小 | 适用 |
|------|---------|------|
| `BYTEDICT` | 256 entry | 极低基数（state code, gender） |
| `TEXT255` | 245 word，每 word ≤ 14 字节 | 字符串中重复 word 较多 |
| `TEXT32K` | 32 KB 总字典 | 较多但仍有限 distinct |
| `RAW` | 不压缩 | 排序键、整数 |
| `ZSTD` | -- | 高基数字符串 fallback |
| `LZO` | -- | 旧默认（已 deprecated） |

```sql
-- 让 Redshift 推荐字典编码
ANALYZE COMPRESSION events;
-- 输出每列推荐的 ENCODE 与节省百分比
```

`TEXT255` 是 Redshift 的特色：**word-level 字典**——把字符串按空格切分成 word，对 word 建字典。这对自然语言文本（产品描述、错误消息）很有效，但要求字符串中 word 重复率高。

`TEXT32K` 是 `TEXT255` 的大字典版本——支持更多 word，代价是单字典占 32 KB（每 1 MB block 内）。

## SQL Server Columnstore：VertiPaq 字典

SQL Server 的列式存储引擎来自 Power Pivot / SSAS 的 VertiPaq。它使用**两层字典**：

```
SQL Server columnstore dict:
  Row Group 1 (1M 行)
    Column A: local dict + RLE IDs
    Column B: local dict + RLE IDs
    ...
  Row Group 2
    ...
  Global String Store (跨 row group 共享)
    Frequently-seen strings shared by all row groups
```

```sql
-- 创建聚集列存索引
CREATE CLUSTERED COLUMNSTORE INDEX ccsi ON fact_sales;

-- 查看 row group 状态
SELECT object_id, partition_number, row_group_id, state_desc, total_rows
FROM sys.column_store_row_groups
WHERE object_id = OBJECT_ID('fact_sales');

-- state_desc 列含义：
--   OPEN: 行组正在加载（buffered，无压缩）
--   CLOSED: 已关闭，等待迁移
--   COMPRESSED: 已压缩（VertiPaq 字典 + RLE + bit-packing）
--   TOMBSTONE: 已删除
```

VertiPaq 的字典策略：
1. 每列在 row group 内建独立字典
2. 字符串列额外维护**全局 string store**（跨 row group 共享高频字符串）
3. 字典 ID 用最小可能 bit width 编码（如 8 distinct 用 3-bit）
4. ID 序列再叠加 RLE

```sql
-- COLUMNSTORE_ARCHIVE: 在 VertiPaq 基础上叠加 LZ77 (XPRESS9)
ALTER INDEX ccsi ON fact_sales REBUILD
  WITH (DATA_COMPRESSION = COLUMNSTORE_ARCHIVE);
-- 通常再省 30-50% 空间，扫描 CPU 翻倍
```

SQL Server 不允许用户禁用 columnstore 字典——这是 VertiPaq 的核心架构假设。

## DuckDB：FSST + Dictionary 互补

DuckDB 0.6+ 默认对 VARCHAR 列尝试两种编码：
- **Dictionary**：用于低基数字符串（distinct < 2/3 行数）
- **FSST**（Fast Static Symbol Table）：用于高基数但有共同子串的字符串（URL、JSON path）

```sql
-- DuckDB 不暴露字典 DDL，自动选择
CREATE TABLE events (
    event_id BIGINT,
    user_id  BIGINT,
    country  VARCHAR,    -- 低基数 → Dictionary
    url      VARCHAR,    -- 高基数 + 共同子串 → FSST
    payload  VARCHAR     -- 高基数随机 → Uncompressed
);

-- 查看每列实际编码
PRAGMA storage_info('events');
```

DuckDB 在 row group 写入时（默认 ~120K 行）按 vector（默认 2048 行）粒度尝试每种 codec，选择压缩比最佳者。这种 "per-row-group + sample-then-decide" 策略是嵌入式列存的标准做法。

FSST 的核心优势：
- 解压可逐 token 进行（不像 LZ4 必须解压整块），允许列上的局部访问与谓词下推
- 压缩比接近 LZ4，对 URL、UUID、JSON path 这类结构化字符串尤其有效
- 编码本身就保序——可在压缩域做 `LIKE 'prefix%'` 谓词

DuckDB 与 ClickHouse 的策略差异：
- ClickHouse 要求用户**显式声明** `LowCardinality(String)`
- DuckDB 自动判断，用户没有控制点

## SAP HANA：N-bit value-id 编码

SAP HANA 是字典编码做得最极致的内存列存：

```
SAP HANA 列编码流程:
  1. 每列建一个 value-id dictionary（按字典序或频率序）
  2. 用 N-bit 编码存 value-id (N = ceil(log2(distinct count)))
     - 8 distinct → 3-bit value-id
     - 256 distinct → 8-bit
     - 1M distinct → 20-bit
  3. 对 value-id 序列再做 prefix / cluster / sparse / indirect / RLE 五选一压缩
  4. 主存储分 delta（写优化）与 main（读优化）两层，定期 merge
```

```sql
-- 提示 HANA 选择 prefix 或 sparse 压缩
ALTER TABLE customers ALTER (customer_id INT NOT NULL UNIQUE);

-- 强制重新选择压缩
UPDATE customers WITH PARAMETERS('OPTIMIZE_COMPRESSION'='FORCE');

-- 查看每列字典与编码
SELECT column_name, dictionary_size, value_id_size, compression_type
FROM SYS.M_CS_COLUMNS
WHERE table_name = 'CUSTOMERS';
```

HANA 在压缩域上的 SIMD 谓词执行使得它能在内存中高效处理 TB 级数据。"all data in memory" 听起来很奢侈，但加上 5-10x 的字典压缩，单服务器 6 TB 内存可以覆盖 30-60 TB 原始数据。

## Apache Pinot：StringColumn 默认字典

Apache Pinot（LinkedIn 2014 开源）是实时 OLAP 数据库，所有 String 类型列默认使用字典：

```json
// Pinot 表配置
{
  "tableName": "events",
  "schema": {
    "dimensionFieldSpecs": [
      {"name": "country", "dataType": "STRING"},
      {"name": "device", "dataType": "STRING"}
    ]
  },
  "tableIndexConfig": {
    "noDictionaryColumns": ["url"],            // 显式禁用字典
    "createInvertedIndexOnDictColumn": true    // 在字典上建倒排
  }
}
```

Pinot 的字典编码策略：
- 默认 **所有 STRING 维度列建字典** + sorted dictionary
- 字典本身排序，便于二分查找与范围谓词
- 在字典上叠加 inverted index、bloom filter、range index 等多种索引
- 高基数列通过 `noDictionaryColumns` 显式禁用

字典默认开启的设计是 Pinot 实时分析的关键：在 1ms 级查询响应时间下，每次都做字符串比较是不可接受的。

## Apache Druid：维度默认字典

Apache Druid（Metamarkets 2011 创建，2018 进入 Apache）的 segment 设计中，所有"维度（dimension）"列**强制字典编码**：

```json
{
  "dataSchema": {
    "dimensionsSpec": {
      "dimensions": [
        "country",
        "device",
        {"name": "url", "type": "string", "createBitmapIndex": false}
      ]
    },
    "metricsSpec": [
      {"name": "count", "type": "count"},
      {"name": "revenue", "type": "doubleSum", "fieldName": "amount"}
    ]
  }
}
```

Druid segment 内每列三个 stream：
- `dictionary`：UTF-8 字符串字典（按字典序排序）
- `value column`：字典 ID 序列（VInt 或 bit-packed）
- `bitmap index`：每个 distinct value 一个 bitmap（默认开启）

这种"字典 + bitmap"的组合是 Druid 实时分析的核心。维度列**没有回退机制**——即使是 UUID 字段，也会被强制字典化。这是 Druid 与 Pinot 的关键差异点。

## TiDB TiFlash：列副本字典

TiDB 的列存副本 TiFlash（基于 ClickHouse fork）实现了与 ClickHouse `LowCardinality` 类似但完全自动的字典编码：

```sql
-- TiDB 用户层
ALTER TABLE events SET TIFLASH REPLICA 1;

-- TiFlash 内部对低基数字符串列自动应用字典编码
-- DMFile pack 内每列独立字典
```

TiFlash 的字典层级：
1. **DMFile pack**：~64K 行一个 pack，pack 内独立字典
2. **DMFile**：多个 pack 组成 DMFile（~1M-10M 行）
3. 跨 DMFile 不共享字典

5.x 之后 TiFlash 增加了对 distinct count 的运行时统计，自动决定是否禁用字典。

## OceanBase：HTAP 列存字典

OceanBase 4.x 引入了真正的列存模式（与 TiDB TiFlash 类似的 HTAP 设计），列存模式下每个 **微块**（microblock，通常 16-256 KB）独立字典：

```sql
-- 创建列存表
CREATE TABLE fact_sales (
    sale_id BIGINT,
    sale_date DATE,
    country VARCHAR(20),
    amount DECIMAL(18, 2)
) WITH COLUMN_GROUP (default_column_group, single_column_group);

-- 列存模式下，country 列自动字典化
```

OceanBase 4.2+ 列存的字典作用域是 **微块级**，与 SQL Server columnstore row group 类似。低基数列在微块内字典 + bit-packing；高基数列回退到 ZSTD/LZ4。

## StarRocks：低基数全局字典

StarRocks 的"低基数全局字典"（Low Cardinality Global Dictionary）是 OLAP 引擎里的一个独特优化：

```
普通字典：每个 segment 独立字典 → 跨 segment 比较需要解码
全局字典：FE 维护表级 string-to-id 映射 → 跨 segment 直接 ID 比较

全局字典适用条件：
  1. 列 distinct count < 阈值（默认 256）
  2. 列被用于 group by / join / 高频谓词

实现：
  1. FE 在 ANALYZE 时构建全局字典
  2. BE 在加载数据时查 FE 字典获取 ID
  3. 查询执行时 BE 用 FE 字典做谓词下推
  4. 数据更新触发字典增量同步
```

```sql
-- StarRocks 自动启用，无需 DDL
CREATE TABLE events (
    event_id BIGINT,
    country VARCHAR(20),
    ...
)
DUPLICATE KEY(event_id)
DISTRIBUTED BY HASH(event_id);

-- 查看全局字典
SELECT * FROM information_schema.global_dict WHERE table_name = 'events';
```

StarRocks 的全局字典极大提升了低基数列的 group by 性能（不再需要字符串哈希），代价是 FE 元数据开销。当 distinct count 超过阈值时，自动放弃全局字典回退到 segment 级。

## Doris：列存字典

Doris（Apache 2018 开源，原百度 Palo）与 StarRocks 同源，但全局字典是 2.x 之后才补齐。Doris 的字典编码作用于 segment 级：

```sql
CREATE TABLE events (
    event_id BIGINT,
    country VARCHAR(20),
    ...
) ENGINE=OLAP
DUPLICATE KEY(event_id)
DISTRIBUTED BY HASH(event_id) BUCKETS 10
PROPERTIES (
    "compression" = "LZ4"
);
```

Doris 自动对 string 列在 segment 内做字典编码，作用域是 segment 内每 64KB 数据块。3.x 计划引入与 StarRocks 类似的全局字典。

## QuestDB：SYMBOL 类型

QuestDB 是时序数据库，把字典编码做成了独立的列类型 `SYMBOL`：

```sql
CREATE TABLE trades (
    ts TIMESTAMP,
    symbol SYMBOL CAPACITY 10000 CACHE,    -- 字典编码
    side SYMBOL,                             -- 默认 capacity = 256
    price DOUBLE,
    qty DOUBLE
) TIMESTAMP(ts) PARTITION BY DAY;
```

`SYMBOL` 在 QuestDB 中：
- 物理存储是 int32 ID + 全表唯一字典
- distinct count 上限由 `CAPACITY` 指定
- `CACHE` 选项把字典常驻内存，加速查找
- 适合股票代码、客户 ID、传感器 ID 等典型时序维度

QuestDB 的设计假设："时序数据中维度列基数有限，事实数据中数值列高基数。"——这是时序场景的典型特征。

## Oracle In-Memory（IM）字典

Oracle Database 12.1.0.2+ 的 In-Memory Column Store（IMC）使用列式压缩 + 字典编码。

```sql
-- 启用 IM 字典编码
ALTER TABLE sales INMEMORY MEMCOMPRESS FOR QUERY HIGH;
-- 内部启用字典 + RLE + bit-packing

-- 查看每列字典统计
SELECT object_name, segment_name, segment_type, dict_size, distinct_values
FROM v$im_segments WHERE object_name = 'SALES';
```

Oracle IM 的压缩层级：

| 模式 | 字典 | 用途 |
|------|------|------|
| `MEMCOMPRESS FOR DML` | 否 | 写优化，无字典 |
| `MEMCOMPRESS FOR QUERY LOW` | 是（基础） | 默认推荐 |
| `MEMCOMPRESS FOR QUERY HIGH` | 是（双层） | 查询性能最佳 |
| `MEMCOMPRESS FOR CAPACITY LOW` | 是（深度） | 空间最省 |
| `MEMCOMPRESS FOR CAPACITY HIGH` | 是（最深） | 极致省空间 |

Oracle 的 HCC（Hybrid Columnar Compression）作用于磁盘 storage（仅 Exadata），同样基于字典 + RLE，但与 IMC 是两个独立子系统。

## PostgreSQL：无原生字典

PostgreSQL 核心代码不提供字典编码——这是行存数据库的典型遗留。但社区扩展填补了空白：

| 扩展 | 说明 |
|------|------|
| Citus columnar | Citus 公司维护的列式 access method（11.x 起内置） |
| Hydra | 基于 Citus columnar 的 fork |
| ZHEAP | 早期列式实验，未进入主线 |
| TimescaleDB | 列式 hypertable 压缩，含字典编码 |
| pg_lakehouse | 实验性 Lakehouse 扩展 |
| parquet_fdw | 通过外部 Parquet 文件读取，享受 Parquet 字典 |

```sql
-- Citus columnar (11.x)
CREATE EXTENSION citus;
CREATE TABLE events (...) USING columnar;
-- 内部使用 Parquet-like 编码（含字典）

-- TimescaleDB hypertable 列式压缩
ALTER TABLE conditions SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'device_id'
);
SELECT add_compression_policy('conditions', INTERVAL '7 days');
-- 老 chunk 自动转为列式，含字典编码
```

PostgreSQL 主线长期未引入字典编码的根本原因是 **HEAP 页面格式与索引强耦合**——引入列式存储需要重写 buffer manager。这也是 EnterpriseDB、Fujitsu Enterprise Postgres 等商业版的差异化点之一。

## MySQL / MariaDB：无原生字典

MySQL InnoDB / MyISAM 都不支持字典编码。InnoDB 的 PAGE 压缩本质是页内字典（重复字节序列被替换为字典 ID），但作用于字节级而非列级，与列存的字典编码完全不同。

MariaDB 在 ColumnStore（已弃用）中曾实现列式字典，但社区版已不再维护。MyRocks（基于 RocksDB）的"字典压缩"也是字节级（RocksDB DictionaryCompressor），非列式。

## Spark / Hive / Trino / Presto：读 Parquet/ORC 字典

Spark SQL、Hive、Trino、Presto 本身不存数据，它们的字典编码完全来自 Parquet / ORC 文件格式：

```sql
-- Spark 写 Parquet（默认字典）
CREATE TABLE events USING parquet
OPTIONS('compression'='snappy', 'parquet.enable.dictionary'='true')
AS SELECT * FROM source;

-- Hive 写 Parquet（默认字典）
SET parquet.enable.dictionary=true;
CREATE TABLE events STORED AS PARQUET
TBLPROPERTIES ('parquet.compression'='SNAPPY')
AS SELECT * FROM source;

-- Trino 通过连接器（Hive、Iceberg、Delta）写 Parquet/ORC
CREATE TABLE hive.db.events
WITH (format='PARQUET', parquet_writer_compression_codec='ZSTD')
AS SELECT * FROM source;
```

读取时四个引擎都实现了字典下推：
- 字典 page 加载一次后缓存
- 谓词在字典上预先求值，得到匹配 ID 集合
- 数据页扫描时只比较 ID
- IN 列表 / 范围谓词都受益

## 时间旅行：字典编码的演进

```
1972 Codd 论文："字符串列应该 normalized 到 lookup 表"  (字典编码理念雏形)
1985-1995 Sybase IQ：商业列存字典（首次产品化）
1999 MonetDB：开源列存字典（学术原型）
2005 C-Store：字典 + RLE + bit-packing 三件套（Stonebraker 团队）
2010 Vertica：商业化 C-Store + 自动 LF/HF 编码选择
2010 Power Pivot / VertiPaq：消费级字典编码（Excel 嵌入）
2012 SQL Server Columnstore：把 VertiPaq 引入企业 OLTP
2013 Apache ORC / Parquet：开放字典规范（Stinger / Cloudera）
2013 Apache Druid：维度强制字典 + bitmap
2014 Apache Pinot：StringColumn 默认字典
2014 BigQuery Capacitor：完全透明字典 + record reorder
2014 Snowflake：micropartition 透明字典
2015 ClickHouse：开源（早期还没有 LowCardinality）
2018 ORC v2 / Parquet 2.x：引入 RLE_DICTIONARY (DICTIONARY_v2)
2019 ClickHouse 19.0：LowCardinality(String) GA
2020 DuckDB FSST：高基数字符串补充字典
2020 StarRocks：低基数全局字典优化
2021 OceanBase 3.x → 4.x：引入列存字典
2023 Doris 2.x：补齐全局字典
```

字典编码作为列存的"基本三件套"之一（与 RLE、bit-packing 并列），从 Sybase IQ 到 Snowflake 经历了 30 多年的演化，从商业秘密变成开放规范，从专家显式选项变成完全透明。

## 字典编码与谓词下推

字典编码与列存谓词下推是天然搭档：

### 等值谓词

```
WHERE country = 'CN'
1. 字典查找：'CN' → dict_id 7
2. 在 ID 序列上做 == 7
3. 跳过字符串解码
```

### IN 列表谓词

```
WHERE country IN ('CN', 'JP', 'KR')
1. 在字典中查 'CN'/'JP'/'KR' → IDs {7, 12, 23}
2. 在 ID 序列上做 IN {7, 12, 23}
3. 编译期把 IN 转换为 bitmap (set membership) 测试
```

### 范围谓词

```
WHERE region BETWEEN 'A' AND 'M'
要求字典是排序的（Druid / Pinot 默认）：
1. 在字典中找 'A' 与 'M' 的 ID 范围 [low_id, high_id]
2. 在 ID 序列上做 BETWEEN
3. 跳过字符串比较

非排序字典（Parquet 默认）：
1. 扫描字典，标记每个 ID 是否在范围内 → 得到 bit set
2. 在 ID 序列上查 bit set
```

### LIKE 谓词

```
WHERE description LIKE 'error%'
要求字典是排序的：
1. 在字典中查 'error' 的前缀范围 → ID set
2. 同上

非排序字典 + FSST：
1. 扫描字典，对每个字符串做 LIKE → 标记 ID set
2. 在 ID 序列上查 ID set
（FSST 编码后可在不解压的情况下做前缀匹配）
```

### 字典级 statistics

```
Parquet column chunk metadata:
  min_value: dict[min_id]    -- 字典中最小字符串
  max_value: dict[max_id]    -- 字典中最大字符串
  distinct_count: dict.size()
```

这些 statistics 让谓词在 row group 级别就能跳过——比字典扫描更早一层的优化。

## 字典编码与 Bloom filter

Bloom filter 是字典编码的天然补充：

```
Parquet 2.x 字典 + Bloom filter:
  1. 字典 page (per row group): 完整 distinct list
  2. Bloom filter (per column chunk): 概率包含测试

谓词执行：
  WHERE user_id = 'U123456789'
  1. Bloom filter 测试 → "可能不存在" → 跳过 row group
  2. 字典查找 → "确定不存在" → 跳过
  3. 字典查找 → "存在" → 扫描 ID 序列

Bloom filter 适用于高基数列（字典回退后），字典适用于低基数列。
```

## 字典编码与压缩域 join

```
fact 表 country_id (字典 ID)：[7, 12, 7, 23, 12, ...]
dim_country 表 country_name + country_id 字典：{7: 'CN', 12: 'US', 23: 'JP'}

传统 join：
  1. 解码 fact.country_id 为 'CN' / 'US' / 'JP'
  2. 与 dim_country.country_name 做字符串 hash join

压缩域 join（SAP HANA / DB2 BLU / Vertica）：
  1. 在字典中查 dim_country.country_name → ID set
  2. 直接 fact.country_id IN ID set
  3. 跳过字符串解码 + 字符串 hash
```

压缩域 join 仅在 fact 表与 dim 表共享字典时高效——这要求构建时显式协调字典 ID 分配，或在查询执行时动态对齐。SAP HANA 的"calc views" 在编译期协调字典；StarRocks 的全局字典在 FE 协调。

## 字典编码的实战权衡

### 何时启用？

```
推荐启用字典编码:
  1. 列 distinct count < 1 万（极低基数）
  2. 列 distinct count < 10 万 + 字符串平均长度 > 8 字节（中低基数 + 长字符串）
  3. 列被频繁用于 group by / join / 谓词
  4. 列在数据中重复率高（top 10 值占 80% 以上）

不推荐启用字典编码:
  1. 高基数列（UUID、URL、Email、自由文本）
  2. 数值列（INT/FLOAT 已经很紧凑）
  3. 写密集型列（字典维护开销大）
  4. 数据均匀分布（字典 ID 仍然 N-bit）
```

### 调优旋钮

| 旋钮 | Parquet | ORC | ClickHouse | Pinot | DuckDB |
|------|---------|-----|-----------|-------|--------|
| 字典大小阈值 | `parquet.dictionary.page.size.bytes` (1MB) | `orc.dictionary.key.threshold` (0.8) | `low_cardinality_max_dictionary_size` (8192) | `noDictionaryColumns` | 自动 |
| 强制启用 | `parquet.enable.dictionary` (true) | -- | `LowCardinality` 类型 | 默认开启 | 自动 |
| 强制禁用 | `parquet.enable.dictionary=false` | `orc.dictionary.key.threshold=0.0` | 用 `String` | `noDictionaryColumns` | 自动 |
| 跨 file 共享 | -- | -- | `low_cardinality_use_single_dictionary_for_part` | -- | -- |
| 字典页大小 | 1 MB 默认 | -- | -- | -- | -- |

### 监控字典效果

```sql
-- ClickHouse: 查看 LowCardinality 列的字典大小
SELECT
    column,
    sum(data_compressed_bytes) AS compressed,
    sum(data_uncompressed_bytes) AS uncompressed,
    compressed / uncompressed AS ratio
FROM system.columns
WHERE table = 'events' AND type LIKE 'LowCardinality%'
GROUP BY column;

-- Parquet: 用 parquet-tools 查看 row group 编码
parquet-tools meta events.parquet
-- 查看每列 encoding 字段，是否包含 RLE_DICTIONARY

-- DuckDB: 查看每列实际编码
PRAGMA storage_info('events');

-- SAP HANA
SELECT column_name, dictionary_size, value_id_size, compression_type
FROM SYS.M_CS_COLUMNS WHERE table_name = 'EVENTS';

-- SQL Server columnstore
SELECT object_id, partition_number, row_group_id,
       state_desc, total_rows, size_in_bytes
FROM sys.column_store_row_groups WHERE object_id = OBJECT_ID('EVENTS');

-- Redshift: 查看每列实际编码
SELECT "column", "type", "encoding"
FROM PG_TABLE_DEF WHERE tablename = 'events';
```

## 与对象存储的交互

字典编码与云对象存储的成本模型紧密相关：

```
S3 / GCS / OSS：按字节扫描计费（BigQuery / Athena / Redshift Spectrum 等）
  字典编码 → 扫描字节减少 → 账单减少

S3 ListObjectsV2 + GetObject：按请求次数与字节计费
  字典 page 单独 GET → 一次小请求即可拿到整列字典
  vs PLAIN 编码：必须 GET 整个 column chunk

ZSTD + 字典：双重压缩
  字典 → 字符串到 ID（语义压缩）
  ZSTD → ID 序列到字节（熵压缩）
  双重叠加可达 10-30x 总压缩比
```

这就是为什么 Snowflake / BigQuery / Redshift Spectrum / Athena 全部默认字典——按字节计费下，字典是最直接的省钱手段。

## 关键发现

1. **没有 SQL 标准**：SQL:2003 / 2016 / 2023 都未定义字典编码语法。所有用户可见的字典控制都是厂商扩展或文件格式规范。

2. **行存 vs 列存的鸿沟**：行存数据库（PostgreSQL / MySQL / MariaDB / SQLite / Informix / Firebird / H2 / HSQLDB / Derby / CockroachDB / YugabyteDB）几乎全部不支持列级字典编码——这是行存架构的根本限制，而非实现缺失。

3. **PostgreSQL 是异类**：作为顶级开源 OLTP 数据库，它在字典编码上完全空白，必须依靠 Citus columnar、TimescaleDB、Hydra 等扩展弥补。这是 PG 行存架构遗留的代价。

4. **Parquet 的 1 MB 阈值是事实标准**：parquet-mr / parquet-cpp 默认 `parquet.dictionary.page.size.bytes = 1048576`，超过即回退 PLAIN。这一阈值通过 Spark / Trino / Hive / Impala / Athena / DuckDB / ClickHouse / Snowflake 外部表传播到整个 Lakehouse 生态，已成开放规范。

5. **ORC 用相对阈值，Parquet 用绝对阈值**：ORC 的 `orc.dictionary.key.threshold = 0.8` 是 distinct/total 比例；Parquet 的 1 MB 是字典绝对大小。在大 stripe / row group 场景下两者效果相近，小数据时 ORC 更激进保留字典。

6. **ClickHouse `LowCardinality` 是用户可见字典编码的孤例**：唯一把字典作为列类型暴露在 DDL 中的开源引擎（19.0 GA, 2019）。这给了用户完整控制权，代价是 schema 设计需要识别哪些列是低基数。

7. **云数仓全部"零旋钮"**：Snowflake / BigQuery / Redshift（基础类型） 完全不暴露字典选择，连"是否使用字典"都不可见。设计哲学：用户应该思考业务，不应该思考编码。

8. **Redshift 是中间路线**：`ENCODE BYTEDICT/TEXT255/TEXT32K` 暴露多种字典类型，又提供 `ANALYZE COMPRESSION` 自动推荐——"专家旋钮 + 默认自动"的折中。

9. **Vertica 是字典编码的开山鼻祖**：C-Store 学术原型 2005，商业产品 2010，自动 LF/HF 选择 + Database Designer 调优工具。今天所有自动选编码的引擎本质都在追赶 Vertica。

10. **Druid / Pinot 的"维度强制字典"哲学**：实时 OLAP 引擎不允许维度列回退——即使是 UUID 也字典化。这是为了 1ms 级查询响应时间，宁可付出字典维护代价也不能容忍字符串扫描。

11. **StarRocks 的全局字典是 OLAP 引擎的独特优化**：FE 维护表级 string-to-id 映射，跨 segment 直接 ID 比较。代价是元数据开销与字典更新协调，收益是 group by / join 性能巨大提升。

12. **DuckDB FSST 与字典互补**：低基数 → Dictionary，高基数有共同子串 → FSST，高基数随机 → 不压缩。这种"按基数分层"的策略代表了嵌入式列存的未来方向。

13. **SAP HANA 的 N-bit value-id 是极致**：value-id 用最小 bit width 编码，再叠加 prefix/cluster/sparse/indirect/RLE 五选一。"all data in memory" 加 5-10x 字典压缩，让单服务器能装下 30-60 TB 数据。

14. **字典与谓词下推是天然搭档**：等值、IN、范围、LIKE 谓词都能在字典上预求值，得到 ID set 后在压缩域匹配。这是列存查询性能的核心来源。

15. **字典与 Bloom filter 是互补关系**：低基数列字典已足够；高基数列回退后由 Bloom filter 接力做行组级跳过。Parquet 2.x 把两者都纳入规范。

16. **压缩域 join 仅在共享字典时高效**：fact 与 dim 必须协调字典 ID 分配（StarRocks 全局字典、SAP HANA calc views）才能跳过字符串解码。多数引擎仍然在执行期解码后 join。

17. **HTAP 引擎用列副本继承字典编码**：TiDB TiFlash、OceanBase 列存模式、SingleStore 列存表都通过 Raft / paxos 同步出列存副本，字典在副本端独立维护。这是 HTAP 时代字典编码的典型部署形态。

18. **QuestDB SYMBOL 类型是时序数据库的字典样板**：把字典做成独立列类型（不是包装类型），用户显式声明 capacity，cache 选项控制内存常驻——为时序场景"少量维度 + 大量数值"设计。

19. **InfluxDB 3.0 的转向间接证明 Parquet 字典已经够强**：放弃自研 TSM 改用 Apache Parquet + DataFusion，意味着 Parquet 的 RLE_DICTIONARY 已经追平时序专用编码。这一信号将影响整个时序生态。

20. **字典编码是按字节计费云数仓的"省钱第一发动机"**：BigQuery / Athena / Redshift Spectrum / Snowflake 的扫描字节计费下，字典编码减少的扫描量直接转化为账单减少——这是字典编码在云时代被全面默认开启的根本原因。

## 参考资料

- Apache Parquet: [Parquet Format Specification](https://github.com/apache/parquet-format/blob/master/Encodings.md)
- Apache ORC: [ORC Specification v1](https://orc.apache.org/specification/ORCv1/)
- ClickHouse: [LowCardinality Data Type](https://clickhouse.com/docs/en/sql-reference/data-types/lowcardinality)
- ClickHouse: 19.0 release notes (LowCardinality GA, 2019)
- Vertica: [Encoding Types](https://docs.vertica.com/latest/en/sql-reference/statements/create-statements/create-projection/encoding-types/)
- SAP HANA: [Column Store Compression](https://help.sap.com/docs/SAP_HANA_PLATFORM)
- SQL Server: [Columnstore Indexes Overview](https://learn.microsoft.com/en-us/sql/relational-databases/indexes/columnstore-indexes-overview)
- Redshift: [ANALYZE COMPRESSION](https://docs.aws.amazon.com/redshift/latest/dg/r_ANALYZE_COMPRESSION.html)
- Redshift: [Compression Encodings](https://docs.aws.amazon.com/redshift/latest/dg/c_Compression_encodings.html)
- DuckDB: [Lightweight Compression in DuckDB](https://duckdb.org/2022/10/28/lightweight-compression.html)
- Apache Pinot: [Indexing Reference](https://docs.pinot.apache.org/basics/indexing)
- Apache Druid: [Segments and Dictionaries](https://druid.apache.org/docs/latest/design/segments)
- Boncz, Neumann, Leis: "FSST: Fast Random Access String Compression" (CWI / TUM, VLDB 2020)
- Stonebraker et al.: "C-Store: A Column-oriented DBMS" (VLDB 2005)
- Lemire, Boytsov: "Decoding billions of integers per second through vectorization" (SP&E, 2015)
- Abadi, Madden, Ferreira: "Integrating Compression and Execution in Column-Oriented Database Systems" (SIGMOD 2006)
- StarRocks: [Low Cardinality Global Dictionary Optimization](https://docs.starrocks.io/docs/table_design/global_dict/)
- Snowflake: [Micro-partitions and Data Clustering](https://docs.snowflake.com/en/user-guide/tables-clustering-micropartitions)
- BigQuery: [Capacitor Storage Format](https://cloud.google.com/blog/products/bigquery/inside-capacitor-bigquerys-next-generation-columnar-storage-format)
