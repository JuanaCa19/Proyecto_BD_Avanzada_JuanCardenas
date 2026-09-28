-- =====================================================================
-- 07_Procedimientos_Almacenados.sql
-- 20 procedimientos almacenados.
-- Requiere haber corrido 01_Esquema_y_Datos.sql y 03_Funciones.sql.
--
-- IMPORTANTE: aunque este es el archivo #7 en la carpeta, se ejecuta
-- ANTES que 04_Seguridad.sql, porque el punto 6.12 de seguridad
-- (GRANT EXECUTE ON PROCEDURE sp_GenerarReporteMensualVentas) necesita
-- que el procedimiento ya exista. Ver README.md para el orden completo.
-- =====================================================================

USE ecommerce;

DELIMITER $$

-- ---------------------------------------------------------------------
-- 1. sp_RealizarNuevaVenta: procesa una venta completa de forma
--    transaccional a partir de un JSON de items:
--    '[{"id_producto":1,"cantidad":2}, {"id_producto":5,"cantidad":1}]'
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_RealizarNuevaVenta(
    IN p_id_cliente INT,
    IN p_items_json JSON,
    OUT p_id_venta INT
)
proc: BEGIN
    DECLARE v_i INT DEFAULT 0;
    DECLARE v_total_items INT;
    DECLARE v_id_producto INT;
    DECLARE v_cantidad INT;
    DECLARE v_precio DECIMAL(10,2);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    INSERT INTO ventas (id_cliente, estado, total) VALUES (p_id_cliente, 'Pendiente de Pago', 0);
    SET p_id_venta = LAST_INSERT_ID();

    SET v_total_items = JSON_LENGTH(p_items_json);

    WHILE v_i < v_total_items DO
        SET v_id_producto = JSON_UNQUOTE(JSON_EXTRACT(p_items_json, CONCAT('$[', v_i, '].id_producto')));
        SET v_cantidad     = JSON_UNQUOTE(JSON_EXTRACT(p_items_json, CONCAT('$[', v_i, '].cantidad')));
        SET v_precio       = fn_ObtenerPrecioProducto(v_id_producto);

        INSERT INTO detalle_ventas (id_producto, id_venta, cantidad, precio_unitario_congelado)
        VALUES (v_id_producto, p_id_venta, v_cantidad, v_precio);
        -- Los triggers trg_check_stock_before_insert_venta,
        -- trg_update_stock_after_insert_venta y
        -- trg_recalculate_total_venta_on_detalle_ins hacen el resto.

        SET v_i = v_i + 1;
    END WHILE;

    COMMIT;
END$$


-- ---------------------------------------------------------------------
-- 2. sp_AgregarNuevoProducto
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_AgregarNuevoProducto(
    IN p_id_categoria INT,
    IN p_id_proveedor INT,
    IN p_nombre VARCHAR(70),
    IN p_descripcion TEXT,
    IN p_precio DECIMAL(10,2),
    IN p_costo DECIMAL(10,2),
    IN p_stock INT,
    IN p_peso_kg DECIMAL(8,3)
)
BEGIN
    DECLARE v_sku VARCHAR(100);
    SET v_sku = fn_GenerarSKU(p_nombre, p_id_categoria);

    INSERT INTO productos (
        id_categoria, id_proveedor, nombre, descripcion,
        precio, costo, stock, sku, peso_kg, activo
    ) VALUES (
        p_id_categoria, p_id_proveedor, p_nombre, p_descripcion,
        p_precio, p_costo, p_stock, v_sku, p_peso_kg, TRUE
    );
END$$


-- ---------------------------------------------------------------------
-- 3. sp_ActualizarDireccionCliente
--    (direccion_envio y ciudad viven solo en clientes; no hay otra
--     tabla que la duplique en este esquema)
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_ActualizarDireccionCliente(
    IN p_id_cliente INT,
    IN p_direccion_envio VARCHAR(200),
    IN p_ciudad VARCHAR(100)
)
BEGIN
    UPDATE clientes
    SET direccion_envio = p_direccion_envio,
        ciudad = p_ciudad
    WHERE id_cliente = p_id_cliente;
END$$


