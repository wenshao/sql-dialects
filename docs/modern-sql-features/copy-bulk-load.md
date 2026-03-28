# 批量数据加载

将大量数据高效导入数据库——从 COPY 到 LOAD DATA，各引擎的批量导入方式和性能差异。

## 支持矩阵

| 引擎 | 命令/工具 | 典型速度 | 来源 | 备注 |
|------|----------|---------|------|------|
| PostgreSQL | COPY | 10-50万行/秒 | stdin / 文件 | **最高效的行式导入** |
| MySQL | LOAD DATA INFILE | 5-30万行/秒 | 本地/服务端文件 | 需 FILE 权限 |
| SQL Server | BULK INSERT / bcp | 10-50万行/秒 | 文件 | 也有 OPENROWSET(BULK) |
| Oracle | SQL*Loader / External Tables | 10-100万行/秒 | 文件 | Direct Path 模式最快 |
| Snowflake | COPY INTO | 极高 | Stage (S3/Azure/GCS) | 分布式并行加载 |
| BigQuery | Load Job / bq load | 极高 | GCS / 本地文件 | 免费（不消耗 slot） |
| ClickHouse | INSERT FORMAT / clickhouse-client | 100万+行/秒 | stdin / 文件 | 列式批量极快 |
| Redshift | COPY | 极高 | S3 | 强制推荐从 S3 加载 |
| DuckDB | COPY / INSERT FROM | 100万+行/秒 | 文件 | Parquet 导入极快 |
| SQLite | .import | 适中 | CSV 文件 | CLI 命令，非 SQL |
| Hive | LOAD DATA | 取决于 HDFS | HDFS / 本地 | 实际是文件移动 |

## 为什么需要批量加载

```sql
-- 逐行 INSERT 的性能问题:
INSERT INTO orders VALUES (1, 'Alice', 100);
INSERT INTO orders VALUES (2, 'Bob', 200);
INSERT INTO orders VALUES (3, 'Charlie', 300);
-- ... 100 万次

-- 每次 INSERT 的开销:
-- 1. SQL 解析和编译
-- 2. 事务开始 + 提交（若 autocommit）
-- 3. WAL 写入
-- 4. 索引更新
-- 5. 网络往返（客户端-服务端）
-- 结果: 可能只有 1000 行/秒

-- 批量加载跳过大部分开销:
-- 1. 无 SQL 解析（直接二进制协议）
-- 2. 单次事务
-- 3. WAL 可合并写入或旁路
-- 4. 索引可延迟构建
-- 5. 流式传输（无逐行往返）
-- 结果: 可达 50万+ 行/秒
```

## 各引擎语法对比

### PostgreSQL COPY

```sql
-- 从文件导入（服务端文件路径）
COPY orders (id, customer_name, amount, order_date)
FROM '/data/orders.csv'
WITH (FORMAT csv, HEADER true, DELIMITER ',', NULL '');

-- 从标准输入导入（客户端文件，最常用）
-- psql 命令:
-- \copy orders FROM '/local/path/orders.csv' WITH (FORMAT csv, HEADER true)

-- 程序化导入（最高性能，使用 COPY 二进制协议）
COPY orders FROM STDIN WITH (FORMAT binary);

-- 导出到文件
COPY orders TO '/data/orders_export.csv' WITH (FORMAT csv, HEADER true);

-- 导出查询结果
COPY (SELECT * FROM orders WHERE amount > 1000)
TO '/data/high_value_orders.csv' WITH (FORMAT csv, HEADER true);

-- WITH 选项:
-- FORMAT: csv, text (默认), binary
-- HEADER: true/false
-- DELIMITER: 分隔符（默认 tab）
-- NULL: NULL 值的字符串表示（默认 \N）
-- QUOTE: 引用字符（默认 "）
-- ESCAPE: 转义字符（默认 "）
-- ENCODING: 字符编码
-- FORCE_NULL: 指定列的空字符串视为 NULL

-- 性能优化:
-- 1. 导入前禁用索引和约束
ALTER TABLE orders DISABLE TRIGGER ALL;
-- 2. 导入后重建索引
ALTER TABLE orders ENABLE TRIGGER ALL;
REINDEX TABLE orders;
-- 3. 增加 maintenance_work_mem
SET maintenance_work_mem = '2GB';
-- 4. 使用 UNLOGGED TABLE（不写 WAL，崩溃后数据丢失）
CREATE UNLOGGED TABLE orders_staging (LIKE orders);
COPY orders_staging FROM '/data/orders.csv' WITH (FORMAT csv);
INSERT INTO orders SELECT * FROM orders_staging;
DROP TABLE orders_staging;
```

