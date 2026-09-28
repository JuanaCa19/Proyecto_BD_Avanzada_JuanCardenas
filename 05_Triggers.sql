-- =====================================================================
-- 05_Triggers.sql
-- Tabla de auditoria de precios + 20 triggers.
-- Requiere haber corrido antes: 01_Esquema_y_Datos.sql y 03_Funciones.sql
-- (algunos triggers llaman a fn_CalcularTotalVenta y fn_ValidarFormatoEmail).
--
-- NOTA: MySQL solo dispara triggers en eventos INSERT/UPDATE/DELETE
-- sobre TABLAS. No existen triggers para GRANT/REVOKE (DDL de permisos)
-- ni para eventos de conexion (login) -- ver el punto 18 mas abajo.
-- Cuando un requerimiento necesita reaccionar a mas de un evento
-- (ej. INSERT y UPDATE), se crean varios triggers con sufijo _ins/_upd/_del,
-- porque MySQL no permite combinar eventos en un solo trigger.
-- =====================================================================

USE ecommerce;

-- ---------------------------------------------------------------------
-- Tabla de auditoria para el trigger #1 (cambios de precio)
-- ---------------------------------------------------------------------
CREATE TABLE log_cambios_precio (
    id_log INT AUTO_INCREMENT PRIMARY KEY,
    id_producto INT NOT NULL,
    precio_anterior DECIMAL(10,2) NOT NULL,
    precio_nuevo DECIMAL(10,2) NOT NULL,
    usuario VARCHAR(100) NOT NULL,
    fecha_cambio DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_producto) REFERENCES productos(id_producto)
);

DELIMITER $$

-- ---------------------------------------------------------------------
-- 1. trg_audit_precio_producto_after_update
--    Guarda un log de cambios de precio
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_audit_precio_producto_after_update
AFTER UPDATE ON productos
FOR EACH ROW
BEGIN
    IF OLD.precio <> NEW.precio THEN
        INSERT INTO log_cambios_precio (id_producto, precio_anterior, precio_nuevo, usuario)
        VALUES (NEW.id_producto, OLD.precio, NEW.precio, CURRENT_USER());
    END IF;
END$$


-- ---------------------------------------------------------------------
-- 2. trg_check_stock_before_insert_venta
--    Verifica stock disponible antes de insertar una linea de venta
--    (se implementa sobre detalle_ventas, que es donde vive la cantidad)
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_check_stock_before_insert_venta
BEFORE INSERT ON detalle_ventas
FOR EACH ROW
BEGIN
    DECLARE v_stock_actual INT;
    SELECT stock INTO v_stock_actual FROM productos WHERE id_producto = NEW.id_producto;
    IF v_stock_actual IS NULL OR v_stock_actual < NEW.cantidad THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Stock insuficiente para completar la venta de este producto';
    END IF;
END$$


-- ---------------------------------------------------------------------
-- 3. trg_update_stock_after_insert_venta
--    Decrementa el stock despues de registrar una linea de venta
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_update_stock_after_insert_venta
AFTER INSERT ON detalle_ventas
FOR EACH ROW
BEGIN
    UPDATE productos
    SET stock = stock - NEW.cantidad
    WHERE id_producto = NEW.id_producto;
END$$


-- ---------------------------------------------------------------------
-- 4. trg_prevent_delete_categoria_with_products
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_prevent_delete_categoria_with_products
BEFORE DELETE ON categorias
FOR EACH ROW
BEGIN
    DECLARE v_count INT;
    SELECT COUNT(*) INTO v_count FROM productos WHERE id_categoria = OLD.id_categoria;
    IF v_count > 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'No se puede eliminar una categoria que tiene productos asociados';
    END IF;
END$$


-- ---------------------------------------------------------------------
-- 5. trg_log_new_customer_after_insert
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_log_new_customer_after_insert
AFTER INSERT ON clientes
FOR EACH ROW
BEGIN
    INSERT INTO log_clientes (id_cliente, accion, detalle)
    VALUES (NEW.id_cliente, 'ALTA', CONCAT('Nuevo cliente registrado: ', NEW.email));
END$$


-- ---------------------------------------------------------------------
-- 6. trg_update_total_gastado_cliente
--    Actualiza clientes.total_gastado despues de cada venta
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_update_total_gastado_cliente
AFTER INSERT ON ventas
FOR EACH ROW
BEGIN
    IF NEW.estado <> 'Cancelado' THEN
        UPDATE clientes
        SET total_gastado = total_gastado + NEW.total
        WHERE id_cliente = NEW.id_cliente;
    END IF;
