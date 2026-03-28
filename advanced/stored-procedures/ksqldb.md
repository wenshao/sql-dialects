# ksqlDB: 存储过程

## ksqlDB 不支持存储过程

通过持久查询和 UDF 实现类似功能

## 持久查询（替代存储过程）


## 持久查询持续运行，类似"自动执行的存储过程"

```sql
CREATE STREAM processed_orders AS
SELECT order_id, user_id,
       amount * 1.1 AS amount_with_tax,
       CASE WHEN amount > 1000 THEN 'high' ELSE 'normal' END AS priority
FROM orders
EMIT CHANGES;
```

## 聚合查询持续维护结果

```sql
CREATE TABLE user_summary AS
SELECT user_id,
       COUNT(*) AS order_count,
       SUM(amount) AS total_amount,
       MAX(amount) AS max_order
FROM orders
GROUP BY user_id
EMIT CHANGES;
```

## 自定义 UDF（Java 实现）


UDF 部署步骤：
1. 编写 Java 类实现 Udf 接口
2. 打包为 JAR
3. 放置到 ksqlDB 的 ext 目录
4. 重启 ksqlDB
示例 Java UDF：
@UdfDescription(name = "multiply", description = "Multiplies two numbers")
public class MultiplyUdf {
@Udf(description = "multiply two ints")
public long multiply(long a, long b) { return a * b; }
}
使用 UDF
SELECT multiply(amount, quantity) FROM orders EMIT CHANGES;
列出可用函数

```sql
SHOW FUNCTIONS;
```

## 查看函数详情

```sql
DESCRIBE FUNCTION UCASE;
```

注意：ksqlDB 不支持存储过程
注意：持久查询是主要的处理机制
注意：自定义 UDF 用 Java 实现
注意：UDF 需要重启 ksqlDB 才能加载
