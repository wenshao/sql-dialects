# BigQuery: ALTER TABLE

> 参考资料:
> - [1] BigQuery SQL Reference - ALTER TABLE SET OPTIONS
>   https://cloud.google.com/bigquery/docs/reference/standard-sql/data-definition-language#alter_table
> - [2] BigQuery Documentation - Managing Tables
>   https://cloud.google.com/bigquery/docs/managing-tables
> - [3] BigQuery Architecture - Dremel/Capacitor format
>   https://cloud.google.com/bigquery/docs/storage_overview


## 1. 基本语法


添加列

```sql
ALTER TABLE myproject.mydataset.users ADD COLUMN phone STRING;
ALTER TABLE myproject.mydataset.users ADD COLUMN IF NOT EXISTS phone STRING;

```

添加嵌套列（STRUCT 内部添加字段）

```sql
ALTER TABLE myproject.mydataset.users
ADD COLUMN address STRUCT<street STRING, city STRING, zip STRING>;

```

向已有 STRUCT 添加嵌套字段

```sql
ALTER TABLE myproject.mydataset.users
ADD COLUMN address.country STRING;

```

删除列（需要列未被视图/策略引用）

```sql
ALTER TABLE myproject.mydataset.users DROP COLUMN phone;
ALTER TABLE myproject.mydataset.users DROP COLUMN IF EXISTS phone;

```

重命名列

```sql
ALTER TABLE myproject.mydataset.users RENAME COLUMN phone TO mobile;

```

修改列类型（仅限拓宽: INT64->NUMERIC, NUMERIC->FLOAT64 等）

```sql
ALTER TABLE myproject.mydataset.users
ALTER COLUMN age SET DATA TYPE NUMERIC;

```

修改列默认值

```sql
ALTER TABLE myproject.mydataset.users
ALTER COLUMN status SET DEFAULT 'active';

```

设置表选项

```sql
ALTER TABLE myproject.mydataset.users
SET OPTIONS (
    description = 'User master table',
    expiration_timestamp = TIMESTAMP '2026-12-31',
    labels = [('env', 'prod'), ('team', 'data')]
);

```

## 2. 无服务器架构对 ALTER TABLE 的影响（对引擎开发者）


### 2.1 BigQuery 的存储层: Capacitor 列式格式

 BigQuery 使用 Google 自研的 Capacitor 列式格式存储数据。
 数据存储在 Colossus（Google 分布式文件系统）上，与计算完全分离。

 这决定了 ALTER TABLE 的行为:
   ADD COLUMN:    仅修改 schema 元数据，不触碰存储文件
                  → 毫秒级完成，无论表多大
                  新列在已有行中读取为 NULL

   DROP COLUMN:   标记列为逻辑删除，物理文件在后台压缩时清理
                  → 立即返回，存储空间延迟回收

   类型变更:      仅支持"拓宽"（widening），不支持缩窄
                  INT64 -> FLOAT64 可以（无损）
                  STRING -> INT64 不行（可能丢失数据）
                  → 因为 BigQuery 不会重写存储文件

 对比:
   MySQL:      ALTER TABLE 可能需要 table rebuild（COPY / INPLACE / INSTANT）
   PostgreSQL: ALTER COLUMN TYPE 需要重写全表（大部分情况）
   ClickHouse: MODIFY COLUMN 类型是异步 mutation（重写列文件）

 设计 trade-off:
   BigQuery 选择了最保守的策略: 只允许不需要重写数据的变更。
   这保证了 ALTER TABLE 始终是 O(1) 操作，但牺牲了灵活性。
   需要缩窄类型或复杂变更时，必须用 CTAS（CREATE TABLE AS SELECT）重建。

### 2.2 三层命名空间: project.dataset.table

 BigQuery 使用 project.dataset.table 三层命名空间，
 ALTER TABLE 需要完整路径（或设置默认 project/dataset）。
 这反映了多租户云服务的设计: project=计费单位, dataset=访问控制边界。

 对比:
   MySQL:      database.table（两层）
   PostgreSQL: database.schema.table（三层，但通常省略 database）
   Snowflake:  database.schema.table（三层，与 BigQuery 类似但命名不同）

## 3. 表级选项（BigQuery 独有的 DDL 概念）


BigQuery 将表属性通过 OPTIONS 统一管理，这是标准 SQL 之外的扩展

设置分区过期（分析数据生命周期管理）

