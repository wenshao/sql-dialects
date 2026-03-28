# Vertica: 触发器

> 参考资料:
> - [Vertica SQL Reference](https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/SQLReferenceManual.htm)
> - [Vertica Functions](https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/Functions/Functions.htm)


Vertica 不支持触发器

## 替代方案


方案一：使用存储过程封装数据变更
```sql
CREATE OR REPLACE PROCEDURE insert_user_with_audit(
    p_id INT, p_username VARCHAR, p_email VARCHAR
)
LANGUAGE PLvSQL
AS $$
BEGIN
    INSERT INTO users (id, username, email) VALUES (p_id, p_username, p_email);
    INSERT INTO audit_log (table_name, action, record_id, created_at)
        VALUES ('users', 'INSERT', p_id, CURRENT_TIMESTAMP);
END;
$$;

CALL insert_user_with_audit(1, 'alice', 'alice@example.com');
```


方案二：使用 Access Policy（行/列级安全）
替代安全相关的触发器

Row Access Policy
```sql
CREATE ACCESS POLICY ON users FOR ROWS
    WHERE username = CURRENT_USER() ENABLE;
```


Column Access Policy
```sql
CREATE ACCESS POLICY ON users FOR COLUMN email
    CASE WHEN ENABLED_ROLE('admin') THEN email
         ELSE '***' END ENABLE;
```


方案三：使用 DEFAULT 值替代自动填充
```sql
CREATE TABLE users_with_defaults (
    id         AUTO_INCREMENT,
    username   VARCHAR(64) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```


方案四：使用调度器定期执行
Vertica 内置 Scheduler
可以定期执行 SQL 任务

方案五：使用 Kafka 集成
Vertica 支持从 Kafka 消费数据
CREATE DATA LOADER my_loader AS
COPY users FROM KAFKA SOURCE my_source;

方案六：客户端应用层实现
在应用代码中实现变更前后的逻辑

审计日志替代方案
Vertica 内置审计功能
SELECT * FROM v_internal.dc_requests_issued;
SELECT * FROM v_monitor.query_requests;

> **注意**: Vertica 不支持触发器
> **注意**: 使用存储过程封装数据变更可以模拟触发器行为
> **注意**: Access Policy 替代安全相关的触发器
> **注意**: 分析型数据库通常不需要触发器
