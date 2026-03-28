# MaxCompute (ODPS): 子查询

> 参考资料:
> - [1] MaxCompute SQL - Subquery
>   https://help.aliyun.com/zh/maxcompute/user-guide/subquery
> - [2] MaxCompute SQL - SELECT
>   https://help.aliyun.com/zh/maxcompute/user-guide/select


## 1. 标量子查询


```sql
SELECT username,
    (SELECT COUNT(*) FROM orders WHERE user_id = users.id) AS order_count
FROM users;

```

 标量子查询必须返回单行单列，否则运行时报错
 对比: PostgreSQL 对多行标量子查询报错，BigQuery 相同

## 2. WHERE 子查询


IN 子查询

```sql
SELECT * FROM users WHERE id IN (SELECT user_id FROM orders WHERE amount > 100);
SELECT * FROM users WHERE id NOT IN (SELECT user_id FROM blacklist);

```

EXISTS 子查询

```sql
SELECT * FROM users u
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);
SELECT * FROM users u
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

```

比较运算符子查询

```sql
SELECT * FROM users WHERE age > (SELECT AVG(age) FROM users);

```

 IN vs EXISTS 的性能差异:
   IN:     子查询结果物化为 hash 表，主查询逐行查找
   EXISTS: 对主查询每行执行子查询（相关子查询）
   MaxCompute 优化器: 通常将 IN/EXISTS 转换为 SEMI JOIN
   最佳实践: 使用 LEFT SEMI JOIN 代替 IN/EXISTS（显式控制执行策略）

## 3. FROM 子查询（派生表）


必须有别名

```sql
SELECT t.city, t.cnt FROM (
    SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
) t WHERE t.cnt > 10;

```

嵌套子查询

```sql
SELECT * FROM users
WHERE city IN (
    SELECT city FROM (
        SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
    ) t WHERE t.cnt > 100
);

```

## 4. 关联子查询


```sql
SELECT u.username,
    (SELECT MAX(amount) FROM orders o WHERE o.user_id = u.id) AS max_order
FROM users u;

```

关联子查询的性能问题:
逻辑上: 对主查询每行执行一次子查询 → O(N*M) 复杂度
MaxCompute 优化器: 尝试将关联子查询转换为 JOIN
如果无法转换: 性能极差，建议手动改写为 JOIN

手动改写为 JOIN（推荐）:

```sql
SELECT u.username, o.max_amount
FROM users u
LEFT JOIN (
    SELECT user_id, MAX(amount) AS max_amount FROM orders GROUP BY user_id
) o ON u.id = o.user_id;

```

## 5. SEMI JOIN / ANTI JOIN —— 子查询的优化形式


LEFT SEMI JOIN = IN 子查询 = EXISTS 子查询

```sql
SELECT u.*
FROM users u
LEFT SEMI JOIN orders o ON u.id = o.user_id;

```

LEFT ANTI JOIN = NOT IN 子查询 = NOT EXISTS 子查询

```sql
SELECT u.*
FROM users u
LEFT ANTI JOIN orders o ON u.id = o.user_id;

```

 设计分析: 为什么 SEMI/ANTI JOIN 通常比子查询快?
   子查询: 优化器需要识别模式并自动转换为 JOIN（可能失败）
   SEMI/ANTI JOIN: 直接告诉优化器用 JOIN 策略执行
   对比:
     Hive:     支持 LEFT SEMI JOIN（较早期不支持 IN 子查询）
     Spark:    支持 LEFT SEMI/ANTI JOIN
     PostgreSQL: 无专门语法（优化器自动转换）
     MySQL:    无专门语法（8.0 优化器改进了子查询处理）

## 6. 子查询 + LATERAL VIEW


```sql
SELECT u.username, tag
FROM users u
LATERAL VIEW EXPLODE(u.tags) t AS tag
WHERE tag IN (SELECT tag_name FROM popular_tags);

```

## 7. 不支持的子查询特性


 不支持 ALL / ANY / SOME 运算符
 标准 SQL: WHERE age > ALL (SELECT age FROM ...)
 MaxCompute 替代: WHERE age > (SELECT MAX(age) FROM ...)

 不支持 LATERAL 子查询（标准 SQL 的侧向子查询）
 标准 SQL: SELECT * FROM t, LATERAL (SELECT ... WHERE t.id = ...) s
 MaxCompute 替代: 使用 LATERAL VIEW EXPLODE 或 JOIN

 子查询嵌套层数有限制

## 8. 子查询的分布式执行


 MaxCompute 子查询在伏羲中的执行:
   非关联子查询: 子查询独立计算 → 结果广播到主查询节点
   关联子查询: 尝试转换为 JOIN → 如果不能则嵌套循环执行
   IN 子查询: 子查询结果物化为 Hash 表 → 主查询 Hash 查找

   性能关键:
     子查询结果集大小: 如果太大则 Hash 表内存溢出
     NOT IN 的 NULL 陷阱: 如果子查询结果含 NULL，NOT IN 返回空集
       解决: 使用 NOT EXISTS 或 LEFT ANTI JOIN

 NOT IN 的 NULL 陷阱（所有 SQL 引擎都存在）:
   SELECT * FROM t WHERE id NOT IN (1, 2, NULL)
   → 对所有行返回 UNKNOWN → 结果为空集
   这是 SQL 三值逻辑的经典陷阱，应总是使用 NOT EXISTS 或 ANTI JOIN

## 9. 横向对比: 子查询优化


 子查询自动展平:
MaxCompute: 优化器尝试展平  | PostgreSQL: 高级展平（lateral flattening）
MySQL 8.0:  改进的展平      | BigQuery: 自动展平
Hive:       有限展平         | Spark: 高级展平（AQE）

 SEMI/ANTI JOIN 语法:
MaxCompute: LEFT SEMI/ANTI JOIN  | Hive/Spark: 相同
PostgreSQL: 无语法（自动优化）   | BigQuery: 无语法
   MySQL:      无语法

## 10. 对引擎开发者的启示


### 1. 子查询展平（decorrelation）是查询优化器最重要的变换之一

### 2. SEMI/ANTI JOIN 作为一等 JOIN 类型简化了优化器和用户的工作

### 3. NOT IN 的 NULL 陷阱应该有编译期 WARNING（很少有引擎做到）

### 4. 关联子查询转 JOIN 是优化器的必备能力 — 否则性能不可接受

### 5. 标量子查询的单行保证需要运行时检查 — 应有清晰的错误信息

### 6. 子查询嵌套限制应该足够高（64+）以不影响正常使用