```sql
ALTER TABLE myproject.mydataset.logs
SET OPTIONS (partition_expiration_days = 90);
```

超过 90 天的分区自动删除
对比 ClickHouse: TTL created_at + INTERVAL 90 DAY DELETE

设置表过期

```sql
ALTER TABLE myproject.mydataset.tmp_results
SET OPTIONS (expiration_timestamp = TIMESTAMP '2026-06-30');

```

require_partition_filter: 强制查询必须带分区过滤条件

```sql
ALTER TABLE myproject.mydataset.logs
SET OPTIONS (require_partition_filter = true);
```

防止全表扫描，保护成本。这是 BigQuery 特有的成本控制机制。
设置后，SELECT * FROM logs 会报错（必须 WHERE _PARTITIONDATE = ...）

max_staleness: 允许读取过期的元数据缓存（加速频繁查询）

```sql
ALTER TABLE myproject.mydataset.users
SET OPTIONS (max_staleness = INTERVAL 15 MINUTE);

```

 设计分析:
   BigQuery 用 OPTIONS 替代了传统数据库的多种 ALTER TABLE 子句:
   传统数据库用多种语法（SET TABLESPACE, SET STATISTICS, SET STORAGE）
   BigQuery 统一用 SET OPTIONS (key=value)，更简洁但非标准 SQL。

## 4. Schema 演进与嵌套类型


### 4.1 STRUCT 嵌套字段的增删

BigQuery 的 STRUCT 类型支持就地添加子字段:

```sql
ALTER TABLE myproject.mydataset.events
ADD COLUMN payload.new_field STRING;

```

 但不能修改已有子字段的类型或删除单个子字段
 需要删除整个 STRUCT 列然后重建（或用 CTAS）

### 4.2 REPEATED（ARRAY）列的限制

 不能 ALTER 已有列为 REPEATED（ARRAY），只能在建表时定义或 ADD COLUMN
 不能将 REPEATED 列改为非 REPEATED
 → 因为 Capacitor 格式中 REPEATED 和非 REPEATED 的物理编码不同

### 4.3 Schema 演进的推荐模式

BigQuery 推荐通过 CTAS 实现复杂 schema 变更:

```sql
CREATE OR REPLACE TABLE myproject.mydataset.users_v2 AS
SELECT
    id,
    username,
    CAST(age AS NUMERIC) AS age,     -- 类型变更
    STRUCT(email, phone) AS contact  -- 重构为嵌套类型
FROM myproject.mydataset.users;

```

## 5. 访问控制相关的 ALTER


列级安全（Column-Level Security）

```sql
ALTER TABLE myproject.mydataset.users
ALTER COLUMN ssn SET OPTIONS (
    description = 'Social Security Number - restricted'
);

```

加密（CMEK 客户管理加密密钥）

```sql
ALTER TABLE myproject.mydataset.users
SET OPTIONS (
    kms_key_name = 'projects/p/locations/us/keyRings/r/cryptoKeys/k'
);

```

信息性约束（帮助优化器，不强制执行）

```sql
ALTER TABLE myproject.mydataset.users
ADD PRIMARY KEY (id) NOT ENFORCED;

ALTER TABLE myproject.mydataset.orders ADD CONSTRAINT fk_user
    FOREIGN KEY (user_id) REFERENCES users (id) NOT ENFORCED;

```

重命名表

```sql
ALTER TABLE myproject.mydataset.users RENAME TO members;

```

## 6. 对比总结与引擎开发者启示

BigQuery ALTER TABLE 的核心设计原则:
(1) 只允许不重写数据的操作 → O(1) 元数据变更
(2) OPTIONS 统一管理表属性 → 简化语法但牺牲标准兼容
(3) STRUCT 字段可增量添加 → 支持嵌套 schema 演进
(4) 分区过期自动管理 → 内置数据生命周期
(5) require_partition_filter → DDL 层面的成本控制

传统数据库的 ALTER TABLE 优化索引和锁（Online DDL），
云数仓的 ALTER TABLE 优化元数据和成本控制。
引擎开发者应根据目标场景选择:
OLTP: 优先考虑 Online DDL（不锁表的 schema 变更）
OLAP: 优先考虑列存友好的 DDL（列级操作 + TTL + 成本控制）
云原生: 优先考虑元数据操作（不重写数据，CTAS 替代复杂变更）

