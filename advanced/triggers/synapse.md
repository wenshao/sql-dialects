# Azure Synapse: 触发器

> 参考资料:
> - [Synapse SQL Features](https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features)
> - [Synapse T-SQL Differences](https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features)


Synapse 专用 SQL 池不支持触发器
使用替代方案实现类似功能

## 替代方案一：存储过程封装


在存储过程中封装业务逻辑
```sql
CREATE PROCEDURE insert_user_with_audit
    @username NVARCHAR(64),
    @email NVARCHAR(255),
    @age INT
AS
BEGIN
    -- 插入用户
    INSERT INTO users (username, email, age) VALUES (@username, @email, @age);
```


模拟触发器：写入审计日志
```sql
    INSERT INTO audit_log (table_name, action, details, created_at)
    VALUES ('users', 'INSERT', N'username=' + @username, GETDATE());
END;

EXEC insert_user_with_audit 'alice', N'alice@example.com', 25;
```


## 替代方案二：CTAS + 验证管道


在数据加载管道中添加验证步骤

1. 加载到暂存堆表
```sql
CREATE TABLE #staging
WITH (DISTRIBUTION = ROUND_ROBIN, HEAP)
AS SELECT * FROM external_staging;
```


2. 验证数据（模拟 BEFORE INSERT 触发器）
检查数据质量
```sql
SELECT * FROM #staging WHERE username IS NULL OR email IS NULL;
```


3. 只插入有效数据
```sql
INSERT INTO users (username, email, age)
SELECT username, email, age FROM #staging
WHERE username IS NOT NULL AND email IS NOT NULL;
```


4. 记录审计日志（模拟 AFTER INSERT 触发器）
```sql
INSERT INTO audit_log (table_name, action, row_count, created_at)
SELECT 'users', 'BATCH_INSERT', COUNT(*), GETDATE()
FROM #staging WHERE username IS NOT NULL;
```


## 替代方案三：Azure Functions + Event Grid


使用 Azure 事件驱动架构：
1. Synapse 管道完成后触发 Event Grid 事件
2. Azure Functions 接收事件并执行后处理
3. 实现通知、审计、级联更新等

## 替代方案四：Synapse 管道（Pipeline）


使用 Synapse Pipelines（类似 Azure Data Factory）
1. Copy Activity: 加载数据
2. SQL Script Activity: 执行验证
3. Stored Procedure Activity: 调用存储过程
4. Web Activity: 发送通知

## 自动维护 updated_at


在 UPDATE 存储过程中自动更新时间戳
```sql
CREATE PROCEDURE update_user_email
    @user_id BIGINT,
    @new_email NVARCHAR(255)
AS
BEGIN
    UPDATE users
    SET email = @new_email, updated_at = GETDATE()
    WHERE id = @user_id;

    INSERT INTO audit_log (table_name, action, details, created_at)
    VALUES ('users', 'UPDATE', N'email changed for user ' + CAST(@user_id AS NVARCHAR), GETDATE());
END;
```


## 数据质量检查存储过程（替代约束触发器）


```sql
CREATE PROCEDURE validate_and_load
AS
BEGIN
    -- 标记无效数据
    UPDATE staging_users SET is_valid = 0
    WHERE username IS NULL OR email IS NULL OR email NOT LIKE '%@%';
```


只加载有效数据
```sql
    INSERT INTO users (username, email, age)
    SELECT username, email, age FROM staging_users WHERE is_valid = 1;
```


记录无效数据
```sql
    INSERT INTO rejected_records (source_table, reason, created_at)
    SELECT 'staging_users',
        CASE
            WHEN username IS NULL THEN 'null username'
            WHEN email IS NULL THEN 'null email'
            ELSE 'invalid email format'
        END,
        GETDATE()
    FROM staging_users WHERE is_valid = 0;
END;
```


注意：Synapse 专用池不支持触发器
注意：存储过程是最常见的替代方案
注意：CTAS + 验证管道适合批量加载场景
注意：Synapse Pipelines 提供编排和调度能力
注意：Azure Functions + Event Grid 实现事件驱动
注意：Serverless 池也不支持触发器
