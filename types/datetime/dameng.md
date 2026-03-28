# DamengDB (达梦): 日期时间类型

Oracle compatible types.

> 参考资料:
> - [DamengDB SQL Reference](https://eco.dameng.com/document/dm/zh-cn/sql-dev/index.html)
> - [DamengDB System Admin Manual](https://eco.dameng.com/document/dm/zh-cn/pm/index.html)


DATE: 日期时间（含时分秒，与 Oracle 相同）
TIME: 时间
TIMESTAMP: 日期时间，精度可达纳秒
TIMESTAMP WITH TIME ZONE: 带时区
INTERVAL YEAR TO MONTH: 年月间隔
INTERVAL DAY TO SECOND: 日秒间隔
DATETIME: 日期时间（达梦扩展）

```sql
CREATE TABLE events (
    id         INT IDENTITY(1,1) PRIMARY KEY,
    event_date DATE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE
);
```

## 获取当前时间

```sql
SELECT CURRENT_TIMESTAMP FROM DUAL;
SELECT SYSDATE FROM DUAL;                -- Oracle 兼容
SELECT SYSTIMESTAMP FROM DUAL;           -- Oracle 兼容，带时区
SELECT CURRENT_DATE FROM DUAL;
SELECT LOCALTIMESTAMP FROM DUAL;
```

## 构造日期

```sql
SELECT TO_DATE('2024-01-15', 'YYYY-MM-DD') FROM DUAL;
SELECT TO_TIMESTAMP('2024-01-15 10:30:00', 'YYYY-MM-DD HH24:MI:SS') FROM DUAL;
```

## 日期加减

```sql
SELECT SYSDATE + 1 FROM DUAL;                    -- 加 1 天
SELECT SYSDATE + INTERVAL '3' MONTH FROM DUAL;
SELECT SYSDATE - INTERVAL '2' HOUR FROM DUAL;
SELECT ADD_MONTHS(SYSDATE, 3) FROM DUAL;
```

## 日期差

```sql
SELECT TO_DATE('2024-12-31', 'YYYY-MM-DD') - TO_DATE('2024-01-01', 'YYYY-MM-DD') FROM DUAL;
SELECT MONTHS_BETWEEN(TO_DATE('2024-12-31', 'YYYY-MM-DD'), TO_DATE('2024-01-01', 'YYYY-MM-DD')) FROM DUAL;
```

## 提取

```sql
SELECT EXTRACT(YEAR FROM SYSDATE) FROM DUAL;
SELECT EXTRACT(MONTH FROM SYSDATE) FROM DUAL;
```

## 格式化

```sql
SELECT TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS') FROM DUAL;
SELECT TO_CHAR(SYSDATE, 'Day, Month DD, YYYY') FROM DUAL;
```

## 截断

```sql
SELECT TRUNC(SYSDATE, 'MM') FROM DUAL;          -- 月初
SELECT TRUNC(SYSDATE, 'YY') FROM DUAL;          -- 年初
```

## LAST_DAY

```sql
SELECT LAST_DAY(SYSDATE) FROM DUAL;
```

## NEXT_DAY

```sql
SELECT NEXT_DAY(SYSDATE, 'MONDAY') FROM DUAL;
```

注意事项：
DATE 类型包含时分秒（与 Oracle 相同，与 PostgreSQL/MySQL 不同）
支持 SYSDATE、SYSTIMESTAMP 等 Oracle 函数
支持 INTERVAL 类型
日期运算语法与 Oracle 兼容
