# BigQuery: 约束（Constraints）

> 参考资料:
> - [1] BigQuery SQL Reference - Table Constraints
>   https://cloud.google.com/bigquery/docs/reference/standard-sql/data-definition-language#table_constraints
> - [2] BigQuery Documentation - Informational Constraints
>   https://cloud.google.com/bigquery/docs/information-schema-table-constraints
> - [3] BigQuery Architecture - Query Optimization
>   https://cloud.google.com/bigquery/docs/best-practices-performance-overview


## 1. BigQuery 的约束哲学: 信息性约束（NOT ENFORCED）


 BigQuery 的约束模型是所有主流数据库中最独特的:
   - PRIMARY KEY: 支持，但 NOT ENFORCED（不检查唯一性/非空性）
   - FOREIGN KEY: 支持，但 NOT ENFORCED（不检查引用完整性）
   - NOT NULL:    唯一强制执行的约束
   - UNIQUE:      不支持
   - CHECK:       不支持

 为什么选择"信息性约束"?
 BigQuery 是无服务器分布式系统，表数据分散在数千个存储节点上:
   (a) 强制唯一性 → 每次 INSERT 需要全表扫描（或维护分布式索引）
       → 在 PB 级表上不可接受
   (b) 强制外键 → 跨表一致性检查 → 分布式事务开销
       → BigQuery 的 DML 配额已经很紧（每表每天 1500 次 DML）
   (c) 数据通常通过 ETL 管道加载 → 数据质量在管道中保证，不需要数据库检查

 但约束元数据对优化器极其有用:
   - PRIMARY KEY → 优化器知道列唯一 → 可以消除不必要的 DISTINCT
   - FOREIGN KEY → 优化器知道 JOIN 关系 → 可以优化 JOIN 顺序
   - 这使得查询性能提升 10-30%（Google 内部基准测试）

## 2. PRIMARY KEY（NOT ENFORCED）


建表时声明

```sql
CREATE TABLE users (
    id       INT64 NOT NULL,
    username STRING NOT NULL,
    email    STRING NOT NULL,
    PRIMARY KEY (id) NOT ENFORCED    -- 必须写 NOT ENFORCED
);

```

复合主键

```sql
CREATE TABLE order_items (
    order_id INT64 NOT NULL,
    item_id  INT64 NOT NULL,
    quantity INT64 NOT NULL DEFAULT 1,
    PRIMARY KEY (order_id, item_id) NOT ENFORCED
);

```

后期添加

```sql
ALTER TABLE users ADD PRIMARY KEY (id) NOT ENFORCED;

```

 关键陷阱: NOT ENFORCED 意味着可以插入重复主键!
 INSERT INTO users VALUES (1, 'alice', 'a@e.com');
 INSERT INTO users VALUES (1, 'bob',   'b@e.com');  -- 成功! 两行 id=1

 优化器如何利用 PRIMARY KEY:
   SELECT DISTINCT id FROM users;
   → 优化器知道 id 唯一，跳过 DISTINCT 操作
   但如果实际数据有重复，结果可能不正确!
   → 数据质量由用户负责

 对比:
   MySQL:       PRIMARY KEY = 聚集索引 + 强制唯一 + 强制 NOT NULL
   PostgreSQL:  PRIMARY KEY = btree 索引 + 强制唯一 + 强制 NOT NULL
   ClickHouse:  PRIMARY KEY = 稀疏索引（不强制唯一，但至少用于排序）
   BigQuery:    PRIMARY KEY = 纯元数据（不排序，不索引，不强制唯一）

## 3. FOREIGN KEY（NOT ENFORCED）


```sql
CREATE TABLE orders (
    id      INT64 NOT NULL,
    user_id INT64 NOT NULL,
    amount  NUMERIC,
    PRIMARY KEY (id) NOT ENFORCED,
    CONSTRAINT fk_user FOREIGN KEY (user_id) REFERENCES users (id) NOT ENFORCED
);

```

后期添加

```sql
ALTER TABLE orders ADD CONSTRAINT fk_user
    FOREIGN KEY (user_id) REFERENCES users (id) NOT ENFORCED;

```

删除外键

