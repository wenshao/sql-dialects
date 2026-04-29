# 内置哈希函数 (Built-in Hash Functions)

哈希函数是数据库中最被低估的"基础设施"——它既是分区裁剪、去重、分片的算法核心，也是数据完整性校验、密码存储、签名校验的关键工具。但 SQL 标准对哈希只字未提，于是每个引擎自行其是：从 PostgreSQL 仅有 `md5()` 一个内置函数，到 ClickHouse 提供 30+ 种哈希函数（cityHash、sipHash、farmHash、xxHash、MurmurHash 等），跨引擎差异之大让人难以想象这是同一种"哈希"。

## 没有 SQL 标准

SQL 标准（SQL:1992 / SQL:2003 / SQL:2016 / SQL:2023）从未定义任何哈希函数。所有的 `MD5`、`SHA1`、`SHA2`、`CRC32`、`xxHash`、`FARM_FINGERPRINT` 等都是各引擎的私有扩展。这导致了几个直接后果：

1. **函数名不统一**：MySQL 用 `MD5()`，PostgreSQL 用 `md5()`，SQL Server 用 `HASHBYTES('MD5', ...)`，Oracle 用 `DBMS_CRYPTO.HASH(...)`。
2. **返回类型不统一**：有的返回 `VARCHAR`（十六进制字符串），有的返回 `BINARY`/`BYTEA`（二进制），有的返回 `BIGINT`（64 位整数）。
3. **算法选择不统一**：同样叫 `HASH()`，Snowflake 实现是基于 SHA-256 的 64 位变体，DuckDB 是 MurmurHash3 的变体，BigQuery 又有完全不同的 `FARM_FINGERPRINT` 实现。

本文按算法和用途分别梳理 45+ 个引擎的内置哈希函数支持情况。

## 哈希函数分类

### 密码学 vs 非密码学哈希

| 类别 | 代表算法 | 特性 | 典型用途 |
|------|---------|------|---------|
| 密码学哈希 (Cryptographic) | MD5, SHA-1, SHA-2, SHA-3 | 抗碰撞、不可逆、雪崩效应 | 数据完整性、密码存储、数字签名 |
| 非密码学哈希 (Non-cryptographic) | xxHash, MurmurHash, CityHash, FarmHash, FNV | 速度极快、分布均匀但可碰撞 | 哈希表、分片键、Bloom filter、HLL |
| 校验和 (Checksum) | CRC32, Adler32 | 检测单比特错误，速度极快 | 网络/磁盘错误检测 |
| 安全哈希 (Keyed Hash) | SipHash, HMAC | 带密钥防 HashDoS 攻击 | 在线服务的哈希表防护 |

**重要**：密码学哈希虽然安全，但速度比非密码学哈希慢一两个数量级。在引擎内部做分片、分区、去重时，应优先选择 xxHash/CityHash/MurmurHash 等非密码学算法。

### 输出长度对比

| 算法 | 位宽 | 字节数 | 十六进制字符数 |
|------|------|-------|-------------|
| CRC32 | 32 | 4 | 8 |
| MD5 | 128 | 16 | 32 |
| SHA-1 | 160 | 20 | 40 |
| SHA-224 | 224 | 28 | 56 |
| SHA-256 | 256 | 32 | 64 |
| SHA-384 | 384 | 48 | 96 |
| SHA-512 | 512 | 64 | 128 |
| SHA3-256 | 256 | 32 | 64 |
| xxHash32 | 32 | 4 | 8 |
| xxHash64 | 64 | 8 | 16 |
| xxHash128 / XXH3 | 128 | 16 | 32 |
| MurmurHash3-32 | 32 | 4 | 8 |
| MurmurHash3-128 | 128 | 16 | 32 |
| CityHash64 | 64 | 8 | 16 |
| CityHash128 | 128 | 16 | 32 |
| FarmHash64 | 64 | 8 | 16 |
| SipHash-2-4-64 | 64 | 8 | 16 |
| SipHash-2-4-128 | 128 | 16 | 32 |
| FNV-1a-64 | 64 | 8 | 16 |

## 支持矩阵（45+ 引擎）

### MD5 / SHA-1 / SHA-2 家族

| 引擎 | MD5 | SHA-1 | SHA-256 | SHA-384 | SHA-512 | SHA-3 | 版本与备注 |
|------|-----|-------|---------|---------|---------|-------|-----------|
| PostgreSQL | `md5()` | `digest()` | `digest()` | `digest()` | `digest()` | -- | md5 自 7.x；其他需 pgcrypto |
| MySQL | `MD5()` | `SHA1()` | `SHA2(s,256)` | `SHA2(s,384)` | `SHA2(s,512)` | -- | MD5/SHA1 自 4.0；SHA2 自 5.5.6 |
| MariaDB | `MD5()` | `SHA1()` | `SHA2(s,256)` | `SHA2(s,384)` | `SHA2(s,512)` | -- | 继承 MySQL；新增 `SHA()` 别名 |
| SQLite | -- | -- | -- | -- | -- | -- | 仅扩展（hash_extension） |
| Oracle | `DBMS_CRYPTO.HASH(t, HASH_MD5)` | `DBMS_CRYPTO.HASH(t, HASH_SH1)` | `DBMS_CRYPTO.HASH(t, HASH_SH256)` | `DBMS_CRYPTO.HASH(t, HASH_SH384)` | `DBMS_CRYPTO.HASH(t, HASH_SH512)` | -- | 10g+；STANDARD_HASH 自 12c |
| SQL Server | `HASHBYTES('MD5',s)` | `HASHBYTES('SHA1',s)` | `HASHBYTES('SHA2_256',s)` | -- | `HASHBYTES('SHA2_512',s)` | -- | MD5/SHA1 自 2005；SHA2 自 2012 |
| DB2 | `HASH(s,0)` 兼容 | `HASH_SHA1()` | `HASH_SHA256()` | -- | `HASH_SHA512()` | -- | LUW 11.1+ |
| Snowflake | `MD5()` / `MD5_HEX()` | `SHA1()` / `SHA1_HEX()` | `SHA2(s,256)` / `SHA2_HEX(s,256)` | `SHA2(s,384)` | `SHA2(s,512)` | -- | GA |
| BigQuery | `MD5(b)` | `SHA1(b)` | `SHA256(b)` | -- | `SHA512(b)` | -- | GA；返回 BYTES |
| Redshift | `MD5()` | `FUNC_SHA1()` | `SHA256()` 等 | -- | `SHA512()` | -- | GA；FUNC_SHA1 是别名 |
| Azure Synapse | `HASHBYTES('MD5',s)` | `HASHBYTES('SHA1',s)` | `HASHBYTES('SHA2_256',s)` | -- | `HASHBYTES('SHA2_512',s)` | -- | GA；继承 SQL Server |
| DuckDB | `md5()` / `md5_number()` | `sha1()` | `sha256()` | -- | -- | -- | 0.7+ |
| ClickHouse | `MD5()` / `MD4()` | `SHA1()` | `SHA256()` | `SHA384()` | `SHA512()` | -- | 早期 |
| Trino | `md5(b)` | `sha1(b)` | `sha256(b)` | -- | `sha512(b)` | -- | 早期 |
| Presto | `md5(b)` | `sha1(b)` | `sha256(b)` | -- | `sha512(b)` | -- | 0.57+ |
| Spark SQL | `md5()` | `sha1()` / `sha(s)` | `sha2(s,256)` | `sha2(s,384)` | `sha2(s,512)` | -- | 1.5+ |
| Hive | `md5()` | `sha1()` | `sha2(s,256)` | -- | `sha2(s,512)` | -- | 1.3+ |
| Flink SQL | `MD5()` | `SHA1()` | `SHA256()` | `SHA384()` | `SHA512()` | -- | 1.4+ |
| Databricks | `md5()` | `sha1()` | `sha2(s,256)` | `sha2(s,384)` | `sha2(s,512)` | -- | GA |
| Teradata | `HASHROW()` 非加密 | `HASH_SHA()` | `HASH_SHA256()` | -- | `HASH_SHA512()` | -- | 16.20+ |
| Greenplum | `md5()` | `digest()` (pgcrypto) | `digest()` | `digest()` | `digest()` | -- | 继承 PG |
| CockroachDB | `md5()` | `sha1()` (实验性) | `sha256()` | -- | `sha512()` | -- | 19.2+ |
| TiDB | `MD5()` | `SHA1()` | `SHA2(s,256)` | `SHA2(s,384)` | `SHA2(s,512)` | -- | 2.0+；MySQL 兼容 |
| OceanBase | `MD5()` | `SHA1()` | `SHA2(s,256)` | `SHA2(s,384)` | `SHA2(s,512)` | -- | 2.0+；MySQL 模式 |
| YugabyteDB | `md5()` | `digest()` | `digest()` | `digest()` | `digest()` | -- | 继承 PG |
| SingleStore | `MD5()` | `SHA1()` | `SHA2(s,256)` | -- | `SHA2(s,512)` | -- | 7.0+ |
| Vertica | `MD5()` | `SHA1()` | `SHA512()` 同字段 | -- | `SHA512()` | -- | 9.0+ |
| Impala | `md5()` (4.0+) | `sha1()` 4.0+ | `sha2()` 4.0+ | -- | `sha2()` | -- | Impala 4.0+ |
| StarRocks | `md5()` | `sha1()` | `sha224()`/`sha256()`/etc | `sha384()` | `sha512()` | -- | 2.5+；提供完整 SHA2 |
| Doris | `md5()`/`md5sum()` | `sha1()` | `sha2(s,256)` | `sha2(s,384)` | `sha2(s,512)` | -- | 1.2+ |
| MonetDB | `md5()` (扩展) | -- | -- | -- | -- | -- | 部分发行版 |
| TimescaleDB | `md5()` | `digest()` | `digest()` | `digest()` | `digest()` | -- | 继承 PG |
| QuestDB | -- | -- | -- | -- | -- | -- | 不支持（仅哈希连接内部使用） |
| Exasol | `HASH_MD5()` | `HASH_SHA1()` | `HASH_SHA256()` | -- | `HASH_SHA512()` | -- | 7.0+ |
| SAP HANA | `HASH_MD5()` (扩展) | `HASH_SHA256()` | `HASH_SHA256()` | -- | -- | -- | SPS 04+ |
| Informix | -- | -- | -- | -- | -- | -- | 仅 BLOB checksum |
| Firebird | `HASH(s)` 非加密 | `CRYPT_HASH(s, 'SHA1')` | `CRYPT_HASH(s, 'SHA256')` | `CRYPT_HASH(s, 'SHA384')` | `CRYPT_HASH(s, 'SHA512')` | -- | 4.0+ |
| H2 | `HASH('SHA256',s)` | `HASH('SHA1',s)` | `HASH('SHA256',s)` | `HASH('SHA384',s)` | `HASH('SHA512',s)` | -- | 1.4+ |
| HSQLDB | -- | -- | -- | -- | -- | -- | 仅 Java 函数 |
| Derby | -- | -- | -- | -- | -- | -- | 不支持 |
| Athena | `md5(b)` | `sha1(b)` | `sha256(b)` | -- | `sha512(b)` | -- | 继承 Trino |
| Materialize | `md5(s)` | `sha1(s)` | `sha256(s)` | -- | `sha512(s)` | -- | GA |
| RisingWave | `md5()` | `sha1()` | `sha256()` | `sha384()` | `sha512()` | -- | GA |
| Google Spanner | `MD5()` | `SHA1()` | `SHA256()` | -- | `SHA512()` | -- | GA；GoogleSQL 方言 |
| InfluxDB IOx | -- | -- | -- | -- | -- | -- | 不支持 |
| DatabendDB | `md5()` | `sha()`/`sha1()` | `sha2(s,256)` | `sha2(s,384)` | `sha2(s,512)` | -- | GA |
| Yellowbrick | `md5()` | `sha1()` | `sha256()` | -- | `sha512()` | -- | 继承 PG 兼容 |
| Firebolt | `md5()` | `sha1()` | `sha256()` | -- | `sha512()` | -- | GA |

