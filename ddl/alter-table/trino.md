# Trino: ALTER TABLE

> 参考资料:
> - [Trino Documentation - ALTER TABLE](https://trino.io/docs/current/sql/alter-table.html)

**引擎定位**: 分布式查询引擎（前身 Presto），不存储数据。通过 Connector 查询异构数据源（Hive/Iceberg/RDBMS）。

## 基本语法（能力取决于 Connector）

添加列
```sql
ALTER TABLE users ADD COLUMN phone VARCHAR;
ALTER TABLE users ADD COLUMN IF NOT EXISTS phone VARCHAR;
ALTER TABLE hive.mydb.users ADD COLUMN phone VARCHAR;  -- 完整限定名

```

删除列（Iceberg/Delta Connector）
```sql
ALTER TABLE iceberg.mydb.users DROP COLUMN bio;

```

重命名列（Iceberg Connector）
```sql
ALTER TABLE iceberg.mydb.users RENAME COLUMN username TO user_name;

```

修改列类型（Iceberg Connector，仅类型放宽）
```sql
ALTER TABLE iceberg.mydb.users ALTER COLUMN age SET DATA TYPE BIGINT;

```

设置/去除 NOT NULL（Iceberg Connector）
```sql
ALTER TABLE iceberg.mydb.users ALTER COLUMN phone SET NOT NULL;
ALTER TABLE iceberg.mydb.users ALTER COLUMN phone DROP NOT NULL;

```

重命名表
```sql
ALTER TABLE users RENAME TO app_users;

```

设置表注释
```sql
COMMENT ON TABLE users IS 'User information table';
COMMENT ON COLUMN users.email IS 'User email address';

```

设置表属性
```sql
ALTER TABLE hive.mydb.users SET PROPERTIES (format = 'PARQUET');

```

## 语法设计分析（对 SQL 引擎开发者）


### ALTER TABLE 的 Connector 依赖性

Trino 的 ALTER TABLE 能力完全取决于底层 Connector。
这是"查询引擎不管存储"架构的直接后果。

各 Connector 支持矩阵:
  操作              Hive     Iceberg  Delta    MySQL   Memory
  ADD COLUMN        支持     支持     支持     支持    支持
  DROP COLUMN       不支持   支持     支持     支持    支持
  RENAME COLUMN     有限     支持     不支持   支持    支持
  ALTER TYPE        不支持   放宽     不支持   有限    不支持
  SET PROPERTIES    支持     支持     有限     N/A     N/A
  ADD/DROP PART.    支持     N/A      N/A      N/A     N/A

**设计 trade-off:**
  优点: 统一 SQL 语法，用户不需要学习底层存储的 DDL 语法
  缺点: 用户必须了解当前 Connector 支持哪些操作（否则报错）；
        错误信息可能不够明确（"This connector does not support ..."）

**对比:**
  Flink:      类似问题（ALTER 能力取决于 Catalog）
  DuckDB:     自有存储，ALTER 能力完全自主可控
  Databricks: Delta Lake 统一存储，ALTER 能力一致且丰富

### Iceberg Connector: Schema Evolution 最强

```sql
ALTER TABLE iceberg.mydb.orders ADD COLUMN discount DECIMAL(10,2);
ALTER TABLE iceberg.mydb.orders DROP COLUMN notes;
ALTER TABLE iceberg.mydb.orders RENAME COLUMN amount TO total_amount;
ALTER TABLE iceberg.mydb.orders ALTER COLUMN quantity SET DATA TYPE BIGINT;

```

Iceberg Schema Evolution 的设计:
  每列有唯一 ID（不依赖列名或位置），所以:
  RENAME COLUMN: 只修改元数据中的列名（不重写数据）
  DROP COLUMN: 读取时跳过该列（不重写数据）
  ADD COLUMN: 旧文件中该列读为 NULL（不重写数据）
  ALTER TYPE: 只允许放宽（int→long, float→double）

**对比:**
  Hive: 依赖列位置（RENAME 可能导致数据错位，非常危险！）
  Delta Lake: 需要启用 Column Mapping 模式才支持 RENAME/DROP
  Parquet: Schema 嵌入文件，每个文件可以有不同 Schema

### Hive Connector: 分区管理

```sql
ALTER TABLE hive.mydb.logs ADD PARTITION (dt = '2024-01-15');
ALTER TABLE hive.mydb.logs DROP PARTITION (dt = '2023-01-01');

```

为什么 Iceberg 不需要手动管理分区?
Iceberg: Hidden Partitioning，分区由元数据管理，写入自动创建
Hive: 目录分区，每个分区是 HDFS/S3 上的一个目录，
       需要在 MetaStore 中注册才能被查询到（MSCK REPAIR TABLE）

### Iceberg 分区演进（Partition Evolution）

```sql
ALTER TABLE iceberg.mydb.orders SET PROPERTIES (
    partitioning = ARRAY['year(order_date)']   -- 修改分区策略
);
```

Iceberg 独有能力: 修改分区策略不需要重写数据
新写入的数据按新策略分区，旧数据保持原样
查询时 Iceberg 自动处理混合分区的裁剪

**对比:**
  Hive: partitioned_by 不能修改，必须重建表
  Databricks: Liquid Clustering 支持 ALTER TABLE CLUSTER BY（类似能力）
  DuckDB: 无分区概念

## SET PROPERTIES: 修改表属性

Hive Connector
```sql
ALTER TABLE hive.mydb.users SET PROPERTIES (format = 'PARQUET');
```

**注意:** 只影响新写入的数据，已有数据仍保持原格式

Iceberg Connector
```sql
ALTER TABLE iceberg.mydb.orders SET PROPERTIES (
    format_version = 2,                    -- 升级到 Iceberg v2
    write_format = 'PARQUET'
);

```

不同 Connector 支持不同属性:
  Hive: format, bucketed_by, bucket_count, sorted_by
  Iceberg: format_version, write_format, partitioning
  Delta: 有限的属性支持

## 不支持的操作

Trino 不支持:
  ALTER TABLE ADD CONSTRAINT（无约束概念）
  ALTER TABLE ADD INDEX（无索引概念）
  ALTER TABLE ADD TRIGGER（无触发器）
  ALTER TABLE CLUSTER BY（Databricks 独有 Liquid Clustering）
  ALTER TABLE MODIFY WATERMARK（Flink 独有流处理语义）
  ALTER TABLE SET DEFAULT（大多数 Connector 不支持列默认值）

**设计理由:**
Trino 是查询层，约束/索引/触发器都是存储层的职责。
如果底层是 MySQL，应该在 MySQL 中直接执行这些操作。

## 横向对比: ALTER TABLE 执行机制

Trino:      委托给 Connector（只修改元数据，不涉及数据移动）
MySQL:      可能触发全表重建（COPY/INPLACE/INSTANT 三种算法）
PostgreSQL: 大部分即时（11+），ALTER TYPE 需要表重写
DuckDB:     大部分即时（列存优势）
Flink:      修改 Catalog 元数据（不涉及物理数据）
Databricks: 修改 Delta Log 元数据（不重写 Parquet 文件）

## 对引擎开发者的启示

Trino 的 ALTER TABLE 展示了"代理模式"的 DDL:
查询引擎将 DDL 请求翻译并转发给底层存储系统。

关键挑战:
  1. 能力发现: 如何让用户知道当前 Connector 支持哪些操作?
  2. 错误处理: 不支持的操作应返回清晰错误信息
  3. 行为一致性: 相同语句在不同 Connector 上行为可能不同

Trino 的 SPI（ConnectorMetadata 接口）解决了统一接口问题，
但无法解决用户认知负担: 用户必须了解底层 Connector 的能力边界。
Iceberg Connector 的成功说明: 功能越丰富的 Connector 用户体验越好。
