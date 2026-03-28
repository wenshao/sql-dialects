# MariaDB: 类型转换

与 MySQL 基本一致, CONVERT 语法同

参考资料:
[1] MariaDB Knowledge Base - CAST / CONVERT
https://mariadb.com/kb/en/cast/

## 1. CAST 和 CONVERT

```sql
SELECT CAST('123' AS SIGNED INTEGER);
SELECT CAST('2024-01-01' AS DATE);
SELECT CAST(3.14 AS DECIMAL(10,2));
SELECT CAST('hello' AS CHAR(10) CHARACTER SET utf8mb4);
SELECT CAST(data AS JSON) FROM raw_events;     -- 10.2.7+

SELECT CONVERT('123', SIGNED INTEGER);
SELECT CONVERT('hello' USING utf8mb4);         -- 字符集转换
```


## 2. 隐式转换

MariaDB (同 MySQL) 类型转换宽松:
```sql
SELECT '100' + 0;           -- 100 (字符串到数字)
SELECT 0 + '100abc';        -- 100 (前缀匹配, 有警告)
SELECT 'abc' + 0;           -- 0   (无法转换)
-- 对比 PostgreSQL: 不允许隐式转换, 必须显式 CAST
```


## 3. INET_ATON / INET_NTOA (IP 地址转换)

```sql
SELECT INET_ATON('192.168.1.1');    -- 3232235777
SELECT INET_NTOA(3232235777);       -- '192.168.1.1'
SELECT INET6_ATON('::1');           -- IPv6 支持
```


## 4. 对引擎开发者的启示

隐式类型转换是 MySQL/MariaDB 的争议设计:
- **优点**:  开发者友好, 减少 CAST 代码
- **缺点**:  导致隐蔽 Bug (如 WHERE varchar_col = 0 匹配所有非数字行)
索引失效: 类型不匹配时优化器可能无法使用索引
PostgreSQL 的严格类型系统更安全, 但学习曲线更陡
建议: 新引擎应默认严格模式, 可选宽松模式作为兼容层
