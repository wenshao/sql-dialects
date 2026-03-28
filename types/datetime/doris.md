# Apache Doris: 日期时间类型

 Apache Doris: 日期时间类型

 参考资料:
   [1] Doris Documentation - Data Types
       https://doris.apache.org/docs/sql-manual/data-types/

## 1. 类型体系

DATE:       日期，0000-01-01 ~ 9999-12-31
DATETIME:   日期时间，秒精度(默认)
DATETIME(p): 亚秒精度 p=0~6(2.0+)
无 TIME 类型。无 TIMESTAMP WITH TIME ZONE。


```sql
CREATE TABLE events (
    id BIGINT, event_date DATE, created_at DATETIME, precise_at DATETIME(6)
) DUPLICATE KEY(id) DISTRIBUTED BY HASH(id);

```

## 2. 当前时间

```sql
SELECT CURRENT_DATE(), NOW(), CURRENT_TIMESTAMP(), CURDATE(), UTC_TIMESTAMP();

```

## 3. 日期运算

```sql
SELECT DATE_ADD('2024-01-15', INTERVAL 7 DAY);
SELECT DATE_SUB('2024-01-15', INTERVAL 1 MONTH);
SELECT DATEDIFF('2024-12-31', '2024-01-01');
SELECT TIMESTAMPDIFF(MONTH, '2024-01-01', '2024-12-31');

```

## 4. 提取与格式化

```sql
SELECT YEAR(NOW()), MONTH(NOW()), DAY(NOW()), HOUR(NOW());
SELECT DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i:%s');
SELECT DATE_TRUNC('month', NOW());

```

## 5. Unix 时间戳

```sql
SELECT UNIX_TIMESTAMP(), FROM_UNIXTIME(1705276800);

```

## 6. 对比其他引擎

时区:
- **Doris**: 无 TIMESTAMPTZ。时区由 FE time_zone 参数决定。
- **StarRocks**: 同样无 TIMESTAMPTZ。
- **MySQL**: TIMESTAMP(存 UTC 自动转) vs DATETIME(存原值)
- **PostgreSQL**: TIMESTAMPTZ(推荐)
- **BigQuery**: TIMESTAMP(有时区) vs DATETIME(无时区)

精度:
- **Doris 2.0+**: 微秒(6位)
- **ClickHouse**: DateTime64(纳秒，9位)
- **MySQL**: 微秒(6位)

对引擎开发者的启示:
分区表常用 DATE 作为分区键——DATE 类型的存储和比较成本最低。
DATETIME 的微秒精度增加了存储开销(8 字节 vs 4 字节)。