### MySQL LOAD DATA INFILE

```sql
-- 从服务端文件加载
LOAD DATA INFILE '/var/lib/mysql-files/orders.csv'
INTO TABLE orders
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES                          -- 跳过表头
(id, customer_name, amount, @order_date)
SET order_date = STR_TO_DATE(@order_date, '%Y-%m-%d');

-- 从客户端文件加载（需启用 local_infile）
LOAD DATA LOCAL INFILE '/local/path/orders.csv'
INTO TABLE orders
FIELDS TERMINATED BY ','
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

-- 性能选项:
-- REPLACE: 遇到重复键时替换
LOAD DATA INFILE '/data/orders.csv' REPLACE INTO TABLE orders ...;

-- IGNORE: 遇到重复键时跳过
LOAD DATA INFILE '/data/orders.csv' IGNORE INTO TABLE orders ...;

-- ⚠️ 安全注意:
-- 1. 需要 FILE 权限
-- 2. LOCAL INFILE 默认关闭（secure_file_priv 控制）
-- 3. 服务端文件路径受 secure_file_priv 限制
SHOW VARIABLES LIKE 'secure_file_priv';

-- 性能优化:
-- 1. 关闭 autocommit
SET autocommit = 0;
-- 2. 禁用唯一性检查
SET unique_checks = 0;
-- 3. 禁用外键检查
SET foreign_key_checks = 0;
-- 4. 调大 bulk_insert_buffer_size
SET bulk_insert_buffer_size = 256 * 1024 * 1024;
-- 5. 使用 ALTER TABLE ... DISABLE KEYS（MyISAM）
ALTER TABLE orders DISABLE KEYS;
LOAD DATA INFILE ...;
ALTER TABLE orders ENABLE KEYS;
```

### SQL Server BULK INSERT / bcp

```sql
-- BULK INSERT（T-SQL 语句）
BULK INSERT orders
FROM '/data/orders.csv'
WITH (
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '\n',
    FIRSTROW = 2,                        -- 跳过表头
    TABLOCK,                             -- 表锁（提升性能）
    BATCHSIZE = 100000,                  -- 每批次行数
    MAXERRORS = 100,                      -- 最大允许错误数
    FORMAT = 'CSV'                       -- SQL Server 2017+
);

-- bcp 命令行工具
-- bcp mydb.dbo.orders in /data/orders.csv -c -t"," -S server -U user -P pass

-- OPENROWSET(BULK) 可以在查询中使用
INSERT INTO orders
SELECT * FROM OPENROWSET(
    BULK '/data/orders.csv',
    FORMATFILE = '/data/orders.fmt',
    FIRSTROW = 2
) AS bulk_data;

-- 最小日志记录条件（大幅提升性能）:
-- 1. 目标表是堆（无聚簇索引）或空表
-- 2. 使用 TABLOCK hint
-- 3. 数据库恢复模式为 SIMPLE 或 BULK_LOGGED
ALTER DATABASE mydb SET RECOVERY BULK_LOGGED;
BULK INSERT orders FROM '/data/orders.csv'
WITH (TABLOCK, BATCHSIZE = 100000);
ALTER DATABASE mydb SET RECOVERY FULL;
```

### Oracle SQL*Loader

```sql
-- SQL*Loader 控制文件 (orders.ctl):
-- LOAD DATA
-- INFILE '/data/orders.csv'
-- INTO TABLE orders
-- FIELDS TERMINATED BY ','
-- OPTIONALLY ENCLOSED BY '"'
-- TRAILING NULLCOLS
-- (id, customer_name, amount, order_date DATE "YYYY-MM-DD")

-- 常规路径加载（通过 SQL 层）
-- sqlldr user/pass@db control=orders.ctl

-- 直接路径加载（旁路 SQL 层，直接写数据文件，最快）
-- sqlldr user/pass@db control=orders.ctl direct=true

-- Oracle 外部表方式（SQL 内使用）
CREATE TABLE ext_orders (
    id NUMBER,
    customer_name VARCHAR2(100),
    amount NUMBER
)
ORGANIZATION EXTERNAL (
    TYPE ORACLE_LOADER
    DEFAULT DIRECTORY data_dir
    ACCESS PARAMETERS (
        RECORDS DELIMITED BY NEWLINE
        FIELDS TERMINATED BY ','
    )
    LOCATION ('orders.csv')
);

INSERT INTO orders SELECT * FROM ext_orders;

-- Oracle 12c+: INSERT /*+ APPEND */ ... SELECT (直接路径插入)
INSERT /*+ APPEND */ INTO orders SELECT * FROM ext_orders;
-- 直接路径: 跳过缓冲区，直接写入数据文件的高水位线之上
-- 限制: 事务提交前表不可查询
```