-- ---------------------------------------------------------------------
-- 4. sp_ProcesarDevolucion
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_ProcesarDevolucion(
    IN p_id_detalle INT,
    IN p_motivo VARCHAR(255)
)
proc: BEGIN
    DECLARE v_id_producto INT;
    DECLARE v_id_venta INT;
    DECLARE v_cantidad INT;
    DECLARE v_precio DECIMAL(10,2);
    DECLARE v_id_cliente INT;
    DECLARE v_monto DECIMAL(12,2);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SELECT id_producto, id_venta, cantidad, precio_unitario_congelado
    INTO v_id_producto, v_id_venta, v_cantidad, v_precio
    FROM detalle_ventas
    WHERE id_detalle = p_id_detalle;

    IF v_id_producto IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El detalle de venta indicado no existe';
    END IF;

    SELECT id_cliente INTO v_id_cliente FROM ventas WHERE id_venta = v_id_venta;
    SET v_monto = v_cantidad * v_precio;

    START TRANSACTION;

    UPDATE productos SET stock = stock + v_cantidad WHERE id_producto = v_id_producto;

    INSERT INTO creditos_cliente (id_cliente, monto, motivo)
    VALUES (v_id_cliente, v_monto, p_motivo);

    INSERT INTO log_ajustes_stock (id_producto, delta, motivo, usuario)
    VALUES (v_id_producto, v_cantidad, CONCAT('Devolucion: ', p_motivo), CURRENT_USER());

    COMMIT;
END$$


-- ---------------------------------------------------------------------
-- 5. sp_ObtenerHistorialComprasCliente
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_ObtenerHistorialComprasCliente(IN p_id_cliente INT)
BEGIN
    SELECT
        v.id_venta,
        v.fecha_venta,
        v.estado,
        v.total,
        p.nombre AS producto,
        dv.cantidad,
        dv.precio_unitario_congelado
    FROM ventas v
    JOIN detalle_ventas dv ON dv.id_venta = v.id_venta
    JOIN productos p ON p.id_producto = dv.id_producto
    WHERE v.id_cliente = p_id_cliente
    ORDER BY v.fecha_venta DESC;
END$$


-- ---------------------------------------------------------------------
-- 6. sp_AjustarNivelStock
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_AjustarNivelStock(
    IN p_id_producto INT,
    IN p_delta INT,
    IN p_motivo VARCHAR(255)
)
BEGIN
    UPDATE productos SET stock = stock + p_delta WHERE id_producto = p_id_producto;

    INSERT INTO log_ajustes_stock (id_producto, delta, motivo, usuario)
    VALUES (p_id_producto, p_delta, p_motivo, CURRENT_USER());
END$$


-- ---------------------------------------------------------------------
-- 7. sp_EliminarClienteDeFormaSegura (anonimiza en vez de borrar)
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_EliminarClienteDeFormaSegura(IN p_id_cliente INT)
BEGIN
    UPDATE clientes
    SET nombre = 'Cliente',
        apellido = 'Eliminado',
        email = CONCAT('eliminado_', p_id_cliente, '@anon.local'),
        contrasena = '',
        direccion_envio = NULL,
        ciudad = '',
        anonimizado = TRUE,
        activo = FALSE
    WHERE id_cliente = p_id_cliente;

    INSERT INTO log_clientes (id_cliente, accion, detalle)
    VALUES (p_id_cliente, 'ANONIMIZADO', 'Cliente anonimizado por solicitud de eliminacion segura');
END$$


-- ---------------------------------------------------------------------
-- 8. sp_AplicarDescuentoPorCategoria
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_AplicarDescuentoPorCategoria(
    IN p_id_categoria INT,
    IN p_pct DECIMAL(5,2)
)
BEGIN
    IF p_pct < 0 OR p_pct >= 100 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El porcentaje de descuento debe estar entre 0 y 100';
    END IF;

    UPDATE productos
    SET precio = fn_AplicarDescuento(precio, p_pct)
    WHERE id_categoria = p_id_categoria;
END$$


-- ---------------------------------------------------------------------
-- 9. sp_GenerarReporteMensualVentas
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_GenerarReporteMensualVentas(
    IN p_anio INT,
    IN p_mes INT
)
BEGIN
    SELECT
        COUNT(*) AS numero_ventas,
        COALESCE(SUM(total), 0) AS ingresos_totales,
        COALESCE(AVG(total), 0) AS ticket_promedio
    FROM ventas
    WHERE YEAR(fecha_venta) = p_anio
      AND MONTH(fecha_venta) = p_mes
      AND estado <> 'Cancelado';
END$$


