# Spark SQL: Constraints (约束)

> 参考资料:
> - [1] Spark SQL Reference - DDL
>   https://spark.apache.org/docs/latest/sql-ref-syntax-ddl.html
> - [2] Delta Lake - Constraints
>   https://docs.delta.io/latest/delta-constraints.html
> - [3] Apache Iceberg - Table Management
>   https://iceberg.apache.org/docs/latest/spark-ddl/


## 1. 约束支持总览: Spark 是约束最弱的 SQL 引擎之一


 Spark SQL 的约束支持极其有限，这是有意的设计决策:
   NOT NULL:      Spark 3.0+ 强制执行（唯一真正强制的约束）
   DEFAULT:       Spark 3.4+（列默认值）
   CHECK:         仅 Delta Lake 支持（写入时强制）
   PRIMARY KEY:   仅 Delta Lake 3.0+（信息性，不强制唯一性）
   FOREIGN KEY:   仅 Delta Lake 3.0+（信息性，不强制引用完整性）
   UNIQUE:        不支持

 设计理由:
   在分布式批处理系统中，全局约束检查需要跨分区通信（Shuffle），代价极高。
   例如 UNIQUE 约束: 每次 INSERT 都需要全表去重检查，在 PB 级数据上不可行。
   Spark 选择将数据质量检查交给应用层 / ETL 流程 / 专门的数据质量框架。

 对比各引擎的约束执行态度:
   MySQL/PostgreSQL: 所有约束严格执行（OLTP 引擎，数据一致性优先）
   BigQuery:         PK/FK/UNIQUE 是信息性的（不强制，用于查询优化）
   Snowflake:        PK/FK 不强制执行，NOT NULL 强制
   ClickHouse:       无任何约束支持（纯 OLAP，数据质量在 ETL 层保证）
   Hive:             无约束（数据湖理念: 先存后验）
   Flink SQL:        PK 是信息性的（用于 Changelog 语义，不强制唯一性）
   MaxCompute:       PK 信息性，NOT NULL 强制

## 2. NOT NULL: 唯一强制执行的约束


```sql
CREATE TABLE users (
    id       BIGINT NOT NULL,
    username STRING NOT NULL,
    email    STRING NOT NULL,
    age      INT                          -- 允许 NULL
) USING PARQUET;

```

通过 ALTER TABLE 管理 NOT NULL（Spark 3.1+, 需数据源支持）

```sql
ALTER TABLE users ALTER COLUMN email SET NOT NULL;
ALTER TABLE users ALTER COLUMN email DROP NOT NULL;

```

 NOT NULL 的实现机制:
   Spark 在写入前检查 DataFrame 中的 NULL 值，违反则抛出异常。
   这是行级检查，不需要全局协调，因此可以在分布式环境中高效执行。
   对比 MySQL: NOT NULL 在 InnoDB 写入路径中检查，语义相同但实现位置不同。

## 3. DEFAULT 值（Spark 3.4+）


```sql
CREATE TABLE users_v2 (
    id         BIGINT,
    username   STRING NOT NULL,
    status     INT DEFAULT 1,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) USING PARQUET;

```

 DEFAULT 的实现:
   Spark 在 INSERT 时如果未提供列值，用 DEFAULT 表达式替换。
   这是 Catalyst 优化器在逻辑计划中处理的——不是存储层特性。

 对比:
   MySQL:      DEFAULT 在 InnoDB 存储层处理，支持 ON UPDATE CURRENT_TIMESTAMP
   PostgreSQL: DEFAULT 在执行层处理，支持复杂表达式（如 gen_random_uuid()）
   Spark:      DEFAULT 是逻辑计划的改写（不支持函数调用类 DEFAULT，仅支持字面量和少数内置函数）

## 4. Delta Lake CHECK 约束（写入时强制执行）


CHECK 约束是 Delta Lake 最实用的约束功能

