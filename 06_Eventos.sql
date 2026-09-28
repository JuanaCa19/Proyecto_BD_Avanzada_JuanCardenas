-- =====================================================================
-- 06_Eventos.sql
-- Tabla de reportes semanales + 20 eventos programados.
-- Requiere haber corrido antes: 01_Esquema_y_Datos.sql y 03_Funciones.sql
-- (algunos eventos usan fn_DeterminarEstadoLealtad).
--
-- El programador de eventos de MySQL esta APAGADO por defecto. Sin esto
-- ningun evento se ejecutara nunca, aunque este creado correctamente:
-- =====================================================================

SET GLOBAL event_scheduler = ON;

USE ecommerce;

-- ---------------------------------------------------------------------
-- Tabla de reportes para el evento #1 (reporte de ventas semanal)
-- ---------------------------------------------------------------------
CREATE TABLE reporte_ventas_semanales (
    id_reporte INT AUTO_INCREMENT PRIMARY KEY,
    fecha_inicio DATE NOT NULL,
    fecha_fin DATE NOT NULL,
    numero_ventas INT NOT NULL,
    ingresos_totales DECIMAL(14,2) NOT NULL,
    ticket_promedio DECIMAL(12,2) NOT NULL,
    fecha_generado DATETIME DEFAULT CURRENT_TIMESTAMP
);

DELIMITER $$

-- 1. Reporte de ventas semanal (se guarda como fila en kpis-like report;
--    aqui se resume en resumen_ventas_diario agregado por semana)
CREATE EVENT evt_generate_weekly_sales_report
ON SCHEDULE EVERY 1 WEEK STARTS '2026-01-05 02:00:00'
DO
    INSERT INTO reporte_ventas_semanales (fecha_inicio, fecha_fin, numero_ventas, ingresos_totales, ticket_promedio)
    SELECT
        CURDATE() - INTERVAL 7 DAY,
        CURDATE(),
        COUNT(*),
        COALESCE(SUM(total), 0),
        COALESCE(AVG(total), 0)
    FROM ventas
    WHERE fecha_venta >= CURDATE() - INTERVAL 7 DAY
      AND estado <> 'Cancelado'$$


-- 2. Limpiar tablas temporales/staging diariamente
CREATE EVENT evt_cleanup_temp_tables_daily
ON SCHEDULE EVERY 1 DAY STARTS '2026-01-01 03:00:00'
DO
    DELETE FROM tabla_temporal_staging
    WHERE fecha_creacion < NOW() - INTERVAL 1 DAY$$


-- 3. Archivar logs de mas de 6 meses (ejemplo con log_precios)
CREATE EVENT evt_archive_old_logs_monthly
ON SCHEDULE EVERY 1 MONTH STARTS '2026-01-01 03:30:00'
DO
    DELETE FROM log_precios
    WHERE fecha_cambio < NOW() - INTERVAL 6 MONTH$$
-- NOTA: idealmente esto primero INSERTa en una tabla log_precios_historico
-- antes de borrar. Se omite aqui por brevedad; el patron es el mismo que
-- usa trg_archive_deleted_venta (INSERT a tabla espejo, luego DELETE).


-- 4. Desactivar promociones expiradas cada hora
CREATE EVENT evt_deactivate_expired_promotions_hourly
ON SCHEDULE EVERY 1 HOUR STARTS '2026-01-01 00:00:00'
DO
    UPDATE promociones
    SET activa = FALSE
    WHERE fecha_fin < CURDATE() AND activa = TRUE$$


-- 5. Recalcular nivel de lealtad de todos los clientes cada noche
CREATE EVENT evt_recalculate_customer_loyalty_tiers_nightly
ON SCHEDULE EVERY 1 DAY STARTS '2026-01-01 01:00:00'
DO
    UPDATE clientes
    SET nivel_lealtad = fn_DeterminarEstadoLealtad(id_cliente)$$


