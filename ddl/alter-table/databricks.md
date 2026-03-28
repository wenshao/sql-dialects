# Databricks SQL: ALTER TABLE

> 参考资料:
> - [Databricks SQL - ALTER TABLE](https://docs.databricks.com/en/sql/language-manual/sql-ref-syntax-ddl-alter-table.html)
> - [Delta Lake - Schema Evolution](https://docs.delta.io/latest/delta-schema.html)


## 1. 基本语法

添加列
```sql
ALTER TABLE users ADD COLUMN phone STRING;
ALTER TABLE users ADD COLUMN IF NOT EXISTS phone STRING AFTER email;
ALTER TABLE users ADD COLUMNS (phone STRING COMMENT 'Phone number', city STRING DEFAULT 'unknown');
```


修改列（类型放宽、注释、默认值）
```sql
ALTER TABLE users ALTER COLUMN age TYPE BIGINT;
ALTER TABLE users ALTER COLUMN status SET DEFAULT 'active';
ALTER TABLE users ALTER COLUMN status DROP DEFAULT;
ALTER TABLE users ALTER COLUMN email COMMENT 'Primary email address';
ALTER TABLE users ALTER COLUMN email SET NOT NULL;
ALTER TABLE users ALTER COLUMN email DROP NOT NULL;
```


删除列（需要 Column Mapping 模式）
```sql
ALTER TABLE users DROP COLUMN bio;
ALTER TABLE users DROP COLUMNS (phone, city);
```


重命名列（需要 Column Mapping 模式）
```sql
ALTER TABLE users RENAME COLUMN username TO user_name;
```


重命名表
```sql
ALTER TABLE users RENAME TO app_users;
```


## 2. 语法设计分析（对 SQL 引擎开发者）


### 2.1 Delta Lake Schema Evolution: 只修改元数据

Databricks 的 ALTER TABLE 几乎所有操作都是"元数据操作":
修改 Delta Log 中的 Schema 记录（不重写 Parquet 数据文件）

工作原理:
ADD COLUMN → 旧文件读取该列时返回 NULL（无需回填）
DROP COLUMN → 旧文件仍保留数据（查询时跳过，REORG 物理删除）
RENAME COLUMN → 通过列 ID 映射（需 Column Mapping 模式）
ALTER TYPE → 只允许放宽（TINYINT→INT→BIGINT, FLOAT→DOUBLE）

**设计 trade-off:**
- **优点**:  零停机、零数据移动，TB 级表也是毫秒级完成
- **缺点**:  DROP COLUMN 不释放存储（需 VACUUM + REORG 重写文件）；
频繁 ALTER 导致 Schema 版本积累，读取时可能需要跨版本合并

**对比:**

MySQL:      ADD COLUMN 可能全表重写（COPY 算法），8.0+ INSTANT 部分即时
PostgreSQL: ADD COLUMN + DEFAULT 在 11+ 即时
Iceberg:    类似 Delta（列有唯一 ID，Schema Evolution 免重写）
Hive:       依赖列位置，RENAME 可能导致数据错位（危险！）

### 2.2 Column Mapping 模式（启用 RENAME/DROP 的前提）

```sql
ALTER TABLE users SET TBLPROPERTIES (
    'delta.columnMapping.mode' = 'name',
    'delta.minReaderVersion' = '2',
    'delta.minWriterVersion' = '5'
);
```

Column Mapping 模式:
'none' (默认): 列按名称匹配 Parquet 列（不支持 RENAME/DROP）
'name': 列通过内部 ID 映射（推荐，支持 RENAME/DROP）
'id': 通过物理 ID 映射（更严格）

为什么默认不启用?
向后兼容: 旧版 Delta Reader 不理解 Column Mapping，启用后需要更高的协议版本

**对比: Iceberg 从 v1 就用列 ID 映射（无此切换问题）**


### 2.3 Liquid Clustering 修改（Databricks 独有能力）

```sql
ALTER TABLE events CLUSTER BY (event_date, user_id);   -- 修改 Clustering Key
ALTER TABLE events CLUSTER BY NONE;                    -- 取消 Clustering
```

传统分区一旦创建不可修改（只能重建表），Liquid Clustering 支持运行时调整。
当查询模式变化时（从按日期查询变为按用户查询），一行 ALTER 即可。

## 3. 约束管理

```sql
ALTER TABLE users ADD CONSTRAINT pk_users PRIMARY KEY (id);            -- 信息性
ALTER TABLE orders ADD CONSTRAINT fk_user FOREIGN KEY (user_id) REFERENCES users(id);  -- 信息性
ALTER TABLE users ADD CONSTRAINT chk_age CHECK (age >= 0 AND age <= 200);  -- 强制执行!
ALTER TABLE users DROP CONSTRAINT pk_users;
```


混合策略: PK/FK/UNIQUE 信息性（优化器提示），CHECK/NOT NULL 强制执行
设计原因: 分布式唯一性检查太昂贵，但值域检查很便宜

## 4. 表属性与维护

```sql
ALTER TABLE users SET TBLPROPERTIES (
    'delta.autoOptimize.optimizeWrite' = 'true',
    'delta.autoOptimize.autoCompact' = 'true',
    'delta.logRetentionDuration' = 'interval 90 days'
);
ALTER TABLE users UNSET TBLPROPERTIES ('delta.autoOptimize.autoCompact');
```


启用变更数据捕获（CDC / Change Data Feed）
```sql
ALTER TABLE users SET TBLPROPERTIES ('delta.enableChangeDataFeed' = 'true');
```


表注释
```sql
COMMENT ON TABLE users IS 'Main user table';
ALTER TABLE users ALTER COLUMN email COMMENT 'Primary contact email';
```


表所有者和标签（Unity Catalog）
```sql
ALTER TABLE users SET OWNER TO `data-team@company.com`;
ALTER TABLE users SET TAGS ('env' = 'prod', 'team' = 'backend');
ALTER TABLE users ALTER COLUMN email SET TAGS ('pii' = 'true');
```


## 5. REORG TABLE: 物理重写数据文件

DROP COLUMN 后数据仍在 Parquet 文件中，需要 REORG 物理删除:
```sql
REORG TABLE users APPLY (PURGE);
```


**对比空间回收:**

PostgreSQL: VACUUM FULL（重写表，锁全表）
MySQL:      ALTER TABLE ... FORCE / OPTIMIZE TABLE（重建表）
DuckDB:     无需手动回收（内部自动管理）
Trino:      Iceberg rewriteDataFiles（通过 Iceberg API）

## 6. 横向对比: Schema Evolution 能力

操作              Databricks   MySQL        PostgreSQL  Trino/Iceberg  Flink
ADD COLUMN        即时(元数据)  INSTANT(8.0+) 即时(11+)  即时(元数据)    部分
DROP COLUMN       即时(需CM)    INSTANT      即时       即时(元数据)    有限
RENAME COLUMN     即时(需CM)    即时         即时       即时(元数据)    有限
ALTER TYPE(放宽)  即时(元数据)  可能重写     需USING    即时(元数据)    有限
ALTER TYPE(缩小)  不支持        可能截断     需USING    不支持          不支持
CLUSTER BY修改    支持(独有)    N/A          N/A        N/A            N/A
(CM = Column Mapping 模式)

## 7. 对引擎开发者的启示

Databricks 的 ALTER TABLE 体现了"Log-Structured"思想:
所有变更都是追加操作（在 Delta Log 中记录新 Schema 版本），
不修改已有的 Parquet 数据文件。

**对比传统"In-Place Update":**

传统: ALTER TABLE → 直接修改磁盘上的数据页
Delta: ALTER TABLE → 追加一条 Schema 变更日志

代价是读取放大: 读取时需要根据 Schema 版本历史来解释不同时期的文件。
REORG TABLE APPLY (PURGE) 正是为了减少这种读取放大。

Liquid Clustering 的可修改性是数据湖的重大创新:
传统方案（Hive 分区、Iceberg 分区）一旦选定分区策略就很难修改，
Databricks 通过增量式 Hilbert Curve 重组实现了"随时可改"。
