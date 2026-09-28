-- =====================================================================
-- 03_Funciones.sql
-- 20 funciones definidas por el usuario (UDFs)
-- Requiere haber corrido antes 01_Esquema_y_Datos.sql
-- Si al crear funciones da error "binary logging" activa esto una vez:
--   SET GLOBAL log_bin_trust_function_creators = 1;
-- =====================================================================

USE ecommerce;

DELIMITER $$

-- 1. Calcula el monto total de una venta especifica
CREATE FUNCTION fn_CalcularTotalVenta(p_id_venta INT)
RETURNS DECIMAL(12,2)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total DECIMAL(12,2);
    SELECT COALESCE(SUM(cantidad * precio_unitario_congelado), 0)
    INTO v_total
    FROM detalle_ventas
    WHERE id_venta = p_id_venta;
    RETURN v_total;
END$$


-- 2. Valida si hay stock suficiente para un producto
CREATE FUNCTION fn_VerificarDisponibilidadStock(p_id_producto INT, p_cantidad INT)
RETURNS BOOLEAN
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_stock INT;
    SELECT stock INTO v_stock FROM productos WHERE id_producto = p_id_producto;
    RETURN v_stock IS NOT NULL AND v_stock >= p_cantidad;
END$$


-- 3. Devuelve el precio actual de un producto
CREATE FUNCTION fn_ObtenerPrecioProducto(p_id_producto INT)
RETURNS DECIMAL(10,2)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_precio DECIMAL(10,2);
    SELECT precio INTO v_precio FROM productos WHERE id_producto = p_id_producto;
    RETURN v_precio;
END$$


-- 4. Calcula la edad de un cliente a partir de su fecha de nacimiento
CREATE FUNCTION fn_CalcularEdadCliente(p_id_cliente INT)
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_edad INT;
    SELECT TIMESTAMPDIFF(YEAR, fecha_nacimiento, CURDATE())
    INTO v_edad
    FROM clientes
    WHERE id_cliente = p_id_cliente;
    RETURN v_edad;   -- NULL si el cliente no tiene fecha_nacimiento registrada
END$$


-- 5. Nombre y apellido de un cliente en formato estandarizado
CREATE FUNCTION fn_FormatearNombreCompleto(p_id_cliente INT)
RETURNS VARCHAR(410)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_resultado VARCHAR(410);
    SELECT CONCAT(
        UPPER(LEFT(nombre,1)), LOWER(SUBSTRING(nombre,2)), ' ',
        UPPER(LEFT(apellido,1)), LOWER(SUBSTRING(apellido,2))
    )
    INTO v_resultado
    FROM clientes
    WHERE id_cliente = p_id_cliente;
    RETURN v_resultado;
END$$


-- 6. VERDADERO si el cliente realizo su primera compra en los ultimos 30 dias
CREATE FUNCTION fn_EsClienteNuevo(p_id_cliente INT)
RETURNS BOOLEAN
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_primera_compra DATETIME;
    SELECT MIN(fecha_venta) INTO v_primera_compra
    FROM ventas
    WHERE id_cliente = p_id_cliente AND estado <> 'Cancelado';
    RETURN v_primera_compra IS NOT NULL
           AND v_primera_compra >= NOW() - INTERVAL 30 DAY;
END$$


-- 7. Costo de envio segun el peso total de los productos de una venta
--    Tarifa de ejemplo: costo base $8000 + $2500 por kg
CREATE FUNCTION fn_CalcularCostoEnvio(p_id_venta INT)
RETURNS DECIMAL(10,2)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_peso_total DECIMAL(10,3);
    DECLARE v_costo_base DECIMAL(10,2) DEFAULT 8000.00;
    DECLARE v_tarifa_kg DECIMAL(10,2) DEFAULT 2500.00;

    SELECT COALESCE(SUM(p.peso_kg * dv.cantidad), 0)
    INTO v_peso_total
    FROM detalle_ventas dv
    JOIN productos p ON p.id_producto = dv.id_producto
    WHERE dv.id_venta = p_id_venta;

    RETURN v_costo_base + (v_peso_total * v_tarifa_kg);