### Snowflake COPY INTO

```sql
-- 1. 创建 Stage（数据暂存区）
CREATE STAGE my_stage URL = 's3://my-bucket/data/'
    CREDENTIALS = (AWS_KEY_ID = '...' AWS_SECRET_KEY = '...');

-- 或使用内部 Stage
CREATE STAGE my_internal_stage;
-- 上传文件: PUT file:///local/path/orders.csv @my_internal_stage;

-- 2. COPY INTO 加载数据
COPY INTO orders
FROM @my_stage/orders/
FILE_FORMAT = (TYPE = CSV SKIP_HEADER = 1 FIELD_OPTIONALLY_ENCLOSED_BY = '"')
PATTERN = '.*\.csv\.gz'               -- 支持 glob 模式
ON_ERROR = 'CONTINUE';                -- 错误时继续（跳过坏行）

-- 从 Parquet 加载（最常见）
COPY INTO orders
FROM @my_stage/orders/
FILE_FORMAT = (TYPE = PARQUET)
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE;  -- 按列名匹配

-- 3. 查看加载历史
SELECT * FROM TABLE(information_schema.copy_history(
    TABLE_NAME => 'orders',
    START_TIME => DATEADD(hours, -24, CURRENT_TIMESTAMP())
));

-- Snowflake COPY 的核心优势:
-- 1. 分布式并行加载（多文件自动并行）
-- 2. 文件去重（同一文件不会重复加载，除非 FORCE = TRUE）
-- 3. 自动压缩检测（gzip, bzip2, snappy 等）
-- 4. 错误处理灵活（CONTINUE, SKIP_FILE, ABORT_STATEMENT）
-- 5. 支持数据转换（在 COPY 中做 SELECT 转换）
COPY INTO orders (id, name, amount_cents)
FROM (SELECT $1, $2, $3 * 100 FROM @my_stage/orders.csv);
```

### ClickHouse INSERT FORMAT

```sql
-- ClickHouse 直接在 INSERT 语句中指定格式

-- CSV 格式
INSERT INTO orders FORMAT CSV
1,"Alice",100,"2024-03-01"
2,"Bob",200,"2024-03-02"
3,"Charlie",300,"2024-03-03"

-- JSONEachRow 格式（每行一个 JSON）
INSERT INTO orders FORMAT JSONEachRow
{"id": 1, "name": "Alice", "amount": 100}
{"id": 2, "name": "Bob", "amount": 200}

-- 通过 clickhouse-client 从文件加载
-- clickhouse-client --query "INSERT INTO orders FORMAT CSV" < orders.csv
-- clickhouse-client --query "INSERT INTO orders FORMAT Parquet" < orders.parquet

-- 通过 HTTP 接口加载
-- curl 'http://localhost:8123/?query=INSERT+INTO+orders+FORMAT+CSV' --data-binary @orders.csv

-- 从 S3 直接加载
INSERT INTO orders
SELECT * FROM s3('https://bucket.s3.amazonaws.com/orders/*.parquet', 'Parquet');

-- 从 URL 加载
INSERT INTO orders
SELECT * FROM url('http://example.com/data.csv', CSV, 'id UInt64, name String');

-- ClickHouse 批量导入极快的原因:
-- 1. 列式存储: 按列压缩存储，压缩率高
-- 2. 合并树引擎: 写入时只追加，后台异步合并
-- 3. 无事务开销: 不保证行级事务
-- 4. 支持的格式丰富: CSV, TSV, JSON, Parquet, ORC, Avro, Arrow 等 70+ 种
```

### Redshift COPY

```sql
-- Redshift 强烈推荐从 S3 加载（性能最佳）
COPY orders
FROM 's3://my-bucket/data/orders/'
IAM_ROLE 'arn:aws:iam::123456789:role/RedshiftCopyRole'
FORMAT AS PARQUET;

-- CSV 加载
COPY orders
FROM 's3://my-bucket/data/orders.csv'
IAM_ROLE 'arn:aws:iam::123456789:role/RedshiftCopyRole'
CSV
IGNOREHEADER 1
DELIMITER ','
REGION 'us-east-1'
GZIP;                                   -- 压缩文件

-- Manifest 文件（精确指定要加载的文件列表）
COPY orders
FROM 's3://my-bucket/manifests/orders_manifest.json'
IAM_ROLE '...'
MANIFEST;

-- 性能最佳实践:
-- 1. 文件数量 = 节点数的倍数（并行加载）
-- 2. 每个文件 100MB-1GB（压缩后）
-- 3. 使用列式格式（Parquet/ORC）优于 CSV
-- 4. 按 SORTKEY 排序的数据加载更快
-- 5. 使用 COMPUPDATE OFF 跳过压缩分析（已知压缩编码时）

-- 查看加载错误
SELECT * FROM stl_load_errors ORDER BY starttime DESC LIMIT 10;
```