> 统计：约 38 个引擎提供 MD5；约 36 个提供 SHA-1；约 35 个提供 SHA-256；约 27 个提供完整 SHA-512；几乎没有引擎内置 SHA-3。

### CRC32 / 校验和

| 引擎 | CRC32 | CRC32C | ADLER32 | 备注 |
|------|-------|--------|---------|------|
| PostgreSQL | -- | -- | -- | 通过 `pg_crc32` 扩展 |
| MySQL | `CRC32()` | -- | -- | 4.1+；返回 UNSIGNED INT |
| MariaDB | `CRC32()` / `CRC32C()` | `CRC32C()` 10.4+ | -- | 继承 MySQL；增加 CRC32C |
| SQLite | -- | -- | -- | 不支持 |
| Oracle | `OWA_OPT_LOCK.CHECKSUM` | -- | -- | 仅 PL/SQL 包 |
| SQL Server | `CHECKSUM()` / `BINARY_CHECKSUM()` | -- | -- | 非标准 CRC，引擎私有算法 |
| DB2 | `HASH4(s)` 类似 | -- | -- | LUW 11.1+ |
| Snowflake | -- | -- | -- | 无内置 CRC32 |
| BigQuery | -- | -- | -- | 无内置 CRC32 |
| Redshift | -- | -- | -- | 无内置 CRC32 |
| ClickHouse | `CRC32()` / `CRC32IEEE()` | `CRC32C()` | -- | 完整 CRC 家族 |
| DuckDB | -- | -- | -- | 无内置 CRC32（可用扩展） |
| Trino | `crc32(b)` | -- | -- | 较新版本 |
| Spark SQL | `crc32()` | -- | -- | 1.5+；返回 BIGINT |
| Hive | -- | -- | -- | 不支持 |
| Flink SQL | -- | -- | -- | 不支持 |
| Teradata | -- | -- | -- | 不支持 |
| TiDB | `CRC32()` | -- | -- | 继承 MySQL |
| OceanBase | `CRC32()` | -- | -- | MySQL 模式 |
| StarRocks | `crc32()` | -- | -- | 较新版本 |
| Doris | `crc32()` | -- | -- | 较新版本 |
| Vertica | `CHECKSUM()` | -- | -- | 私有算法 |
| Impala | -- | -- | -- | 不支持 |
| H2 | -- | -- | -- | 不支持 |
| Firebolt | -- | -- | -- | 不支持 |

> 注：SQL Server 的 `CHECKSUM()` 不是标准 CRC32，是 32 位的引擎私有算法，碰撞率较高。

### xxHash 家族

xxHash 由 Yann Collet 于 2012 年发布，因其极高的速度（每周期处理多个字节）成为非密码学哈希的事实标准。XXH3（2019）进一步提升了速度。

| 引擎 | xxHash32 | xxHash64 | XXH3-64 | XXH3-128 | 备注 |
|------|---------|---------|---------|----------|------|
| ClickHouse | `xxHash32()` | `xxHash64()` | -- | -- | 完整支持 |
| DuckDB | -- | -- | -- | -- | 内部使用，不暴露 SQL |
| Spark SQL | -- | `xxhash64()` | -- | -- | 3.0+ |
| Databricks | -- | `xxhash64()` | -- | -- | GA |
| Doris | `xxhash_32()` | `xxhash_64()` | -- | -- | 较新版本 |
| StarRocks | -- | `xx_hash3_64()` 类 | -- | -- | 部分版本 |
| Trino | -- | `xxhash64(b)` | -- | -- | 较新版本 |
| Athena | -- | `xxhash64(b)` | -- | -- | 继承 Trino |
| Snowflake | -- | -- | -- | -- | 无内置 |
| BigQuery | -- | -- | -- | -- | 无内置 |
| PostgreSQL | -- | -- | -- | -- | 无内置（可用 pg_hashids 等扩展） |
| MySQL | -- | -- | -- | -- | 内部使用，不暴露 SQL |

### CityHash / FarmHash 家族

CityHash（Google 2011）和 FarmHash（Google 2014，CityHash 后继）专为短字符串高速哈希设计。BigQuery 的 `FARM_FINGERPRINT` 直接基于 FarmHash。

| 引擎 | CityHash64 | CityHash128 | FarmHash64 | FarmHash128 | 备注 |
|------|-----------|-------------|-----------|-------------|------|
| ClickHouse | `cityHash64()` | -- | `farmHash64()` | -- | 早期支持 |
| BigQuery | -- | -- | `FARM_FINGERPRINT(s)` | -- | GA；返回 INT64 |
| Doris | -- | -- | -- | -- | 无 |
| StarRocks | -- | -- | -- | -- | 无 |
| Snowflake | -- | -- | -- | -- | 无 |
| 其他引擎 | -- | -- | -- | -- | 几乎无内置 |

> BigQuery 的 `FARM_FINGERPRINT` 是 64 位有符号整数，常用作分片键和去重指纹。

### MurmurHash 家族

| 引擎 | Murmur2-32 | Murmur2-64 | Murmur3-32 | Murmur3-64 | Murmur3-128 | 备注 |
|------|-----------|------------|------------|------------|-------------|------|
| ClickHouse | `murmurHash2_32()` | `murmurHash2_64()` | `murmurHash3_32()` | `murmurHash3_64()` | `murmurHash3_128()` | 完整 |
| Spark SQL | -- | -- | `hash()` | -- | -- | 默认 hash() = Murmur3 |
| Databricks | -- | -- | `hash()` | -- | -- | 同 Spark |
| DuckDB | -- | -- | -- | -- | -- | hash() 内部用 Murmur3 变体 |
| Trino | -- | -- | -- | `xxhash64()` | -- | 无 Murmur 但有 xxHash |
| 其他引擎 | -- | -- | -- | -- | -- | 多数无 |

