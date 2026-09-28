-- =====================================================================
-- 02_Consultas_Avanzadas.sql
-- 20 consultas de analisis y reporteo sobre la base de datos ecommerce.
-- Requiere haber ejecutado antes 01_Esquema_y_Datos.sql.
--
-- Motor objetivo: MySQL 8.0+ (se usan las funciones de ventana NTILE y
-- LAG en las preguntas 2, 17, 19 y 20, escritas con subconsultas
-- anidadas en vez de WITH/CTE. NTILE y LAG no existen en MySQL < 8.0
-- ni en MariaDB < 10.2).
-- =====================================================================

USE ecommerce;


-- ---------------------------------------------------------------------
-- 1. TOP 10 PRODUCTOS MAS VENDIDOS (por ingresos generados)
-- ---------------------------------------------------------------------
SELECT
    p.id_producto,
    p.nombre,
    SUM(dv.cantidad)                              AS unidades_vendidas,
    SUM(dv.cantidad * dv.precio_unitario_congelado) AS ingresos_totales
FROM detalle_ventas dv
JOIN productos p ON p.id_producto = dv.id_producto
GROUP BY p.id_producto, p.nombre
ORDER BY ingresos_totales DESC
LIMIT 10;


-- ---------------------------------------------------------------------
-- 2. PRODUCTOS CON BAJAS VENTAS (10% inferior, incluye productos sin
--    ninguna venta, ya que son los primeros candidatos a descontinuar)
-- ---------------------------------------------------------------------
SELECT id_producto, nombre, unidades_vendidas
FROM (
    SELECT
        vp.*,
        NTILE(10) OVER (ORDER BY unidades_vendidas ASC) AS decil
    FROM (
        SELECT
            p.id_producto,
            p.nombre,
            COALESCE(SUM(dv.cantidad), 0) AS unidades_vendidas
        FROM productos p
        LEFT JOIN detalle_ventas dv ON dv.id_producto = p.id_producto
        GROUP BY p.id_producto, p.nombre
    ) vp
) ranked
WHERE decil = 1
ORDER BY unidades_vendidas ASC;


-- ---------------------------------------------------------------------
-- 3. CLIENTES VIP: Top 5 por LTV (gasto total historico)
-- ---------------------------------------------------------------------
SELECT
    c.id_cliente,
    c.nombre,
    c.apellido,
    SUM(v.total) AS gasto_total
FROM clientes c
JOIN ventas v ON v.id_cliente = c.id_cliente
WHERE v.estado <> 'Cancelado'
GROUP BY c.id_cliente, c.nombre, c.apellido
ORDER BY gasto_total DESC
LIMIT 5;


-- ---------------------------------------------------------------------
-- 4. ANALISIS DE VENTAS MENSUALES
-- ---------------------------------------------------------------------
SELECT
    YEAR(fecha_venta)  AS anio,
    MONTH(fecha_venta) AS mes,
    COUNT(*)           AS numero_ventas,
    SUM(total)         AS ingresos_totales
FROM ventas
WHERE estado <> 'Cancelado'
GROUP BY YEAR(fecha_venta), MONTH(fecha_venta)
ORDER BY anio, mes;


-- ---------------------------------------------------------------------
-- 5. CRECIMIENTO DE CLIENTES: nuevos clientes por trimestre
-- ---------------------------------------------------------------------
SELECT
    YEAR(fecha_registro)    AS anio,
    QUARTER(fecha_registro) AS trimestre,
    COUNT(*)                AS nuevos_clientes
FROM clientes
GROUP BY YEAR(fecha_registro), QUARTER(fecha_registro)
ORDER BY anio, trimestre;


-- ---------------------------------------------------------------------
-- 6. TASA DE COMPRA REPETIDA
-- ---------------------------------------------------------------------
SELECT
    COUNT(*)                                                     AS total_clientes_con_compra,
    SUM(CASE WHEN num_compras > 1 THEN 1 ELSE 0 END)              AS clientes_recurrentes,
    ROUND(100 * SUM(CASE WHEN num_compras > 1 THEN 1 ELSE 0 END)
          / COUNT(*), 2)                                          AS pct_recurrentes
FROM (
    SELECT id_cliente, COUNT(*) AS num_compras
    FROM ventas
    WHERE estado <> 'Cancelado'
    GROUP BY id_cliente
) t;