-- ---------------------------------------------------------------------
-- 10. sp_CambiarEstadoPedido
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_CambiarEstadoPedido(
    IN p_id_venta INT,
    IN p_nuevo_estado VARCHAR(30)
)
BEGIN
    UPDATE ventas
    SET estado = p_nuevo_estado
    WHERE id_venta = p_id_venta;
    -- trg_log_order_status_change registra el cambio automaticamente.
    -- "Notificar a otros sistemas" queda fuera del alcance de SQL puro;
    -- normalmente se hace desde la aplicacion escuchando este cambio.
END$$


-- ---------------------------------------------------------------------
-- 11. sp_RegistrarNuevoCliente
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_RegistrarNuevoCliente(
    IN p_nombre VARCHAR(200),
    IN p_apellido VARCHAR(200),
    IN p_email VARCHAR(250),
    IN p_contrasena_hash VARCHAR(500),
    IN p_direccion_envio VARCHAR(200)
)
BEGIN
    IF EXISTS (SELECT 1 FROM clientes WHERE email = p_email) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Ya existe un cliente registrado con ese email';
    END IF;

    INSERT INTO clientes (nombre, apellido, email, contrasena, direccion_envio)
    VALUES (p_nombre, p_apellido, p_email, p_contrasena_hash, p_direccion_envio);
END$$


-- ---------------------------------------------------------------------
-- 12. sp_ObtenerDetallesProductoCompleto
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_ObtenerDetallesProductoCompleto(IN p_id_producto INT)
BEGIN
    SELECT
        p.*,
        c.nombre AS categoria,
        pr.nombre AS proveedor,
        pr.email_contacto AS proveedor_email
    FROM productos p
    JOIN categorias c ON c.id_categoria = p.id_categoria
    JOIN proveedores pr ON pr.id_proveedor = p.id_proveedor
    WHERE p.id_producto = p_id_producto;
END$$


-- ---------------------------------------------------------------------
-- 13. sp_FusionarCuentasCliente
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_FusionarCuentasCliente(
    IN p_id_cliente_mantener INT,
    IN p_id_cliente_duplicado INT
)
proc: BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF p_id_cliente_mantener = p_id_cliente_duplicado THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No se puede fusionar un cliente consigo mismo';
    END IF;

    START TRANSACTION;

    UPDATE ventas SET id_cliente = p_id_cliente_mantener WHERE id_cliente = p_id_cliente_duplicado;

    UPDATE clientes
    SET total_gastado = total_gastado + (
        SELECT total_gastado FROM clientes WHERE id_cliente = p_id_cliente_duplicado
    )
    WHERE id_cliente = p_id_cliente_mantener;

    CALL sp_EliminarClienteDeFormaSegura(p_id_cliente_duplicado);

    COMMIT;
END$$


-- ---------------------------------------------------------------------
-- 14. sp_AsignarProductoAProveedor
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_AsignarProductoAProveedor(
    IN p_id_producto INT,
    IN p_id_proveedor INT
)
BEGIN
    UPDATE productos
    SET id_proveedor = p_id_proveedor
    WHERE id_producto = p_id_producto;
END$$


-- ---------------------------------------------------------------------
-- 15. sp_BuscarProductos (filtros opcionales: pasa NULL para ignorarlos)
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_BuscarProductos(
    IN p_nombre VARCHAR(70),
    IN p_id_categoria INT,
    IN p_precio_min DECIMAL(10,2),
    IN p_precio_max DECIMAL(10,2)
)
BEGIN
    SELECT p.*, c.nombre AS categoria
    FROM productos p
    JOIN categorias c ON c.id_categoria = p.id_categoria
    WHERE p.activo = TRUE
      AND (p_nombre IS NULL OR p.nombre LIKE CONCAT('%', p_nombre, '%'))
      AND (p_id_categoria IS NULL OR p.id_categoria = p_id_categoria)
      AND (p_precio_min IS NULL OR p.precio >= p_precio_min)
      AND (p_precio_max IS NULL OR p.precio <= p_precio_max)
    ORDER BY p.nombre;
END$$


