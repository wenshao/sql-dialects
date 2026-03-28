# Vertica: 索引

> 参考资料:
> - [Vertica SQL Reference](https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/SQLReferenceManual.htm)
> - [Vertica Functions](https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/Functions/Functions.htm)


Vertica 使用 Projections 替代传统索引
Projections 是数据的物理存储副本，按特定排序顺序组织

## Projections（核心概念）


自动创建的 Super Projection（默认覆盖所有列）
建表时 Vertica 自动创建一个包含所有列的 super projection

手动创建排序优化的 Projection
```sql
CREATE PROJECTION users_by_city AS
SELECT id, username, email, city, age
FROM users
ORDER BY city, age
SEGMENTED BY HASH(id) ALL NODES;
```


未分段 Projection（复制到所有节点）
```sql
CREATE PROJECTION users_replicated AS
SELECT id, username, email
FROM users
ORDER BY id
UNSEGMENTED ALL NODES;
```


仅覆盖部分列（减少 IO）
```sql
CREATE PROJECTION orders_summary AS
SELECT id, user_id, amount, order_date
FROM orders
ORDER BY order_date, user_id
SEGMENTED BY HASH(id) ALL NODES;
```


预聚合 Projection（Live Aggregate Projection）
```sql
CREATE PROJECTION daily_revenue AS
SELECT order_date, user_id,
    SUM(amount) AS total_amount,
    COUNT(*) AS order_count
FROM orders
GROUP BY order_date, user_id
SEGMENTED BY HASH(user_id) ALL NODES;
```


Top-K Projection
```sql
CREATE PROJECTION top_orders AS
SELECT id, user_id, amount, order_date
FROM orders
ORDER BY amount DESC
LIMIT 1000
SEGMENTED BY HASH(id) ALL NODES;
```


## Projection 管理


查看 Projections
```sql
SELECT projection_name, anchor_table_name, is_super_projection
FROM projections WHERE anchor_table_name = 'users';
```


删除 Projection
```sql
DROP PROJECTION users_by_city;
```


刷新 Projection（使数据最新）
```sql
SELECT REFRESH('users');
SELECT START_REFRESH();
```


Projection 设计工具
```sql
SELECT DESIGNER_CREATE_DESIGN('my_design');
SELECT DESIGNER_ADD_DESIGN_QUERIES('my_design', 'SELECT city, COUNT(*) FROM users GROUP BY city');
SELECT DESIGNER_RUN_DESIGN('my_design');
```


## 列编码（列级优化）


在 Projection 中指定编码
```sql
CREATE PROJECTION users_encoded AS
SELECT
    id       ENCODING DELTAVAL,
    username ENCODING AUTO,
    city     ENCODING RLE,
    age      ENCODING BLOCKDICT_COMP
FROM users
ORDER BY city, age;
```


编码类型：
AUTO: 自动选择
RLE: 游程编码（适合排序列、低基数列）
DELTAVAL: 增量编码（适合递增数值）
BLOCKDICT_COMP: 块字典压缩（适合中基数列）
COMMONDELTA_COMP: 公共增量压缩
GCDDELTA: GCD 增量压缩

## 分区裁剪


分区自动实现数据裁剪
```sql
CREATE TABLE events (
    id         INT,
    event_name VARCHAR(128),
    event_time TIMESTAMP
)
ORDER BY event_time
PARTITION BY event_time::DATE;
```


查询自动裁剪不相关的分区
```sql
SELECT * FROM events WHERE event_time::DATE = '2024-01-15';
```


注意：Vertica 没有 B-tree / Hash 传统索引
注意：Projections 是 Vertica 最核心的优化机制
注意：每个 Projection 存储一份数据副本，增加存储开销
注意：查询优化器自动选择最优 Projection
注意：ORDER BY 定义 Projection 的排序键（影响范围查询效率）