-- 6. Lista diaria de productos que necesitan reabastecimiento
CREATE EVENT evt_generate_reorder_list_daily
ON SCHEDULE EVERY 1 DAY STARTS '2026-01-01 04:00:00'
DO
    INSERT INTO alertas_stock (id_producto, stock_actual)
    SELECT p.id_producto, p.stock
    FROM productos p
    WHERE p.stock < p.stock_minimo
      AND p.activo = TRUE
      AND NOT EXISTS (
          SELECT 1 FROM alertas_stock a
          WHERE a.id_producto = p.id_producto
            AND DATE(a.fecha_alerta) = CURDATE()
      )$$


-- 7. Reconstruir indices de las tablas mas usadas cada semana
CREATE EVENT evt_rebuild_indexes_weekly
ON SCHEDULE EVERY 1 WEEK STARTS '2026-01-05 02:30:00'
DO
    BEGIN
        OPTIMIZE TABLE productos;
        OPTIMIZE TABLE ventas;
        OPTIMIZE TABLE detalle_ventas;
        OPTIMIZE TABLE clientes;
    END$$


-- 8. Suspender cuentas inactivas hace mas de un ano, cada trimestre
CREATE EVENT evt_suspend_inactive_accounts_quarterly
ON SCHEDULE EVERY 3 MONTH STARTS '2026-01-01 05:00:00'
DO
    UPDATE clientes
    SET activo = FALSE
    WHERE activo = TRUE
      AND (
            (fecha_ultima_compra IS NOT NULL AND fecha_ultima_compra < NOW() - INTERVAL 1 YEAR)
         OR (fecha_ultima_compra IS NULL AND fecha_registro < NOW() - INTERVAL 1 YEAR)
      )$$


-- 9. Agregar los datos de ventas del dia en una tabla de resumen
CREATE EVENT evt_aggregate_daily_sales_data
ON SCHEDULE EVERY 1 DAY STARTS '2026-01-01 23:55:00'
DO
    INSERT INTO resumen_ventas_diario (fecha, numero_ventas, total_ventas)
    SELECT CURDATE(), COUNT(*), COALESCE(SUM(total), 0)
    FROM ventas
    WHERE DATE(fecha_venta) = CURDATE() AND estado <> 'Cancelado'
    ON DUPLICATE KEY UPDATE
        numero_ventas = VALUES(numero_ventas),
        total_ventas = VALUES(total_ventas)$$


-- 10. Buscar inconsistencias (ej. ventas sin detalle) cada noche
CREATE EVENT evt_check_data_consistency_nightly
ON SCHEDULE EVERY 1 DAY STARTS '2026-01-01 02:00:00'
DO
    INSERT INTO log_inconsistencias (descripcion, referencia_id)
    SELECT 'Venta sin ninguna linea de detalle', v.id_venta
    FROM ventas v
    LEFT JOIN detalle_ventas dv ON dv.id_venta = v.id_venta
    WHERE dv.id_detalle IS NULL$$


-- 11. Lista diaria de clientes que cumplen anos
CREATE EVENT evt_send_birthday_greetings_daily
ON SCHEDULE EVERY 1 DAY STARTS '2026-01-01 06:00:00'
DO
    INSERT INTO notificaciones_cumpleanos (id_cliente, fecha_generada)
    SELECT id_cliente, CURDATE()
    FROM clientes
    WHERE fecha_nacimiento IS NOT NULL
      AND MONTH(fecha_nacimiento) = MONTH(CURDATE())
      AND DAY(fecha_nacimiento) = DAY(CURDATE())$$
-- NOTA: MySQL no puede enviar correos por si mismo. Esta tabla queda
-- lista para que tu aplicacion/backend la lea y envie el cupon.


-- 12. Actualizar ranking de productos mas populares cada hora
CREATE EVENT evt_update_product_rankings_hourly
ON SCHEDULE EVERY 1 HOUR STARTS '2026-01-01 00:15:00'
DO
    BEGIN
        DELETE FROM ranking_productos;
        INSERT INTO ranking_productos (id_producto, unidades_vendidas_periodo, posicion)
        SELECT
            id_producto,
            unidades,
            ROW_NUMBER() OVER (ORDER BY unidades DESC)
        FROM (
            SELECT dv.id_producto, SUM(dv.cantidad) AS unidades
            FROM detalle_ventas dv
            JOIN ventas v ON v.id_venta = dv.id_venta
            WHERE v.fecha_venta >= NOW() - INTERVAL 30 DAY
            GROUP BY dv.id_producto
        ) t;
    END$$
