# Hive: ALTER TABLE

> 参考资料:
> - [1] Apache Hive Language Manual - DDL: Alter Table
>   https://cwiki.apache.org/confluence/display/Hive/LanguageManual+DDL#LanguageManualDDL-AlterTable
> - [2] Apache Hive - Partition Management
>   https://cwiki.apache.org/confluence/display/Hive/LanguageManual+DDL#LanguageManualDDL-AddPartitions


## 1. 列操作: ADD COLUMNS (追加式设计)

Hive 只支持在列末尾追加新列，不支持任意位置插入列

```sql
ALTER TABLE users ADD COLUMNS (
    phone  STRING COMMENT '手机号',
    status INT    COMMENT '状态码'
);

```

REPLACE COLUMNS: 替换所有列定义（危险操作）
这不会修改已有数据文件，只改变 Metastore 中的 schema

```sql
ALTER TABLE users_text REPLACE COLUMNS (
    id    BIGINT,
    name  STRING,
    email STRING
);

```

 设计分析: ADD vs REPLACE 的 Schema-on-Read 影响
 Hive 的 ALTER TABLE ADD/REPLACE COLUMNS 只修改 Metastore 元数据，不重写数据文件。
 这意味着:
1. ADD COLUMNS 后，旧文件中不存在的列返回 NULL（Schema Evolution）

2. REPLACE COLUMNS 后，若新 schema 与数据文件不匹配，查询可能返回错误数据

3. ORC/Parquet 支持按列名匹配（安全），TextFile 按位置匹配（不安全）


 对比其他引擎:
   MySQL:      ALTER TABLE ADD COLUMN 需要重建表（8.0 INSTANT 优化仅限追加末尾）
   PostgreSQL: ADD COLUMN + DEFAULT 在 11+ 是即时的（只改 catalog）
   BigQuery:   ADD COLUMN 只支持追加末尾（与 Hive 相同的限制）
   Spark SQL:  继承 Hive 的 ADD COLUMNS 行为
   Iceberg:    支持列重命名、重排、删除（比 Hive 的能力强得多）

 对引擎开发者的启示:
   "只改元数据不重写数据"的设计在大数据量下是必要的（TB 级表不可能做 ALTER 重写），
   但要求存储格式支持 Schema Evolution。列式格式（ORC/Parquet）天然支持按列名匹配，
   行式格式（TextFile/CSV）依赖列位置匹配，Schema 变更会破坏数据对齐。

## 2. 修改列类型与名称

CHANGE COLUMN: 重命名 + 改类型 + 改注释

```sql
ALTER TABLE users CHANGE COLUMN phone phone_number STRING COMMENT '电话号码';

```

改类型（只允许兼容的类型转换）

```sql
ALTER TABLE users CHANGE COLUMN age age BIGINT;

```

列位置调整

```sql
ALTER TABLE users CHANGE COLUMN phone phone STRING AFTER email;
ALTER TABLE users CHANGE COLUMN phone phone STRING FIRST;

```

 类型转换限制:
   INT -> BIGINT:     允许（向上兼容）
   BIGINT -> INT:     不允许（可能丢失数据）
   STRING -> INT:     不允许（不兼容类型）
   ORC 格式:          支持更宽松的类型演化（通过 orc.force.positional.evolution 控制）

## 3. 分区管理 (Hive ALTER TABLE 最核心的操作)

添加分区

```sql
ALTER TABLE orders ADD PARTITION (dt='2024-01-15', region='us')
    LOCATION '/warehouse/orders/dt=2024-01-15/region=us';

ALTER TABLE orders ADD IF NOT EXISTS
    PARTITION (dt='2024-02-01') LOCATION '/data/orders/2024-02-01'
    PARTITION (dt='2024-02-02') LOCATION '/data/orders/2024-02-02';

```

删除分区

```sql
ALTER TABLE orders DROP PARTITION (dt='2023-01-01');
ALTER TABLE orders DROP IF EXISTS PARTITION (dt < '2023-01-01');  -- 范围删除

```

重命名分区

```sql
ALTER TABLE orders PARTITION (dt='20240115')
    RENAME TO PARTITION (dt='2024-01-15');

```

修改分区位置

```sql
ALTER TABLE orders PARTITION (dt='2024-01-01')
    SET LOCATION '/new_warehouse/orders/2024-01-01';

```

TOUCH: 更新元数据时间戳（不修改数据）

```sql
ALTER TABLE orders TOUCH;
ALTER TABLE orders TOUCH PARTITION (dt='20240115');

```

CONCATENATE: 合并小文件（仅 RCFile/ORC）

