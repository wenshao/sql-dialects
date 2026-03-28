# Snowflake: 迁移速查表

> 参考资料:
> - [1] Snowflake Documentation - Migration Guide
>   https://docs.snowflake.com/en/user-guide/migration


## 1. 数据类型映射

 源类型              → Snowflake 类型          注意事项
 INT/INTEGER         → NUMBER(38,0) / INT      所有整数别名底层相同
 FLOAT/DOUBLE        → FLOAT                   统一双精度
 DECIMAL(p,s)        → NUMBER(p,s)             最大精度 38
 VARCHAR(n)/TEXT      → VARCHAR(n)              不指定默认 16MB
 BOOLEAN             → BOOLEAN
 DATE                → DATE
 DATETIME(MySQL)     → TIMESTAMP_NTZ           无时区
 TIMESTAMP WITH TZ   → TIMESTAMP_TZ            带时区偏移
 TIMESTAMP(PG)       → TIMESTAMP_NTZ
 TIMESTAMPTZ(PG)     → TIMESTAMP_LTZ           本地时区
 BLOB/BYTEA          → BINARY                  最大 8MB
 JSON/JSONB          → VARIANT                 核心差异: 用 : 访问
 ARRAY               → ARRAY (VARIANT)
 SERIAL(PG)/AUTO_INC → AUTOINCREMENT / IDENTITY 值不保证连续

## 2. 迁移核心注意事项


### 2.1 约束不执行

 PK/UNIQUE/FK 是信息性的，不阻止重复/孤儿数据写入
 数据质量必须在 ETL 管道或应用层保证
 用 dbt 测试或 SQL 查询验证唯一性

### 2.2 无索引

 无 CREATE INDEX（也不需要）
 查询优化依赖微分区裁剪 + CLUSTER BY
 对于高基数列点查: 使用 Search Optimization Service (Enterprise+)

### 2.3 标识符默认大写

 CREATE TABLE MyTable → 内部存储为 MYTABLE
 使用双引号保留大小写: CREATE TABLE "MyTable" → 存储为 MyTable
 从 PostgreSQL 迁移时尤其注意（PG 默认小写）

### 2.4 三种 TIMESTAMP

 默认 TIMESTAMP = TIMESTAMP_NTZ（无时区）
 可通过 ALTER SESSION SET TIMESTAMP_TYPE_MAPPING 修改
 从 PG 迁移: TIMESTAMPTZ → TIMESTAMP_LTZ

## 3. 函数映射

 源函数                        → Snowflake
 ISNULL/IFNULL/NVL             → NVL(a,b) / IFNULL(a,b) / COALESCE
 GETDATE()/NOW()               → CURRENT_TIMESTAMP()
 DATEADD                       → DATEADD(part, n, d)
 DATEDIFF                      → DATEDIFF(part, a, b)
 TO_CHAR/FORMAT                → TO_CHAR(d, 'YYYY-MM-DD')
 STRING_AGG(PG)/GROUP_CONCAT   → LISTAGG(col, ',')
 generate_series(PG)           → TABLE(GENERATOR(ROWCOUNT => N))
 unnest(PG)/UNNEST(BQ)         → LATERAL FLATTEN(input => ...)
 jsonb_extract_path(PG)        → data:path::TYPE（冒号语法）
 JSON_EXTRACT(MySQL)           → data:path::TYPE
 FILTER(PG 窗口)               → IFF + COUNT/SUM（无 FILTER 子句）

## 4. 语法差异速查


自增

```sql
CREATE TABLE t (id NUMBER AUTOINCREMENT START 1 INCREMENT 1);
CREATE SEQUENCE my_seq START = 1 INCREMENT = 1;
SELECT my_seq.NEXTVAL;

```

日期函数

```sql
SELECT CURRENT_TIMESTAMP();
SELECT DATEADD('day', 1, CURRENT_DATE());
SELECT DATEDIFF('day', '2024-01-01', '2024-12-31');
SELECT TO_CHAR(CURRENT_TIMESTAMP(), 'YYYY-MM-DD HH24:MI:SS');

```

字符串函数

```sql
SELECT LENGTH('hello');
SELECT SUBSTR('hello', 2, 3);
SELECT SPLIT_PART('a,b,c', ',', 2);
SELECT LISTAGG(name, ', ') WITHIN GROUP (ORDER BY name) FROM users;
SELECT 'hello' || ' world';

```

类型转换

```sql
SELECT CAST('123' AS INTEGER);
SELECT '123'::INTEGER;                    -- PG 风格
SELECT TRY_CAST('abc' AS INTEGER);       -- 安全转换（返回 NULL）

```

VARIANT / JSON

```sql
SELECT PARSE_JSON('{"name":"alice"}');
SELECT data:name::STRING FROM events;    -- 冒号语法访问 VARIANT

```

## 5. 从特定数据库迁移


 从 MySQL 迁移:
   AUTO_INCREMENT → AUTOINCREMENT
   JSON → VARIANT
   ON DUPLICATE KEY UPDATE → MERGE
   LIMIT m,n → LIMIT n OFFSET m
   ENGINE=InnoDB → 无（自动管理）
   CREATE INDEX → 无（微分区裁剪）

 从 PostgreSQL 迁移:
   SERIAL/IDENTITY → AUTOINCREMENT/IDENTITY
   JSONB → VARIANT
   ON CONFLICT → MERGE
   generate_series → GENERATOR
   array_agg + unnest → ARRAY_AGG + FLATTEN
   RLS → Row Access Policy
   EXPLAIN ANALYZE → Query Profile (Web UI)

 从 Oracle 迁移:
   NUMBER → NUMBER（最兼容）
   CONNECT BY → 继续使用（Snowflake 兼容）
   PL/SQL 包 → 不支持（需要拆分为独立过程）
   VPD → Row Access Policy + Masking Policy
   Materialized View → 继续使用（Snowflake 自动维护）

## 6. 数据加载方式


批量加载（推荐）:

```sql
COPY INTO users FROM @my_stage/users.csv
FILE_FORMAT = (TYPE = 'CSV' SKIP_HEADER = 1);

```

从外部存储:

```sql
COPY INTO users FROM 's3://mybucket/data/'
CREDENTIALS = (AWS_KEY_ID = '...' AWS_SECRET_KEY = '...')
FILE_FORMAT = (TYPE = 'PARQUET');

```

流式加载:
CREATE PIPE auto_load AUTO_INGEST = TRUE
AS COPY INTO users FROM @my_stage FILE_FORMAT = (TYPE = 'CSV');