```sql
ALTER TABLE orders DROP CONSTRAINT fk_user;

```

 外键的优化器价值:
   SELECT u.username, o.amount
   FROM users u JOIN orders o ON u.id = o.user_id;
   → 优化器知道 JOIN 是多对一关系
   → 可以选择更优的 JOIN 策略（broadcast vs shuffle）
   → 可以推断 GROUP BY u.id 后 u.username 是函数依赖（不需要额外聚合）

## 4. NOT NULL: 唯一强制执行的约束


```sql
CREATE TABLE events (
    id        INT64 NOT NULL,        -- 强制执行: INSERT NULL 会报错
    name      STRING NOT NULL,       -- 强制执行
    value     FLOAT64,               -- 默认允许 NULL
    metadata  STRING                 -- 默认允许 NULL
);

```

放宽 NOT NULL（不可反向收紧）

```sql
ALTER TABLE events ALTER COLUMN name DROP NOT NULL;

```

 为什么不能从可空改为 NOT NULL?
 因为已有数据可能包含 NULL 值，BigQuery 不会扫描全表验证。
 这与"ALTER TABLE 不重写数据"的设计原则一致。

 对比:
   MySQL:      ALTER TABLE ... MODIFY COLUMN col INT NOT NULL; -- 会扫描验证
   PostgreSQL: ALTER TABLE ... ALTER COLUMN col SET NOT NULL;  -- 会扫描验证
   ClickHouse: 默认 NOT NULL，Nullable 需要 opt-in（方向相反）

## 5. DEFAULT


```sql
CREATE TABLE users (
    id         INT64 NOT NULL,
    status     INT64 NOT NULL DEFAULT 1,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    region     STRING DEFAULT 'us-central1'
);

ALTER TABLE users ALTER COLUMN status SET DEFAULT 0;
ALTER TABLE users ALTER COLUMN status DROP DEFAULT;

```

 BigQuery 的 DEFAULT 是在 INSERT 时由服务端填充的。
 不支持生成列（GENERATED ALWAYS AS）或计算列。
 需要计算列时，使用视图或 CTAS:

   CREATE VIEW users_computed AS
   SELECT *, CONCAT(first_name, ' ', last_name) AS full_name FROM users;

## 6. 数据质量保证的替代方案


### 6.1 ETL 管道中的数据验证（推荐）

 BigQuery 的设计假设: 数据质量在进入 BigQuery 之前就应该保证。
 典型的数据管道: Source → Validation → BigQuery
 工具: Dataflow, Dataproc, dbt tests, Great Expectations

### 6.2 使用 MERGE 防止重复

```sql
MERGE INTO users AS target
USING staging AS source
ON target.id = source.id
WHEN NOT MATCHED THEN
    INSERT (id, username, email) VALUES (source.id, source.username, source.email);

```

### 6.3 使用 INFORMATION_SCHEMA 查看约束

```sql
SELECT constraint_name, constraint_type, is_deferrable, enforced
FROM myproject.mydataset.INFORMATION_SCHEMA.TABLE_CONSTRAINTS
WHERE table_name = 'users';

SELECT * FROM myproject.mydataset.INFORMATION_SCHEMA.KEY_COLUMN_USAGE
WHERE table_name = 'users';

```

### 6.4 查询时去重（后置保护）

```sql
SELECT * FROM users QUALIFY ROW_NUMBER() OVER (PARTITION BY id ORDER BY created_at DESC) = 1;

```

## 7. 对比与引擎开发者启示

BigQuery 的约束设计代表了云数仓的共识:
Snowflake: PRIMARY KEY/UNIQUE/FOREIGN KEY 都不强制执行
Redshift:  PRIMARY KEY/UNIQUE 不强制执行，FOREIGN KEY 同样
Databricks: 完全不支持约束

这不是偶然: 分布式列存系统中强制约束的成本远高于收益。
但"接受语法+不执行"是比"不接受语法"更好的设计选择:
(1) 迁移兼容: 从 MySQL/PostgreSQL 迁移时不需要删除约束语法
(2) 优化器提示: 约束元数据帮助查询优化
(3) 文档化意图: 约束声明了数据的业务语义

对引擎开发者的启示:
如果设计分布式分析引擎，建议采用 NOT ENFORCED 模式:
接受约束语法 → 存储元数据 → 优化器利用 → 但不在写入路径检查。
这是 MySQL 8.0 之前 CHECK 约束"接受但不执行"的合理版本
（区别在于 BigQuery 明确标记了 NOT ENFORCED）。