## 性能对比

| 方式 | 速度 | 事务安全 | 索引影响 | WAL 开销 | 适用场景 |
|------|------|---------|---------|---------|---------|
| 逐行 INSERT | 最慢 | 每行一个事务 | 实时更新 | 每行写入 | 小批量 |
| 批量 INSERT | 中等 | 一个事务 | 实时更新 | 批量写入 | 千~万行 |
| COPY / LOAD DATA | 快 | 一个事务 | 可禁用 | 可旁路 | 万~亿行 |
| 直接路径加载 | 最快 | 特殊事务 | 必须重建 | 完全旁路 | 初始加载 |

## 对引擎开发者的实现建议

1. 批量导入接口设计

```
BulkLoader {
    // 阶段 1: 准备
    fn begin_load(table, options):
        if options.bypass_wal:
            disable_wal_for_session()
        if options.disable_indexes:
            disable_indexes(table)
        if options.disable_constraints:
            disable_constraints(table)

    // 阶段 2: 数据写入（流式）
    fn write_batch(rows: Vec<Row>):
        // 直接写入存储层，跳过 SQL 解析
        // 批量写入缓冲区，积累到一定大小后刷盘
        buffer.extend(rows)
        if buffer.size() > BATCH_SIZE:
            flush_to_storage(buffer)

    // 阶段 3: 完成
    fn finish_load():
        flush_remaining()
        if options.disable_indexes:
            rebuild_indexes(table)      // 批量重建比逐行维护快得多
        if options.disable_constraints:
            validate_constraints(table)  // 一次性验证
        if options.bypass_wal:
            force_checkpoint()           // 确保数据持久化
}
```

2. 旁路 WAL 的权衡

```
正常写入路径:
  用户数据 → WAL 写入 → 数据页写入 → WAL 可用于恢复

旁路 WAL 路径:
  用户数据 → 直接写入数据页 → 无法从 WAL 恢复

旁路 WAL 的条件:
- 数据可以从外部重新加载（如 S3 上的文件）
- 加载完成后做 checkpoint
- 明确告知用户崩溃时的风险

PostgreSQL: UNLOGGED TABLE
Oracle: Direct Path Load (APPEND hint)
MySQL: 无法旁路 InnoDB redo log
```

3. 错误处理策略

```
三种策略:
1. ABORT: 任何错误立即终止（最安全）
2. SKIP: 跳过错误行，继续加载（记录到错误表）
3. REPLACE: 遇到冲突时替换已有行

建议: 默认 ABORT，通过选项切换为 SKIP
错误行应写入 reject 表/文件，包含行号、原始数据、错误原因
```

4. 并行加载设计

```
-- 分布式引擎的并行加载:
1. 协调器将文件列表分发给各计算节点
2. 每个节点独立读取分配的文件
3. 按分区/分桶键路由数据到目标存储节点
4. 各存储节点并行写入

-- 关键: 文件粒度的分配策略
-- 均匀分配: 每个节点分配相同数量的文件
-- 大小均衡: 按文件大小均衡分配
-- 数据亲和: 按分区键将文件分配给对应的存储节点
```

## 参考资料

- PostgreSQL: [COPY](https://www.postgresql.org/docs/current/sql-copy.html)
- MySQL: [LOAD DATA](https://dev.mysql.com/doc/refman/8.0/en/load-data.html)
- SQL Server: [BULK INSERT](https://learn.microsoft.com/en-us/sql/t-sql/statements/bulk-insert-transact-sql)
- Oracle: [SQL*Loader](https://docs.oracle.com/en/database/oracle/oracle-database/19/sutil/oracle-sql-loader.html)
- Snowflake: [COPY INTO](https://docs.snowflake.com/en/sql-reference/sql/copy-into-table)
- ClickHouse: [INSERT](https://clickhouse.com/docs/en/sql-reference/statements/insert-into)
- Redshift: [COPY](https://docs.aws.amazon.com/redshift/latest/dg/r_COPY.html)