-- ---------------------------------------------------------------------
-- 7. PRODUCTOS COMPRADOS JUNTOS FRECUENTEMENTE (market basket, pares)
-- ---------------------------------------------------------------------
SELECT
    p1.nombre AS producto_a,
    p2.nombre AS producto_b,
    COUNT(*)  AS veces_juntos
FROM detalle_ventas dv1
JOIN detalle_ventas dv2
    ON dv1.id_venta = dv2.id_venta
   AND dv1.id_producto < dv2.id_producto   -- evita pares duplicados/espejo
JOIN productos p1 ON p1.id_producto = dv1.id_producto
JOIN productos p2 ON p2.id_producto = dv2.id_producto
GROUP BY dv1.id_producto, dv2.id_producto, p1.nombre, p2.nombre
ORDER BY veces_juntos DESC
LIMIT 20;


-- ---------------------------------------------------------------------
-- 8. ROTACION DE INVENTARIO POR CATEGORIA
--    Rotacion aproximada = unidades vendidas / stock actual total.
--    NOTA: la formula "correcta" de rotacion usa el inventario PROMEDIO
--    en el periodo, no el stock actual; como no guardamos historial de
--    stock, se usa el stock actual como aproximacion.
-- ---------------------------------------------------------------------
SELECT
    cat.id_categoria,
    cat.nombre                                              AS categoria,
    COALESCE(SUM(dv.cantidad), 0)                           AS unidades_vendidas,
    SUM(p.stock)                                             AS stock_actual_total,
    ROUND(COALESCE(SUM(dv.cantidad), 0) / NULLIF(SUM(p.stock), 0), 2) AS rotacion_aproximada
FROM categorias cat
JOIN productos p ON p.id_categoria = cat.id_categoria
LEFT JOIN detalle_ventas dv ON dv.id_producto = p.id_producto
GROUP BY cat.id_categoria, cat.nombre
ORDER BY rotacion_aproximada DESC;


-- ---------------------------------------------------------------------
-- 9. PRODUCTOS QUE NECESITAN REABASTECIMIENTO
-- ---------------------------------------------------------------------
SELECT id_producto, nombre, stock, stock_minimo
FROM productos
WHERE activo = TRUE
  AND stock < stock_minimo
ORDER BY stock ASC;


-- ---------------------------------------------------------------------
-- 10. ANALISIS DE CARRITO ABANDONADO (SIMULADO)
--    No hace falta una tabla de carritos: se puede "simular" el
--    abandono con lo que ya existe: una venta que quedo en
--    'Pendiente de Pago' y ya paso mas de 1 dia desde que se creo se
--    trata como si el cliente hubiera abandonado el proceso de compra.
-- ---------------------------------------------------------------------
SELECT
    v.id_venta,
    c.id_cliente,
    c.nombre,
    c.apellido,
    v.fecha_venta,
    v.total,
    DATEDIFF(NOW(), v.fecha_venta) AS dias_pendiente
FROM ventas v
JOIN clientes c ON c.id_cliente = v.id_cliente
WHERE v.estado = 'Pendiente de Pago'
  AND v.fecha_venta < NOW() - INTERVAL 1 DAY
ORDER BY v.fecha_venta ASC;


-- ---------------------------------------------------------------------
-- 11. RENDIMIENTO DE PROVEEDORES (por volumen de ventas de sus productos)
-- ---------------------------------------------------------------------
SELECT
    pr.id_proveedor,
    pr.nombre                                                     AS proveedor,
    COUNT(DISTINCT dv.id_venta)                                   AS ventas_distintas,
    COALESCE(SUM(dv.cantidad), 0)                                 AS unidades_vendidas,
    COALESCE(SUM(dv.cantidad * dv.precio_unitario_congelado), 0)  AS ingresos_generados
FROM proveedores pr
JOIN productos p ON p.id_proveedor = pr.id_proveedor
LEFT JOIN detalle_ventas dv ON dv.id_producto = p.id_producto
GROUP BY pr.id_proveedor, pr.nombre
ORDER BY ingresos_generados DESC;


-- ---------------------------------------------------------------------
-- 12. ANALISIS GEOGRAFICO DE VENTAS
-- ---------------------------------------------------------------------
SELECT
    c.ciudad,
    COUNT(DISTINCT v.id_venta) AS numero_ventas,
    SUM(v.total)               AS ingresos_totales
