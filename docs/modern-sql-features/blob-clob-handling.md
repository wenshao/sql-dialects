# BLOB/CLOB 大对象处理 (Large Object Handling)

一张订单表不会让 DBA 半夜起床，一个 GB 级的 BLOB 字段会。大对象 (LOB) 几乎是所有生产事故的高频来源：内存溢出、事务日志膨胀、复制延迟、备份超时、连接池耗尽，根源往往都在一条 `SELECT document FROM docs` 上。从 SQL:1999 把 BLOB/CLOB/NCLOB 写进标准至今，40+ 主流引擎在此上拆分出了至少四条技术路线——内联 + TOAST、独立 LOB 段、外部文件引用、对象存储指针——没有任何一条能同时满足 "ACID、大容量、流式 API、低存储放大" 四个要求。

## SQL:1999 标准定义

SQL:1999 (ISO/IEC 9075-2) 在 Part 2 Foundation 中正式引入大对象类型：

```sql
<data type> ::=
    | CHARACTER LARGE OBJECT [ ( <large object length> ) ]
    | BINARY LARGE OBJECT [ ( <large object length> ) ]
    | NATIONAL CHARACTER LARGE OBJECT [ ( <large object length> ) ]

-- 常用别名
CLOB      = CHARACTER LARGE OBJECT
BLOB      = BINARY LARGE OBJECT
NCLOB     = NATIONAL CHARACTER LARGE OBJECT
```

标准的关键语义：

1. **LOB 是一个值，不是文件引用**：必须参与事务、受 ACID 保护
2. **LOB 定位符 (Locator)**：允许客户端通过句柄访问 LOB，无需一次性读入内存
3. **部分访问**：`SUBSTRING(clob FROM pos FOR len)` 支持随机读写
4. **LOB 类型不能用于 PRIMARY KEY / UNIQUE / GROUP BY / ORDER BY 等**
5. **比较运算有限**：通常仅支持相等性比较，不支持 `<`、`>` 等

## 支持矩阵（综合）

### 基础类型支持

| 引擎 | BLOB | CLOB | NCLOB | TEXT | BYTEA | 最大单值大小 |
|------|------|------|-------|------|-------|-------------|
| PostgreSQL | -- | -- | -- | `TEXT` | `BYTEA` | 1GB (TOAST) / 4TB (LO) |
| MySQL | `TINYBLOB..LONGBLOB` | -- | -- | `TINYTEXT..LONGTEXT` | -- | 4GB (LONGBLOB) |
| MariaDB | `TINYBLOB..LONGBLOB` | -- | -- | `TINYTEXT..LONGTEXT` | -- | 4GB |
| SQLite | `BLOB` | -- | -- | `TEXT` | -- | 2GB (实际受配置限制) |
| Oracle | `BLOB` | `CLOB` | `NCLOB` | -- | -- | (4GB - 1) * DB_BLOCK_SIZE (最大 128TB) |
| SQL Server | `VARBINARY(MAX)` | -- | -- | `VARCHAR(MAX)` / `NVARCHAR(MAX)` | -- | 2GB |
| DB2 | `BLOB` | `CLOB` / `DBCLOB` | -- | -- | -- | 2GB (常规) / 4GB (EXTENDED) |
| Snowflake | -- | -- | -- | `VARCHAR`/`BINARY` | `BINARY` | 16MB (VARCHAR/BINARY 列) |
| BigQuery | `BYTES` | -- | -- | `STRING` | -- | 10MB (列值) |
| Redshift | -- | -- | -- | `VARCHAR(65535)` | -- | 64KB |
| DuckDB | `BLOB` | -- | -- | `VARCHAR` | -- | 4GB 行级限制 |
| ClickHouse | -- | -- | -- | `String` | -- | 无显式上限 (受内存/磁盘限制) |
| Trino | `VARBINARY` | -- | -- | `VARCHAR` | -- | 连接器相关 |
| Presto | `VARBINARY` | -- | -- | `VARCHAR` | -- | 连接器相关 |
| Spark SQL | `BINARY` | -- | -- | `STRING` | -- | 2GB (JVM 数组限制) |
| Hive | `BINARY` | -- | -- | `STRING` | -- | 2GB |
| Flink SQL | `BYTES` / `VARBINARY` | -- | -- | `STRING` / `VARCHAR` | -- | 2GB |
| Databricks | `BINARY` | -- | -- | `STRING` | -- | 2GB |
| Teradata | `BLOB` | `CLOB` | -- | -- | -- | 2GB |
| Greenplum | -- | -- | -- | `TEXT` | `BYTEA` | 1GB |
| CockroachDB | -- | -- | -- | `STRING` | `BYTES` | 64MiB (软限制) / 1GB (硬限制) |
| TiDB | `TINYBLOB..LONGBLOB` | -- | -- | `TINYTEXT..LONGTEXT` | -- | 6MB (单列默认) / 120MB (事务限制) |
| OceanBase | `BLOB` | `CLOB` | -- | `TEXT` | -- | 48MB (默认) / 512MB (调参) |
| YugabyteDB | -- | -- | -- | `TEXT` | `BYTEA` | 256MB (软限制，继承 PG) |
| SingleStore | `BLOB..LONGBLOB` | -- | -- | `TEXT..LONGTEXT` | -- | 4GB |
| Vertica | -- | -- | -- | `LONG VARCHAR` | `LONG VARBINARY` | 32MB |
| Impala | -- | -- | -- | `STRING` | -- | 2GB |
| StarRocks | -- | -- | -- | `STRING` / `VARCHAR` | -- | 1MB (STRING 默认) |
| Doris | -- | -- | -- | `STRING` / `VARCHAR` | -- | 2GB |
| MonetDB | `BLOB` | `CLOB` | -- | -- | -- | ~2GB |
| CrateDB | -- | -- | -- | `TEXT` | -- | 文件系统级 (BLOB 表) |
| TimescaleDB | -- | -- | -- | `TEXT` | `BYTEA` | 继承 PostgreSQL |
| QuestDB | -- | -- | -- | `STRING` | `BINARY` | 2GB |
| Exasol | -- | `CLOB` | -- | `VARCHAR` | -- | 2MB (VARCHAR 限制) |
| SAP HANA | `BLOB` | `CLOB` | `NCLOB` | `TEXT` | -- | 2GB |
| Informix | `BLOB` / `BYTE` | `CLOB` / `TEXT` | -- | -- | -- | 4TB (Smart LOB) |
| Firebird | `BLOB SUB_TYPE 0` | `BLOB SUB_TYPE 1` (TEXT) | -- | -- | -- | 4GB |
| H2 | `BLOB` | `CLOB` | -- | `TEXT` | -- | 2^31-1 字节 |
| HSQLDB | `BLOB` | `CLOB` | -- | -- | -- | 64TB (理论) / 2GB (实际) |
| Derby | `BLOB` | `CLOB` | -- | -- | -- | 2GB |
| Amazon Athena | `VARBINARY` | -- | -- | `VARCHAR` | -- | 继承 Trino |
| Azure Synapse | `VARBINARY(MAX)` | -- | -- | `VARCHAR(MAX)` | -- | 2GB |
| Google Spanner | `BYTES(MAX)` | -- | -- | `STRING(MAX)` | -- | 10MiB (列) |
| Materialize | -- | -- | -- | `TEXT` | `BYTEA` | 继承 PG 协议 (1GB) |
| RisingWave | -- | -- | -- | `VARCHAR` | `BYTEA` | 继承 PG 协议 |
| InfluxDB (SQL) | -- | -- | -- | `STRING` | -- | 64KB (field 软限制) |
| Databend | -- | -- | -- | `STRING` | `BINARY` | 1MB (推荐) |
| Yellowbrick | -- | -- | -- | `VARCHAR` | `VARBINARY` | 64000 字节 (VARCHAR) |
| Firebolt | -- | -- | -- | `TEXT` | `BYTEA` | 8MB |