### SipHash 家族

SipHash 是 Aumasson & Bernstein 2012 设计的"伪随机函数"，专为防 HashDoS 攻击设计，被 Python、Rust 等语言用作 dict 默认哈希。

| 引擎 | SipHash64 | SipHash128 | 备注 |
|------|----------|------------|------|
| ClickHouse | `sipHash64()` / `sipHash64Keyed()` | `sipHash128()` / `sipHash128Keyed()` | 提供 keyed 版本 |
| 其他引擎 | -- | -- | 几乎无 |

### FNV 家族

FNV-1a 是简单快速的非密码学哈希，常用于嵌入式和早期 HashMap 实现。

| 引擎 | FNV-32 | FNV-64 | FNV-128 | 备注 |
|------|--------|--------|---------|------|
| 几乎无引擎 | -- | -- | -- | 通常通过 UDF 实现 |
| Greenplum / GPDB | 内部使用 | 内部使用 | -- | 用于 hash distribution |
| PostgreSQL Citus | 内部使用 | -- | -- | 用于分布式哈希 |

### 其他/通用 HASH 函数

| 引擎 | 函数 | 算法 | 输出 | 备注 |
|------|------|------|------|------|
| Snowflake | `HASH(...)` | 基于 SHA-256 的 64 位变体 | NUMBER(38) | 内部分布式 |
| BigQuery | `FARM_FINGERPRINT(s)` | FarmHash64 | INT64 | 主要 hash 函数 |
| DuckDB | `hash(...)` | MurmurHash3 变体 | UINT64 | 通用哈希 |
| ClickHouse | `halfMD5()` | 取 MD5 前 64 位 | UInt64 | 兼容传统 ID 哈希 |
| ClickHouse | `intHash32()` / `intHash64()` | 整数特化 | UInt32/64 | 快速 |
| ClickHouse | `javaHash()` | Java String.hashCode() | Int32 | Java 互操作 |
| ClickHouse | `hiveHash()` | Hive 字符串哈希 | Int32 | Hive 互操作 |
| Spark SQL | `hash(...)` | MurmurHash3 | INT | 多列哈希 |
| Spark SQL | `xxhash64(...)` | xxHash64 | BIGINT | 较快 |
| H2 | `HASH(algo, val)` | 字符串选择算法 | BINARY | 通用 |
| Firebird | `HASH(val)` | 私有 64 位非加密 | BIGINT | 4.0+ |
| Teradata | `HASHROW()` / `HASHBUCKET()` / `HASHAMP()` | 私有分布哈希 | BYTE/INT | 用于 AMP 路由 |
| DB2 | `HASH4()` / `HASH8()` | 32/64 位私有 | INT/BIGINT | LUW 11.1+ |

## 各引擎细节

### PostgreSQL

```sql
-- 核心：md5() 是唯一内置加密哈希函数（自 PostgreSQL 7.x）
SELECT md5('hello');
-- 5d41402abc4b2a76b9719d911017c592 (32 字符 hex 字符串)

-- 输入是 text 或 bytea，输出是 text（不是 bytea！）
SELECT md5('abc')::text;

-- 其他算法需要安装 pgcrypto 扩展
CREATE EXTENSION pgcrypto;

SELECT digest('hello', 'sha1');
-- \xaaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d (bytea)

SELECT digest('hello', 'sha256');
SELECT digest('hello', 'sha384');
SELECT digest('hello', 'sha512');

-- 转十六进制字符串
SELECT encode(digest('hello', 'sha256'), 'hex');
-- 2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824

-- HMAC（需要 pgcrypto）
SELECT hmac('hello', 'secret', 'sha256');
SELECT encode(hmac('hello', 'secret', 'sha256'), 'hex');

-- 注意：PostgreSQL 没有内置 CRC32 或 xxHash
-- 可使用扩展：
--   pg_crc32 / pg_hashids / citus_xxhash_text 等
```

### MySQL / MariaDB

```sql
-- MD5 / SHA1 自 4.0
SELECT MD5('hello');
-- 5d41402abc4b2a76b9719d911017c592

SELECT SHA1('hello');
-- aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d

-- SHA() 是 SHA1() 的别名
SELECT SHA('hello');

-- SHA2 自 5.5.6（要求 MySQL 编译时启用 SSL）
SELECT SHA2('hello', 256);
-- 2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824

SELECT SHA2('hello', 384);
SELECT SHA2('hello', 512);
SELECT SHA2('hello', 224);
SELECT SHA2('hello', 0);   -- 0 == 256

-- CRC32 自 4.1，返回 UNSIGNED INT
SELECT CRC32('hello');
-- 907060870

-- MariaDB 增加 CRC32C（10.4+）
SELECT CRC32C('hello');

-- 重要：MD5/SHA1 在 MySQL 8.0 之后不推荐用于密码存储
-- 应使用 password() 或更现代的 caching_sha2_password 验证插件
```

### SQL Server

```sql
-- HASHBYTES 是统一接口（自 SQL Server 2005）
-- 注意：返回 VARBINARY，不是字符串

SELECT HASHBYTES('MD5', 'hello');
-- 0x5D41402ABC4B2A76B9719D911017C592

SELECT HASHBYTES('SHA1', 'hello');
SELECT HASHBYTES('SHA2_256', 'hello');   -- 自 SQL Server 2012
SELECT HASHBYTES('SHA2_512', 'hello');   -- 自 SQL Server 2012

-- 转字符串需要 CONVERT
SELECT CONVERT(VARCHAR(64),
              HASHBYTES('SHA2_256', 'hello'), 2);  -- 2 = no 0x prefix
-- 2CF24DBA5FB0A30E26E83B2AC5B9E29E1B161E5C1FA7425E73043362938B9824

-- 输入限制：SQL Server 2014 及之前 HASHBYTES 输入最大 8000 字节
-- SQL Server 2016+ 取消此限制

-- 非密码学：CHECKSUM / BINARY_CHECKSUM
-- CHECKSUM 大小写敏感取决于 collation
SELECT CHECKSUM('hello');           -- 私有 32 位 hash
SELECT BINARY_CHECKSUM('hello');    -- 二进制版本

-- CHECKSUM_AGG: 行集校验
SELECT CHECKSUM_AGG(CHECKSUM(*)) FROM table_name;

-- 注意：SQL Server 至今没有内置 CRC32 或 xxHash
-- HASHBYTES('MD2', ...) 和 HASHBYTES('MD4', ...) 已弃用
```

### Oracle

```sql
-- DBMS_CRYPTO 包（自 Oracle 10g）
-- 注意：需要 EXECUTE 权限

DECLARE
  v_input  RAW(32767) := UTL_RAW.CAST_TO_RAW('hello');
  v_hash   RAW(32);
BEGIN
  v_hash := DBMS_CRYPTO.HASH(v_input, DBMS_CRYPTO.HASH_SH256);
  DBMS_OUTPUT.PUT_LINE(RAWTOHEX(v_hash));
END;
/

-- HASH_MD5     = 2
-- HASH_SH1     = 3
-- HASH_SH256   = 4   (12c+)
-- HASH_SH384   = 5   (12c+)
-- HASH_SH512   = 6   (12c+)

-- STANDARD_HASH 函数（Oracle 12c+，更易用）
SELECT STANDARD_HASH('hello', 'MD5') FROM dual;
-- 5D41402ABC4B2A76B9719D911017C592

SELECT STANDARD_HASH('hello', 'SHA1') FROM dual;
SELECT STANDARD_HASH('hello', 'SHA256') FROM dual;
SELECT STANDARD_HASH('hello', 'SHA384') FROM dual;
SELECT STANDARD_HASH('hello', 'SHA512') FROM dual;

-- ORA_HASH：非加密哈希（用于分桶/分区，不要用于安全场景）
-- 返回 NUMBER 0..max_bucket（默认 max=4294967295）
SELECT ORA_HASH('hello') FROM dual;
SELECT ORA_HASH('hello', 99) FROM dual;          -- 0..99
SELECT ORA_HASH('hello', 99, 42) FROM dual;      -- with seed

-- 注意：Oracle 没有内置 CRC32 或 xxHash
-- DBMS_OBFUSCATION_TOOLKIT 已弃用，使用 DBMS_CRYPTO
```

### ClickHouse（最丰富的哈希函数库）

