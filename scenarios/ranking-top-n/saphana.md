# SAP HANA: Top-N 查询（排名与分组取前 N 条）

> 参考资料:
> - [SAP HANA SQL Reference - Window Functions](https://help.sap.com/docs/SAP_HANA_PLATFORM/4fe29514fd584807ac9f2a04f6754767)
> - [SAP HANA SQL Reference - LIMIT](https://help.sap.com/docs/SAP_HANA_PLATFORM/4fe29514fd584807ac9f2a04f6754767)


## 示例数据上下文

假设表结构:
orders(order_id INTEGER, customer_id INTEGER, amount DECIMAL(10,2), order_date DATE)

## Top-N 整体


```sql
SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
LIMIT 10;

SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
LIMIT 10 OFFSET 20;
```

## TOP 语法

```sql
SELECT TOP 10 order_id, customer_id, amount
FROM orders
ORDER BY amount DESC;
```

## Top-N 分组


## ROW_NUMBER() 方式

```sql
SELECT *
FROM (
    SELECT order_id, customer_id, amount, order_date,
           ROW_NUMBER() OVER (
               PARTITION BY customer_id
               ORDER BY amount DESC
           ) AS rn
    FROM orders
) ranked
WHERE rn <= 3;
```

## RANK() 方式

```sql
SELECT *
FROM (
    SELECT order_id, customer_id, amount, order_date,
           RANK() OVER (
               PARTITION BY customer_id
               ORDER BY amount DESC
           ) AS rnk
    FROM orders
) ranked
WHERE rnk <= 3;
```

## DENSE_RANK() 方式

```sql
SELECT *
FROM (
    SELECT order_id, customer_id, amount, order_date,
           DENSE_RANK() OVER (
               PARTITION BY customer_id
               ORDER BY amount DESC
           ) AS drnk
    FROM orders
) ranked
WHERE drnk <= 3;
```

## CROSS APPLY（SAP HANA 支持）


```sql
SELECT c.customer_id, t.order_id, t.amount
FROM (SELECT DISTINCT customer_id FROM orders) c
CROSS APPLY (
    SELECT TOP 3 order_id, amount
    FROM orders o
    WHERE o.customer_id = c.customer_id
    ORDER BY amount DESC
) t;
```

## 关联子查询方式


```sql
SELECT o.*
FROM orders o
WHERE (
    SELECT COUNT(*)
    FROM orders o2
    WHERE o2.customer_id = o.customer_id
      AND o2.amount > o.amount
) < 3
ORDER BY o.customer_id, o.amount DESC;
```

## 性能考量


SAP HANA 是内存列式数据库，窗口函数性能极高
使用列式存储自动优化排序和过滤
CROSS APPLY 在 SAP HANA 中可用
注意：SAP HANA 不支持 QUALIFY / LATERAL / FETCH FIRST WITH TIES
