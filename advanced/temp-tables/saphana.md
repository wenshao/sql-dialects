# SAP HANA: 临时表与临时存储

> 参考资料:
> - [SAP HANA Documentation - CREATE TABLE (Temporary)](https://help.sap.com/docs/SAP_HANA_PLATFORM/4fe29514fd584807ac9f2a04f6754767/)


## 全局临时表


```sql
CREATE GLOBAL TEMPORARY TABLE gtt_users (
    id BIGINT, username NVARCHAR(100), email NVARCHAR(200)
);
```

## ON COMMIT 选项

```sql
CREATE GLOBAL TEMPORARY TABLE gtt_tx_data (
    id BIGINT, value DECIMAL(10,2)
) ON COMMIT DELETE ROWS;

CREATE GLOBAL TEMPORARY TABLE gtt_session_data (
    id BIGINT, value DECIMAL(10,2)
) ON COMMIT PRESERVE ROWS;
```

## 本地临时表（#前缀）


```sql
CREATE LOCAL TEMPORARY TABLE #temp_orders (
    user_id BIGINT, total DECIMAL(10,2)
);
```

## 从查询创建

```sql
CREATE LOCAL TEMPORARY TABLE #temp_stats AS (
    SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id
);
```

## 列存储临时表（分析查询优化）

```sql
CREATE LOCAL TEMPORARY COLUMN TABLE #temp_analytics (
    id BIGINT, metric DOUBLE
);
```

## 行存储临时表

```sql
CREATE LOCAL TEMPORARY ROW TABLE #temp_oltp (
    id BIGINT PRIMARY KEY, data NVARCHAR(1000)
);
```

## 使用临时表


```sql
INSERT INTO #temp_orders SELECT user_id, SUM(amount) FROM orders GROUP BY user_id;
SELECT * FROM #temp_orders;
DROP TABLE #temp_orders;
```

## 表变量（SQLScript）


```sql
DO BEGIN
    DECLARE lt_users TABLE (id BIGINT, username NVARCHAR(100));
    lt_users = SELECT id, username FROM users WHERE status = 1;
    SELECT * FROM :lt_users;
END;
```

## CTE


```sql
WITH stats AS (
    SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id
)
SELECT u.username, s.total FROM users u JOIN stats s ON u.id = s.user_id;
```

注意：SAP HANA 支持全局临时表和本地临时表（#前缀）
注意：列存储临时表适合分析查询，行存储适合 OLTP
注意：SQLScript 中的表变量提供过程内的临时存储
注意：HANA 的内存架构使临时表性能很高
