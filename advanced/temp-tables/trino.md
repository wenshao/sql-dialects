# Trino: 临时表

> 参考资料:
> - [Trino Documentation - SQL Statement List](https://trino.io/docs/current/sql.html)
> - [Trino Documentation - WITH Clause](https://trino.io/docs/current/sql/select.html#with-clause)

**引擎定位**: 分布式查询引擎（前身 Presto），不存储数据。通过 Connector 查询异构数据源（Hive/Iceberg/RDBMS）。

## CTE（推荐方式）


```sql
WITH active_users AS (
    SELECT * FROM users WHERE status = 1
),
user_orders AS (
    SELECT u.id, u.username, COUNT(o.id) AS order_count
    FROM active_users u
    LEFT JOIN orders o ON u.id = o.user_id
    GROUP BY u.id, u.username
)
SELECT * FROM user_orders WHERE order_count > 5;

```

## CREATE TABLE AS（Connector 依赖）


在 Hive/Iceberg/Delta Lake Connector 中：
```sql
CREATE TABLE staging.temp_results AS
SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id;

```

使用后删除
```sql
DROP TABLE staging.temp_results;

```

## UNNEST（内联临时数据）


```sql
SELECT * FROM UNNEST(ARRAY[1, 2, 3, 4, 5]) AS t(id);

SELECT * FROM UNNEST(
    ARRAY['alice', 'bob'],
    ARRAY[30, 25]
) AS t(name, age);

```

## VALUES 表达式


```sql
SELECT * FROM (VALUES (1, 'alice'), (2, 'bob'), (3, 'charlie'))
AS t(id, name);

```

**注意:** Trino 是查询引擎，不支持临时表
**注意:** CTE 是最常用的临时数据组织方式
**注意:** CREATE TABLE AS 取决于底层 Connector
**注意:** UNNEST 和 VALUES 可以创建内联临时数据
