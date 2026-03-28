# StarRocks: 缓慢变化维度

> 参考资料:
> - [1] StarRocks - Primary Key Model
>   https://docs.starrocks.io/docs/table_design/table_types/


## 1. SCD Type 1: Primary Key 模型(自动覆盖)

```sql
CREATE TABLE dim_customer (
    customer_id VARCHAR(20) NOT NULL,
    name VARCHAR(100), city VARCHAR(100), tier VARCHAR(20)
) PRIMARY KEY(customer_id) DISTRIBUTED BY HASH(customer_id) BUCKETS 4
PROPERTIES ("replication_num" = "1");

INSERT INTO dim_customer SELECT * FROM stg_customer;

```

## 2. SCD Type 2: Duplicate Key 模型

与 Doris 方案完全相同(分步 UPDATE + INSERT)。
StarRocks 同样不支持 MERGE 语句。

```sql
CREATE TABLE dim_customer_scd2 (
    customer_key BIGINT NOT NULL AUTO_INCREMENT,
    customer_id VARCHAR(20) NOT NULL,
    name VARCHAR(100), city VARCHAR(100), tier VARCHAR(20),
    effective_date DATE NOT NULL, expiry_date DATE NOT NULL,
    is_current TINYINT NOT NULL DEFAULT 1
) DUPLICATE KEY(customer_key) DISTRIBUTED BY HASH(customer_id) BUCKETS 4
PROPERTIES ("replication_num" = "1");

```

分步操作与 Doris 完全相同。