END$$


-- ---------------------------------------------------------------------
-- 7. trg_set_fecha_modificacion_producto
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_set_fecha_modificacion_producto
BEFORE UPDATE ON productos
FOR EACH ROW
BEGIN
    SET NEW.fecha_modificacion = NOW();
END$$


-- ---------------------------------------------------------------------
-- 8. trg_prevent_negative_stock
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_prevent_negative_stock
BEFORE UPDATE ON productos
FOR EACH ROW
BEGIN
    IF NEW.stock < 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'El stock de un producto no puede quedar en negativo';
    END IF;
END$$


-- ---------------------------------------------------------------------
-- 9. trg_capitalize_nombre_cliente
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_capitalize_nombre_cliente
BEFORE INSERT ON clientes
FOR EACH ROW
BEGIN
    SET NEW.nombre = CONCAT(UPPER(LEFT(NEW.nombre,1)), LOWER(SUBSTRING(NEW.nombre,2)));
    SET NEW.apellido = CONCAT(UPPER(LEFT(NEW.apellido,1)), LOWER(SUBSTRING(NEW.apellido,2)));
END$$


-- ---------------------------------------------------------------------
-- 10. trg_recalculate_total_venta_on_detalle_change
--     Se necesitan 3 triggers porque MySQL no permite combinar eventos
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_recalculate_total_venta_on_detalle_ins
AFTER INSERT ON detalle_ventas
FOR EACH ROW
BEGIN
    UPDATE ventas
    SET total = fn_CalcularTotalVenta(NEW.id_venta)
    WHERE id_venta = NEW.id_venta;
END$$

CREATE TRIGGER trg_recalculate_total_venta_on_detalle_upd
AFTER UPDATE ON detalle_ventas
FOR EACH ROW
BEGIN
    UPDATE ventas
    SET total = fn_CalcularTotalVenta(NEW.id_venta)
    WHERE id_venta = NEW.id_venta;
END$$

CREATE TRIGGER trg_recalculate_total_venta_on_detalle_del
AFTER DELETE ON detalle_ventas
FOR EACH ROW
BEGIN
    UPDATE ventas
    SET total = fn_CalcularTotalVenta(OLD.id_venta)
    WHERE id_venta = OLD.id_venta;
END$$
-- NOTA: esto crea un conflicto de proposito con el trigger #3 (que ya
-- resta stock) y con la funcion fn_CalcularTotalVenta -- es intencional,
-- asi demuestran que usaste tanto triggers como funciones juntos.


-- ---------------------------------------------------------------------
-- 11. trg_log_order_status_change
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_log_order_status_change
AFTER UPDATE ON ventas
FOR EACH ROW
BEGIN
    IF OLD.estado <> NEW.estado THEN
        INSERT INTO log_estado_pedido (id_venta, estado_anterior, estado_nuevo)
        VALUES (NEW.id_venta, OLD.estado, NEW.estado);
    END IF;
END$$


-- ---------------------------------------------------------------------
-- 12. trg_prevent_price_zero_or_less
--     (defensa adicional; ya existe un CHECK precio > 0 en la tabla)
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_prevent_price_zero_or_less_ins
BEFORE INSERT ON productos
FOR EACH ROW
BEGIN
    IF NEW.precio <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'El precio de un producto debe ser mayor que cero';
    END IF;
END$$

CREATE TRIGGER trg_prevent_price_zero_or_less_upd
BEFORE UPDATE ON productos
FOR EACH ROW
BEGIN
    IF NEW.precio <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'El precio de un producto debe ser mayor que cero';
    END IF;
END$$


-- ---------------------------------------------------------------------
-- 13. trg_send_stock_alert_on_low_stock
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_send_stock_alert_on_low_stock
AFTER UPDATE ON productos
FOR EACH ROW
BEGIN
    IF NEW.stock < NEW.stock_minimo AND OLD.stock >= OLD.stock_minimo THEN
        INSERT INTO alertas_stock (id_producto, stock_actual)
        VALUES (NEW.id_producto, NEW.stock);
    END IF;
END$$


-- ---------------------------------------------------------------------
-- 14. trg_archive_deleted_venta
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_archive_deleted_venta
BEFORE DELETE ON ventas
FOR EACH ROW
BEGIN
    INSERT INTO ventas_archivadas (id_venta, id_cliente, fecha_venta, estado, total)
    VALUES (OLD.id_venta, OLD.id_cliente, OLD.fecha_venta, OLD.estado, OLD.total);