-- ---------------------------------------------------------------------
-- 16. sp_ObtenerDashboardAdmin
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_ObtenerDashboardAdmin()
BEGIN
    SELECT
        (SELECT COUNT(*) FROM ventas WHERE DATE(fecha_venta) = CURDATE() AND estado <> 'Cancelado') AS ventas_hoy,
        (SELECT COALESCE(SUM(total),0) FROM ventas WHERE DATE(fecha_venta) = CURDATE() AND estado <> 'Cancelado') AS ingresos_hoy,
        (SELECT COUNT(*) FROM clientes WHERE DATE(fecha_registro) = CURDATE()) AS nuevos_clientes_hoy,
        (SELECT COUNT(*) FROM productos WHERE stock < stock_minimo AND activo = TRUE) AS productos_bajo_stock,
        (SELECT COUNT(*) FROM ventas WHERE estado = 'Pendiente de Pago') AS pedidos_pendientes_pago;
END$$


-- ---------------------------------------------------------------------
-- 17. sp_ProcesarPago (simulado: marca la venta como Pagado)
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_ProcesarPago(
    IN p_id_venta INT,
    IN p_metodo_pago VARCHAR(50)
)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM ventas WHERE id_venta = p_id_venta AND estado = 'Pendiente de Pago') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La venta no existe o ya no esta pendiente de pago';
    END IF;

    UPDATE ventas
    SET estado = 'Pagado',
        metodo_pago = p_metodo_pago,
        fecha_pago = NOW()
    WHERE id_venta = p_id_venta;
END$$


-- ---------------------------------------------------------------------
-- 18. sp_AñadirReseñaProducto
--     Solo permite resenar productos que el cliente realmente compro.
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_AnadirResenaProducto(
    IN p_id_producto INT,
    IN p_id_cliente INT,
    IN p_calificacion TINYINT,
    IN p_comentario VARCHAR(1000)
)
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM detalle_ventas dv
        JOIN ventas v ON v.id_venta = dv.id_venta
        WHERE dv.id_producto = p_id_producto
          AND v.id_cliente = p_id_cliente
          AND v.estado NOT IN ('Cancelado', 'Pendiente de Pago')
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Solo puedes resenar productos que hayas comprado';
    END IF;

    INSERT INTO resenas (id_producto, id_cliente, calificacion, comentario)
    VALUES (p_id_producto, p_id_cliente, p_calificacion, p_comentario);
END$$
-- NOTA: el nombre original pedia la enie (sp_AñadirReseñaProducto).
-- Se evita por seguridad de codificacion entre distintos clientes SQL;
-- si tu motor y consola manejan UTF-8 sin problema, puedes renombrarlo
-- de vuelta con: RENAME ... o simplemente CREATE con el nombre original.


-- ---------------------------------------------------------------------
-- 19. sp_ObtenerProductosRelacionados (market basket, top 5)
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_ObtenerProductosRelacionados(IN p_id_producto INT)
BEGIN
    SELECT
        p2.id_producto,
        p2.nombre,
        COUNT(*) AS veces_comprado_junto
    FROM detalle_ventas dv1
    JOIN detalle_ventas dv2
        ON dv1.id_venta = dv2.id_venta
       AND dv1.id_producto <> dv2.id_producto
    JOIN productos p2 ON p2.id_producto = dv2.id_producto
    WHERE dv1.id_producto = p_id_producto
    GROUP BY p2.id_producto, p2.nombre
    ORDER BY veces_comprado_junto DESC
    LIMIT 5;
END$$


-- ---------------------------------------------------------------------
-- 20. sp_MoverProductosEntreCategorias
--     p_ids_producto: lista separada por comas, ej. '1,5,12,20'
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_MoverProductosEntreCategorias(
    IN p_ids_producto VARCHAR(1000),
    IN p_id_categoria_destino INT
)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM categorias WHERE id_categoria = p_id_categoria_destino) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La categoria de destino no existe';
    END IF;

    UPDATE productos
    SET id_categoria = p_id_categoria_destino
    WHERE FIND_IN_SET(id_producto, p_ids_producto) > 0;
END$$

DELIMITER ;

-- ---------------------------------------------------------------------
-- Ejemplos de uso (comentados):
-- CALL sp_RegistrarNuevoCliente('Ana','Ruiz','ana.ruiz@mail.com','hash123','Calle 10 #5-20, Cali');
-- CALL sp_BuscarProductos('camiseta', NULL, 20000, 100000);
-- CALL sp_ObtenerDashboardAdmin();
-- SET @id_venta = 0;
-- CALL sp_RealizarNuevaVenta(1, '[{"id_producto":3,"cantidad":2}]', @id_venta);
-- SELECT @id_venta;
-- ---------------------------------------------------------------------