-- Usa ROW_NUMBER() (MySQL 8.0+). En version sin funciones de ventana,
-- se puede reemplazar por una variable de sesion incremental (@n:=@n+1).


-- 13. "Backup" logico diario de tablas criticas
--     LIMITACION: un evento SQL NO puede ejecutar mysqldump ni tocar el
--     sistema de archivos. Un backup real se agenda por fuera de MySQL
--     (cron + mysqldump, o Percona XtraBackup). Aqui solo se deja
--     constancia en una bitacora, y se copian filas a tablas espejo
--     como aproximacion de "backup logico" dentro de la misma BD.
CREATE EVENT evt_backup_critical_tables_daily
ON SCHEDULE EVERY 1 DAY STARTS '2026-01-01 01:30:00'
DO
    INSERT INTO backups_log (tablas, estado)
    VALUES ('productos,clientes,ventas,detalle_ventas', 'PENDIENTE_EJECUCION_EXTERNA')$$
-- Programa el backup real fuera de MySQL, por ejemplo en cron:
-- 30 1 * * * mysqldump -u backup_user -p ecommerce > /backups/ecommerce_$(date +\%F).sql


-- 14. Vaciar carritos abandonados hace mas de 72 horas
CREATE EVENT evt_clear_abandoned_carts_daily
ON SCHEDULE EVERY 1 DAY STARTS '2026-01-01 03:15:00'
DO
    BEGIN
        UPDATE carritos
        SET estado = 'Abandonado'
        WHERE estado = 'Activo'
          AND fecha_creacion < NOW() - INTERVAL 72 HOUR;

        DELETE ci FROM carrito_items ci
        JOIN carritos c ON c.id_carrito = ci.id_carrito
        WHERE c.estado = 'Abandonado';
    END$$


-- 15. Calcular KPIs del mes y guardarlos
CREATE EVENT evt_calculate_monthly_kpis
ON SCHEDULE EVERY 1 MONTH STARTS '2026-02-01 00:30:00'
DO
    INSERT INTO kpis_mensuales (anio, mes, ventas_totales, numero_ventas, nuevos_clientes, ticket_promedio)
    SELECT
        YEAR(CURDATE() - INTERVAL 1 MONTH),
        MONTH(CURDATE() - INTERVAL 1 MONTH),
        COALESCE(SUM(v.total), 0),
        COUNT(v.id_venta),
        (SELECT COUNT(*) FROM clientes
         WHERE YEAR(fecha_registro) = YEAR(CURDATE() - INTERVAL 1 MONTH)
           AND MONTH(fecha_registro) = MONTH(CURDATE() - INTERVAL 1 MONTH)),
        COALESCE(AVG(v.total), 0)
    FROM ventas v
    WHERE YEAR(v.fecha_venta) = YEAR(CURDATE() - INTERVAL 1 MONTH)
      AND MONTH(v.fecha_venta) = MONTH(CURDATE() - INTERVAL 1 MONTH)
      AND v.estado <> 'Cancelado'
    ON DUPLICATE KEY UPDATE
        ventas_totales = VALUES(ventas_totales),
        numero_ventas = VALUES(numero_ventas),
        nuevos_clientes = VALUES(nuevos_clientes),
        ticket_promedio = VALUES(ticket_promedio),
        fecha_calculo = NOW()$$