```sql
ALTER TABLE orders PARTITION (dt='20240115') CONCATENATE;

```

MSCK REPAIR TABLE: 同步文件系统与 Metastore
当直接向 HDFS 写入数据（不通过 Hive）时，Metastore 不知道新分区的存在

```sql
MSCK REPAIR TABLE orders;

```

 设计分析: 为什么需要 MSCK REPAIR TABLE?
 Hive Metastore 和 HDFS 是两个独立系统，分区信息在 Metastore 中维护。
 当 Spark/MR 作业直接写入 HDFS 而不更新 Metastore 时，就出现元数据不一致。
 MSCK REPAIR TABLE 是"事后同步"机制。

 局限性:
1. 分区数量极大时（数万级），MSCK REPAIR TABLE 非常慢

2. 只能发现新分区，不能检测已删除的分区

3. 分区目录格式必须严格遵循 key=value 模式


 对比:
   Spark SQL:    ALTER TABLE ... RECOVER PARTITIONS（等价操作）
   Iceberg:      无此问题（manifest 文件是事务性的，不会不一致）
   Delta Lake:   无此问题（事务日志记录所有文件变更）

## 4. 表级属性修改

重命名表

```sql
ALTER TABLE users RENAME TO users_v2;

```

修改表属性

```sql
ALTER TABLE users SET TBLPROPERTIES ('comment' = '用户主表');
ALTER TABLE users SET TBLPROPERTIES ('orc.compress' = 'ZLIB');

```

修改 SerDe 属性

```sql
ALTER TABLE users SET SERDE 'org.apache.hadoop.hive.serde2.lazy.LazySimpleSerDe'
    WITH SERDEPROPERTIES ('field.delim' = '|');

```

修改文件格式（只影响后续写入，不重写已有文件）

```sql
ALTER TABLE users SET FILEFORMAT ORC;

```

修改表位置（移动元数据指向，不移动数据）

```sql
ALTER TABLE users SET LOCATION '/new/location/users';

```

转换管理表为外部表（或反向）

```sql
ALTER TABLE users SET TBLPROPERTIES ('EXTERNAL' = 'TRUE');   -- 转为外部表
ALTER TABLE users SET TBLPROPERTIES ('EXTERNAL' = 'FALSE');  -- 转为管理表

```

## 5. 压缩操作 (ACID 表)

```sql
ALTER TABLE users COMPACT 'minor';          -- 合并 delta 文件
ALTER TABLE users COMPACT 'major';          -- 重写所有文件（含 base + delta）
ALTER TABLE users PARTITION (dt='2024-01-01') COMPACT 'major';

```

## 6. 已知限制

1. 不支持 DROP COLUMN: Hive 无法删除列（REPLACE COLUMNS 是替代方案但很危险）

    对比: MySQL 8.0+ ALTER TABLE DROP COLUMN 可 INSTANT; BigQuery 支持 DROP COLUMN
2. 不支持任意位置插入列: ADD COLUMNS 只能追加末尾

3. 不支持修改分区列: 分区列是目录结构的一部分，无法修改类型或名称

4. ALTER TABLE SET FILEFORMAT 不重写数据: 只影响新写入的数据，旧数据仍是原格式

    这可能导致同一表中混合多种格式（TextFile + ORC），查询时需要兼容处理
5. REPLACE COLUMNS 在 ORC/Parquet 中安全（按列名匹配），在 TextFile 中危险（按位置匹配）

6. Metastore 是瓶颈: 大量分区的 ADD/DROP 操作对 Metastore 后端数据库压力大

7. ALTER TABLE 不是事务性的: DDL 操作不受 ACID 事务保护


## 7. 跨引擎对比: ALTER TABLE 能力矩阵

操作           Hive       MySQL(8.0)  PostgreSQL  BigQuery   Spark SQL
ADD COLUMN     末尾追加   任意位置    末尾追加    末尾追加   末尾追加
DROP COLUMN    不支持     支持        支持        支持       不支持
RENAME COLUMN  支持       支持        支持(9.6+)  不支持     不支持
CHANGE TYPE    兼容转换   部分支持    部分支持    不支持     不支持
RENAME TABLE   支持       支持        支持        不支持     支持
分区管理       核心功能   有限        声明式      自动       继承Hive

对引擎开发者的启示:
大数据引擎的 ALTER TABLE 设计需要在"功能完整性"和"执行代价"之间权衡。
Hive 选择了最低代价（只改元数据），但牺牲了功能（无法删列）。
Iceberg/Delta 通过 table format 层实现了更丰富的 Schema Evolution，
证明了可以在不重写数据文件的前提下支持列删除、重命名、重排等操作。
