# Azure Synapse: 字符串函数

> 参考资料:
> - [Synapse SQL Features](https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features)
> - [Synapse T-SQL Differences](https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features)


拼接
```sql
SELECT 'hello' + ' ' + 'world';                      -- 'hello world'（T-SQL 用 +）
SELECT CONCAT('hello', ' ', 'world');                 -- 'hello world'（NULL 安全）
SELECT CONCAT_WS(',', 'a', 'b', 'c');                -- 'a,b,c'
```


长度
```sql
SELECT LEN('hello');                                  -- 5（去除尾部空格）
SELECT DATALENGTH('hello');                           -- 5（字节数，NVARCHAR 为 10）
SELECT LEN(N'你好');                                   -- 2（字符数）
SELECT DATALENGTH(N'你好');                             -- 4（NVARCHAR 字节数）
```


大小写
```sql
SELECT UPPER('hello');                                -- 'HELLO'
SELECT LOWER('HELLO');                                -- 'hello'
-- 没有 INITCAP，用替代方案：
SELECT UPPER(LEFT('hello world', 1)) + LOWER(SUBSTRING('hello world', 2, LEN('hello world')));
```


截取
```sql
SELECT SUBSTRING('hello world', 7, 5);                -- 'world'
SELECT LEFT('hello', 3);                              -- 'hel'
SELECT RIGHT('hello', 3);                             -- 'llo'
```


查找
```sql
SELECT CHARINDEX('world', 'hello world');              -- 7
SELECT CHARINDEX('world', 'hello world', 8);           -- 0（从位置 8 开始找）
SELECT PATINDEX('%wor%', 'hello world');               -- 7（支持通配符）
```


替换 / 填充 / 修剪
```sql
SELECT REPLACE('hello world', 'world', 'synapse');    -- 'hello synapse'
SELECT REPLICATE('ab', 3);                            -- 'ababab'
SELECT STUFF('hello world', 7, 5, 'synapse');         -- 'hello synapse'（替换指定位置）
SELECT TRIM('  hello  ');                             -- 'hello'
SELECT LTRIM('  hello');                              -- 'hello'
SELECT RTRIM('hello  ');                              -- 'hello'
```


翻转
```sql
SELECT REVERSE('hello');                              -- 'olleh'
```


空格和填充
```sql
SELECT SPACE(5);                                      -- '     '（5 个空格）
-- 没有 LPAD/RPAD，用替代方案：
SELECT RIGHT(REPLICATE('0', 5) + '42', 5);            -- '00042'（LPAD 效果）
```


ASCII / CHAR
```sql
SELECT ASCII('A');                                    -- 65
SELECT CHAR(65);                                      -- 'A'
SELECT UNICODE(N'你');                                 -- Unicode 码点
SELECT NCHAR(20320);                                  -- Unicode 字符
```


字符串聚合
```sql
SELECT STRING_AGG(username, ', ') WITHIN GROUP (ORDER BY username) FROM users;
```


分组聚合
```sql
SELECT city, STRING_AGG(username, ', ') WITHIN GROUP (ORDER BY username) AS user_list
FROM users GROUP BY city;
```


QUOTENAME（对象名引用）
```sql
SELECT QUOTENAME('table name');                       -- [table name]
SELECT QUOTENAME('value', '''');                      -- 'value'
```


FORMAT（格式化，可能在专用池中受限）
```sql
SELECT FORMAT(12345.678, 'N2');                       -- '12,345.68'
```


注意：T-SQL 使用 + 拼接字符串（不是 ||）
注意：+ 拼接中任何 NULL 导致整个结果为 NULL，用 CONCAT 避免
注意：没有 LPAD / RPAD 函数，需要用 REPLICATE + RIGHT/LEFT 模拟
注意：没有 INITCAP 函数
注意：没有正则函数（REGEXP_REPLACE 等不支持）
注意：PATINDEX 提供有限的模式匹配
注意：STRING_AGG 是推荐的字符串聚合函数