-- 16. "Actualizar vistas materializadas"
--     LIMITACION: MySQL no tiene vistas materializadas nativas (a
--     diferencia de PostgreSQL/Oracle). Se simula con una tabla resumen
--     que se trunca y se vuelve a poblar -- resumen_ventas_diario ya
--     cumple ese rol; este evento la refresca completa cada noche.
CREATE EVENT evt_refresh_materialized_views_nightly
ON SCHEDULE EVERY 1 DAY STARTS '2026-01-01 02:45:00'
DO
    BEGIN
        TRUNCATE TABLE resumen_ventas_diario;
        INSERT INTO resumen_ventas_diario (fecha, numero_ventas, total_ventas)
        SELECT DATE(fecha_venta), COUNT(*), SUM(total)
        FROM ventas
        WHERE estado <> 'Cancelado'
        GROUP BY DATE(fecha_venta);
    END$$


-- 17. Registrar el tamano de la base de datos cada semana
CREATE EVENT evt_log_database_size_weekly
ON SCHEDULE EVERY 1 WEEK STARTS '2026-01-05 04:00:00'
DO
    INSERT INTO tamano_bd_historico (tamano_mb)
    SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2)
    FROM information_schema.tables
    WHERE table_schema = 'ecommerce'$$


-- 18. Detectar actividad sospechosa cada hora
--     Regla de ejemplo: un cliente con 3+ ventas canceladas en la ultima hora
CREATE EVENT evt_detect_fraudulent_activity_hourly
ON SCHEDULE EVERY 1 HOUR STARTS '2026-01-01 00:05:00'
DO
    INSERT INTO actividad_sospechosa (id_cliente, motivo)
    SELECT id_cliente, CONCAT(COUNT(*), ' ventas canceladas en la ultima hora')
    FROM ventas
    WHERE estado = 'Cancelado'
      AND fecha_venta >= NOW() - INTERVAL 1 HOUR
    GROUP BY id_cliente
    HAVING COUNT(*) >= 3$$


-- 19. Reporte mensual de rendimiento de proveedores
CREATE EVENT evt_generate_supplier_performance_report_monthly
ON SCHEDULE EVERY 1 MONTH STARTS '2026-02-01 01:00:00'
DO
    INSERT INTO reporte_proveedores_mensual (anio, mes, id_proveedor, unidades_vendidas, ingresos_generados)
    SELECT
        YEAR(CURDATE() - INTERVAL 1 MONTH),
        MONTH(CURDATE() - INTERVAL 1 MONTH),
        pr.id_proveedor,
        COALESCE(SUM(dv.cantidad), 0),
        COALESCE(SUM(dv.cantidad * dv.precio_unitario_congelado), 0)
    FROM proveedores pr
    JOIN productos p ON p.id_proveedor = pr.id_proveedor
    LEFT JOIN detalle_ventas dv ON dv.id_producto = p.id_producto
    LEFT JOIN ventas v ON v.id_venta = dv.id_venta
        AND YEAR(v.fecha_venta) = YEAR(CURDATE() - INTERVAL 1 MONTH)
        AND MONTH(v.fecha_venta) = MONTH(CURDATE() - INTERVAL 1 MONTH)
    GROUP BY pr.id_proveedor$$


-- 20. Purgar registros marcados para borrado hace mas de 30 dias
--     Ejemplo con clientes.eliminado (ver sp_EliminarClienteDeFormaSegura,
--     que en la practica anonimiza en vez de marcar para borrado; este
--     evento cubre el caso en que si se use el flag "eliminado").
CREATE EVENT evt_purge_soft_deleted_records_weekly
ON SCHEDULE EVERY 1 WEEK STARTS '2026-01-05 05:00:00'
DO
    UPDATE clientes
    SET anonimizado = TRUE,
        nombre = 'Cliente', apellido = 'Eliminado',
        email = CONCAT('purgado_', id_cliente, '@anon.local'),
        direccion_envio = NULL
    WHERE eliminado = TRUE
      AND fecha_marcado_borrado < NOW() - INTERVAL 30 DAY
      AND anonimizado = FALSE$$
-- NOTA: no se hace DELETE fisico porque clientes esta referenciado por
-- ventas (integridad referencial); por eso "purgar" aqui significa
-- anonimizar de forma irreversible, no borrar la fila.

DELIMITER ;
