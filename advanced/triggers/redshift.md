# Redshift: 触发器

> 参考资料:
> - [Redshift SQL Reference](https://docs.aws.amazon.com/redshift/latest/dg/cm_chap_SQLCommandRef.html)
> - [Redshift SQL Functions](https://docs.aws.amazon.com/redshift/latest/dg/c_SQL_functions.html)
> - [Redshift Data Types](https://docs.aws.amazon.com/redshift/latest/dg/c_Supported_data_types.html)


Redshift 不支持触发器
使用替代方案实现类似功能

## 替代方案一：存储过程 + 应用层调用


在存储过程中封装业务逻辑
```sql
CREATE OR REPLACE PROCEDURE insert_user_with_audit(
    p_username VARCHAR, p_email VARCHAR, p_age INT
)
AS $$
BEGIN
    -- 插入用户
    INSERT INTO users (username, email, age) VALUES (p_username, p_email, p_age);
```


模拟 AFTER INSERT 触发器：写入审计日志
```sql
    INSERT INTO audit_log (table_name, action, details, created_at)
    VALUES ('users', 'INSERT', 'username=' || p_username, GETDATE());
END;
$$ LANGUAGE plpgsql;
```


应用层调用存储过程而非直接 INSERT
```sql
CALL insert_user_with_audit('alice', 'alice@example.com', 25);
```


## 替代方案二：ETL 管道中实现逻辑


在数据加载管道中添加审计和验证步骤
1. 加载到暂存表
```sql
CREATE TEMP TABLE staging (LIKE users);
COPY staging FROM 's3://my-bucket/data/users.csv'
IAM_ROLE 'arn:aws:iam::123456789012:role/MyRole' CSV;
```


2. 验证数据（模拟 BEFORE INSERT 触发器）
```sql
SELECT * FROM staging WHERE username IS NULL OR email IS NULL;
```


3. 插入有效数据
```sql
INSERT INTO users SELECT * FROM staging WHERE username IS NOT NULL AND email IS NOT NULL;
```


4. 写入审计日志（模拟 AFTER INSERT 触发器）
```sql
INSERT INTO audit_log (table_name, action, details, created_at)
SELECT 'users', 'INSERT', 'batch load ' || COUNT(*) || ' rows', GETDATE()
FROM staging WHERE username IS NOT NULL;
```


## 替代方案三：Lambda UDF + 外部服务


使用 Lambda UDF 调用外部服务（如 SNS 通知）
CREATE EXTERNAL FUNCTION notify_change(action VARCHAR, details VARCHAR)
RETURNS VARCHAR
VOLATILE
LAMBDA 'my-notification-lambda'
IAM_ROLE 'arn:aws:iam::123456789012:role/MyLambdaRole';

## 替代方案四：Amazon EventBridge + CDC


使用零 ETL 集成或 Kinesis Data Streams 捕获变更
通过 EventBridge 触发下游处理

## 自动维护 updated_at（应用层实现）


在 UPDATE 存储过程中自动更新时间戳
```sql
CREATE OR REPLACE PROCEDURE update_user(
    p_id BIGINT, p_email VARCHAR
)
AS $$
BEGIN
    UPDATE users SET email = p_email, updated_at = GETDATE()
    WHERE id = p_id;
END;
$$ LANGUAGE plpgsql;
```


注意：Redshift 不支持触发器（BEFORE / AFTER / INSTEAD OF）
注意：使用存储过程封装业务逻辑是最常见的替代方案
注意：ETL 管道中的验证步骤可以替代 BEFORE 触发器
注意：Lambda UDF 可以调用外部服务实现通知功能
注意：对于 CDC（变更数据捕获），使用 AWS 原生服务
