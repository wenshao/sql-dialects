# Hive: 日期时间类型

> 参考资料:
> - [1] Apache Hive - Data Types (Date/Time)
>   https://cwiki.apache.org/confluence/display/Hive/LanguageManual+Types
> - [2] Apache Hive - Date Functions
>   https://cwiki.apache.org/confluence/display/Hive/LanguageManual+UDF#LanguageManualUDF-DateFunctions


## 1. Hive 的日期时间类型

TIMESTAMP: 日期+时间，精度到纳秒，不含时区 (0.8+)
DATE:      仅日期，YYYY-MM-DD 格式 (0.12+)
INTERVAL:  时间间隔，仅用于表达式 (1.2+)
无 TIME 类型，无 TIMESTAMPTZ 类型


```sql
CREATE TABLE events (
    id         BIGINT,
    event_date DATE,                -- 0.12+
    created_at TIMESTAMP            -- 0.8+
) STORED AS ORC;

```

 设计分析: 早期 Hive 只有 STRING 类型存储日期
 Hive 0.12 之前没有 DATE 类型，所有日期用 STRING 表示（如 '2024-01-15'）。
 这源于 Schema-on-Read 哲学: 数据文件中的日期是字符串，建表时不强制类型。
 DATE 类型在 0.12 引入后，实践中 STRING 仍然广泛使用（尤其作为分区列）。

## 2. 基本操作

```sql
SELECT CURRENT_DATE;                                    -- DATE (2.0+)
SELECT CURRENT_TIMESTAMP;                              -- TIMESTAMP (2.0+)
SELECT UNIX_TIMESTAMP();                               -- 当前 Unix 秒级时间戳

```

构造

```sql
SELECT CAST('2024-01-15' AS DATE);
SELECT CAST('2024-01-15 10:30:00' AS TIMESTAMP);
SELECT TO_DATE('2024-01-15 10:30:00');                  -- 提取日期部分

```

日期加减

```sql
SELECT DATE_ADD('2024-01-15', 7);                       -- 加 7 天
SELECT DATE_SUB('2024-01-15', 7);                       -- 减 7 天
SELECT ADD_MONTHS('2024-01-31', 1);                     -- 2024-02-29

```

INTERVAL (1.2+)

```sql
SELECT CURRENT_TIMESTAMP + INTERVAL '1' DAY;
SELECT CURRENT_TIMESTAMP - INTERVAL '2' HOUR;

```

日期差

```sql
SELECT DATEDIFF('2024-12-31', '2024-01-01');            -- 365 天
SELECT MONTHS_BETWEEN('2024-12-31', '2024-01-01');      -- 月数

```

提取

```sql
SELECT YEAR('2024-01-15'), MONTH('2024-01-15'), DAY('2024-01-15');
SELECT HOUR('10:30:00'), MINUTE('10:30:00'), SECOND('10:30:00');
SELECT EXTRACT(YEAR FROM TIMESTAMP '2024-01-15 10:30:00');  -- 2.2+

```

格式化

```sql
SELECT DATE_FORMAT('2024-01-15', 'yyyy/MM/dd');          -- Java SimpleDateFormat
SELECT FROM_UNIXTIME(1705312800, 'yyyy-MM-dd');
SELECT UNIX_TIMESTAMP('2024-01-15', 'yyyy-MM-dd');

```

截断与边界

```sql
SELECT TRUNC('2024-01-15', 'MM');                        -- 月初
SELECT LAST_DAY('2024-01-15');                           -- 月末
SELECT NEXT_DAY('2024-01-15', 'MO');                     -- 下一个周一

```

## 3. 时区处理

```sql
SELECT FROM_UTC_TIMESTAMP('2024-01-15 10:00:00', 'Asia/Shanghai');
SELECT TO_UTC_TIMESTAMP('2024-01-15 18:00:00', 'Asia/Shanghai');

```

 Hive 3.0+ 引入 TIMESTAMPLOCALTZ（带本地时区的时间戳）
 但使用不广泛，大多数场景仍用 TIMESTAMP + 手动时区转换

## 4. 跨引擎对比: 日期时间类型

 引擎          DATE  TIMESTAMP   TIME   TIMESTAMPTZ  INTERVAL
 MySQL         支持  DATETIME    TIME   TIMESTAMP    不支持
 PostgreSQL    支持  TIMESTAMP   TIME   TIMESTAMPTZ  支持
 Oracle        支持  TIMESTAMP   不支持 WITH TZ      支持
 Hive          0.12+ 0.8+       不支持 3.0+(有限)   1.2+(表达式)
 Spark SQL     支持  支持        不支持 不支持       支持
 BigQuery      支持  TIMESTAMP   TIME   TIMESTAMP即UTC 不支持

## 5. 已知限制

### 1. 无 TIME 类型: 不能表示纯时间（只有 DATE 和 TIMESTAMP）

### 2. TIMESTAMP 不含时区: 解释为服务器本地时区（容易出错）

### 3. DATEDIFF 只返回天数: 不能直接计算小时/分钟差

### 4. 格式字符串是 Java 风格: yyyy-MM-dd（与 MySQL % 和 PG YYYY 不同）

### 5. INTERVAL 仅用于表达式: 不能作为列类型


## 6. 对引擎开发者的启示

### 1. TIMESTAMP 应该默认带时区: Hive 的无时区 TIMESTAMP 是常见的错误来源

### 2. DATE 类型晚于 TIMESTAMP 引入说明了演进路径: 先解决"有日期"的问题，再细化类型

### 3. INTERVAL 作为列类型有实际需求: Hive 只在表达式中支持 INTERVAL 是不足的

### 4. 日期格式化字符串应该标准化: 不同引擎的格式模式差异是迁移的主要痛点