### 存储机制与流式 API

| 引擎 | 内联阈值 | 外存机制 | LOB 定位符 | 部分读 | 部分写 | 流式 API |
|------|---------|---------|-----------|--------|--------|---------|
| PostgreSQL (BYTEA/TEXT) | ~2KB (TOAST 阈值) | TOAST 表 | -- | `substring()` | `overlay()` | 整体读 |
| PostgreSQL (Large Object) | -- | `pg_largeobject` | `oid` | `lo_read` | `lo_write` | `lo_open`/`lo_seek` |
| MySQL | 768 字节 (行内指针) | 溢出页 | -- | `SUBSTRING` | `UPDATE` 重写 | JDBC `getBinaryStream` |
| Oracle | 4000 字节 (默认) | LOB 段 (SECUREFILE) | LOB Locator | `DBMS_LOB.SUBSTR` | `DBMS_LOB.WRITE` | `DBMS_LOB.READ`/`WRITE` |
| SQL Server | 8000 字节 | LOB_DATA 分配单元 | Text Pointer (已废弃) | `SUBSTRING` | `.WRITE()` | `OPENROWSET(BULK)` |
| DB2 | 由 INLINE LENGTH 决定 | LOB 表空间 | LOB Locator | `DBMS_LOB.SUBSTR` | `DBMS_LOB.WRITE` | 是 |
| SQLite | 页级 (跨页链接) | 溢出页 | `sqlite3_blob` 句柄 | `sqlite3_blob_read` | `sqlite3_blob_write` | 增量 I/O |
| Snowflake | 微分区列存 | -- | -- | `SUBSTR` | -- | Stage 下载 |
| BigQuery | 列式存储 | -- | -- | `SUBSTR` | -- | GCS URI |
| Informix | 字节级可配 | Smart Large Object Space | LO handle | `LO_READ` | `LO_WRITE` | 是 |
| Firebird | 8KB 页 (段链) | BLOB page chain | BLOB ID | 段级读 | 段级写 | Event-based |
| HSQLDB | -- | `.lobs` 文件 | BLOB Locator | `getBytes(pos,len)` | `setBytes` | 是 |
| Derby | 32K 以内行内 | 独立页 | BLOB Locator | `getBytes(pos,len)` | `setBytes` | 是 |

### 高级特性

| 引擎 | 事务性 LOB | 全文索引 | 外部 LOB (BFILE) | 压缩 | 去重 (SECUREFILE) | 加密 |
|------|-----------|---------|------------------|------|------------------|------|
| PostgreSQL | 是 | `tsvector`/GIN | -- | TOAST (pglz/lz4) | -- | 列级 (pgcrypto) |
| Oracle | 是 | Oracle Text | `BFILE` | SECUREFILE 压缩 | SECUREFILE Dedup | SECUREFILE 加密 |
| SQL Server | 是 | Full-Text Search | FILESTREAM/FileTable | PAGE/ROW 压缩 | -- | TDE/Always Encrypted |
| MySQL | 是 | `FULLTEXT` 索引 | -- | `COMPRESS()`/InnoDB 压缩 | -- | Keyring |
| DB2 | 是 | Net Search Extender | FILE LINK | ROW/PAGE 压缩 | -- | Native Encryption |
| SQLite | 是 | FTS5 虚拟表 | -- | -- | -- | SQLCipher (扩展) |
| Snowflake | 是 (快照) | -- | Stage 引用 | 自动 | 微分区级 | 自动 |
| SQL Server FILESTREAM | NTFS 事务 | 是 | 是 (NTFS) | NTFS 压缩 | -- | TDE |
| Oracle BFILE | 只读 | Oracle Text | 是 (OS 文件) | 文件系统级 | -- | 文件系统级 |
| Informix | 是 | 是 (Bts) | 是 (External) | Smart LOB 压缩 | -- | 是 |
| Firebird | 是 | -- | `EXTERNAL FILE` | -- | -- | -- |

> 统计：完整支持 SQL:1999 LOB 类型 (BLOB + CLOB) 的引擎约 15 个；采用 TEXT/VARCHAR(MAX)/BYTEA 等替代方案的约 25 个；不支持二进制类型或仅支持外部引用的约 5 个 (Redshift、BigQuery 严格意义上的 BLOB 等)。

## PostgreSQL：两套 LOB 系统并存

PostgreSQL 是唯一一个同时提供两套完全不同的 LOB 机制的主流数据库：

### TOAST (The Oversized-Attribute Storage Technique)

```sql
-- BYTEA 和 TEXT 自动走 TOAST
CREATE TABLE documents (
    id SERIAL PRIMARY KEY,
    content TEXT,           -- 自动 TOAST
    data BYTEA              -- 自动 TOAST
);

-- 查看 TOAST 配置
SELECT
    c.relname,
    a.attname,
    a.attstorage,           -- 'p'=plain, 'e'=external, 'm'=main, 'x'=extended
    a.attcompression        -- 'p'=pglz, 'l'=lz4 (PG14+)
FROM pg_class c
JOIN pg_attribute a ON c.oid = a.attrelid
WHERE c.relname = 'documents';

-- 修改存储策略
ALTER TABLE documents ALTER COLUMN content SET STORAGE EXTERNAL;   -- 外存不压缩
ALTER TABLE documents ALTER COLUMN content SET STORAGE EXTENDED;   -- 外存+压缩（默认）
ALTER TABLE documents ALTER COLUMN content SET COMPRESSION lz4;    -- PG14+ 切换算法

-- 查看 TOAST 表
SELECT reltoastrelid::regclass FROM pg_class WHERE relname = 'documents';
-- 返回: pg_toast.pg_toast_<oid>
```

