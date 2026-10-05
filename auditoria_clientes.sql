-- =====================================================================
-- Auditoría de cambios en Clientes (MySQL 5.7+ / 8.x)
-- Registra cada cambio en los campos sensibles: email y direccion_envio.
--
-- Supuestos sobre la tabla existente:
--   Clientes(id_cliente, ..., email, direccion_envio, ...)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Tabla de auditoría
--    Una fila por cada campo modificado (si cambian email y dirección
--    en el mismo UPDATE, se generan dos filas).
--    No se define FOREIGN KEY a propósito: si un cliente se elimina, su
--    historial de auditoría debe conservarse.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS Auditoria_Clientes (
    id_auditoria       INT UNSIGNED NOT NULL AUTO_INCREMENT,
    id_cliente         INT          NOT NULL,                      -- cliente afectado
    campo_modificado   VARCHAR(50)  NOT NULL,                      -- 'email' o 'direccion_envio'
    valor_antiguo      TEXT         NULL,                          -- valor antes del UPDATE (puede ser NULL)
    valor_nuevo        TEXT         NULL,                          -- valor después del UPDATE (puede ser NULL)
    fecha_modificacion DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_auditoria),
    INDEX idx_auditoria_cliente (id_cliente),                      -- consultas por cliente
    INDEX idx_auditoria_fecha   (fecha_modificacion)               -- consultas por rango de fechas
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------
-- 2. Trigger AFTER UPDATE sobre Clientes
--    - OLD.campo = valor antes del UPDATE; NEW.campo = valor después.
--    - Se usa el operador <=> (comparación segura con NULL), porque con
--      "<>" una comparación contra NULL daría NULL y el cambio de
--      NULL -> valor (o valor -> NULL) no se detectaría.
--    - Cada campo se evalúa por separado: solo se inserta fila si ese
--      campo realmente cambió. Si el UPDATE toca otras columnas, o
--      reasigna el mismo valor, no se registra nada.
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_audit_cliente_after_update;

DELIMITER $$

CREATE TRIGGER trg_audit_cliente_after_update
AFTER UPDATE ON Clientes
FOR EACH ROW
BEGIN
    -- Cambio en el email
    IF NOT (OLD.email <=> NEW.email) THEN
        INSERT INTO Auditoria_Clientes
            (id_cliente, campo_modificado, valor_antiguo, valor_nuevo)
        VALUES
            (OLD.id_cliente, 'email', OLD.email, NEW.email);
    END IF;

    -- Cambio en la dirección de envío
    IF NOT (OLD.direccion_envio <=> NEW.direccion_envio) THEN
        INSERT INTO Auditoria_Clientes
            (id_cliente, campo_modificado, valor_antiguo, valor_nuevo)
        VALUES
            (OLD.id_cliente, 'direccion_envio', OLD.direccion_envio, NEW.direccion_envio);
    END IF;
END$$

DELIMITER ;

-- ---------------------------------------------------------------------
-- 3. Prueba rápida (opcional; descomenta para verificar)
-- ---------------------------------------------------------------------
-- UPDATE Clientes
--    SET email = 'nuevo@correo.com', direccion_envio = 'Calle 1 # 2-3'
--  WHERE id_cliente = 1;
--
-- SELECT * FROM Auditoria_Clientes WHERE id_cliente = 1 ORDER BY id_auditoria;