```sql
-- 加密哈希
SELECT MD4('hello');
SELECT MD5('hello');
SELECT SHA1('hello');
SELECT SHA224('hello');
SELECT SHA256('hello');
SELECT SHA384('hello');
SELECT SHA512('hello');
-- 注意：返回 FixedString，需要 hex() 转十六进制
SELECT hex(MD5('hello'));
-- 5D41402ABC4B2A76B9719D911017C592

SELECT halfMD5('a', 'b');   -- 取 MD5 前 64 位

-- CityHash 家族
SELECT cityHash64('hello');
SELECT cityHash64('a', 'b', 'c');

-- FarmHash
SELECT farmHash64('hello');
SELECT farmFingerprint64('hello');   -- 与 BigQuery 兼容

-- xxHash
SELECT xxHash32('hello');
SELECT xxHash64('hello');

-- MurmurHash
SELECT murmurHash2_32('hello');
SELECT murmurHash2_64('hello');
SELECT murmurHash3_32('hello');
SELECT murmurHash3_64('hello');
SELECT murmurHash3_128('hello');

-- SipHash（带 keyed 版本）
SELECT sipHash64('hello');
SELECT sipHash64Keyed((1, 2), 'hello');     -- 128 位密钥
SELECT sipHash128('hello');
SELECT sipHash128Keyed((1, 2), 'hello');

-- CRC 家族
SELECT CRC32('hello');
SELECT CRC32IEEE('hello');
SELECT CRC64('hello');

-- 整数特化
SELECT intHash32(42);
SELECT intHash64(42);

-- Java/Hive 互操作
SELECT javaHash('hello');         -- Java String.hashCode()
SELECT javaHashUTF16LE('hello');
SELECT hiveHash('hello');         -- Hive PartitionWriter

-- URL 哈希（保留域名层级，便于子域聚合）
SELECT URLHash('https://example.com/path');
SELECT URLHash('https://a.b.example.com/path', 1);

-- 一致性哈希
SELECT yandexConsistentHash(123, 4);

-- 性能比较（10 亿次调用，参考数据）：
--   xxHash64       ~ 4 GB/s
--   cityHash64     ~ 5 GB/s  (高度优化)
--   farmHash64     ~ 5 GB/s
--   murmurHash3_64 ~ 4 GB/s
--   sipHash64      ~ 1 GB/s  (但抗碰撞攻击)
--   MD5            ~ 0.5 GB/s
--   SHA-256        ~ 0.3 GB/s (无 SHA-NI 时)
```

### BigQuery

```sql
-- 密码学哈希：返回 BYTES，不是 STRING
SELECT MD5('hello');
-- 0x5d41402abc4b2a76b9719d911017c592 (BYTES)

-- 转字符串
SELECT TO_HEX(MD5('hello'));
-- 5d41402abc4b2a76b9719d911017c592

SELECT TO_HEX(SHA1('hello'));
SELECT TO_HEX(SHA256('hello'));
SELECT TO_HEX(SHA512('hello'));

-- 注意：输入也是 BYTES 或 STRING（自动转 UTF-8）
SELECT MD5(CAST('hello' AS BYTES));
SELECT MD5(b'hello');     -- BYTES literal

-- FARM_FINGERPRINT：基于 FarmHash 的 64 位有符号整数
-- 这是 BigQuery 推荐的非加密哈希
SELECT FARM_FINGERPRINT('hello');
-- -7286425919675154353  (INT64, 可能为负)

-- 多列联合指纹
SELECT FARM_FINGERPRINT(CONCAT(CAST(user_id AS STRING),
                               '|',
                               CAST(session_id AS STRING)))
FROM events;

-- 用于分桶（取模）
SELECT *,
       MOD(ABS(FARM_FINGERPRINT(user_id)), 100) AS bucket
FROM users;

-- 注意：BigQuery 没有内置 CRC32 或 xxHash
-- 也没有内置 HMAC，但可用 KEYS.KEYSET_FROM_JSON + ENCRYPT 间接实现
```

### Snowflake

```sql
-- 加密哈希返回 VARCHAR（hex 字符串），与 PostgreSQL 风格一致
SELECT MD5('hello');
-- 5d41402abc4b2a76b9719d911017c592

SELECT MD5_HEX('hello');     -- 等价
SELECT MD5_BINARY('hello');  -- 返回 BINARY

SELECT SHA1('hello');
SELECT SHA1_HEX('hello');
SELECT SHA1_BINARY('hello');

SELECT SHA2('hello', 256);   -- 默认 256
SELECT SHA2('hello', 384);
SELECT SHA2('hello', 512);
SELECT SHA2_HEX('hello', 256);
SELECT SHA2_BINARY('hello', 256);

-- 通用 HASH（Snowflake 私有）
-- 返回 NUMBER(38)，基于 SHA-256 的 64 位变体
SELECT HASH('hello');
-- -83815761819588488 (NUMBER, 可能为负)

-- 多参数：所有参数拼合后哈希
SELECT HASH('a', 'b', 'c');
SELECT HASH(col1, col2, col3) FROM t;

-- HASH_AGG：聚合行集
-- 用于检测大表行集是否相同（顺序无关）
SELECT HASH_AGG(col1, col2) FROM table_a;

-- 注意：Snowflake 的 HASH() 是非加密的，专为内部分桶/JOIN 优化
-- 不要用于安全场景，请使用 SHA2()
-- 也没有 CRC32 或 xxHash
```

### DuckDB

```sql
-- md5（自 0.7+）
SELECT md5('hello');
-- 5d41402abc4b2a76b9719d911017c592

SELECT md5_number('hello');    -- HUGEINT 形式
SELECT md5_number_lower('hello');
SELECT md5_number_upper('hello');

-- SHA1 / SHA256
SELECT sha1('hello');
SELECT sha256('hello');
-- DuckDB 0.10+ 才稳定支持 sha256

-- 通用 hash（基于 MurmurHash3 变体，64 位）
SELECT hash('hello');
-- 17552050321691691193 (UBIGINT)

-- 多列 hash
SELECT hash(col1, col2, col3) FROM t;

-- 注意：DuckDB 至今没有内置 CRC32 / xxHash / SHA-512
-- 但 hash() 性能极高，是分桶/去重首选
```

### Spark SQL / Databricks

```sql
-- 加密哈希
SELECT md5('hello');
SELECT sha1('hello');
SELECT sha('hello');           -- = sha1
SELECT sha2('hello', 256);
SELECT sha2('hello', 384);
SELECT sha2('hello', 512);
SELECT sha2('hello', 0);       -- = 256

-- CRC32（自 1.5）
SELECT crc32('hello');
-- 907060870 (BIGINT)

-- 通用 hash：MurmurHash3 32 位（多列）
SELECT hash(col1, col2, col3) FROM t;
-- 返回 INT，可能为负

-- xxhash64（自 3.0）
SELECT xxhash64('hello');
SELECT xxhash64(col1, col2);
-- 返回 BIGINT，分布更均匀，更适合分桶

-- 选择建议：
-- - 分桶 hash：xxhash64() （3.0+ 推荐）
-- - 多列指纹：xxhash64(col1, col2, ...)
-- - 数据完整性：sha2(s, 256) 或更高
-- - 临时唯一标识：md5() （32 字符紧凑）
```

### Trino / Presto / Athena

```sql
-- 输入和输出都是 VARBINARY
SELECT md5(CAST('hello' AS VARBINARY));
-- 0x5d41402abc4b2a76b9719d911017c592 (varbinary)

-- 转 hex 字符串
SELECT to_hex(md5(CAST('hello' AS VARBINARY)));
-- 5d41402abc4b2a76b9719d911017c592

SELECT to_hex(sha1(CAST('hello' AS VARBINARY)));
SELECT to_hex(sha256(CAST('hello' AS VARBINARY)));
SELECT to_hex(sha512(CAST('hello' AS VARBINARY)));

-- 自 Trino 较新版本：xxhash64
SELECT xxhash64(CAST('hello' AS VARBINARY));
-- 返回 VARBINARY

SELECT to_hex(xxhash64(CAST('hello' AS VARBINARY)));

-- crc32
SELECT crc32(CAST('hello' AS VARBINARY));
-- 返回 BIGINT

-- spooky_hash_v2_32 / spooky_hash_v2_64
SELECT spooky_hash_v2_32(CAST('hello' AS VARBINARY));
SELECT spooky_hash_v2_64(CAST('hello' AS VARBINARY));

-- 注意：Trino 强制 VARBINARY 输入，与其他引擎不同
-- 多列哈希需要 concat 后转 BINARY
```

### Hive

```sql
-- md5 / sha2（Hive 1.3+）
SELECT md5('hello');
SELECT sha1('hello');
SELECT sha2('hello', 256);
SELECT sha2('hello', 0);   -- = 256
SELECT sha2('hello', 512);

-- hash（旧版 Java hashCode 风格）
SELECT hash('hello');           -- INT，多个参数会异或合并
SELECT hash(col1, col2);

-- 注意：Hive hash() 是 Java hashCode，分布不如 Murmur3 均匀
-- 重要：Hive bucket 划分内部使用 hash() 决定 bucket
```

### Teradata

```sql
-- 私有分布哈希（用于 AMP 路由，决定行存储位置）
SELECT HASHROW(col1)            -- BYTE(4)，行哈希
FROM table;
SELECT HASHBUCKET(HASHROW(col1)) AS bucket  -- 0..65535 或 0..1048575
FROM table;
SELECT HASHAMP(HASHBUCKET(HASHROW(col1))) -- AMP 编号
FROM table;

-- 注意：HASHROW 不是密码学哈希，仅用于均衡分布
-- 不同 hash 模式可能影响碰撞率

-- 加密哈希：HASH_SHA / HASH_SHA256 / HASH_SHA512（16.20+）
-- 名字略不同
SELECT HASH_SHA('hello');             -- SHA1
SELECT HASH_SHA256('hello');
SELECT HASH_SHA512('hello');

-- HASH_MD5（旧版本/某些发行）
SELECT HASH_MD5('hello');
```