END$$


-- 8. Aplica un porcentaje de descuento a un monto dado
CREATE FUNCTION fn_AplicarDescuento(p_monto DECIMAL(12,2), p_pct DECIMAL(5,2))
RETURNS DECIMAL(12,2)
DETERMINISTIC
NO SQL
BEGIN
    IF p_pct < 0 OR p_pct > 100 THEN
        RETURN p_monto;
    END IF;
    RETURN ROUND(p_monto * (1 - p_pct / 100), 2);
END$$


-- 9. Fecha de la ultima compra de un cliente
CREATE FUNCTION fn_ObtenerUltimaFechaCompra(p_id_cliente INT)
RETURNS DATETIME
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_fecha DATETIME;
    SELECT MAX(fecha_venta) INTO v_fecha
    FROM ventas
    WHERE id_cliente = p_id_cliente AND estado <> 'Cancelado';
    RETURN v_fecha;
END$$


-- 10. Valida formato de correo electronico
CREATE FUNCTION fn_ValidarFormatoEmail(p_email VARCHAR(250))
RETURNS BOOLEAN
DETERMINISTIC
NO SQL
BEGIN
    RETURN p_email REGEXP '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$';
END$$


-- 11. Nombre de la categoria a partir del ID de un producto
CREATE FUNCTION fn_ObtenerNombreCategoria(p_id_producto INT)
RETURNS VARCHAR(100)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_nombre VARCHAR(100);
    SELECT c.nombre INTO v_nombre
    FROM productos p
    JOIN categorias c ON c.id_categoria = p.id_categoria
    WHERE p.id_producto = p_id_producto;
    RETURN v_nombre;
END$$


-- 12. Numero total de compras realizadas por un cliente
CREATE FUNCTION fn_ContarVentasCliente(p_id_cliente INT)
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total INT;
    SELECT COUNT(*) INTO v_total
    FROM ventas
    WHERE id_cliente = p_id_cliente AND estado <> 'Cancelado';
    RETURN v_total;
END$$


-- 13. Dias transcurridos desde la ultima compra de un cliente
CREATE FUNCTION fn_CalcularDiasDesdeUltimaCompra(p_id_cliente INT)
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_fecha DATETIME;
    SELECT MAX(fecha_venta) INTO v_fecha
    FROM ventas
    WHERE id_cliente = p_id_cliente AND estado <> 'Cancelado';
    IF v_fecha IS NULL THEN
        RETURN NULL;
    END IF;
    RETURN DATEDIFF(NOW(), v_fecha);
END$$


-- 14. Estado de lealtad (Bronce, Plata, Oro) segun gasto total
CREATE FUNCTION fn_DeterminarEstadoLealtad(p_id_cliente INT)
RETURNS VARCHAR(20)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_gasto DECIMAL(12,2);
    SELECT COALESCE(SUM(total), 0) INTO v_gasto
    FROM ventas
    WHERE id_cliente = p_id_cliente AND estado <> 'Cancelado';

    IF v_gasto >= 2000000 THEN
        RETURN 'Oro';
    ELSEIF v_gasto >= 500000 THEN
        RETURN 'Plata';
    ELSE
        RETURN 'Bronce';
    END IF;
END$$


-- 15. Genera un SKU unico basado en nombre y categoria
CREATE FUNCTION fn_GenerarSKU(p_nombre VARCHAR(70), p_id_categoria INT)
RETURNS VARCHAR(100)
DETERMINISTIC
NO SQL
BEGIN
    DECLARE v_prefijo VARCHAR(10);
    DECLARE v_sufijo VARCHAR(10);
    SET v_prefijo = UPPER(LEFT(REPLACE(p_nombre, ' ', ''), 5));
    SET v_sufijo = LPAD(FLOOR(RAND() * 99999), 5, '0');
    RETURN CONCAT('SKU-', LPAD(p_id_categoria, 3, '0'), '-', v_prefijo, '-', v_sufijo);