FROM clientes c
JOIN ventas v ON v.id_cliente = c.id_cliente
WHERE v.estado <> 'Cancelado'
GROUP BY c.ciudad
ORDER BY ingresos_totales DESC;


-- ---------------------------------------------------------------------
-- 13. VENTAS POR HORA DEL DIA (horas pico)
-- ---------------------------------------------------------------------
SELECT
    HOUR(fecha_venta) AS hora_del_dia,
    COUNT(*)           AS numero_ventas,
    SUM(total)         AS ingresos_totales
FROM ventas
WHERE estado <> 'Cancelado'
GROUP BY HOUR(fecha_venta)
ORDER BY hora_del_dia;


-- ---------------------------------------------------------------------
-- 14. IMPACTO DE PROMOCIONES (antes / durante / despues)
--    Usa la tabla promociones (creada en 01_Esquema_y_Datos.sql).
--    Reemplaza el id_producto por el que quieras analizar.
-- ---------------------------------------------------------------------
SELECT
    CASE
        WHEN v.fecha_venta < pr.fecha_inicio THEN 'Antes'
        WHEN v.fecha_venta BETWEEN pr.fecha_inicio AND pr.fecha_fin THEN 'Durante'
        ELSE 'Despues'
    END AS periodo,
    SUM(dv.cantidad) AS unidades_vendidas
FROM detalle_ventas dv
JOIN ventas v ON v.id_venta = dv.id_venta
JOIN promociones pr ON pr.id_producto = dv.id_producto
WHERE dv.id_producto = (SELECT id_producto FROM promociones LIMIT 1)  -- <-- ajustar segun necesidad
GROUP BY periodo;


-- ---------------------------------------------------------------------
-- 15. ANALISIS DE COHORT (retencion mes a mes desde la primera compra)
-- ---------------------------------------------------------------------
SELECT
    mes_cohort,
    mes_relativo,
    COUNT(DISTINCT id_cliente) AS clientes_activos
FROM (
    SELECT
        v.id_cliente,
        pc.mes_cohort,
        TIMESTAMPDIFF(
            MONTH,
            pc.mes_cohort,
            DATE_FORMAT(v.fecha_venta, '%Y-%m-01')
        ) AS mes_relativo
    FROM ventas v
    JOIN (
        SELECT
            id_cliente,
            DATE_FORMAT(MIN(fecha_venta), '%Y-%m-01') AS mes_cohort
        FROM ventas
        WHERE estado <> 'Cancelado'
        GROUP BY id_cliente
    ) pc ON pc.id_cliente = v.id_cliente
    WHERE v.estado <> 'Cancelado'
) compras
GROUP BY mes_cohort, mes_relativo
ORDER BY mes_cohort, mes_relativo;


-- ---------------------------------------------------------------------
-- 16. MARGEN DE BENEFICIO POR PRODUCTO
--    (productos.costo ya existe en el esquema, no hace falta agregarlo)
-- ---------------------------------------------------------------------
SELECT
    id_producto,
    nombre,
    precio,
    costo,
    (precio - costo)                          AS margen_absoluto,
    ROUND(100 * (precio - costo) / precio, 2) AS margen_porcentual
FROM productos
ORDER BY margen_porcentual DESC;


-- ---------------------------------------------------------------------
-- 17. TIEMPO PROMEDIO ENTRE COMPRAS (por cliente y global)
-- ---------------------------------------------------------------------
-- Promedio por cliente:
SELECT
    id_cliente,
    ROUND(AVG(dias_entre_compras), 1) AS dias_promedio_entre_compras
FROM (
    SELECT
        id_cliente,
        TIMESTAMPDIFF(DAY, compra_anterior, fecha_venta) AS dias_entre_compras
    FROM (
        SELECT
            id_cliente,
            fecha_venta,
            LAG(fecha_venta) OVER (PARTITION BY id_cliente ORDER BY fecha_venta) AS compra_anterior
        FROM ventas
        WHERE estado <> 'Cancelado'
    ) compras_ordenadas
    WHERE compra_anterior IS NOT NULL
) dias_por_cliente
GROUP BY id_cliente
ORDER BY dias_promedio_entre_compras;