### DB2 (LUW)

```sql
-- DB2 LUW 11.1+
SELECT HASH4('hello');        -- 32 位非加密
SELECT HASH8('hello');        -- 64 位非加密

-- 加密哈希
SELECT HASH_SHA1('hello');         -- SHA1
SELECT HASH_SHA256('hello');
SELECT HASH_SHA512('hello');
SELECT HASH_MD5('hello');          -- MD5

-- 输入支持 VARCHAR / VARBINARY / CHAR
SELECT HEX(HASH_SHA256('hello'));
```

### Greenplum / TimescaleDB / YugabyteDB

```sql
-- 这三者都基于 PostgreSQL，行为完全一致

SELECT md5('hello');                          -- 内置
SELECT digest('hello', 'sha256');             -- 需 pgcrypto
SELECT encode(digest('hello', 'sha256'), 'hex');

-- 启用 pgcrypto
CREATE EXTENSION pgcrypto;

-- HMAC
SELECT encode(hmac('hello', 'secret', 'sha256'), 'hex');

-- 注意：Greenplum/Citus/分布式 PG 内部用自己的哈希函数
-- 决定数据分布（不一定是 md5），用户不可见
```

### CockroachDB

```sql
-- md5
SELECT md5('hello'::BYTES);
-- 注意：CockroachDB md5 接受 BYTES 输入

-- sha256 / sha512
SELECT sha256('hello'::BYTES);
SELECT sha512('hello'::BYTES);

-- fnv32 / fnv32a / fnv64 / fnv64a / crc32ieee / crc32c
SELECT fnv32('hello'::BYTES);
SELECT fnv64a('hello'::BYTES);
SELECT crc32ieee('hello'::BYTES);
SELECT crc32c('hello'::BYTES);

-- pgcrypto 兼容函数
SELECT digest('hello', 'sha256');
```

### Firebird

```sql
-- HASH 函数：64 位非加密哈希（4.0+）
SELECT HASH('hello') FROM rdb$database;
-- BIGINT

-- CRYPT_HASH：加密哈希
SELECT CRYPT_HASH('hello' USING SHA1) FROM rdb$database;
SELECT CRYPT_HASH('hello' USING SHA256) FROM rdb$database;
SELECT CRYPT_HASH('hello' USING SHA384) FROM rdb$database;
SELECT CRYPT_HASH('hello' USING SHA512) FROM rdb$database;
SELECT CRYPT_HASH('hello' USING MD5) FROM rdb$database;

-- 转十六进制
SELECT HEX(CRYPT_HASH('hello' USING SHA256)) FROM rdb$database;
```

### H2

```sql
-- HASH 是统一接口
SELECT HASH('SHA256', 'hello');           -- BINARY
SELECT HASH('SHA1', 'hello');
SELECT HASH('SHA384', 'hello');
SELECT HASH('SHA512', 'hello');

-- 多次哈希迭代
SELECT HASH('SHA256', 'hello', 1000);     -- 1000 次

-- 转字符串
SELECT RAWTOHEX(HASH('SHA256', 'hello'));
```

### SAP HANA

```sql
-- SAP HANA 哈希函数（私有）
SELECT HASH_MD5('hello') FROM dummy;     -- 返回 BIGINT (64位)
SELECT HASH_SHA256('hello') FROM dummy;  -- 返回 BINARY

-- 注意：HASH_MD5 不是真正的 MD5，是 MD5 派生的 64 位 hash
-- 用于内部分布
```

### Exasol

```sql
SELECT HASH_MD5('hello');
-- 返回 CHAR(32)，hex 字符串

SELECT HASH_SHA1('hello');
SELECT HASH_SHA256('hello');
SELECT HASH_SHA512('hello');

-- 也支持 HASH_TIGER, HASH_SIPHASH 等
SELECT HASH_TIGER('hello');
SELECT HASH_SIPHASH24('hello');
```

### StarRocks / Doris

```sql
-- 这两者基于类似的 MySQL 兼容方言

SELECT md5('hello');
SELECT md5sum('hello', 'world');     -- Doris：拼接后 md5

SELECT sha1('hello');
SELECT sha2('hello', 256);
SELECT sha2('hello', 512);

-- crc32
SELECT crc32('hello');

-- xxhash（StarRocks）
SELECT xx_hash3_64('hello');

-- xxhash（Doris）
SELECT xxhash_32('hello');
SELECT xxhash_64('hello');

-- murmur_hash3
SELECT murmur_hash3_32('hello');
SELECT murmur_hash3_64('hello');
```

### Materialize / RisingWave

```sql
-- PostgreSQL 兼容方言
SELECT md5('hello');
SELECT sha1('hello');
SELECT sha256('hello');
SELECT sha384('hello');
SELECT sha512('hello');

-- 输入：text 或 bytea；输出：text （hex 字符串）
```

## 哈希函数的典型用途

### 1. 分片键 / 分区函数

```sql
-- 用哈希取模决定数据落在哪个分片
-- BigQuery
CREATE TABLE events_sharded
PARTITION BY MOD(ABS(FARM_FINGERPRINT(user_id)), 100)
AS SELECT * FROM events;

-- ClickHouse
CREATE TABLE events_sharded
ENGINE = MergeTree()
PARTITION BY (cityHash64(user_id) % 32)
ORDER BY (event_time);

-- PostgreSQL（声明式分区，自 11+）
CREATE TABLE events (
    user_id BIGINT,
    event_time TIMESTAMP,
    payload JSONB
) PARTITION BY HASH (user_id);

CREATE TABLE events_p0 PARTITION OF events
    FOR VALUES WITH (MODULUS 4, REMAINDER 0);
CREATE TABLE events_p1 PARTITION OF events
    FOR VALUES WITH (MODULUS 4, REMAINDER 1);
-- ... 等

-- 注意：PostgreSQL HASH 分区使用内部哈希函数，
-- 不是 md5()，跨版本算法可能变化
```

### 2. 数据完整性校验

```sql
-- 跨系统迁移后验证数据未损坏
-- 方法：对每行计算指纹，再聚合所有指纹

-- Snowflake / SQL Server: 行级 + 聚合
SELECT HASH_AGG(col1, col2, col3) FROM source_table;
SELECT HASH_AGG(col1, col2, col3) FROM target_table;
-- 两个值相等 ⇒ 行集相同（顺序无关）

-- PostgreSQL：用 MD5 + array_agg
SELECT md5(string_agg(md5(t::text), ',' ORDER BY id))
FROM source_table t;

-- ClickHouse
SELECT cityHash64(groupArray(cityHash64(*))) FROM source_table;

-- BigQuery
SELECT TO_HEX(SHA256(STRING_AGG(TO_HEX(SHA256(TO_JSON_STRING(t))),
                                ',' ORDER BY id)))
FROM source_table t;
```

### 3. 去重 / Bloom filter

```sql
-- 用哈希作为唯一指纹去重大表
-- 比直接比较 1KB 文本快 100 倍

-- 标准模式：先对长字段哈希，再 GROUP BY 哈希值
WITH fingerprinted AS (
    SELECT *,
           md5(CONCAT_WS('|', long_text_a, long_text_b, long_text_c))
               AS fingerprint
    FROM logs
)
SELECT MIN(id), fingerprint
FROM fingerprinted
GROUP BY fingerprint;

-- ClickHouse 用 cityHash64 更快
SELECT MIN(id), cityHash64(long_text_a, long_text_b, long_text_c) AS h
FROM logs
GROUP BY h;
```

### 4. 分桶随机抽样

```sql
-- 用哈希值的低位决定是否抽样
-- 优势：相同 user_id 总是被分到同一组（A/B 测试稳定性）

-- BigQuery
SELECT *
FROM users
WHERE MOD(ABS(FARM_FINGERPRINT(user_id)), 100) < 10;   -- 10% 用户

-- PostgreSQL + pgcrypto
SELECT *
FROM users
WHERE (('x' || substr(md5(user_id::text), 1, 8))::bit(32)::int % 100) BETWEEN 0 AND 9;
-- 取 md5 的前 8 个字符（hex），转 32 位整数，然后取模

-- ClickHouse
SELECT *
FROM users
WHERE cityHash64(user_id) % 100 < 10;

-- Snowflake
SELECT *
FROM users
WHERE ABS(HASH(user_id)) % 100 < 10;
```

### 5. 密码 / 凭证存储（不推荐 MD5/SHA）