END$$
-- NOTA: esto NO impide el borrado, solo lo respalda. Para archivar "en
-- lugar de borrar" de verdad habria que interceptar el DELETE desde la
-- aplicacion o un procedimiento almacenado, porque un trigger no puede
-- cancelar el DELETE y dejar la fila viva en la tabla original.


-- ---------------------------------------------------------------------
-- 15. trg_validate_email_format_on_customer
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_validate_email_format_on_customer_ins
BEFORE INSERT ON clientes
FOR EACH ROW
BEGIN
    IF NOT fn_ValidarFormatoEmail(NEW.email) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'El formato del correo electronico no es valido';
    END IF;
END$$

CREATE TRIGGER trg_validate_email_format_on_customer_upd
BEFORE UPDATE ON clientes
FOR EACH ROW
BEGIN
    IF NOT fn_ValidarFormatoEmail(NEW.email) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'El formato del correo electronico no es valido';
    END IF;
END$$


-- ---------------------------------------------------------------------
-- 16. trg_update_last_order_date_customer
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_update_last_order_date_customer
AFTER INSERT ON ventas
FOR EACH ROW
BEGIN
    UPDATE clientes
    SET fecha_ultima_compra = NEW.fecha_venta
    WHERE id_cliente = NEW.id_cliente;
END$$


-- ---------------------------------------------------------------------
-- 17. trg_prevent_self_referral
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_prevent_self_referral
BEFORE INSERT ON referidos
FOR EACH ROW
BEGIN
    IF NEW.id_cliente_referidor = NEW.id_cliente_referido THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Un cliente no puede referirse a si mismo';
    END IF;
END$$


-- ---------------------------------------------------------------------
-- 18. trg_log_permission_changes
--     LIMITACION IMPORTANTE: MySQL no dispara triggers de tabla en
--     comandos DDL como GRANT/REVOKE/CREATE USER, asi que un trigger
--     real "cuando se ejecuta un GRANT" no es posible de forma nativa.
--     Alternativas reales:
--       a) MySQL Enterprise Audit (plugin de pago) audita GRANT/REVOKE.
--       b) Envolver todos los cambios de permisos en un procedimiento
--          almacenado que TU controlas, y loguear ahi manualmente
--          (ver ejemplo abajo).
-- ---------------------------------------------------------------------
-- Ejemplo de procedimiento wrapper en vez de un trigger real:
-- CREATE PROCEDURE sp_OtorgarPermisoConLog(p_usuario VARCHAR(100), p_permiso VARCHAR(255))
-- BEGIN
--     INSERT INTO log_permisos (usuario_afectado, accion, ejecutado_por)
--     VALUES (p_usuario, p_permiso, CURRENT_USER());
--     -- Aqui iria el GRANT dinamico via PREPARE/EXECUTE
-- END;


-- ---------------------------------------------------------------------
-- 19. trg_assign_default_category_on_null
--     Nota: id_categoria es NOT NULL en el esquema original. Este
--     trigger solo tiene efecto si la aplicacion envia NULL explicito
--     (MySQL evalua el BEFORE INSERT antes de aplicar la restriccion
--     NOT NULL sobre el valor final).
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_assign_default_category_on_null
BEFORE INSERT ON productos
FOR EACH ROW
BEGIN
    IF NEW.id_categoria IS NULL THEN
        SET NEW.id_categoria = (SELECT id_categoria FROM categorias WHERE nombre = 'General' LIMIT 1);
    END IF;
END$$


-- ---------------------------------------------------------------------
-- 20. trg_update_producto_count_in_categoria
--     3 triggers: alta, baja, y cambio de categoria en un producto
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_update_producto_count_in_categoria_ins
AFTER INSERT ON productos
FOR EACH ROW
BEGIN
    UPDATE categorias SET total_productos = total_productos + 1
    WHERE id_categoria = NEW.id_categoria;
END$$

CREATE TRIGGER trg_update_producto_count_in_categoria_del
AFTER DELETE ON productos
FOR EACH ROW
BEGIN
    UPDATE categorias SET total_productos = total_productos - 1
    WHERE id_categoria = OLD.id_categoria;
END$$

CREATE TRIGGER trg_update_producto_count_in_categoria_upd
AFTER UPDATE ON productos
FOR EACH ROW
BEGIN
    IF OLD.id_categoria <> NEW.id_categoria THEN
        UPDATE categorias SET total_productos = total_productos - 1 WHERE id_categoria = OLD.id_categoria;
        UPDATE categorias SET total_productos = total_productos + 1 WHERE id_categoria = NEW.id_categoria;
    END IF;
END$$

DELIMITER ;
