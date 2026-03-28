# Apache Impala: 约束

> 参考资料:
> - [Impala SQL Reference](https://impala.apache.org/docs/build/html/topics/impala_langref.html)
> - [Impala Built-in Functions](https://impala.apache.org/docs/build/html/topics/impala_functions.html)


Impala 对约束的支持非常有限
Hive 表几乎没有约束，Kudu 表支持部分约束

## Kudu 表: PRIMARY KEY（唯一支持约束的表类型）


```sql
CREATE TABLE users_kudu (
    id       BIGINT,
    username STRING,
    email    STRING,
    age      INT,
    PRIMARY KEY (id)
)
STORED AS KUDU;
```


复合主键
```sql
CREATE TABLE order_items_kudu (
    order_id BIGINT,
    item_id  BIGINT,
    quantity INT,
    PRIMARY KEY (order_id, item_id)
)
PARTITION BY HASH (order_id) PARTITIONS 8
STORED AS KUDU;
```


## Kudu 表: NOT NULL


```sql
CREATE TABLE users_kudu (
    id       BIGINT NOT NULL,
    username STRING NOT NULL,
    email    STRING,                          -- 允许 NULL
    PRIMARY KEY (id)
)
STORED AS KUDU;
```


主键列隐式 NOT NULL

## Kudu 表: DEFAULT


```sql
CREATE TABLE users_kudu (
    id       BIGINT,
    status   INT NOT NULL DEFAULT 1,
    name     STRING DEFAULT 'unknown',
    PRIMARY KEY (id)
)
STORED AS KUDU;
```


## Kudu 表: ENCODING 和 COMPRESSION


```sql
CREATE TABLE users_kudu (
    id       BIGINT ENCODING AUTO_ENCODING COMPRESSION DEFAULT_COMPRESSION,
    username STRING ENCODING DICT_ENCODING COMPRESSION LZ4,
    age      INT ENCODING BIT_SHUFFLE COMPRESSION SNAPPY,
    PRIMARY KEY (id)
)
STORED AS KUDU;
```


编码方式：AUTO_ENCODING, PLAIN_ENCODING, RLE, DICT_ENCODING, BIT_SHUFFLE, PREFIX_ENCODING
压缩方式：DEFAULT_COMPRESSION, NO_COMPRESSION, SNAPPY, LZ4, ZLIB

## Hive 表: 无约束支持


Hive 表不支持以下约束：
NOT NULL: 不支持
PRIMARY KEY: 不支持
UNIQUE: 不支持
FOREIGN KEY: 不支持
CHECK: 不支持
DEFAULT: 不支持

```sql
CREATE TABLE users (
    id       BIGINT,
    username STRING,
    email    STRING
)
STORED AS PARQUET;
```


## 数据完整性替代方案


1. Kudu 表用于需要约束的场景
2. 在 ETL 流程中验证数据
3. 查询时使用 WHERE 过滤无效数据
4. 使用 COMPUTE STATS 后优化器可以检测数据分布

查询时检查数据质量
```sql
SELECT * FROM users WHERE id IS NULL;
SELECT id, COUNT(*) FROM users GROUP BY id HAVING COUNT(*) > 1;
```


注意：只有 Kudu 表支持 PRIMARY KEY / NOT NULL / DEFAULT
注意：任何表类型都不支持 FOREIGN KEY / CHECK / UNIQUE
注意：数据完整性主要由 ETL 流程和应用层保证