```sql
-- 错误示范（永远不要这样存储密码）：
INSERT INTO users(username, password_hash)
VALUES ('alice', md5('user_password'));

-- 正确做法：使用专用密码哈希函数（bcrypt / argon2 / scrypt）
-- PostgreSQL + pgcrypto
INSERT INTO users(username, password_hash)
VALUES ('alice', crypt('user_password', gen_salt('bf', 12)));
-- bf = blowfish (bcrypt), 12 = work factor

-- 验证
SELECT * FROM users
WHERE username = 'alice'
  AND password_hash = crypt('input_password', password_hash);

-- MySQL / MariaDB：内置 password() 已弃用，应用层处理
-- SQL Server：使用 PWDENCRYPT()（系统内部）或应用层 bcrypt
```

### 6. JOIN 加速：哈希指纹

```sql
-- 长字符串 JOIN 时，先比较短指纹再比较原值
SELECT a.*, b.*
FROM table_a a
JOIN table_b b
  ON md5(a.long_id) = md5(b.long_id)   -- 先比较 32 字符 hash
 AND a.long_id = b.long_id;             -- 再确认（可能省略，看碰撞率）
-- 实际优化器会基于哈希优化 JOIN 算法（Hash Join）
-- 用户层一般不需要手动加 hash
```

### 7. CDC / 增量同步指纹

```sql
-- 检测哪些行有变化（不需要存储所有列的旧值）
-- 在源表添加 row_hash 列
ALTER TABLE source_table ADD COLUMN row_hash CHAR(32);

UPDATE source_table SET row_hash = md5(CONCAT_WS('|', col1, col2, col3));

-- 同步：仅复制 hash 不同的行
SELECT s.*
FROM source_table s
LEFT JOIN target_table t ON s.id = t.id
WHERE t.id IS NULL                  -- 新行
   OR s.row_hash <> t.row_hash;     -- 修改行
```

## 密码学 vs 非密码学：选择指南

### 何时使用密码学哈希（MD5/SHA）

| 场景 | 推荐 | 原因 |
|------|------|------|
| 数据完整性校验 | SHA-256 | 标准、可移植 |
| 数字签名输入 | SHA-256 / SHA-512 | 抗碰撞、合规 |
| 数据脱敏（不可逆映射） | SHA-256 + salt | 防彩虹表 |
| 跨系统数据指纹 | MD5 / SHA-256 | 跨语言、库支持广 |
| URL 安全 token | SHA-256 + base64 | 标准做法 |

### 何时使用非密码学哈希

| 场景 | 推荐 | 原因 |
|------|------|------|
| 哈希表 / 分桶 | xxHash64 / CityHash | 速度极快 |
| Bloom filter | MurmurHash3 / xxHash | 分布均匀 |
| 分片路由 | FarmHash64 / xxHash64 | 速度 + 均匀 |
| HyperLogLog | MurmurHash3 / xxHash | 分布均匀关键 |
| 一致性哈希环 | MurmurHash3 | 雪崩效应好 |
| 网络在线服务 | SipHash | 防 HashDoS |

### 何时使用校验和

| 场景 | 推荐 | 原因 |
|------|------|------|
| 文件下载校验 | CRC32 / SHA-256 | 检测错误 |
| 网络包校验 | CRC32C | 硬件加速 |
| 块设备校验 | CRC32C / Adler32 | 硬件指令 |

### MD5 / SHA-1 的安全状态

```
MD5  - 已破解（2004 王小云教授碰撞攻击）
       - 不要用于：数字签名、密码学协议
       - 仍可用于：非安全的指纹、数据完整性（针对随机错误）

SHA-1 - 已破解（2017 SHAttered 攻击）
       - 不要用于：数字签名、HTTPS 证书
       - 仍可用于：版本控制（Git 仍用，但已加防御）

SHA-256+ - 目前安全
SHA-3   - 新设计，在所有引擎中都未原生支持
```

## ClickHouse 哈希函数家族对比

ClickHouse 提供 30+ 个哈希函数，是所有 SQL 引擎中最丰富的。理解它们的差异对性能调优很关键：

| 函数 | 算法 | 输出 | 速度 | 用途 |
|------|------|------|------|------|
| `MD5` | MD5 | FixedString(16) | 慢 | 兼容、完整性 |
| `SHA256` | SHA-256 | FixedString(32) | 慢 | 完整性 |
| `halfMD5` | MD5 前 64 位 | UInt64 | 慢 | 旧系统迁移 |
| `cityHash64` | Google CityHash | UInt64 | 极快 | 默认推荐 |
| `farmHash64` | Google FarmHash | UInt64 | 极快 | 与 BigQuery 兼容 |
| `xxHash32` | xxHash | UInt32 | 极快 | 32 位指纹 |
| `xxHash64` | xxHash | UInt64 | 极快 | 现代分布式 |
| `murmurHash2_32` | MurmurHash2 | UInt32 | 快 | 旧系统兼容 |
| `murmurHash2_64` | MurmurHash2 | UInt64 | 快 | 旧系统兼容 |
| `murmurHash3_32` | MurmurHash3 | UInt32 | 快 | Spark/Java 兼容 |
| `murmurHash3_64` | MurmurHash3 | UInt64 | 快 | Spark/Java 兼容 |
| `murmurHash3_128` | MurmurHash3 | FixedString(16) | 快 | 128 位指纹 |
| `sipHash64` | SipHash-2-4 | UInt64 | 中 | 防碰撞攻击 |
| `sipHash64Keyed` | SipHash w/ key | UInt64 | 中 | 带密钥 |
| `sipHash128` | SipHash 128 | FixedString(16) | 中 | 防碰撞攻击 |
| `sipHash128Keyed` | SipHash w/ key | FixedString(16) | 中 | 带密钥 |
| `gccMurmurHash` | GCC libstdc++ Murmur | UInt64 | 快 | 与 C++ 互操作 |
| `intHash32` | 整数特化 | UInt32 | 极快 | 整数键 |
| `intHash64` | 整数特化 | UInt64 | 极快 | 整数键 |
| `javaHash` | Java hashCode | Int32 | 极快 | Java 互操作 |
| `javaHashUTF16LE` | Java UTF16 hashCode | Int32 | 快 | Java/JVM 互操作 |
| `hiveHash` | Hive 字符串哈希 | Int32 | 快 | Hive 兼容 |
| `URLHash` | 域名分层哈希 | UInt64 | 快 | URL 聚合 |
| `URLHashLevel` | URL 截断哈希 | UInt64 | 快 | 子域聚合 |
| `yandexConsistentHash` | 一致性哈希 | UInt32 | 快 | 分片路由 |
| `jumpConsistentHash` | Google jump hash | Int64 | 快 | 一致性哈希 |
| `kafkaMurmurHash` | Kafka 风格 Murmur | Int32 | 快 | Kafka 兼容 |

### ClickHouse 推荐选择

```sql
-- 默认建议: cityHash64
-- 兼容 BigQuery: farmHash64 (FARM_FINGERPRINT 等价)
-- 兼容 Spark: murmurHash3_64
-- 防 HashDoS:  sipHash64Keyed
-- 极速整数:    intHash64
-- 跨集群一致性: jumpConsistentHash

-- 多列联合
SELECT cityHash64(user_id, event_type, toDate(event_time))
FROM events;

-- 与 BigQuery 互通
SELECT farmFingerprint64(user_id) FROM events;
-- 等价 BQ 的 FARM_FINGERPRINT(user_id)
```

## 各引擎 HMAC（消息认证码）支持

HMAC 用于带密钥的消息认证，常用于 API 签名校验。

| 引擎 | HMAC 函数 | 算法支持 | 备注 |
|------|----------|---------|------|
| PostgreSQL | `hmac(s, key, algo)` | md5/sha1/sha224/sha256/sha384/sha512 | 需 pgcrypto |
| MySQL | -- | -- | 不内置（需用户函数） |
| SQL Server | -- | -- | 不内置（PowerShell/CLR） |
| Oracle | `DBMS_CRYPTO.MAC()` | MAC_MD5/MAC_SH1/MAC_SH256/...  | 10g+ |
| ClickHouse | -- | -- | 不内置 |
| Snowflake | -- | -- | 不内置 |
| BigQuery | `KEYS.KEYSET_FROM_JSON` + `KEYS.NEW_KEYSET` | AES-GCM 等 | 间接 |
| Trino | `hmac_md5/hmac_sha1/hmac_sha256/hmac_sha512` | 完整 | 较新版本 |
| Spark SQL | -- | -- | 不内置 |
| DuckDB | -- | -- | 不内置 |
| Materialize | -- | -- | 不内置 |
| H2 | -- | -- | 不内置 |
| MariaDB | -- | -- | 不内置 |

## 性能对比（参考）

实测哈希函数吞吐（CPU 单核，输入 1KB 字符串）：

