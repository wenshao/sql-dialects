# OceanBase: 错误处理

> 参考资料:
> - [OceanBase Documentation](https://www.oceanbase.com/docs/common-oceanbase-database-cn)

**引擎定位**: 分布式关系型数据库，兼容 MySQL/Oracle 双模式。基于 LSM-Tree 存储，Paxos 共识。

## MySQL 模式: DECLARE HANDLER / SIGNAL

```sql
DELIMITER //
CREATE PROCEDURE safe_insert_mysql(IN p_name VARCHAR(100))
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @msg = MESSAGE_TEXT;
        SELECT CONCAT('Error: ', @msg) AS result;
    END;

    INSERT INTO users(username) VALUES(p_name);
END //
DELIMITER ;

```

## Oracle 模式: EXCEPTION WHEN

```sql
DECLARE
    v_name VARCHAR2(100);
BEGIN
    SELECT username INTO v_name FROM users WHERE id = 999;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('Not found');
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLCODE);
END;
/

```

RAISE_APPLICATION_ERROR (Oracle 模式)
```sql
CREATE OR REPLACE PROCEDURE validate_amount(p_amount NUMBER) AS
BEGIN
    IF p_amount <= 0 THEN
        RAISE_APPLICATION_ERROR(-20001, 'Amount must be positive');
    END IF;
END;
/

```

**注意:** OceanBase 支持 MySQL 和 Oracle 两种兼容模式
**注意:** MySQL 模式使用 DECLARE HANDLER/SIGNAL
**注意:** Oracle 模式使用 EXCEPTION WHEN/RAISE_APPLICATION_ERROR
**限制:** 兼容性取决于版本
