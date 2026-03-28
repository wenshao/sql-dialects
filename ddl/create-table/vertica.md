# Vertica: CREATE TABLE

> 参考资料:
> - [Vertica SQL Reference](https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/SQLReferenceManual.htm)
> - [Vertica Functions](https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/Functions/Functions.htm)


基本表（列存储，默认）
```sql
CREATE TABLE users (
    id         INT NOT NULL,
    username   VARCHAR(64) NOT NULL,
    email      VARCHAR(255) NOT NULL,
    age        INT,
    balance    NUMERIC(10,2) DEFAULT 0.00,
    bio        VARCHAR(65000),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
```


指定分段分布（Hash 分布到所有节点）
```sql
CREATE TABLE orders (
    id         INT NOT NULL,
    user_id    INT NOT NULL,
    amount     NUMERIC(10,2),
    order_date DATE NOT NULL
)
ORDER BY order_date
SEGMENTED BY HASH(id) ALL NODES;
```


未分段表（复制到所有节点，适合小维表）
```sql
CREATE TABLE regions (
    id         INT NOT NULL,
    name       VARCHAR(64) NOT NULL
)
UNSEGMENTED ALL NODES;
```


分区表
```sql
CREATE TABLE events (
    id         INT NOT NULL,
    event_name VARCHAR(128),
    event_time TIMESTAMP NOT NULL
)
ORDER BY event_time
SEGMENTED BY HASH(id) ALL NODES
PARTITION BY event_time::DATE
GROUP BY CALENDAR_HIERARCHY_DAY(event_time::DATE, 2, 2);
```


分区 + 分层存储
```sql
CREATE TABLE logs (
    id         INT,
    message    VARCHAR(65000),
    log_date   DATE NOT NULL
)
ORDER BY log_date
PARTITION BY log_date;
```


Flex 表（半结构化数据，无需预定义 Schema）
```sql
CREATE FLEX TABLE events_flex ();
```


向 Flex 表加载 JSON 数据
COPY events_flex FROM '/data/events.json' PARSER fjsonparser();

从 Flex 表计算列定义
SELECT COMPUTE_FLEXTABLE_KEYS('events_flex');

临时表
```sql
CREATE LOCAL TEMPORARY TABLE tmp_import (
    id INT, name VARCHAR(64)
) ON COMMIT PRESERVE ROWS;
```


CTAS
```sql
CREATE TABLE users_backup AS
SELECT * FROM users WHERE created_at > '2024-01-01';
```


LIKE（复制表结构）
```sql
CREATE TABLE users_copy LIKE users INCLUDING PROJECTIONS;
```


列约束
```sql
CREATE TABLE products (
    id         AUTO_INCREMENT,
    name       VARCHAR(128) NOT NULL,
    sku        VARCHAR(32) NOT NULL UNIQUE,
    price      NUMERIC(10,2) CHECK (price > 0),
    category   VARCHAR(64),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id)
);
```


编码和压缩
```sql
CREATE TABLE events_compressed (
    id         INT ENCODING DELTAVAL,
    event_name VARCHAR(128) ENCODING AUTO,
    event_time TIMESTAMP ENCODING BLOCKDICT_COMP,
    amount     NUMERIC(10,2) ENCODING RLE
)
ORDER BY event_time
SEGMENTED BY HASH(id) ALL NODES;
```


注意：Vertica 是列存储数据库，ORDER BY 定义排序键（影响查询性能）
注意：Projections 是 Vertica 独有概念，替代传统索引
注意：SEGMENTED BY 控制数据在集群中的分布
注意：支持 AUTO_INCREMENT
注意：默认自动创建 super projection