| 算法 | 吞吐 (MB/s) | 相对速度 |
|------|------------|---------|
| memcpy（基线） | ~12000 | 1x |
| xxHash64 (XXH3) | ~5500 | 0.45x |
| CityHash64 | ~5000 | 0.42x |
| FarmHash64 | ~5000 | 0.42x |
| MurmurHash3-64 | ~3500 | 0.29x |
| MurmurHash3-128 | ~3000 | 0.25x |
| SipHash-2-4-64 | ~1200 | 0.10x |
| FNV-1a-64 | ~800 | 0.07x |
| CRC32C (硬件) | ~12000 | 1x |
| CRC32 (软件) | ~600 | 0.05x |
| MD5 | ~600 | 0.05x |
| SHA-1 | ~500 | 0.04x |
| SHA-256 (软件) | ~300 | 0.025x |
| SHA-256 (SHA-NI) | ~2500 | 0.21x |
| SHA-512 (软件) | ~400 | 0.033x |
| SHA-3 | ~250 | 0.02x |

> 关键观察：
> - 非密码学哈希比密码学哈希快 10-20 倍
> - SHA-NI（Intel 硬件加速）能让 SHA-256 接近 xxHash 速度
> - CRC32C 在支持 SSE 4.2 的 CPU 上几乎是免费的

## 跨引擎兼容性陷阱

### 1. 输出类型差异

| 引擎 | MD5 输出类型 | 长度 |
|------|------------|------|
| PostgreSQL | text (hex) | 32 |
| MySQL | varchar (hex) | 32 |
| SQL Server | varbinary | 16 字节 |
| Oracle | RAW | 16 字节 |
| BigQuery | BYTES | 16 字节 |
| Snowflake | varchar (hex) | 32 |
| ClickHouse | FixedString | 16 字节 |
| Spark SQL | string (hex) | 32 |
| Trino | varbinary | 16 字节 |

迁移时注意：从 hex 字符串到二进制需要 `decode(s, 'hex')` 或 `from_hex(s)`，反之则需要 `to_hex()` 或 `encode(b, 'hex')`。

### 2. 输入编码差异

```sql
-- 同一个字符串，不同引擎的 MD5 输出可能不同！
-- 原因：是否启用 multi-byte UTF-8

-- MySQL（默认 utf8mb4）
SELECT MD5('中文');   -- a7bac2239fcdcb3a067903d8077c4a07

-- MySQL（默认 latin1）
SET NAMES latin1;
SELECT MD5('中文');   -- 不同结果！

-- 建议：跨引擎兼容时，先统一编码
SELECT MD5(CONVERT(s USING utf8mb4)) FROM t;
```

### 3. NULL 处理

```sql
-- PostgreSQL
SELECT md5(NULL);   -- NULL

-- MySQL
SELECT MD5(NULL);   -- NULL

-- Snowflake
SELECT MD5(NULL);   -- NULL

-- 多列哈希时 NULL 处理：
-- ClickHouse
SELECT cityHash64(NULL, 'b');   -- 不同于 cityHash64('', 'b')！
-- 显式处理：
SELECT cityHash64(coalesce(a, '\\N'), b);
```

### 4. 字符大小写

```sql
-- 大多数引擎返回小写 hex
SELECT md5('hello');             -- 5d41402a... (lower)

-- SQL Server HASHBYTES 转字符串需要手动控制
SELECT CONVERT(VARCHAR(32), HASHBYTES('MD5', 'hello'), 2);
-- 5D41402A... (upper)

SELECT LOWER(CONVERT(VARCHAR(32), HASHBYTES('MD5', 'hello'), 2));
-- 5d41402a... (lower)
```

### 5. 多列拼接歧义

```sql
-- 错误：用 + / || / CONCAT 直接拼接可能导致歧义
SELECT md5(col1 || col2);   -- 'ab'+'c' = 'abc'+'' 同结果

-- 正确：用分隔符
SELECT md5(col1 || '|' || col2);
SELECT md5(CONCAT_WS('|', col1, col2, col3));
SELECT md5(ROW(col1, col2, col3)::text);   -- PostgreSQL

-- ClickHouse 多参数原生支持
SELECT cityHash64(col1, col2, col3);   -- 不会歧义
```

## 设计争议

### 为什么 PostgreSQL 只内置 md5？

PostgreSQL 7.x 内置了 `md5()` 主要是为了密码存储（虽然现在不推荐这样用）。其他算法被放到 pgcrypto 扩展中，是因为：

1. **OpenSSL 依赖**：完整哈希家族依赖 OpenSSL，PostgreSQL 团队希望核心保持纯净。
2. **使用场景频率**：MD5 在早期是密码默认选择，使用极频繁；其他算法相对较少。
3. **扩展生态**：PostgreSQL 推崇扩展机制，pgcrypto 也是默认安装的 contrib 模块。

但代价是：用户需要 `CREATE EXTENSION pgcrypto;`，新手常常困惑为什么 SQL Server 的 HASHBYTES 在 PG 中找不到。

### 为什么 ClickHouse 哈希函数这么多？

ClickHouse 团队的哲学是"性能优先 + 开放选择"：

1. **跨系统互操作**：用户经常需要与 Hive、Spark、BigQuery 等系统交换数据，需要等价哈希。
2. **场景多样性**：A/B 测试、HLL、Bloom filter、分片、签名各自有最佳算法。
3. **学术开放**：Yandex 团队跟进学界进展（CityHash, FarmHash, xxHash, SipHash），快速集成。

但也带来困扰：新用户不知道选哪个，团队后期推出 `cityHash64` 作为默认推荐。

### Snowflake / BigQuery 为什么不暴露太多算法？

云数据仓库强调"托管简洁"：

1. **简化心智**：只暴露一个 `HASH()` (Snowflake) 或 `FARM_FINGERPRINT` (BigQuery)，让用户不必选择。
2. **内部优化空间**：算法选择是引擎实现细节，可以未来迭代。
3. **跨版本稳定**：Snowflake `HASH()` 承诺跨版本稳定（同输入同输出），不会变更算法。

### 哈希函数的版本稳定性问题

```
重要：某些引擎不保证跨版本哈希值稳定
- PostgreSQL HASH 分区: 不同 PG 版本可能算法不同
- DuckDB hash(): 0.x 与 1.x 之间可能不同
- Spark SQL hash(): 跨版本不稳定（曾改变）
- Snowflake HASH(): 承诺稳定
- BigQuery FARM_FINGERPRINT: 承诺稳定
- ClickHouse 命名函数（cityHash64 等）: 稳定（绑定到具体算法）
```

实际影响：依赖哈希分桶的查询，跨版本升级时可能需要重新分布数据。

## 对引擎开发者的实现建议

### 1. 选择默认哈希算法

```
推荐: xxHash64 或 CityHash64 作为内部哈希
原因:
  - 速度快（接近 memcpy）
  - 分布均匀（雪崩效应好）
  - 实现简单（< 200 行 C 代码）
  - 多种平台优化版本

不推荐: MurmurHash2 (有缺陷)、FNV (分布偏)、CRC32 (碰撞高)
```

### 2. 暴露给用户的函数集

```sql
-- 最小可用集
md5(s)               -- 兼容性，肯定要有
sha256(s)            -- 现代加密哈希
hash(s, ...)         -- 通用快速哈希（命名为 hash）

-- 进阶集
sha1(s) sha512(s)    -- 完整 SHA 家族
crc32(s)             -- 校验和
xxhash64(s, ...)     -- 高性能选项
hmac(s, key, algo)   -- 带密钥
```

### 3. 多列哈希设计

```
方案 A: 多参数函数（ClickHouse 风格）
  cityHash64(a, b, c)
  优势: 类型安全、零拷贝
  劣势: 函数签名复杂

方案 B: 字符串拼接（PG 风格）
  md5(a || '|' || b || '|' || c)
  优势: 简单、无需多签名
  劣势: 字符串拼接开销 + 歧义问题

方案 C: 数组/元组（部分引擎）
  hash(ARRAY[a, b, c])
  hash(ROW(a, b, c))

推荐: 方案 A 性能最好。无论哪种，文档需明确"NULL 如何处理"和"分隔符语义"
```

### 4. 输出类型的选择

```
对密码学哈希:
  推荐: BINARY/BYTEA + 显式 to_hex() / encode() 函数
  原因: 二进制更紧凑，比较更快，HMAC 链接方便
  反例: MySQL/PG 默认返回 hex 字符串，导致 32 字节存储一个 16 字节哈希

对非密码学哈希:
  推荐: 整数类型 (INT64/UINT64)
  原因: 比较是 1 个 CPU 指令，索引存储 8 字节
```

### 5. 性能与缓存

```
向量化实现要点:
  - 批量处理: 一次哈希 1024 行（SIMD 友好）
  - 内联函数: hash 函数应内联到列扫描循环
  - 平台特化: SHA-NI / AVX2 / NEON 指令集
  - 流水线友好: 避免分支预测失败（哈希内部循环展开）

哈希结果缓存:
  - 列存引擎可在 row group 元数据中预计算并缓存哈希
  - 仅对长字符串值得（短整数哈希本身已经很快）
```

### 6. 安全考量

