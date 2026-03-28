# TiDB: 错误处理

> 参考资料:
> - [TiDB Documentation - Error Handling](https://docs.pingcap.com/tidb/stable/error-handling)

**引擎定位**: 分布式 HTAP 数据库，兼容 MySQL 协议。基于 TiKV 行存 + TiFlash 列存，Raft 共识。

## DECLARE HANDLER (MySQL 兼容)

```sql
DELIMITER //
CREATE PROCEDURE safe_insert(IN p_name VARCHAR(100))
BEGIN
    DECLARE CONTINUE HANDLER FOR 1062
        SELECT 'Duplicate key ignored' AS warning;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            @state = RETURNED_SQLSTATE,
            @msg = MESSAGE_TEXT;
        SELECT @state, @msg;
    END;

    INSERT INTO users(username) VALUES(p_name);
END //
DELIMITER ;

```

## SIGNAL                                              -- 6.3+

```sql
DELIMITER //
CREATE PROCEDURE validate(IN p_val INT)
BEGIN
    IF p_val < 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Value must be non-negative';
    END IF;
END //
DELIMITER ;

```

**注意:** TiDB 兼容 MySQL 错误处理语法
**注意:** DECLARE HANDLER 和 SIGNAL 均支持
**限制:** 某些 MySQL 特有的错误码在 TiDB 中可能不同
