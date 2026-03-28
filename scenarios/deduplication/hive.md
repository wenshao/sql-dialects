# Hive: 数据去重 (Deduplication)

> 参考资料:
> - [1] Apache Hive - Window Functions
>   https://cwiki.apache.org/confluence/display/Hive/LanguageManual+WindowingAndAnalytics


## 1. 查找重复数据

```sql
SELECT email, COUNT(*) AS cnt
FROM users GROUP BY email HAVING COUNT(*) > 1;

```

查看重复行的详细信息

```sql
SELECT u.*
FROM users u
JOIN (SELECT email FROM users GROUP BY email HAVING COUNT(*) > 1) dup
ON u.email = dup.email
ORDER BY u.email, u.created_at;

```

## 2. ROW_NUMBER 去重 (最常用的 Hive 去重方式)

保留每组最新的一行

```sql
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (
        PARTITION BY email ORDER BY created_at DESC
    ) AS rn
    FROM users
) ranked WHERE rn = 1;

```

RANK 去重（保留并列排名的所有行）

```sql
SELECT * FROM (
    SELECT *, RANK() OVER (
        PARTITION BY email ORDER BY created_at DESC
    ) AS rnk
    FROM users
) ranked WHERE rnk = 1;

```

 设计分析: 为什么 ROW_NUMBER 是 Hive 去重的标准方法?
1. 灵活: 可以精确控制保留哪一行（ORDER BY 决定）

2. 高效: 一次扫描 + 窗口函数，比自连接更高效

3. 通用: 支持任意去重逻辑（最新/最旧/最大值等）


## 3. 物理去重: CTAS + INSERT OVERWRITE

方案 A: CTAS 创建去重后的新表

```sql
CREATE TABLE users_clean AS
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY email ORDER BY created_at DESC) AS rn
    FROM users
) ranked WHERE rn = 1;

```

方案 B: INSERT OVERWRITE 原表（非 ACID 表）

```sql
INSERT OVERWRITE TABLE users
SELECT user_id, email, username, created_at FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY email ORDER BY created_at DESC) AS rn
    FROM users
) ranked WHERE rn = 1;

```

方案 C: ACID 表的 DELETE

```sql
DELETE FROM users
WHERE user_id NOT IN (
    SELECT keep_id FROM (
        SELECT MAX(user_id) AS keep_id FROM users GROUP BY email
    ) keepers
);

```

## 4. DISTINCT vs GROUP BY

```sql
SELECT DISTINCT email FROM users;
SELECT email FROM users GROUP BY email;
```

两者在 Hive 中效果相同，GROUP BY 可以附带聚合

近似去重计数

```sql
SELECT APPROX_COUNT_DISTINCT(email) AS approx_count FROM users;
```

 比 COUNT(DISTINCT email) 快，但有约 2% 误差

## 5. 跨引擎对比: 去重方法

 引擎        行级去重方式                        物理去重
 MySQL       DELETE + 子查询 / ROW_NUMBER       DELETE
 PostgreSQL  DISTINCT ON (col)                  DELETE USING
 Hive        ROW_NUMBER + 子查询               CTAS / INSERT OVERWRITE
 Spark SQL   ROW_NUMBER + 子查询               同 Hive
 BigQuery    ROW_NUMBER + 子查询               MERGE / DML

 PostgreSQL 的 DISTINCT ON 是最简洁的去重语法:
 SELECT DISTINCT ON (email) * FROM users ORDER BY email, created_at DESC;
 Hive 不支持 DISTINCT ON

## 6. 对引擎开发者的启示

1. ROW_NUMBER 去重是分析引擎的标准模式: 所有引擎都应该高效支持

2. DISTINCT ON 是有用的语法糖: 比 ROW_NUMBER + 子查询简洁得多

3. INSERT OVERWRITE 是 Hive 物理去重的关键: 不需要行级 DELETE

4. APPROX_COUNT_DISTINCT 对大数据量很重要: 精确去重需要全量数据 Shuffle

