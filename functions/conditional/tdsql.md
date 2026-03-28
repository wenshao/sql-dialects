# TDSQL: 条件函数 (Conditional Functions)

> 参考资料:
> - [TDSQL-C MySQL Documentation](https://cloud.tencent.com/document/product/1003)
> - [TDSQL MySQL Documentation](https://cloud.tencent.com/document/product/557)
> - [MySQL 8.0 Reference Manual - Flow Control Functions](https://dev.mysql.com/doc/refman/8.0/en/flow-control-functions.html)


## 说明: TDSQL 是腾讯云分布式数据库，条件函数与 MySQL 完全兼容。

MySQL 拥有丰富的专有条件函数（IF/IFNULL/ELT/FIELD 等）。

## CASE WHEN: 标准条件表达式


## 搜索式 CASE WHEN（推荐，更灵活）

```sql
SELECT username,
    CASE
        WHEN age < 18 THEN 'minor'
        WHEN age < 65 THEN 'adult'
        ELSE 'senior'
    END AS age_category
FROM users;
```

## 简单 CASE 表达式

```sql
SELECT username,
    CASE status
        WHEN 0 THEN 'inactive'
        WHEN 1 THEN 'active'
        WHEN 2 THEN 'deleted'
        ELSE 'unknown'
    END AS status_name
FROM users;
```

## CASE 在 ORDER BY 中的使用（自定义排序）

```sql
SELECT * FROM orders
ORDER BY CASE status
    WHEN 'urgent' THEN 1
    WHEN 'high' THEN 2
    WHEN 'normal' THEN 3
    ELSE 4
END;
```

CASE 在 UPDATE 中的使用
UPDATE products SET price = CASE
WHEN category = 'premium' THEN price * 1.1
WHEN category = 'standard' THEN price * 1.05
ELSE price
END;

## IF: 三元条件函数 (MySQL 专有)


## IF(condition, true_value, false_value)

```sql
SELECT username, IF(age >= 18, 'adult', 'minor') AS category FROM users;
SELECT IF(score >= 60, 'pass', 'fail') AS result FROM exams;
SELECT IFNULL(phone, 'N/A') AS contact FROM users;    -- IFNULL 是 IF 的 NULL 版
```

## IF 在 SELECT 和 WHERE 中都可用

```sql
SELECT * FROM users WHERE IF(active = 1, TRUE, FALSE);
```

## 注意: IF 是 MySQL 专有函数，迁移到其他数据库需改为 CASE WHEN

## IFNULL / COALESCE: NULL 处理


## IFNULL(expr, default): MySQL 专有，只接受 2 个参数

```sql
SELECT IFNULL(phone, 'N/A') FROM users;
SELECT IFNULL(email, 'no-email') FROM contacts;
```

## COALESCE(expr1, expr2, ..., exprN): SQL 标准，接受多个参数

```sql
SELECT COALESCE(phone, email, 'unknown') FROM users;  -- 返回第一个非 NULL 值
SELECT COALESCE(discount, 0) * price AS final_price FROM products;
```

对比:
IFNULL(phone, 'N/A')    -- MySQL 专有，2 个参数
COALESCE(phone, email)  -- SQL 标准，N 个参数
建议: 优先使用 COALESCE（跨数据库兼容）

## NULLIF: 条件 NULL 化


## NULLIF(expr1, expr2): 相等返回 NULL，不等返回 expr1

```sql
SELECT NULLIF(age, 0) AS safe_age FROM users;        -- age=0 → NULL
SELECT NULLIF(status, '') AS non_empty FROM orders;   -- 空字符串 → NULL
```

## 防止除零错误

```sql
SELECT total / NULLIF(count, 0) AS avg_value FROM metrics;
```

## 类型转换: CAST / CONVERT


## CAST: SQL 标准类型转换

```sql
SELECT CAST('123' AS SIGNED);                         -- 123（有符号整数）
SELECT CAST('3.14' AS DECIMAL(10, 2));                -- 3.14
SELECT CAST('2024-01-15' AS DATE);                    -- 2024-01-15
SELECT CAST(42 AS CHAR);                              -- '42'
```

## CONVERT: MySQL 风格类型转换

```sql
SELECT CONVERT('123', SIGNED);                        -- 123
SELECT CONVERT('hello' USING utf8mb4);                -- 字符集转换
```

## 注意: MySQL 不支持 :: 类型转换（与 PostgreSQL 不同）

注意: 没有 TRY_CAST，转换失败在严格模式下报错

## ELT / FIELD / INTERVAL: 位置映射函数


## ELT(index, str1, str2, ...): 按索引返回字符串

```sql
SELECT ELT(2, 'a', 'b', 'c');                         -- 'b'（第 2 个参数）
SELECT ELT(DAYOFWEEK(NOW()), 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat');
```

## FIELD(str, str1, str2, ...): 返回字符串在列表中的位置

```sql
SELECT FIELD('b', 'a', 'b', 'c');                     -- 2
SELECT FIELD('x', 'a', 'b', 'c');                     -- 0（未找到）
```

## INTERVAL: 数值区间比较（返回区间索引）

```sql
SELECT INTERVAL(23, 0, 10, 20, 30, 40);              -- 2（23 在 20~30 之间）
```

## GREATEST / LEAST: 多值比较


```sql
SELECT GREATEST(1, 3, 2);                             -- 3（最大值）
SELECT LEAST(1, 3, 2);                                -- 1（最小值）
SELECT GREATEST(score1, score2, score3) AS best FROM results;
SELECT LEAST(price_a, price_b, price_c) AS min_price FROM products;
```

## NULL 语义: 任一参数为 NULL → 结果为 NULL

```sql
SELECT GREATEST(10, NULL, 20);                        -- NULL
```

## 边界约束

```sql
SELECT GREATEST(0, LEAST(100, score)) AS clamped FROM exams;
```

## ISNULL: NULL 检测


```sql
SELECT ISNULL(phone) FROM users;                      -- 1=NULL, 0=非 NULL
SELECT * FROM users WHERE ISNULL(phone);              -- 等价于 WHERE phone IS NULL
```

注意: ISNULL(expr) 与 IFNULL(expr, default) 不同!
ISNULL: 返回布尔值 (1/0)
IFNULL: 返回第一个非 NULL 参数

## 条件聚合（CASE WHEN 模式）


## MySQL 不支持 FILTER 子句，用 CASE WHEN 实现条件聚合

```sql
SELECT
    COUNT(*) AS total,
    SUM(CASE WHEN age > 30 THEN 1 ELSE 0 END) AS over_30,
    SUM(CASE WHEN age <= 30 THEN 1 ELSE 0 END) AS under_30,
    AVG(CASE WHEN status = 'active' THEN score ELSE NULL END) AS active_avg
FROM users;
```

## 行转列（PIVOT 模拟）

```sql
SELECT
    username,
    MAX(CASE WHEN subject = 'math' THEN score END) AS math_score,
    MAX(CASE WHEN subject = 'english' THEN score END) AS english_score,
    MAX(CASE WHEN subject = 'science' THEN score END) AS science_score
FROM exam_scores GROUP BY username;
```

## 分布式注意事项


## CASE WHEN/IF/COALESCE 等在各分片独立执行，无跨分片问题

## CAST/CONVERT 中涉及日期字符串时，确保各分片时区一致

## 条件函数不涉及数据路由，性能不受分布式影响

## GROUP BY 中的 CASE WHEN 可能导致跨分片聚合（注意 shardkey 对齐）


## 版本兼容性

MySQL 5.7 / TDSQL: IF/IFNULL/CASE/COALESCE/NULLIF/CAST/CONVERT
MySQL 8.0 / TDSQL: REGEXP_LIKE (可用于条件判断)
确认 TDSQL 底层 MySQL 版本以确定可用功能范围
