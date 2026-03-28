# MariaDB: 缓慢变化维度 (Slowly Changing Dimension)

> 参考资料:
> - [MariaDB Knowledge Base - INSERT ... ON DUPLICATE KEY UPDATE](https://mariadb.com/kb/en/insert-on-duplicate-key-update/)
> - [MariaDB Knowledge Base - System-Versioned Tables](https://mariadb.com/kb/en/system-versioned-tables/)


## 维度表

```sql
CREATE TABLE dim_customer (
    customer_key   INT AUTO_INCREMENT PRIMARY KEY,
    customer_id    VARCHAR(20) NOT NULL,
    name           VARCHAR(100),
    city           VARCHAR(100),
    tier           VARCHAR(20),
    effective_date DATE NOT NULL DEFAULT (CURRENT_DATE),
    expiry_date    DATE NOT NULL DEFAULT '9999-12-31',
    is_current     TINYINT NOT NULL DEFAULT 1,
    UNIQUE KEY uk_cust (customer_id, is_current, effective_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```


## SCD Type 1: INSERT ... ON DUPLICATE KEY UPDATE

```sql
INSERT INTO dim_customer (customer_id, name, city, tier)
SELECT customer_id, name, city, tier FROM stg_customer
ON DUPLICATE KEY UPDATE
    name = VALUES(name),
    city = VALUES(city),
    tier = VALUES(tier);
```


## SCD Type 2: UPDATE + INSERT（同 MySQL）

```sql
UPDATE dim_customer t
JOIN   stg_customer s ON t.customer_id = s.customer_id
SET    t.expiry_date = DATE_SUB(CURRENT_DATE, INTERVAL 1 DAY),
       t.is_current  = 0
WHERE  t.is_current = 1
  AND  (t.name <> s.name OR t.city <> s.city OR t.tier <> s.tier);

INSERT INTO dim_customer (customer_id, name, city, tier, effective_date, expiry_date, is_current)
SELECT s.customer_id, s.name, s.city, s.tier,
       CURRENT_DATE, '9999-12-31', 1
FROM   stg_customer s
WHERE  NOT EXISTS (
    SELECT 1 FROM dim_customer d
    WHERE  d.customer_id = s.customer_id AND d.is_current = 1
);
```


## 系统版本化表（MariaDB 10.3.4+）

自动跟踪行的历史版本
```sql
CREATE TABLE dim_customer_temporal (
    customer_id    VARCHAR(20) PRIMARY KEY,
    name           VARCHAR(100),
    city           VARCHAR(100),
    tier           VARCHAR(20)
) WITH SYSTEM VERSIONING;
```


直接 UPDATE，历史自动保存
```sql
UPDATE dim_customer_temporal SET city = 'Shenzhen' WHERE customer_id = 'C001';
```


查询历史
```sql
SELECT * FROM dim_customer_temporal FOR SYSTEM_TIME ALL
WHERE  customer_id = 'C001';
```


查询某个时间点
```sql
SELECT * FROM dim_customer_temporal
FOR SYSTEM_TIME AS OF TIMESTAMP '2024-06-01 00:00:00';
```
