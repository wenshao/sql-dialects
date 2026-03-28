# MaxCompute (ODPS): 约束

> 参考资料:
> - [1] MaxCompute SQL - CREATE TABLE
>   https://help.aliyun.com/zh/maxcompute/user-guide/create-table-1
> - [2] MaxCompute Transactional Tables
>   https://help.aliyun.com/zh/maxcompute/user-guide/transactional-tables


## 1. NOT NULL —— 唯一的通用列级约束


```sql
CREATE TABLE users (
    id       BIGINT NOT NULL,
    username STRING NOT NULL,
    email    STRING,                        -- 默认允许 NULL
    status   BIGINT DEFAULT 1,
    name     STRING DEFAULT 'unknown'
);

```

 设计决策: NOT NULL 在批处理引擎中有实际意义
   AliORC 列式存储对 NULL 有专门编码（位图标记）
   NOT NULL 列可以跳过 NULL 检查，略微提升读取性能
   更重要的是: ETL 管道中的数据质量保证

 DEFAULT 值: 支持常量默认值
   但不支持表达式默认值（如 CURRENT_TIMESTAMP）
   不支持 ON UPDATE（没有行级 UPDATE 的触发时机）
   对比 MySQL: 支持 DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP

## 2. PRIMARY KEY —— 仅事务表支持，声明式不强制


事务表: 可以定义主键

```sql
CREATE TABLE users_transactional (
    id       BIGINT NOT NULL,
    username STRING NOT NULL,
    email    STRING,
    PRIMARY KEY (id)
) TBLPROPERTIES ('transactional' = 'true');

```

关键问题: PK 是否强制唯一?
MaxCompute 2.0 事务表: PK 用于 MERGE/UPDATE/DELETE 的行标识
是否强制唯一取决于版本和配置，但总体上是"声明式"的
这与 BigQuery/Snowflake 的设计哲学一致: 约束是信息性的

设计分析: 为什么分布式引擎不强制 PK?
强制唯一需要: 全局去重（跨所有节点检查，代价极高）
或者: 按 PK 分桶（限制了数据分布灵活性）
INSERT OVERWRITE 语义下: 整分区替换，PK 唯一性由源数据保证

对比:
MySQL:       PK 强制唯一（InnoDB 聚集索引，违反时报错）
PostgreSQL:  PK 强制唯一（B-tree 索引支持）
BigQuery:    PK 声明不强制（信息性约束）
Snowflake:   PK 声明不强制（用于查询优化提示）
Hive:        3.0+ 支持 PK 声明，不强制
ClickHouse:  无 PK 概念（ORDER BY 定义排序键，允许重复）

非事务表: 不支持主键

```sql
CREATE TABLE orders (
    id       BIGINT NOT NULL,
    user_id  BIGINT,
    amount   DECIMAL(10,2)
)
PARTITIONED BY (dt STRING);
```

 这里没有 PK，唯一性需要在 ETL 逻辑中保证

## 3. 不支持的约束


 UNIQUE:      不支持（原因同 PK，分布式全局唯一检查代价太高）
 FOREIGN KEY: 不支持（分布式跨表引用检查不现实）
 CHECK:       不支持（批处理引擎的约束应在 ETL 管道中验证）
 EXCLUDE:     不支持（PostgreSQL 特有）

 关于 CHECK 约束的设计哲学:
   OLTP 引擎: 约束在 INSERT/UPDATE 时实时检查 → 适合 CHECK
   批处理引擎: 数据批量写入，实时检查每行的代价不合理
   MaxCompute 的选择: 不接受语法 → 比 MySQL 5.7 的"接受但不执行"更诚实
   对引擎开发者: 约束要么执行，要么不接受语法。静默忽略是最差的选择

## 4. 隐式约束: 分区列


```sql
CREATE TABLE events (
    id     BIGINT,
    amount DECIMAL(10,2)
)
PARTITIONED BY (dt STRING, region STRING);

```

分区列的隐式约束:
NOT NULL: 分区列值不能为 NULL（目录路径不能包含 NULL）
类型限制: 推荐 STRING 类型（分区值编码在目录路径中）
长度限制: 分区键值最大 256 字节
值不变性: 写入后分区值不可修改（除非重建分区）

LIFECYCLE: 表级存储约束

```sql
CREATE TABLE temp_data (id BIGINT) LIFECYCLE 7;  -- 7 天后自动回收

```

## 5. 数据质量保证的替代方案


### 5.1 ROW_NUMBER 去重（替代 UNIQUE 约束）

```sql
INSERT OVERWRITE TABLE users_clean
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (
        PARTITION BY id ORDER BY updated_at DESC
    ) AS rn
    FROM users
) t WHERE rn = 1;

```

### 5.2 DataWorks 数据质量规则（替代 CHECK 约束）

   在 DataWorks 中配置:
   - 表行数波动不超过 20%
   - 关键列空值率不超过 1%
   - 值域检查: amount > 0
   这是"在管道级别而非存储级别做约束"的范例

### 5.3 ETL 管道中的断言（替代所有约束）

写入前验证

```sql
SELECT COUNT(*) AS invalid_count
FROM staging_data
WHERE amount < 0 OR user_id IS NULL;
```

如果 invalid_count > 0，终止管道

写入目标表

```sql
INSERT OVERWRITE TABLE target_data PARTITION (dt = '20240115')
SELECT * FROM staging_data
WHERE amount >= 0 AND user_id IS NOT NULL;

```

## 6. 横向对比: 约束支持


 NOT NULL:
MaxCompute: 支持（列级）  | MySQL/PG/Oracle: 支持
 PRIMARY KEY:
MaxCompute: 事务表声明式  | BigQuery/Snowflake: 声明不强制
MySQL/PG: 强制执行        | Hive 3.0+: 声明不强制
 UNIQUE:
MaxCompute: 不支持        | BigQuery/Snowflake: 声明不强制
   MySQL/PG: 强制执行
 FOREIGN KEY:
MaxCompute: 不支持        | BigQuery: 声明不强制
MySQL/PG: 强制执行        | Hive/Snowflake: 不支持
 CHECK:
MaxCompute: 不支持        | MySQL 8.0.16+: 强制执行
PostgreSQL: 强制执行      | BigQuery/Snowflake: 不支持
 DEFAULT:
MaxCompute: 常量支持      | MySQL/PG: 表达式支持

## 7. 对引擎开发者的启示


1. 分布式引擎的约束困境: 强制执行需要全局协调，代价极高

2. "声明不强制"是务实的折中: 约束信息可用于查询优化（如 PK 消除不必要的 DISTINCT）

3. 数据质量应该在管道级别保证（而非存储级别），这是批处理引擎的最佳实践

4. NOT NULL 是唯一低成本的约束: 列式存储可以利用它优化编码

5. 如果接受约束语法但不执行，必须有明确的文档和警告

6. MaxCompute 的分区隐式 NOT NULL 是目录编码的必然结果

