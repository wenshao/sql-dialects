# MariaDB: 日期和时间类型

与 MySQL 一致, 系统版本表的时间列是独有扩展

参考资料:
[1] MariaDB Knowledge Base - Date and Time Data Types
https://mariadb.com/kb/en/date-and-time-data-types/

## 1. 日期时间类型

DATE:      3 字节, 1000-01-01 ~ 9999-12-31
TIME:      3 字节, -838:59:59 ~ 838:59:59
DATETIME:  5 字节, 1000-01-01 ~ 9999-12-31 (不含时区)
TIMESTAMP: 4 字节, 1970-01-01 ~ 2038-01-19 (存 UTC, 自动时区转换)
YEAR:      1 字节, 1901~2155
```sql
CREATE TABLE time_demo (
    event_date DATE,
    event_time TIME(3),           -- 毫秒精度
    created_at DATETIME(6),        -- 微秒精度
    logged_at  TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6),
    birth_year YEAR
);
```


## 2. DATETIME vs TIMESTAMP 选择

DATETIME: 存字面值, 不受时区影响, 适合业务时间
TIMESTAMP: 存 UTC, 读取时按 session time_zone 转换, 适合系统时间
2038 问题: TIMESTAMP 最大 2038-01-19 03:14:07 UTC
MariaDB 的立场与 MySQL 相同: 推荐 DATETIME 避免 2038 问题

## 3. 系统版本表的时间列 (MariaDB 独有)

GENERATED ALWAYS AS ROW START/ROW END 是 MariaDB 独有的列属性
使用 TIMESTAMP(6) 精度记录行的生命周期
这些列通常声明为 INVISIBLE, 不影响 SELECT *

## 4. 对引擎开发者的启示

TIMESTAMP 的 2038 年问题是所有 32 位 Unix 时间戳系统的共同问题
解决方案: 内部使用 64 位存储 (如 PostgreSQL TIMESTAMPTZ: 8 字节, 微秒精度)
MariaDB/MySQL 选择保持 4 字节 TIMESTAMP 是向后兼容的代价
系统版本表要求精确的时间比较: 6 位精度 (微秒) 是最低要求