TOAST 的关键特征：
- 自动触发：行大小超过 `TOAST_TUPLE_THRESHOLD` (默认约 2KB) 时启动
- 分块：大值切成 `TOAST_MAX_CHUNK_SIZE` (默认约 2000 字节) 的 chunk，存入 TOAST 表
- 单值上限：1GB (internal `varlena` header 限制)
- 压缩算法：pglz (默认) 或 lz4 (PG14+)
- 透明：应用层无感知，`SELECT` 返回完整值

### Large Object (lo_\*)

```sql
-- 创建大对象
SELECT lo_create(0);                         -- 返回新 OID
-- 或从文件导入
SELECT lo_import('/tmp/big_file.bin');       -- 服务端路径

-- 读写（必须在事务中）
BEGIN;
SELECT lo_open(12345, 131072);               -- 131072 = INV_WRITE | INV_READ
SELECT lowrite(0, E'\\x48656c6c6f');         -- fd=0, 写入 "Hello"
SELECT loread(0, 100);                       -- 读最多 100 字节
SELECT lo_close(0);
COMMIT;

-- 元数据目录
\d pg_largeobject_metadata     -- OID -> 所有者/权限
\d pg_largeobject              -- OID -> (pageno, data) 分块存储

-- 删除
SELECT lo_unlink(12345);

-- 从表中引用
CREATE TABLE files (
    id SERIAL PRIMARY KEY,
    name TEXT,
    data oid                  -- 指向 pg_largeobject 的 OID
);

-- 自动清理孤儿 LO
-- vacuumlo -h localhost -U postgres mydb
```

Large Object 的特征：
- 容量：单对象 4TB (自 PG 9.3+，之前 2GB)
- 流式 API：`lo_open`/`lo_read`/`lo_write`/`lo_seek`
- 需要显式管理：应用必须负责 `lo_unlink`，否则成为孤儿
- 不随表删除自动回收：需要 `vacuumlo` 工具或 ON DELETE 触发器

### TOAST vs Large Object 对比

| 维度 | TOAST (BYTEA/TEXT) | Large Object |
|------|-------------------|--------------|
| 容量 | 1GB | 4TB |
| API | 普通 SQL | `lo_*` 函数族 |
| 流式读写 | -- | 是 |
| 部分更新 | 需重写整个值 | `lo_seek` + `lo_write` |
| 自动清理 | 是 | 否 (需 vacuumlo) |
| 复制到从库 | 是 | 是 (自 PG 9.0) |
| 透明度 | 应用无感知 | 需显式调用 API |

## Oracle：功能最完整的 LOB 体系

### DBMS_LOB API

```sql
-- 表定义
CREATE TABLE documents (
    id NUMBER PRIMARY KEY,
    title VARCHAR2(200),
    content CLOB,
    payload BLOB,
    thumbnail BFILE
)
LOB(content) STORE AS SECUREFILE content_lob (
    TABLESPACE lob_ts
    ENABLE STORAGE IN ROW                 -- 小 LOB 行内存储
    CHUNK 8192                            -- LOB chunk 大小
    NOCACHE LOGGING
    COMPRESS MEDIUM                       -- SECUREFILE 压缩
    DEDUPLICATE                            -- 去重
    ENCRYPT USING 'AES192'                -- 加密
);

-- 读取部分内容
DECLARE
    v_chunk VARCHAR2(32767);
    v_amount NUMBER := 32767;
    v_offset NUMBER := 1;
BEGIN
    SELECT content INTO v_chunk FROM documents WHERE id = 1
    FOR UPDATE;

    -- SUBSTR：从 offset 开始读 amount 字符
    v_chunk := DBMS_LOB.SUBSTR(content, v_amount, v_offset);

    -- READ：循环读取整个 LOB
    WHILE v_offset <= DBMS_LOB.GETLENGTH(content) LOOP
        DBMS_LOB.READ(content, v_amount, v_offset, v_chunk);
        -- 处理 v_chunk
        v_offset := v_offset + v_amount;
    END LOOP;
END;
/

-- 写入/追加
DECLARE
    v_clob CLOB;
BEGIN
    SELECT content INTO v_clob FROM documents WHERE id = 1 FOR UPDATE;

    -- WRITE：在指定 offset 写入
    DBMS_LOB.WRITE(v_clob, 5, 10, 'Hello');

    -- WRITEAPPEND：追加
    DBMS_LOB.WRITEAPPEND(v_clob, 13, ' World, Oracle!');

    -- COPY：在两个 LOB 间复制
    DECLARE v_src CLOB; v_dst CLOB;
    BEGIN
        DBMS_LOB.COPY(v_dst, v_src, 100, 1, 1);  -- 复制 100 字符
    END;

    -- ERASE：清空一段范围
    DBMS_LOB.ERASE(v_clob, 50, 10);              -- 从 offset 10 清空 50 字符

    COMMIT;
END;
/

-- 常用函数
SELECT DBMS_LOB.GETLENGTH(content) FROM documents WHERE id = 1;
SELECT DBMS_LOB.INSTR(content, 'keyword', 1, 1) FROM documents;
SELECT DBMS_LOB.COMPARE(c1.content, c2.content) FROM ...;
```

### BFILE：外部文件引用

```sql
-- 1. 创建目录对象 (DBA 权限)
CREATE DIRECTORY docs_dir AS '/u01/app/oracle/docs';
GRANT READ ON DIRECTORY docs_dir TO app_user;

-- 2. 插入 BFILE
INSERT INTO documents (id, thumbnail)
VALUES (1, BFILENAME('DOCS_DIR', 'thumb_001.jpg'));

-- 3. 读取 BFILE (只读)
DECLARE
    v_bfile BFILE;
    v_buffer RAW(32767);
    v_amount BINARY_INTEGER := 32767;
    v_offset NUMBER := 1;
BEGIN
    SELECT thumbnail INTO v_bfile FROM documents WHERE id = 1;

    DBMS_LOB.FILEOPEN(v_bfile, DBMS_LOB.FILE_READONLY);
    DBMS_LOB.READ(v_bfile, v_amount, v_offset, v_buffer);
    DBMS_LOB.FILECLOSE(v_bfile);
END;
/
```

BFILE 限制：
- 只读，不受事务保护
- 大小上限 = 4GB * 文件系统 block size
- 数据库只保留引用，实际内容在 OS 文件系统
- 备份需要独立处理

