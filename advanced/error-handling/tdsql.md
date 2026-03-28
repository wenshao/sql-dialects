# TDSQL: Error Handling

> 参考资料:
> - [TDSQL Documentation](https://cloud.tencent.com/document/product/557)
> - ============================================================
> - DECLARE HANDLER / SIGNAL (MySQL 兼容)
> - ============================================================

```sql
DELIMITER //
CREATE PROCEDURE safe_insert(IN p_name VARCHAR(100))
BEGIN
    DECLARE EXIT HANDLER FOR 1062
        SELECT 'Duplicate key' AS error;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @msg = MESSAGE_TEXT;
        SELECT CONCAT('Error: ', @msg) AS error;
    END;

    INSERT INTO users(username) VALUES(p_name);
END //
DELIMITER ;
```

## SIGNAL

```sql
DELIMITER //
CREATE PROCEDURE validate(IN p_val INT)
BEGIN
    IF p_val < 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Value must be non-negative';
    END IF;
END //
DELIMITER ;
```

## 注意：TDSQL 兼容 MySQL 错误处理语法

限制：分布式场景下部分错误码可能不同