-- Promedio global de la tienda (ejecutar por separado):
-- SELECT ROUND(AVG(dias_entre_compras), 1) AS promedio_global_dias
-- FROM (
--     SELECT
--         TIMESTAMPDIFF(DAY, compra_anterior, fecha_venta) AS dias_entre_compras
--     FROM (
--         SELECT
--             fecha_venta,
--             LAG(fecha_venta) OVER (PARTITION BY id_cliente ORDER BY fecha_venta) AS compra_anterior
--         FROM ventas
--         WHERE estado <> 'Cancelado'
--     ) compras_ordenadas
--     WHERE compra_anterior IS NOT NULL
-- ) dias_por_cliente;


-- ---------------------------------------------------------------------
-- 18. PRODUCTOS MAS VISTOS VS. MAS COMPRADOS
--    Usa la tabla vistas_producto (creada y poblada en 01_Esquema_y_Datos.sql).
-- ---------------------------------------------------------------------
SELECT
    p.id_producto,
    p.nombre,
    COUNT(DISTINCT vp.id_vista)            AS numero_vistas,
    COALESCE(SUM(dv.cantidad), 0)          AS unidades_compradas,
    ROUND(100 * COALESCE(SUM(dv.cantidad),0) / NULLIF(COUNT(DISTINCT vp.id_vista),0), 2)
                                            AS tasa_conversion_pct
FROM productos p
LEFT JOIN vistas_producto vp ON vp.id_producto = p.id_producto
LEFT JOIN detalle_ventas dv ON dv.id_producto = p.id_producto
GROUP BY p.id_producto, p.nombre
ORDER BY numero_vistas DESC;


-- ---------------------------------------------------------------------
-- 19. SEGMENTACION DE CLIENTES (RFM: Recencia, Frecuencia, Monetario)
-- ---------------------------------------------------------------------
SELECT
    id_cliente,
    recencia_dias,
    frecuencia,
    monetario,
    r_score,
    f_score,
    m_score,
    (r_score + f_score + m_score) AS rfm_total,
    CASE
        WHEN (r_score + f_score + m_score) >= 13 THEN 'Campeon'
        WHEN (r_score + f_score + m_score) >= 10 THEN 'Leal'
        WHEN (r_score + f_score + m_score) >= 7  THEN 'Potencial'
        ELSE 'En riesgo'
    END AS segmento
FROM (
    SELECT
        id_cliente,
        recencia_dias,
        frecuencia,
        monetario,
        NTILE(5) OVER (ORDER BY recencia_dias DESC) AS r_score,  -- menos dias = mejor score
        NTILE(5) OVER (ORDER BY frecuencia ASC)     AS f_score,
        NTILE(5) OVER (ORDER BY monetario ASC)      AS m_score
    FROM (
        SELECT
            c.id_cliente,
            DATEDIFF(CURDATE(), MAX(v.fecha_venta)) AS recencia_dias,
            COUNT(v.id_venta)                       AS frecuencia,
            SUM(v.total)                            AS monetario
        FROM clientes c
        JOIN ventas v ON v.id_cliente = c.id_cliente
        WHERE v.estado <> 'Cancelado'
        GROUP BY c.id_cliente
    ) rfm_base
) rfm_scores
ORDER BY rfm_total DESC;


-- ---------------------------------------------------------------------
-- 20. PREDICCION DE DEMANDA SIMPLE (promedio movil por categoria)
--    Proyecta el proximo mes como el promedio historico mensual de
--    unidades vendidas para una categoria especifica.
-- ---------------------------------------------------------------------
SELECT
    id_categoria,
    categoria,
    ROUND(AVG(unidades_vendidas), 1) AS promedio_mensual_historico,
    ROUND(AVG(unidades_vendidas), 0) AS proyeccion_proximo_mes
FROM (
    SELECT
        cat.id_categoria,
        cat.nombre                            AS categoria,
        DATE_FORMAT(v.fecha_venta, '%Y-%m')   AS anio_mes,
        SUM(dv.cantidad)                      AS unidades_vendidas
    FROM ventas v
    JOIN detalle_ventas dv ON dv.id_venta = v.id_venta
    JOIN productos p ON p.id_producto = dv.id_producto
    JOIN categorias cat ON cat.id_categoria = p.id_categoria
    WHERE v.estado <> 'Cancelado'
    GROUP BY cat.id_categoria, cat.nombre, DATE_FORMAT(v.fecha_venta, '%Y-%m')
) ventas_categoria_mes
WHERE id_categoria = 1              -- <-- reemplazar por la categoria de interes
GROUP BY id_categoria, categoria;