### SECUREFILE vs BASICFILE

Oracle 11g (2007) 引入 SECUREFILE 取代 BASICFILE：

| 特性 | BASICFILE (旧) | SECUREFILE (11g+) |
|------|---------------|-------------------|
| 压缩 | -- | MEDIUM / HIGH |
| 去重 | -- | 是 |
| 加密 | -- | AES128/192/256 |
| 单实例性能 | 慢 | 快 2-5 倍 |
| 空间回收 | 碎片化 | 预分配 |
| 日志开销 | 高 | 可选 FILESYSTEM_LIKE_LOGGING |

12c 后 `DB_SECUREFILE=PREFERRED` 为默认，19c 后新 LOB 列一律 SECUREFILE。

## SQL Server：从 TEXT/IMAGE 到 VARCHAR(MAX) 再到 FILESTREAM

### VARCHAR(MAX) / VARBINARY(MAX) (SQL Server 2005+)

```sql
-- 现代 LOB 类型 (推荐)
CREATE TABLE Documents (
    Id INT PRIMARY KEY,
    Content VARCHAR(MAX),       -- 最大 2GB
    Unicode_Content NVARCHAR(MAX),  -- 最大 1GB 字符 (2GB 字节)
    Binary_Data VARBINARY(MAX)  -- 最大 2GB
);

-- 已废弃 (SQL Server 2005 之后不推荐)
-- TEXT, NTEXT, IMAGE

-- .WRITE() 部分更新 (仅 MAX 类型)
UPDATE Documents
SET Content.WRITE('new chunk', @offset, @length)
WHERE Id = 1;

-- SUBSTRING 部分读取
SELECT SUBSTRING(Content, 100, 500) FROM Documents WHERE Id = 1;

-- DATALENGTH 获取字节长度
SELECT DATALENGTH(Binary_Data) FROM Documents WHERE Id = 1;
```

### FILESTREAM (SQL Server 2008+)

FILESTREAM 将 VARBINARY(MAX) 存入 NTFS 文件系统，同时保留事务一致性：

```sql
-- 1. 服务实例启用 FILESTREAM
EXEC sp_configure 'filestream access level', 2;
RECONFIGURE;

-- 2. 数据库添加 FILESTREAM 文件组
ALTER DATABASE MyDB
ADD FILEGROUP FS_Group CONTAINS FILESTREAM;

ALTER DATABASE MyDB
ADD FILE (
    NAME = 'FS_Data',
    FILENAME = 'C:\MSSQL\FS_Data'
) TO FILEGROUP FS_Group;

-- 3. 定义 FILESTREAM 列
CREATE TABLE PhotoAlbum (
    Id UNIQUEIDENTIFIER ROWGUIDCOL NOT NULL UNIQUE,
    Name VARCHAR(100),
    Photo VARBINARY(MAX) FILESTREAM NULL
) FILESTREAM_ON FS_Group;

-- 4. 客户端通过 Win32 Streaming API 访问
-- SqlFileStream 类 (.NET) 或 OpenSqlFilestream (C API)
-- 特点: 数据存在 NTFS 文件, 但受 SQL 事务保护
```

### FileTable (SQL Server 2012+)

FileTable 把 Windows 文件夹暴露为表：

```sql
-- 启用非事务访问
ALTER DATABASE MyDB
SET FILESTREAM (NON_TRANSACTED_ACCESS = FULL, DIRECTORY_NAME = 'MyFiles');

-- 创建 FileTable
CREATE TABLE DocumentStore AS FILETABLE
WITH (
    FILETABLE_DIRECTORY = 'Documents',
    FILETABLE_COLLATE_FILENAME = database_default
);

-- 现在: \\SQLSERVER\MSSQLSERVER\MyFiles\Documents 可作为普通 Windows 共享访问
-- 同时: SELECT name, file_stream FROM DocumentStore;
-- SQL 和 Windows 两端保持同步
```

## MySQL：TINY/MEDIUM/LONG 四档

```sql
-- MySQL 四档 BLOB/TEXT
CREATE TABLE attachments (
    id INT PRIMARY KEY AUTO_INCREMENT,
    tiny_col TINYBLOB,        -- 2^8 - 1   = 255 字节
    norm_col BLOB,            -- 2^16 - 1  = 64KB
    med_col  MEDIUMBLOB,      -- 2^24 - 1  = 16MB
    big_col  LONGBLOB,        -- 2^32 - 1  = 4GB
    txt_col  LONGTEXT
);

-- InnoDB 行外存储
-- ROW_FORMAT = DYNAMIC (默认 MySQL 5.7+):
--   BLOB/TEXT 列只在行内保留 20 字节指针，整列存入溢出页
-- ROW_FORMAT = COMPACT:
--   前 768 字节行内，其余溢出

-- 查看存储格式
SHOW TABLE STATUS LIKE 'attachments';

-- 调整 innodb_page_size 影响 LOB 分配效率
-- max_allowed_packet 限制单条 SQL 中 LOB 大小 (默认 64MB)

-- 部分读
SELECT SUBSTRING(big_col, 1, 1024) FROM attachments WHERE id = 1;

-- 部分写 (整体重写)
UPDATE attachments SET big_col = CONCAT(big_col, ?) WHERE id = 1;
-- 不存在 DBMS_LOB.WRITEAPPEND 等价物

-- 压缩
UPDATE attachments SET big_col = COMPRESS(?) WHERE id = 1;
SELECT UNCOMPRESS(big_col) FROM attachments WHERE id = 1;

-- InnoDB 透明页压缩 (MySQL 5.7+)
CREATE TABLE logs (
    id INT PRIMARY KEY,
    payload LONGTEXT
) COMPRESSION = 'zlib';
```

MySQL LOB 特别注意：
- `max_allowed_packet` 限制单条消息大小
- `innodb_log_file_size` 影响大事务 LOB 的写入能力
- 8.0 之前 LOB 的部分更新性能极差 (整列重写)
- 8.0 引入 LOB 部分更新 (JSON 列专用，不适用 BLOB)

## DB2：工业级事务 LOB