END$$
-- NOTA: RAND() hace que esta funcion NO sea realmente deterministica;
-- MySQL la acepta igual, pero si tu version es estricta con
-- DETERMINISTIC, cambia a NOT DETERMINISTIC.


-- 16. Calcula el IVA (19%) sobre el total de una venta
CREATE FUNCTION fn_CalcularIVA(p_monto DECIMAL(12,2))
RETURNS DECIMAL(12,2)
DETERMINISTIC
NO SQL
BEGIN
    RETURN ROUND(p_monto * 0.19, 2);
END$$


-- 17. Suma el stock de todos los productos de una categoria
CREATE FUNCTION fn_ObtenerStockTotalPorCategoria(p_id_categoria INT)
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_stock_total INT;
    SELECT COALESCE(SUM(stock), 0) INTO v_stock_total
    FROM productos
    WHERE id_categoria = p_id_categoria;
    RETURN v_stock_total;
END$$


-- 18. Fecha estimada de entrega segun la ciudad del cliente
CREATE FUNCTION fn_EstimarFechaEntrega(p_id_cliente INT)
RETURNS DATE
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_ciudad VARCHAR(100);
    DECLARE v_dias INT;
    SELECT ciudad INTO v_ciudad FROM clientes WHERE id_cliente = p_id_cliente;

    SET v_dias = CASE
        WHEN v_ciudad IN ('Bogota','Medellin','Cali') THEN 2
        WHEN v_ciudad IS NULL OR v_ciudad = '' THEN 7
        ELSE 5
    END;

    RETURN DATE_ADD(CURDATE(), INTERVAL v_dias DAY);
END$$


-- 19. Convierte un monto de COP a otra moneda usando tasa fija (tabla tasas_cambio)
CREATE FUNCTION fn_ConvertirMoneda(p_monto_cop DECIMAL(12,2), p_moneda_destino VARCHAR(3))
RETURNS DECIMAL(12,2)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_tasa DECIMAL(12,4);
    SELECT tasa_a_cop INTO v_tasa FROM tasas_cambio WHERE moneda = p_moneda_destino;
    IF v_tasa IS NULL OR v_tasa = 0 THEN
        RETURN NULL;
    END IF;
    RETURN ROUND(p_monto_cop / v_tasa, 2);
END$$


-- 20. Verifica que una contrasena cumpla criterios de seguridad:
--     min 8 caracteres, al menos 1 mayuscula, 1 minuscula, 1 digito, 1 caracter especial
CREATE FUNCTION fn_ValidarComplejidadContrasena(p_password VARCHAR(255))
RETURNS BOOLEAN
DETERMINISTIC
NO SQL
BEGIN
    IF LENGTH(p_password) < 8 THEN RETURN FALSE; END IF;
    IF p_password NOT REGEXP '[A-Z]' THEN RETURN FALSE; END IF;
    IF p_password NOT REGEXP '[a-z]' THEN RETURN FALSE; END IF;
    IF p_password NOT REGEXP '[0-9]' THEN RETURN FALSE; END IF;
    IF p_password NOT REGEXP '[^A-Za-z0-9]' THEN RETURN FALSE; END IF;
    RETURN TRUE;
END$$

DELIMITER ;

-- ---------------------------------------------------------------------
-- Ejemplos de uso (comentados):
-- SELECT fn_CalcularTotalVenta(1);
-- SELECT fn_VerificarDisponibilidadStock(5, 10);
-- SELECT fn_AplicarDescuento(100000, 15);
-- SELECT fn_ValidarFormatoEmail('correo@ejemplo.com');
-- SELECT fn_ValidarComplejidadContrasena('Clave123!');
-- ---------------------------------------------------------------------
