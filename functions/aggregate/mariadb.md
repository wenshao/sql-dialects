# MariaDB: 聚合函数

与 MySQL 基本一致, GROUP_CONCAT 差异值得注意

参考资料:
[1] MariaDB Knowledge Base - Aggregate Functions
https://mariadb.com/kb/en/aggregate-functions/

## 1. 标准聚合函数

```sql
SELECT COUNT(*), COUNT(DISTINCT age), SUM(age), AVG(age), MIN(age), MAX(age)
FROM users;

SELECT dept_id, COUNT(*) AS cnt, AVG(salary) AS avg_sal
FROM employees GROUP BY dept_id;
```


## 2. GROUP_CONCAT

```sql
SELECT dept_id, GROUP_CONCAT(name ORDER BY name SEPARATOR ', ') AS members
FROM employees GROUP BY dept_id;
-- group_concat_max_len 默认 1024 (同 MySQL), 超长截断
```


## 3. JSON 聚合 (10.5+)

```sql
SELECT JSON_ARRAYAGG(username) FROM users;
SELECT JSON_OBJECTAGG(username, age) FROM users;
```


## 4. 统计聚合

```sql
SELECT STDDEV(salary), VARIANCE(salary), STDDEV_POP(salary), VAR_POP(salary)
FROM employees;
```


## 5. 对引擎开发者的启示

GROUP_CONCAT 是 MySQL/MariaDB 独有的聚合函数
PostgreSQL 等价: string_agg() 或 array_agg() + array_to_string()
实现要点: 需要在聚合过程中维护可变长度的字符串缓冲区
排序选项 (ORDER BY) 需要在聚合阶段做局部排序
截断行为是安全设计: 防止内存溢出, 但可能导致数据丢失