```sql
CREATE TABLE documents (
    id INTEGER NOT NULL PRIMARY KEY,
    title VARCHAR(200),
    content CLOB(2G) LOGGED NOT COMPACT INLINE LENGTH 4096,
    binary_data BLOB(4G) NOT LOGGED COMPACT
);

-- INLINE LENGTH: 指定行内存储字节数
-- LOGGED / NOT LOGGED: 是否参与事务日志
-- COMPACT: 紧凑存储 (删除/更新碎片回收)
-- EXTENDED BLOB: 最大 4GB (非标准)

-- 部分读
SELECT SUBSTR(content, 1, 1024) FROM documents WHERE id = 1;

-- DB2 独有：FILE LINK (引用 OS 文件)
CREATE TABLE linked_docs (
    id INTEGER,
    link DATALINK(200)
        LINKTYPE URL
        FILE LINK CONTROL
        INTEGRITY ALL
        READ PERMISSION DB
        WRITE PERMISSION BLOCKED
);

INSERT INTO linked_docs VALUES (1, DLVALUE('file://server/docs/a.pdf'));
```

## SQLite：增量 BLOB I/O

```sql
CREATE TABLE images (
    id INTEGER PRIMARY KEY,
    name TEXT,
    data BLOB
);

-- SQLite 最大单值: 默认 1GB (SQLITE_MAX_LENGTH)，编译时可调至 2GB

-- 普通 SQL
INSERT INTO images (id, name, data) VALUES (1, 'logo.png', ?);
SELECT length(data), substr(data, 1, 1024) FROM images WHERE id = 1;

-- C API: sqlite3_blob_open / read / write (增量 I/O)
/*
sqlite3_blob *blob;
sqlite3_blob_open(db, "main", "images", "data", 1, 1, &blob);
sqlite3_blob_read(blob, buffer, 4096, offset);     // 随机读
sqlite3_blob_write(blob, buffer, 4096, offset);    // 随机写 (不能改变总长度)
sqlite3_blob_close(blob);
*/

-- 限制：sqlite3_blob_write 不能扩展 BLOB 大小
-- 如需扩容，必须整体 UPDATE

-- SQLite 推荐阈值: 单 BLOB 超过 ~100KB 时考虑独立文件 + 路径存储
-- "35% Faster Than The Filesystem" 研究: BLOB ≤ ~100KB 时存 DB 更快
```

## 其他引擎速览

### Snowflake：无 BLOB，依赖 Stage

```sql
-- Snowflake 最大 VARCHAR/BINARY 列 16MB
CREATE TABLE media (
    id INTEGER,
    small_blob BINARY(16777216),        -- 16MB 上限
    metadata VARCHAR                     -- 16MB 上限
);

-- 大文件通过 Stage
CREATE STAGE my_stage URL='s3://bucket/path/'
    CREDENTIALS = (AWS_KEY_ID='...' AWS_SECRET_KEY='...');

CREATE TABLE asset_refs (
    id INTEGER,
    stage_path VARCHAR        -- 指向 @my_stage/files/001.mp4
);

-- 通过 GET_PRESIGNED_URL 生成临时 URL
SELECT GET_PRESIGNED_URL(@my_stage, 'files/001.mp4', 3600) FROM asset_refs;

-- 读取文本内容 (小文件)
COPY INTO my_table FROM @my_stage/files/;
```

### BigQuery：BYTES + GCS 引用

```sql
-- BigQuery BYTES 类型最大 10MB
CREATE TABLE project.dataset.images (
    id INT64,
    thumbnail BYTES,               -- ≤10MB
    full_size_gcs_uri STRING       -- 'gs://bucket/path/img.jpg' 引用
);

-- 外部表指向 GCS
CREATE EXTERNAL TABLE project.dataset.gcs_files
OPTIONS (
    format = 'CSV',
    uris = ['gs://bucket/files/*.csv']
);

-- Object Tables (2023+): 将 GCS 非结构化数据以表呈现
CREATE OBJECT TABLE project.dataset.images_obj
WITH CONNECTION `project.us.conn`
OPTIONS (
    object_metadata = 'SIMPLE',
    uris = ['gs://bucket/images/*']
);
```

### ClickHouse：String 无上限

```sql
CREATE TABLE logs (
    ts DateTime,
    host String,
    message String,          -- 理论无上限，实际受单值/行/块内存限制
    payload FixedString(16)  -- 固定长度二进制
) ENGINE = MergeTree()
ORDER BY (host, ts);

-- ClickHouse 对 String 列采用多种压缩
ALTER TABLE logs MODIFY COLUMN message String CODEC(ZSTD(3));

-- 部分读
SELECT substring(message, 1, 1024) FROM logs WHERE host = 'web01';

-- ClickHouse 不支持流式 LOB API
-- 大对象建议走 S3 Table Engine
CREATE TABLE s3_data (id UInt64, raw String)
ENGINE = S3('https://bucket.s3.region.amazonaws.com/path/*.json', 'JSONEachRow');
```

### SAP HANA / Informix / Firebird

```sql
-- SAP HANA
CREATE TABLE documents (
    id INTEGER,
    content NCLOB MEMORY THRESHOLD 1000   -- 内存阈值 (超过写磁盘)
);

-- Informix Smart Large Object
CREATE TABLE media (
    id SERIAL,
    video BLOB,
    description CLOB
) PUT video IN (sbspace1), description IN (sbspace1);

-- Firebird BLOB SUB_TYPE
CREATE TABLE documents (
    id INTEGER,
    raw BLOB SUB_TYPE 0 SEGMENT SIZE 8192,       -- 二进制
    text_data BLOB SUB_TYPE 1 SEGMENT SIZE 8192  -- 文本 (即 TEXT)
);
```

## 流式 LOB：从数据库到应用的零拷贝

### JDBC 流式读写 (通用模式)

```java
// 读取：避免一次性加载
PreparedStatement ps = conn.prepareStatement(
    "SELECT payload FROM attachments WHERE id = ?");
ps.setInt(1, 42);
ResultSet rs = ps.executeQuery();
if (rs.next()) {
    try (InputStream in = rs.getBinaryStream("payload");
         OutputStream out = new FileOutputStream("/tmp/out.bin")) {
        byte[] buf = new byte[8192];
        int n;
        while ((n = in.read(buf)) != -1) {
            out.write(buf, 0, n);
        }
    }
}

// 写入：避免构造大字节数组
PreparedStatement ps = conn.prepareStatement(
    "INSERT INTO attachments(id, payload) VALUES(?, ?)");
ps.setInt(1, 42);
try (InputStream in = new FileInputStream("/tmp/big.bin")) {
    ps.setBinaryStream(2, in);  // 驱动按 chunk 推送
    ps.executeUpdate();
}
```

### 各驱动流式实现细节