```
密码哈希:
  - 不要建议用户用 md5() / sha2() 存密码
  - 提供 crypt() / argon2() / scrypt() 等专用函数

加盐:
  - 文档示例必须展示加盐用法
  - 错误示范: md5(password)
  - 正确示范: digest(password || salt, 'sha256') 或 crypt()

时间常数比较:
  - 用户层很难做时间常数比较（防 timing attack）
  - 如果暴露 HMAC 验证函数，应自带时间常数比较
```

### 7. 跨版本兼容性承诺

```
明确文档化承诺:
  类型 A: 算法绑定函数（如 cityHash64）
    - 算法不变，输入相同则输出永远相同
    - 优势: 用户可放心存储哈希结果
    - 缺点: 团队后期发现算法缺陷难以替换

  类型 B: 通用 hash 函数（如 PG hash 分区、Spark hash）
    - 不保证版本间稳定
    - 优势: 团队可随意改进
    - 缺点: 升级时分布可能改变

  推荐: 同时提供两类函数。算法稳定函数命名包含算法名（cityHash64/sha256），
        通用函数命名为 hash() 并明确"不保证跨版本稳定"
```

### 8. EXPLAIN 输出

```
哈希算子在 EXPLAIN 中应显示：
  - 哈希函数选择（cityHash64 / xxhash64 / etc.）
  - 是否启用硬件加速（SHA-NI、CRC32C）
  - 多列时的拼接顺序

示例:
  HashJoin
    HashFunction: cityHash64
    LeftKeys: (user_id, event_type)
    RightKeys: (uid, type)
```

## 总结对比矩阵

### 主流引擎核心哈希支持

| 能力 | PG | MySQL | SQL Server | Oracle | ClickHouse | Snowflake | BigQuery | DuckDB | Spark | Trino |
|------|-----|-------|------------|--------|-----------|-----------|----------|--------|-------|-------|
| MD5 | 内置 | 内置 | HASHBYTES | DBMS_CRYPTO | 内置 | 内置 | 内置 | 内置 | 内置 | 内置 |
| SHA-1 | pgcrypto | 内置 | HASHBYTES | DBMS_CRYPTO | 内置 | 内置 | 内置 | 内置 | 内置 | 内置 |
| SHA-256 | pgcrypto | SHA2() | HASHBYTES | DBMS_CRYPTO | 内置 | 内置 | 内置 | 内置 | 内置 | 内置 |
| SHA-512 | pgcrypto | SHA2() | HASHBYTES | DBMS_CRYPTO | 内置 | 内置 | 内置 | -- | 内置 | 内置 |
| CRC32 | 扩展 | 内置 | -- | -- | 内置 | -- | -- | -- | 内置 | 内置 |
| xxHash | -- | -- | -- | -- | 内置 | -- | -- | -- | xxhash64 | xxhash64 |
| CityHash | -- | -- | -- | -- | 内置 | -- | -- | -- | -- | -- |
| FarmHash | -- | -- | -- | -- | 内置 | -- | FARM_FINGERPRINT | -- | -- | -- |
| MurmurHash | -- | -- | -- | -- | 内置 | -- | -- | hash() | hash() | -- |
| SipHash | -- | -- | -- | -- | 内置 | -- | -- | -- | -- | -- |
| HMAC | pgcrypto | -- | -- | DBMS_CRYPTO | -- | -- | -- | -- | -- | 内置 |
| 通用 HASH() | -- | -- | -- | ORA_HASH | 多个 | HASH() | -- | hash() | hash() | -- |

### 引擎选型建议

| 场景 | 推荐引擎 | 推荐函数 |
|------|---------|---------|
| 高速分桶（数据仓库内部） | ClickHouse | `cityHash64` |
| BigQuery 互通 | ClickHouse / BigQuery | `farmFingerprint64` / `FARM_FINGERPRINT` |
| Spark/Hive 互通 | Spark / ClickHouse | `hash()` / `murmurHash3_32` |
| 加密合规 | 任何支持 SHA-256 的引擎 | `sha2(s, 256)` 或等价 |
| 高频写入 + 抗碰撞攻击 | ClickHouse | `sipHash64Keyed` |
| 跨系统数据完整性 | 任何引擎 | `MD5` 或 `SHA-256` |
| 仅 PG 的轻量需求 | PostgreSQL | `md5()` 内置 |
| PG 完整加密 | PostgreSQL | `pgcrypto` 的 `digest/hmac` |
| OLTP 简单需求 | MySQL / PG | `md5()` / `sha2()` |
| 数据湖快速指纹 | DuckDB | `hash()` |

## 关键发现

1. **哈希在 SQL 标准中完全缺失**：所有 45+ 引擎的哈希函数都是私有扩展，命名、类型、行为各不相同。

2. **PostgreSQL 的极简主义** vs **ClickHouse 的极致丰富**：PG 仅内置 `md5`，而 ClickHouse 提供 30+ 个哈希函数。这两端代表了"扩展中心"和"内置丰富"两种生态哲学。

3. **MD5/SHA-1 在密码学上已不安全**，但作为非加密指纹仍广泛使用。引擎应在文档中明确分类用途。

4. **非密码学哈希速度比密码学哈希快 10-20 倍**：内部 JOIN/分桶/HLL 优先用 xxHash/CityHash，而非 MD5。

5. **xxHash (2012, Yann Collet) 已成为非密码学哈希事实标准**：但只有少数引擎暴露给用户（ClickHouse、Spark 3.0+、Trino、Doris、StarRocks）。

6. **Snowflake/BigQuery 走"少即是多"路线**：仅暴露一个通用 `HASH` / `FARM_FINGERPRINT`，简化用户决策。

7. **输出类型差异是迁移最大坑**：hex 字符串（32 字符）vs 二进制（16 字节）vs 整数（8 字节），转换代码常被忽略。

8. **跨版本稳定性需要明确承诺**：算法绑定函数（cityHash64）和通用 hash() 应分开命名，避免用户依赖未承诺的稳定性。

9. **HMAC 支持远不普及**：只有 PG（pgcrypto）、Oracle、Trino 内置 HMAC，其他引擎需要应用层实现。

10. **BigQuery 的 FARM_FINGERPRINT 是优秀设计**：单一函数、INT64 输出、稳定承诺，足以覆盖 95% 的非加密哈希需求。其他引擎可借鉴。

11. **SQL Server 的 HASHBYTES 输入限制（旧版 8000 字节）**是常被忽略的迁移陷阱。

12. **CRC32 不是 SQL Server 的 CHECKSUM**：CHECKSUM 是私有 32 位算法，碰撞率比 CRC32 高，跨版本可能改变。

13. **SHA-3 几乎没有 SQL 引擎支持**：在密码学社区已是标准的 SHA-3，在数据库世界仍属罕见。

14. **哈希函数的硬件加速差异巨大**：CRC32C（SSE 4.2）和 SHA-256（SHA-NI）在现代 CPU 上接近 memcpy 速度，但默认实现不一定启用。

15. **Oracle 的 ORA_HASH 是被低估的工具**：不需要 DBMS_CRYPTO 权限，可直接用作分桶/抽样。

## 参考资料

- PostgreSQL: [Cryptographic Functions](https://www.postgresql.org/docs/current/functions-binarystring.html), [pgcrypto](https://www.postgresql.org/docs/current/pgcrypto.html)
- MySQL: [Encryption and Compression Functions](https://dev.mysql.com/doc/refman/8.0/en/encryption-functions.html)
- SQL Server: [HASHBYTES](https://learn.microsoft.com/en-us/sql/t-sql/functions/hashbytes-transact-sql)
- Oracle: [DBMS_CRYPTO](https://docs.oracle.com/en/database/oracle/oracle-database/19/arpls/DBMS_CRYPTO.html), [STANDARD_HASH](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/STANDARD_HASH.html)
- ClickHouse: [Hash Functions](https://clickhouse.com/docs/en/sql-reference/functions/hash-functions)
- Snowflake: [Cryptographic and Checksum Functions](https://docs.snowflake.com/en/sql-reference/functions/hash)
- BigQuery: [Hash Functions](https://cloud.google.com/bigquery/docs/reference/standard-sql/hash_functions)
- Spark SQL: [Hash Functions](https://spark.apache.org/docs/latest/api/sql/index.html#hash)
- Trino: [Binary Functions](https://trino.io/docs/current/functions/binary.html)
- DuckDB: [Hash Functions](https://duckdb.org/docs/sql/functions/utility)
- Yann Collet, "xxHash - Extremely fast non-cryptographic hash algorithm" (2012)
- Geoff Pike & Jyrki Alakuijala, "CityHash" (Google, 2011)
- Austin Appleby, "MurmurHash3" (2011)
- Aumasson & Bernstein, "SipHash: a fast short-input PRF" (2012)
- Wang Xiaoyun et al., "How to Break MD5 and Other Hash Functions" (EUROCRYPT 2005)
- Stevens et al., "The first collision for full SHA-1" (CRYPTO 2017)