```sql
ALTER TABLE users ADD CONSTRAINT chk_age CHECK (age >= 0 AND age <= 200);
ALTER TABLE users ADD CONSTRAINT chk_dates CHECK (end_date > start_date);
ALTER TABLE users DROP CONSTRAINT chk_age;

```

 CHECK 约束的执行机制:
   Delta Lake 在每次写入（INSERT/UPDATE/MERGE）时对新数据评估 CHECK 表达式。
   违反 CHECK 的行会导致整个写入事务失败（不是跳过违反行）。
   检查在 Driver 端执行，不需要额外的 Shuffle。

 对比:
   MySQL 8.0.16+: CHECK 约束在行级别强制执行（5.7 及之前接受语法但不执行!）
   PostgreSQL:     CHECK 约束从第一版就严格执行
   BigQuery:       无 CHECK 约束
   Snowflake:      不支持 CHECK 约束
   ClickHouse:     无 CHECK 约束

## 5. 信息性 PK/FK（Delta Lake 3.0+, 不强制执行）


 信息性 PK: 不检查唯一性，不创建索引，仅用于优化器提示
 CREATE TABLE users (
     id       BIGINT,
     username STRING,
     CONSTRAINT pk_users PRIMARY KEY (id)
 ) USING DELTA;

 信息性 FK: 不检查引用完整性
 ALTER TABLE orders ADD CONSTRAINT fk_user
     FOREIGN KEY (user_id) REFERENCES users(id);

 信息性约束的价值:
### 1. 查询优化: 优化器知道 PK 列唯一，可以优化 JOIN 和聚合

### 2. BI 工具集成: Tableau/Power BI 可以读取 PK/FK 关系自动建立星型模型

### 3. 数据文档: 作为 Schema 的自描述元数据


 设计争议:
   这与 MySQL 8.0.16 之前的 CHECK 约束陷阱类似——接受语法但不执行。
   不同的是，信息性约束被明确标注为"不强制执行"，用户知情。
   BigQuery、Snowflake、Databricks 都采用了这一设计，说明业界已达成共识:
   分布式系统中约束的优化价值 > 约束的强制执行价值。

## 6. 应用层约束替代方案


唯一性检查: 通过 SQL 查询验证

```sql
SELECT email, COUNT(*) AS cnt
FROM users
GROUP BY email
HAVING COUNT(*) > 1;

```

去重（ROW_NUMBER 模式）

```sql
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY email ORDER BY id) AS rn
    FROM users
) WHERE rn = 1;

```

 DataFrame API 数据质量检查
 df.filter("age >= 0 AND age <= 200").write.saveAsTable("users")

 对引擎开发者的启示:
   约束的设计选择本质上是"正确性 vs 性能"的 trade-off:
   - OLTP 引擎（MySQL/PostgreSQL）: 正确性优先，所有约束严格执行
   - OLAP 引擎（Spark/BigQuery）: 性能优先，约束要么不支持要么仅信息性
   - Lakehouse 引擎（Delta Lake）: 折中——CHECK 强制执行（低成本），PK/FK 信息性

   如果你在设计引擎，建议:
### 1. NOT NULL 必须强制执行（成本低，价值大）

### 2. CHECK 约束可选强制执行（行级检查，不需要全局协调）

### 3. PK/UNIQUE/FK 在分布式环境中至少提供信息性支持（用于优化器和工具集成）

### 4. 不要接受语法但不执行——这是 MySQL CHECK 约束的历史教训


## 7. 查看约束元数据

```sql
DESCRIBE EXTENDED users;
SHOW TBLPROPERTIES users;

```

## 8. 版本演进

Spark 3.0:  NOT NULL 约束强制执行
Spark 3.1:  ALTER COLUMN SET/DROP NOT NULL
Spark 3.4:  DEFAULT 列值
Delta 1.0+: CHECK 约束（强制执行）
Delta 3.0+: 信息性 PK/FK
Iceberg:    不支持 CHECK/PK/FK 约束（通过 Spark 的 NOT NULL 支持非空）