| 驱动 | 读流式方法 | 写流式方法 | 分块大小 |
|------|-----------|-----------|---------|
| PostgreSQL JDBC | `getBinaryStream` (Large Object) / `getBytes` (BYTEA) | `setBinaryStream` | 驱动配置 |
| MySQL Connector/J | `getBinaryStream` | `setBinaryStream` | `blobSendChunkSize` 默认 1 MiB (1048576 字节) |
| Oracle JDBC | `getBinaryStream` / LOB API | `setBinaryStream` / `DBMS_LOB` | 32KB |
| Microsoft JDBC | `getBinaryStream` | `setBinaryStream` | 可配置 |
| psycopg2 (Python) | `lobject()` API | `lobject().write()` | 内存全载 (BYTEA) |
| SQLAlchemy | 流式需手动实现 | -- | -- |

### ODBC / ADO.NET

```csharp
// ADO.NET 流式读取 (SqlClient)
using var cmd = new SqlCommand(
    "SELECT Content FROM Documents WHERE Id = @id", conn);
cmd.Parameters.AddWithValue("@id", 42);

using var reader = cmd.ExecuteReader(CommandBehavior.SequentialAccess);
if (reader.Read()) {
    using var stream = reader.GetStream(0);
    stream.CopyTo(outputStream);
}
```

## 全文索引与 LOB 的配合

对 CLOB/TEXT 列的全文搜索是常见需求，但实现差异很大：

| 引擎 | 全文索引方案 | 对 LOB 支持 |
|------|-------------|------------|
| PostgreSQL | `tsvector` + GIN 索引 | TEXT/BYTEA 均可 |
| MySQL/MariaDB | `FULLTEXT` 索引 (InnoDB/MyISAM) | TEXT/CHAR/VARCHAR，不含 BLOB |
| Oracle | Oracle Text (CONTEXT/CTXCAT) | CLOB/BFILE |
| SQL Server | Full-Text Search | VARCHAR(MAX)/NVARCHAR(MAX)/VARBINARY(MAX) (需 IFilter) |
| DB2 | Net Search Extender | CLOB/BLOB |
| SAP HANA | Fuzzy/Text Analytics | NCLOB |
| SQLite | FTS5 虚拟表 | TEXT (不含 BLOB) |
| Snowflake | `CONTAINS` / `SEARCH` (2024+) | VARCHAR |
| Informix | BladeManager / Bts | CLOB |

```sql
-- PostgreSQL 示例
CREATE TABLE docs (id SERIAL, body TEXT);
CREATE INDEX idx_body_fts ON docs USING GIN (to_tsvector('english', body));

SELECT id FROM docs
WHERE to_tsvector('english', body) @@ to_tsquery('english', 'clob & lob');

-- Oracle Text
CREATE INDEX idx_content ON documents(content) INDEXTYPE IS CTXSYS.CONTEXT;
SELECT id FROM documents WHERE CONTAINS(content, 'Oracle NEAR LOB') > 0;

-- SQL Server 全文
CREATE FULLTEXT CATALOG ftCatalog;
CREATE FULLTEXT INDEX ON Documents(Content TYPE COLUMN FileExt)
    KEY INDEX PK_Documents ON ftCatalog;
SELECT Id FROM Documents WHERE CONTAINS(Content, '"large object"');
```

## 压缩与去重

### Oracle SECUREFILE 压缩

```sql
ALTER TABLE documents MODIFY LOB(content) (COMPRESS HIGH);
-- HIGH: 最高压缩率 (慢, CPU 密集)
-- MEDIUM: 平衡 (默认推荐)
-- LOW: 快 (最低压缩率)

-- 检查压缩效果
SELECT DBMS_LOB.GETLENGTH(content) AS logical_size,
       DBMS_LOB.GET_STORAGE_LIMIT(content) AS storage_size
FROM documents WHERE id = 1;

-- 去重 (相同内容只存一次)
ALTER TABLE documents MODIFY LOB(content) (DEDUPLICATE);

-- 查询去重统计
SELECT lob_name, deduplication FROM user_lobs WHERE table_name = 'DOCUMENTS';
```

### PostgreSQL TOAST 压缩

```sql
-- PG14+ 切换算法
ALTER TABLE documents ALTER COLUMN content SET COMPRESSION lz4;

-- 查看列级压缩
SELECT pg_column_compression(content) FROM documents WHERE id = 1;

-- 全局默认
ALTER SYSTEM SET default_toast_compression = 'lz4';

-- TOAST 压缩阈值 (超过此比例不压缩)
-- PGLZ: min_input_size=32, max_input_size=1MB, strategy
-- LZ4: 自适应
```

### SQL Server 压缩

```sql
-- PAGE 或 ROW 压缩 (作用于堆/索引，LOB 列有限)
ALTER TABLE Documents REBUILD WITH (DATA_COMPRESSION = PAGE);

-- 列存储索引对 LOB 有限支持
-- FILESTREAM 使用 NTFS 压缩（OS 级）
```

## 事务性与复制

### 大对象与 WAL/Redo

| 引擎 | LOB 写入是否进日志 | 复制支持 | 影响 |
|------|-------------------|---------|------|
| PostgreSQL (TOAST) | 是 | 是 | WAL 放大，复制延迟 |
| PostgreSQL (LO) | 是 (chunks) | 是 (9.0+) | 同上 |
| Oracle (SECUREFILE LOGGED) | 是 | 是 | 可选 NOLOGGING |
| Oracle (SECUREFILE NOLOGGING) | 最少日志 | 可能数据丢失 | 初始加载使用 |
| SQL Server | 完全日志 | 完整复制 | 大 LOB 严重影响 LDF |
| SQL Server FILESTREAM | 元数据日志 | 独立机制 | 减轻日志压力 |
| MySQL | Binlog 记录完整 | Row-based 复制大 BLOB 慢 | `binlog_row_image=MINIMAL` 优化 |
| DB2 NOT LOGGED LOB | 不日志 | 不复制 | 回滚失效 |

```sql
-- Oracle 绕过日志 (初始加载)
ALTER TABLE documents MODIFY LOB(payload) (NOCACHE NOLOGGING);
INSERT /*+ APPEND */ INTO documents SELECT * FROM staging;

-- DB2 NOT LOGGED LOB (事务中不产生日志)
CREATE TABLE imports (
    id INT,
    payload BLOB(4G) NOT LOGGED COMPACT
);
-- 风险：ROLLBACK 会把 LOB 置空或报错

-- MySQL row-based binlog 大 BLOB 优化
SET GLOBAL binlog_row_image = MINIMAL;
-- 只记录主键 + 实际变更列
```

## 常见踩坑与最佳实践

### 1. 连接池耗尽 (大 LOB 长连接占用)

```
场景: JDBC 连接读取 2GB LOB, 传输 30 秒, 此期间连接不可复用
    → 连接池大小 = max(并发用户, 平均传输时间 / 请求周期)
    → 大 LOB 读取导致连接池饥饿
解决:
    1) 流式 API (边读边响应，不持久占用连接)
    2) 大 LOB 走独立连接池
    3) 预签名 URL 让客户端直连对象存储
```

