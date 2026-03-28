# MaxCompute (ODPS): 错误处理

> 参考资料:
> - [1] MaxCompute Documentation - Error Codes
>   https://help.aliyun.com/zh/maxcompute/user-guide/error-codes


## 1. MaxCompute 不支持服务端错误处理 —— 设计决策


 不支持:
   TRY/CATCH（SQL Server 风格）
   EXCEPTION WHEN（PostgreSQL/Oracle 风格）
   DECLARE HANDLER（MySQL 风格）
   SIGNAL/RESIGNAL

 为什么?
   MaxCompute 没有存储过程 → 没有过程式错误处理的上下文
   每个 SQL 是独立的分布式作业:
     成功: 所有 Instance 成功 → 结果写入
     失败: 任何 Instance 失败 → 整个作业回滚
   没有"部分成功"的概念

 对比:
   PostgreSQL: BEGIN ... EXCEPTION WHEN ... END（最完整）
   Oracle:     PL/SQL EXCEPTION WHEN（最成熟）
   MySQL:      DECLARE HANDLER FOR SQLSTATE/ERROR（存储过程中）
   SQL Server: TRY...CATCH（最直观）
   BigQuery:   BEGIN...EXCEPTION WHEN ERROR THEN...END（2023+）
   Snowflake:  BEGIN...EXCEPTION WHEN...END（存储过程中）
   Hive:       不支持（与 MaxCompute 相同）

## 2. SQL 层面的错误预防


IF NOT EXISTS / IF EXISTS 防止常见错误

```sql
CREATE TABLE IF NOT EXISTS users (id BIGINT, name STRING);
DROP TABLE IF EXISTS temp_table;
ALTER TABLE orders ADD IF NOT EXISTS PARTITION (dt = '20250101');
ALTER TABLE orders DROP IF EXISTS PARTITION (dt = '20250101');

```

 这是 MaxCompute 中最重要的错误预防手段:
   没有 IF NOT EXISTS: 表已存在 → 作业失败
   有 IF NOT EXISTS: 表已存在 → 静默成功

## 3. 常见错误码与排查


 语法和对象错误:
   ODPS-0110061: 表不存在（检查表名拼写和项目名）
   ODPS-0110111: 分区不存在（检查分区值格式）
   ODPS-0120006: 语法错误（检查 SQL 语法）
   ODPS-0123055: 列不存在（检查列名，注意大小写）

 权限错误:
   ODPS-0130013: 权限不足（申请相应权限）
   ODPS-0130071: 资源不足（等待或申请更多 CU）

 运行时错误:
   ODPS-0010000: 系统内部错误（联系技术支持）
   ODPS-0123091: CTE 嵌套层数超限
   ODPS-0123065: 数据类型不匹配
   ODPS-0420061: CAST 转换失败（数据清洗问题）

## 4. 应用层错误处理: PyODPS


 from odps import ODPS, errors

 o = ODPS('access_id', 'access_key', 'project', 'endpoint')

 try:
     instance = o.execute_sql('SELECT * FROM nonexistent_table')
     instance.wait_for_success()
 except errors.ODPSError as e:
     print(f'MaxCompute error: {e}')
     print(f'Error code: {e.code}')
 except errors.NoSuchObject as e:
     print(f'Table not found: {e}')
 except Exception as e:
     print(f'Unexpected error: {e}')

## 5. 应用层错误处理: Java SDK


 import com.aliyun.odps.OdpsException;

 try {
     Instance instance = SQLTask.run(odps, sql);
     instance.waitForSuccess();
 } catch (OdpsException e) {
     System.err.println("Error code: " + e.getErrorCode());
     System.err.println("Message: " + e.getMessage());
     // 重试逻辑 / 告警 / 回退方案
 }

## 6. 数据质量错误的防御模式


### 6.1 安全转换（替代 TRY_CAST）

```sql
SELECT
    CASE WHEN col RLIKE '^-?[0-9]+$'
         THEN CAST(col AS BIGINT) ELSE NULL END AS safe_int,
    CASE WHEN ISDATE(col, 'yyyy-MM-dd')
         THEN TO_DATE(col, 'yyyy-MM-dd') ELSE NULL END AS safe_date
FROM dirty_data;

```

### 6.2 Staging → Validate → Publish 模式

步骤 1: 写入 staging 表

```sql
INSERT OVERWRITE TABLE staging PARTITION (dt = '20240115')
SELECT * FROM raw_data;

```

步骤 2: 验证

```sql
SELECT 'row_count' AS check_name, COUNT(*) AS value FROM staging WHERE dt = '20240115'
UNION ALL
SELECT 'null_ratio', COUNT(*) - COUNT(amount) FROM staging WHERE dt = '20240115'
UNION ALL
SELECT 'negative_amount', SUM(IF(amount < 0, 1, 0)) FROM staging WHERE dt = '20240115';
```

在 DataWorks 中: 检查 value 是否在合理范围内

步骤 3: 通过验证后 publish

```sql
INSERT OVERWRITE TABLE production PARTITION (dt = '20240115')
SELECT * FROM staging WHERE dt = '20240115';

```

## 7. 任务状态检查


```sql
SHOW P;                                     -- 查看正在运行的任务
```

 SHOW INSTANCES;                          -- 查看历史任务

## 8. 横向对比: 错误处理


 服务端异常处理:
MaxCompute: 不支持              | PostgreSQL: EXCEPTION WHEN（最完整）
BigQuery:   BEGIN...EXCEPTION   | Snowflake: BEGIN...EXCEPTION
Oracle:     PL/SQL EXCEPTION    | MySQL: DECLARE HANDLER
   Hive:       不支持

 TRY_CAST:
MaxCompute: 不支持（需 CASE+REGEXP） | BigQuery: SAFE_CAST
Snowflake:  TRY_CAST                 | SQL Server: TRY_CAST
   PostgreSQL: 不支持（需自定义）

 IF EXISTS/IF NOT EXISTS:
   所有引擎均支持（这是最基本的错误预防）

## 9. 对引擎开发者的启示


### 1. TRY_CAST/SAFE_CAST 是最高优先级的容错功能 — 批处理作业不应因一行坏数据失败

### 2. IF EXISTS/IF NOT EXISTS 是最基本的错误预防 — 必须支持

### 3. 错误码体系应该结构化（ODPS-0120006 比"syntax error"更可定位）

### 4. BigQuery 的 BEGIN...EXCEPTION 证明批处理引擎可以支持异常处理

### 5. Staging → Validate → Publish 模式是批处理的"应用层事务"

### 6. 详细的错误信息（含行号、列名、数据值）极大加速调试

