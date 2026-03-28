# ClickHouse: 字符串类型

> 参考资料:
> - [1] ClickHouse - String Data Type
>   https://clickhouse.com/docs/en/sql-reference/data-types/string
> - [2] ClickHouse - FixedString
>   https://clickhouse.com/docs/en/sql-reference/data-types/fixedstring


## 1. String: 无长度限制的字节序列


ClickHouse 的 String 类型是任意长度的字节序列:

```sql
CREATE TABLE logs (
    id      UInt64,
    message String,           -- 无长度限制，UTF-8 编码
    ip      String            -- 也可以存非 UTF-8 数据（本质是字节序列）
) ENGINE = MergeTree() ORDER BY id;

```

 String 不是"文本"，而是"字节序列":
   可以存储 UTF-8 文本、二进制数据、甚至图片
   没有编码验证（不保证是有效 UTF-8）
   没有长度限制（受内存限制）
   没有 VARCHAR(n) 的概念（不存在截断行为）

 对比:
   MySQL: VARCHAR(255)/TEXT/MEDIUMTEXT → 分级存储
   PostgreSQL: TEXT（无限制）vs VARCHAR(n)（有限制）
   BigQuery: STRING（无限制，保证 UTF-8）
   SQLite: TEXT（无限制）

## 2. FixedString(N): 定长字节序列


```sql
CREATE TABLE events (
    id      UInt64,
    country FixedString(2),   -- 国家代码，恰好 2 字节
    hash    FixedString(32)   -- MD5 哈希，恰好 32 字节
) ENGINE = MergeTree() ORDER BY id;

```

 FixedString(N) 总是恰好存储 N 个字节:
   短于 N 字节: 用 \0 填充到 N 字节
   长于 N 字节: 报错

 为什么需要 FixedString?
 (a) 列存压缩: 定长列的压缩率更高（列内对齐，无长度前缀）
 (b) 内存对齐: 定长列支持更高效的 SIMD 运算
 (c) 省空间: 没有 1-4 字节的长度前缀（String 需要 varint 长度前缀）
 适用场景: 国家代码、货币代码、MD5/SHA 哈希

## 3. LowCardinality: 字典编码优化


```sql
CREATE TABLE events (
    id     UInt64,
    status LowCardinality(String),  -- 字典编码
    source LowCardinality(String)
) ENGINE = MergeTree() ORDER BY id;

```

 LowCardinality 是 ClickHouse 独有的类型修饰符:
   存储: 将重复值替换为字典索引（如 'active'→0, 'inactive'→1）
   查询: 比较字典索引而非完整字符串
   压缩: 100 万行 status 列只存 2 个唯一值 + 100 万个 1-byte 索引

 适用条件: 唯一值少于 ~10,000 个
 性能提升: 查询速度提升 2-10 倍（取决于基数）

 对比:
   MySQL: 没有类似功能（需要手动建枚举表 + JOIN）
   PostgreSQL: 没有类似功能
   BigQuery: 列式压缩自动检测重复值（但不暴露给用户）

## 4. UUID 类型


```sql
CREATE TABLE users (
    id   UUID DEFAULT generateUUIDv4(),  -- 128 位 UUID
    name String
) ENGINE = MergeTree() ORDER BY id;

```

 UUID 比 String 存储 UUID 更高效:
   UUID: 16 字节定长（FixedString(16) 的别名）
   String: 36 字节（'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx' + 长度前缀）

## 5. Enum vs LowCardinality(String)


 Enum8/Enum16: 编译时定义值集合，添加新值需要 ALTER TABLE
 LowCardinality(String): 运行时自动学习值集合，灵活

 推荐: 优先使用 LowCardinality(String)（更灵活）
 只在需要严格限制值集合时使用 Enum

## 6. 对比与引擎开发者启示

ClickHouse 字符串类型的设计:
(1) String = 字节序列 → 不验证编码
(2) FixedString(N) → 定长优化（压缩 + SIMD）
(3) LowCardinality → 字典编码（低基数列的杀手级优化）
(4) UUID 专用类型 → 比 String 节省 56% 空间

对引擎开发者的启示:
列存引擎应提供 LowCardinality/字典编码:
日志/事件数据中大量列是低基数的（status, country, source）。
字典编码可以将这些列的存储减少 90%+ 并加速查询。
FixedString 对已知定长数据（哈希、代码）有显著的存储优势。