### 2. N+1 LOB 查询

```sql
-- 反例：行处理循环中对每行再查一次 LOB
SELECT id FROM docs;
-- for each id: SELECT content FROM docs WHERE id = ?;

-- 正例：批量 JOIN 或流式游标
SELECT id, content FROM docs;   -- 一次流式读取
```

### 3. `SELECT *` 的代价

LOB 列随 `SELECT *` 一起传输会导致网络/内存爆炸：

```sql
-- 反例
SELECT * FROM attachments WHERE owner_id = 42;

-- 正例：分离元数据与内容
SELECT id, name, size, created_at FROM attachments WHERE owner_id = 42;
-- 详情页再查：SELECT content FROM attachments WHERE id = ?
```

### 4. 复制延迟爆炸

大 LOB 写入主库后，复制到从库需要：
- PostgreSQL: 完整 WAL 传送 (TOAST chunks + lo_page)
- MySQL: row-based binlog 的 BEFORE/AFTER image
- Oracle: Redo + LogMiner (SECUREFILE 可选压缩)

建议：
- LOB 列尽量拆表 (1:1 关联)
- 或使用异步队列 + 对象存储
- 监控 `pg_stat_replication` / `SHOW SLAVE STATUS` 延迟

### 5. 备份窗口失控

```
200GB 表, 其中 180GB 是 LOB:
  逻辑备份 (pg_dump / mysqldump): 单线程，可能 6+ 小时
  物理备份 (pg_basebackup / Oracle RMAN): 可能 30-60 分钟
  LOB 外置 (S3/GCS): 备份时间不变，但 RPO/RTO 模型改变
```

### 6. 内存溢出

驱动默认一次性加载 LOB 到内存：
- JDBC `getBytes()` → 2GB 可能导致 OOM
- psycopg2 `cursor.fetchone()` 的 BYTEA 字段直接转 `bytes`
- 改用 `getBinaryStream` / `lobject()` / `chunked fetch`

## 关键发现

1. **两套 LOB 系统是常态**：PG TOAST + Large Object、Oracle 内部 LOB + BFILE、SQL Server VARCHAR(MAX) + FILESTREAM，都是"透明小 LOB + 显式大 LOB"两条路线。

2. **LOB 类型消亡中**：TEXT/IMAGE (SQL Server) 被 VARCHAR(MAX) 取代；Snowflake/BigQuery/Redshift 等云仓直接废弃 LOB 概念，依赖对象存储。

3. **流式 API 差异巨大**：Oracle DBMS_LOB、SQLite `sqlite3_blob_*`、SQL Server `OpenSqlFilestream`、PostgreSQL `lo_*` 四套独立 API，没有任何 SQL 标准承认的流式接口。

4. **内联阈值是关键调优参数**：2KB (PG) / 768B (MySQL) / 4000B (Oracle) / 8000B (SQL Server)，决定了小 LOB 在行内还是行外，直接影响扫描性能。

5. **SYSTEM 日志放大**：PostgreSQL TOAST 写入产生 ~3x WAL (原值 + TOAST chunk + index)，Oracle SECUREFILE LOGGED 有 ~1.5x Redo。NOLOGGING/NOT LOGGED 选项以可用性换性能。

6. **全文索引 != 简单支持**：多数引擎需要独立全文扩展 (Oracle Text、SQL Server FT、PG GIN)，配置与 LOB 存储分离，维护复杂。

7. **外部 LOB 趋势**：Snowflake Stage、BigQuery Object Tables、SQL Server FILESTREAM、Oracle BFILE 都指向同一方向——把大对象踢出 DB，保留元数据与引用。

8. **4GB 是心理关口**：32-bit 长度字段带来的物理上限，LONGBLOB、SECUREFILE BASIC、DB2 EXTENDED 都在此边界。突破需要 64-bit 改造，如 PostgreSQL LO (4TB)、Oracle LOB (128TB)。

9. **去重/压缩仅 Oracle 标准化**：SECUREFILE DEDUPLICATE + COMPRESS 是唯一同时提供行级块级双重压缩与去重的商业数据库特性。开源引擎只能靠 TOAST lz4 或应用层处理。

10. **事务回滚代价高**：LOB 列的 UPDATE/DELETE 在未提交前会产生临时副本，大事务回滚极慢。建议大 LOB 变更放在短事务中，或采用"先写新再切指针"模式。

## 对引擎开发者的建议

### 1. 选择存储策略

```
方案 A: 内联 + 溢出 (PostgreSQL TOAST / MySQL InnoDB)
  优点: 对应用透明，小 LOB 高效
  缺点: 单行大小受限，溢出页管理复杂
  实现关键: 阈值自适应、压缩算法可插拔、chunk 大小对齐页大小

方案 B: 独立 LOB 段 (Oracle SECUREFILE / DB2 / Informix Smart LOB)
  优点: 与行存储解耦，支持流式 API
  缺点: 需要独立元数据、独立空间管理、外部 API
  实现关键: locator 结构、预分配策略、碎片回收

方案 C: 对象存储指针 (Snowflake Stage / BigQuery Object Table)
  优点: 无限容量，原生云支持
  缺点: 非事务、需要应用管理一致性
  实现关键: presigned URL、生命周期、权限传递

方案 D: 双模并存 (PostgreSQL TOAST + LO)
  优点: 应用按需选择
  缺点: 两套 API，维护成本高
```

### 2. LOB 定位符设计

```
LOB Locator 核心字段:
  - LOB ID (全局唯一，通常 64-bit)
  - 版本号 (MVCC 支持)
  - 长度
  - 权限位 (读/写/追加)
  - 缓存/持久标志

关键操作:
  open(locator, mode) -> handle
  read(handle, offset, len) -> bytes
  write(handle, offset, bytes) -> written
  truncate(handle, new_len)
  close(handle) [+ commit/rollback]

生命周期:
  - 事务内: 可写
  - 事务提交后: 固化版本号
  - 读事务: 只读视图，MVCC 保护
```

### 3. WAL/Redo 策略

```
默认全量日志: 语义最强，但 WAL 膨胀最快
NOLOGGING/直接路径: 初始加载专用，放弃回滚能力
INLINE LOG + CHUNK LOG: DB2 混合策略，内联部分日志，外部异步
引用计数 COW: SECUREFILE Dedup 特有，日志只记引用变化
```

### 4. 客户端协议

```
现状问题:
  - PostgreSQL 协议: 整值传输 (BYTEA/TEXT 受 1GB 限制)
  - MySQL 协议: 64MB 单消息 (max_allowed_packet)
  - Oracle NET: 专有流式协议
  - ODBC/JDBC: 应用层切片

建议:
  - 协议层支持 chunked transfer (类似 HTTP chunked)
  - 协议层支持 skip (客户端跳过不需要的 LOB)
  - 客户端驱动默认开启流式 API，避免一次性加载
```

### 5. 优化器

```
统计信息:
  - LOB 列应有特殊统计 (长度分布、行内/外比例)
  - 避免基于 LOB 列做 JOIN / ORDER BY / GROUP BY

执行计划:
  - LOB 列投影下推: 不需要时完全不读 TOAST 表
  - 部分读下推: SUBSTR(lob, 1, 1024) 只读第一个 chunk
  - 长度查询优化: LENGTH(lob) 只读元数据，不读内容
```

### 6. 测试要点

```
功能测试:
  - 边界值: 0 字节、1 字节、阈值-1、阈值、阈值+1、最大值、最大值+1
  - Null 与空值区分: NULL vs 长度为 0 的 LOB
  - 字符集: CLOB 跨 UTF-8/UTF-16 转换

性能测试:
  - 单行读取 (小 LOB / 大 LOB)
  - 批量扫描 (LOB 列投影 / 非投影)
  - 流式读写吞吐
  - 并发读写冲突

事务测试:
  - 大 LOB 插入后回滚 (空间回收)
  - 并发更新同一 LOB (锁粒度)
  - 跨事务 LOB 引用 (应失败)

可观测性:
  - LOB 读字节计数
  - TOAST/LOB 段大小
  - 压缩比统计
  - 溢出页碎片率
```

## 总结对比矩阵

### 功能完整度总览

| 能力 | Oracle | PostgreSQL | SQL Server | MySQL | DB2 | SQLite | Snowflake | BigQuery |
|------|--------|-----------|------------|-------|-----|--------|-----------|----------|
| BLOB 类型 | 是 | BYTEA | VARBINARY(MAX) | 是 | 是 | 是 | -- | BYTES |
| CLOB 类型 | 是 | TEXT | VARCHAR(MAX) | TEXT | 是 | TEXT | -- | -- |
| NCLOB 类型 | 是 | -- | NVARCHAR(MAX) | -- | DBCLOB | -- | -- | -- |
| 最大大小 | 128TB | 4TB (LO) / 1GB (TOAST) | 2GB | 4GB | 4GB | 2GB | 16MB | 10MB |
| 流式 API | DBMS_LOB | lo_* | FILESTREAM | JDBC | DBMS_LOB | blob_* | -- | -- |
| 部分读 | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| 部分写 | 是 | 是 (LO) | .WRITE() | -- | 是 | 是 | -- | -- |
| 外部 LOB | BFILE | -- | FILESTREAM/FileTable | -- | DATALINK | -- | Stage | Object Table |
| 压缩 | SECUREFILE | TOAST (lz4) | PAGE/ROW | COMPRESS() | ROW/PAGE | -- | 自动 | 自动 |
| 去重 | SECUREFILE | -- | -- | -- | -- | -- | -- | -- |
| 加密 | TDE+SECUREFILE | pgcrypto | TDE | Keyring | Native | SQLCipher | 自动 | 自动 |
| 全文索引 | Oracle Text | GIN+tsvector | Full-Text | FULLTEXT | NSE | FTS5 | -- | -- |

### 场景推荐

| 场景 | 推荐方案 | 理由 |
|------|---------|------|
| 高并发小 LOB (<10KB) | PostgreSQL TOAST / MySQL LONGBLOB | 透明、高效 |
| GB 级科学数据 | Oracle SECUREFILE / PG Large Object | 流式 API、部分读写 |
| 海量图片/视频 | Snowflake Stage / S3 + 指针 | 成本、可扩展性 |
| 严格事务二进制 | Oracle SECUREFILE / SQL Server FILESTREAM | ACID + 大容量 |
| 嵌入式场景 | SQLite Incremental Blob I/O | 零依赖 |
| 全文搜索为主 | Oracle Text / PG GIN / SQL Server FT | 原生集成 |
| 归档只读 | BFILE / DATALINK / 外部表 | 不占 DB 存储 |
| 云原生分析 | BigQuery Object Table / Snowflake Stage | Serverless |

## 参考资料

- SQL:1999 标准: ISO/IEC 9075-2:1999, Part 2 Foundation, Section 4.3 "String types"
- PostgreSQL: [TOAST](https://www.postgresql.org/docs/current/storage-toast.html) / [Large Objects](https://www.postgresql.org/docs/current/largeobjects.html)
- Oracle: [SecureFiles and Large Objects Developer's Guide](https://docs.oracle.com/en/database/oracle/oracle-database/19/adlob/)
- Oracle: [DBMS_LOB](https://docs.oracle.com/en/database/oracle/oracle-database/19/arpls/DBMS_LOB.html)
- SQL Server: [FILESTREAM](https://learn.microsoft.com/en-us/sql/relational-databases/blob/filestream-sql-server) / [FileTables](https://learn.microsoft.com/en-us/sql/relational-databases/blob/filetables-sql-server)
- SQL Server: [Large Value Types](https://learn.microsoft.com/en-us/sql/t-sql/data-types/ntext-text-and-image-transact-sql)
- MySQL: [BLOB and TEXT Types](https://dev.mysql.com/doc/refman/8.0/en/blob.html)
- DB2: [Large objects (LOBs)](https://www.ibm.com/docs/en/db2/11.5?topic=types-large-objects-lobs)
- SQLite: [Incremental BLOB I/O](https://www.sqlite.org/c3ref/blob_open.html)
- SQLite: [35% Faster Than The Filesystem](https://www.sqlite.org/fasterthanfs.html)
- Snowflake: [Stages](https://docs.snowflake.com/en/user-guide/data-load-local-file-system-create-stage)
- BigQuery: [Object Tables](https://cloud.google.com/bigquery/docs/object-table-introduction)
- ClickHouse: [String Data Types](https://clickhouse.com/docs/en/sql-reference/data-types/string)
- SAP HANA: [LOB Data Types](https://help.sap.com/docs/SAP_HANA_PLATFORM/4fe29514fd584807ac9f2a04f6754767/20a1569875191014b507dfaae5003b59.html)
- Informix: [Smart Large Objects](https://www.ibm.com/docs/en/informix-servers/14.10?topic=objects-smart-large)
- Firebird: [BLOB Type](https://firebirdsql.org/refdocs/langrefupd25-datatypes-binarytypes.html)
