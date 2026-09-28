-- =====================================================================
-- 01_Esquema_y_Datos.sql
-- Estructura completa de la base de datos ecommerce + datos de ejemplo.
--
-- Incluye TODAS las tablas del proyecto excepto dos, que se crean en su
-- propio archivo porque ahi es donde se usan por primera vez:
--   - log_cambios_precio   -> se crea en 05_Triggers.sql
--   - reporte_ventas_semanales -> se crea en 06_Eventos.sql
--
-- ORDEN DE EJECUCION DEL PROYECTO COMPLETO (ver README.md):
--   1) 01_Esquema_y_Datos.sql              <- este archivo
--   2) 02_Consultas_Avanzadas.sql
--   3) 03_Funciones.sql
--   4) 07_Procedimientos_Almacenados.sql   <- correrlo antes que el 04
--   5) 04_Seguridad.sql
--   6) 05_Triggers.sql
--   7) 06_Eventos.sql
--
-- Se insertan los datos ANTES de crear los triggers a proposito: si los
-- triggers ya existieran, cada INSERT masivo dispararia recalculos que
-- chocarian con los valores que este script ya calcula a mano (stock,
-- totales, contadores). Los triggers deben nacer sobre datos ya limpios.
-- =====================================================================

DROP DATABASE IF EXISTS ecommerce;
CREATE DATABASE ecommerce;
USE ecommerce;

-- ---------- TABLAS PRINCIPALES ----------

CREATE TABLE categorias(
    id_categoria INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL UNIQUE,
    descripcion TEXT,
    total_productos INT NOT NULL DEFAULT 0
);


CREATE TABLE proveedores(
    id_proveedor INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(150) NOT NULL,
    email_contacto VARCHAR(250) UNIQUE,
    telefono_contacto VARCHAR(15)
);


CREATE TABLE sucursales(
    id_sucursal INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    ciudad VARCHAR(100) NOT NULL
);


CREATE TABLE productos(
    id_producto INT AUTO_INCREMENT PRIMARY KEY,
    id_categoria INT NOT NULL,
    id_proveedor INT NOT NULL,
    nombre VARCHAR(70) NOT NULL UNIQUE,
    descripcion TEXT,
    precio DECIMAL(10,2) NOT NULL CHECK (precio > 0),
    costo DECIMAL(10,2) NOT NULL CHECK (costo >= 0),
    stock INT NOT NULL DEFAULT 0 CHECK (stock >= 0),
    stock_minimo INT NOT NULL DEFAULT 5,
    peso_kg DECIMAL(8,3) NOT NULL DEFAULT 0.500,
    ubicacion VARCHAR(100),
    sku VARCHAR(100) NOT NULL UNIQUE,
    fecha_creacion DATETIME NOT NULL,
    fecha_modificacion DATETIME NULL,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    FOREIGN KEY (id_categoria) REFERENCES categorias(id_categoria) ON DELETE RESTRICT ON UPDATE CASCADE,
    FOREIGN KEY (id_proveedor) REFERENCES proveedores(id_proveedor) ON DELETE RESTRICT ON UPDATE CASCADE
);


CREATE TABLE clientes(
    id_cliente INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(200) NOT NULL,
    apellido VARCHAR(200) NOT NULL,
    email VARCHAR(250) UNIQUE NOT NULL,
    contrasena VARCHAR(500) NOT NULL,
    direccion_envio VARCHAR(200),
    ciudad VARCHAR(100) NOT NULL DEFAULT '',
    fecha_nacimiento DATE NULL,
    fecha_registro DATETIME NOT NULL,
    fecha_ultima_compra DATETIME NULL,
    total_gastado DECIMAL(12,2) NOT NULL DEFAULT 0,
    nivel_lealtad VARCHAR(20) NOT NULL DEFAULT 'Bronce',
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    anonimizado BOOLEAN NOT NULL DEFAULT FALSE,
    eliminado BOOLEAN NOT NULL DEFAULT FALSE,
    fecha_marcado_borrado DATETIME NULL
);


CREATE TABLE usuarios_sucursal(
    usuario_bd VARCHAR(100) PRIMARY KEY,
    id_sucursal INT NOT NULL,
    FOREIGN KEY (id_sucursal) REFERENCES sucursales(id_sucursal)
);


CREATE TABLE ventas(
    id_venta INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente INT NOT NULL,
    id_sucursal INT NULL,
    fecha_venta DATETIME NOT NULL,
    estado ENUM('Pendiente de Pago','Pagado','Procesando','Enviado','Entregado','Cancelado') NOT NULL,
    metodo_pago VARCHAR(50) NULL,
    fecha_pago DATETIME NULL,
    total DECIMAL(12,2) NOT NULL DEFAULT 0,
    FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente) ON DELETE RESTRICT ON UPDATE CASCADE,
    FOREIGN KEY (id_sucursal) REFERENCES sucursales(id_sucursal) ON DELETE SET NULL ON UPDATE CASCADE
);


CREATE TABLE detalle_ventas(
    id_detalle INT AUTO_INCREMENT PRIMARY KEY,
    id_producto INT NOT NULL,
    id_venta INT NOT NULL,
    cantidad INT NOT NULL CHECK (cantidad > 0),
    precio_unitario_congelado DECIMAL(10,2) NOT NULL CHECK (precio_unitario_congelado > 0),
    FOREIGN KEY (id_producto) REFERENCES productos(id_producto) ON DELETE RESTRICT ON UPDATE CASCADE,
    FOREIGN KEY (id_venta) REFERENCES ventas(id_venta) ON DELETE RESTRICT ON UPDATE CASCADE
);

-- ---------- TABLAS DE SOPORTE (funciones/triggers/eventos/procedimientos) ----------

CREATE TABLE log_clientes(
    id_log INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente INT NOT NULL,
    accion VARCHAR(50) NOT NULL,
    detalle VARCHAR(255),
    fecha DATETIME DEFAULT CURRENT_TIMESTAMP
);


CREATE TABLE log_estado_pedido(
    id_log INT AUTO_INCREMENT PRIMARY KEY,
    id_venta INT NOT NULL,
    estado_anterior VARCHAR(30) NOT NULL,
    estado_nuevo VARCHAR(30) NOT NULL,
    fecha_cambio DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_venta) REFERENCES ventas(id_venta)
);


CREATE TABLE log_permisos(
    id_log INT AUTO_INCREMENT PRIMARY KEY,
    usuario_afectado VARCHAR(100) NOT NULL,
    accion VARCHAR(255) NOT NULL,
    ejecutado_por VARCHAR(100) NOT NULL,
    fecha DATETIME DEFAULT CURRENT_TIMESTAMP
);


CREATE TABLE log_intentos_login(
    id_log INT AUTO_INCREMENT PRIMARY KEY,
    usuario VARCHAR(100) NOT NULL,
    exito BOOLEAN NOT NULL,
    ip_origen VARCHAR(45),
    fecha DATETIME DEFAULT CURRENT_TIMESTAMP
);


CREATE TABLE log_ajustes_stock(
    id_log INT AUTO_INCREMENT PRIMARY KEY,
    id_producto INT NOT NULL,
    delta INT NOT NULL,
    motivo VARCHAR(255) NOT NULL,
    usuario VARCHAR(100) NOT NULL,
    fecha DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_producto) REFERENCES productos(id_producto)
);


CREATE TABLE alertas_stock(
    id_alerta INT AUTO_INCREMENT PRIMARY KEY,
    id_producto INT NOT NULL,
    stock_actual INT NOT NULL,
    fecha_alerta DATETIME DEFAULT CURRENT_TIMESTAMP,
    atendida BOOLEAN NOT NULL DEFAULT FALSE,
    FOREIGN KEY (id_producto) REFERENCES productos(id_producto)
);


CREATE TABLE ventas_archivadas(
    id_venta INT NOT NULL,
    id_cliente INT NOT NULL,
    fecha_venta DATETIME,
    estado VARCHAR(30),
    total DECIMAL(12,2),
    fecha_eliminacion DATETIME DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_venta)
);


CREATE TABLE promociones(
    id_promocion INT AUTO_INCREMENT PRIMARY KEY,
    id_producto INT NOT NULL,
    fecha_inicio DATE NOT NULL,
    fecha_fin DATE NOT NULL,
    descuento_pct DECIMAL(5,2) NOT NULL,
    activa BOOLEAN NOT NULL DEFAULT TRUE,
    FOREIGN KEY (id_producto) REFERENCES productos(id_producto)
);


CREATE TABLE carritos(
    id_carrito INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente INT NOT NULL,
    fecha_creacion DATETIME NOT NULL,
    estado ENUM('Activo','Convertido','Abandonado') NOT NULL DEFAULT 'Activo',
    FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente)
);


CREATE TABLE carrito_items(
    id_item INT AUTO_INCREMENT PRIMARY KEY,
    id_carrito INT NOT NULL,
    id_producto INT NOT NULL,
    cantidad INT NOT NULL,
    fecha_agregado DATETIME NOT NULL,
    FOREIGN KEY (id_carrito) REFERENCES carritos(id_carrito),
    FOREIGN KEY (id_producto) REFERENCES productos(id_producto)
);


CREATE TABLE resenas(
    id_resena INT AUTO_INCREMENT PRIMARY KEY,
    id_producto INT NOT NULL,
    id_cliente INT NOT NULL,
    calificacion TINYINT NOT NULL,
    comentario VARCHAR(1000),
    fecha DATETIME NOT NULL,
    FOREIGN KEY (id_producto) REFERENCES productos(id_producto),
    FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente),
    CHECK (calificacion BETWEEN 1 AND 5)
);


CREATE TABLE referidos(
    id_referido INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente_referidor INT NOT NULL,
    id_cliente_referido INT NOT NULL,
    fecha DATETIME NOT NULL,
    FOREIGN KEY (id_cliente_referidor) REFERENCES clientes(id_cliente),
    FOREIGN KEY (id_cliente_referido) REFERENCES clientes(id_cliente)
);


CREATE TABLE vistas_producto(
    id_vista INT AUTO_INCREMENT PRIMARY KEY,
    id_producto INT NOT NULL,
    id_cliente INT NULL,
    fecha_vista DATETIME NOT NULL,
    FOREIGN KEY (id_producto) REFERENCES productos(id_producto),
    FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente)
);


CREATE TABLE kpis_mensuales(
    id_kpi INT AUTO_INCREMENT PRIMARY KEY,
    anio INT NOT NULL,
    mes INT NOT NULL,
    ventas_totales DECIMAL(14,2) NOT NULL,
    numero_ventas INT NOT NULL,
    nuevos_clientes INT NOT NULL,
    ticket_promedio DECIMAL(12,2) NOT NULL,
    fecha_calculo DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_kpi_periodo (anio, mes)
);


CREATE TABLE ranking_productos(
    id_producto INT PRIMARY KEY,
    unidades_vendidas_periodo INT NOT NULL,
    posicion INT NOT NULL,
    fecha_actualizacion DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_producto) REFERENCES productos(id_producto)
);


CREATE TABLE tasas_cambio(
    moneda VARCHAR(3) PRIMARY KEY,
    tasa_a_cop DECIMAL(12,4) NOT NULL,
    fecha_actualizacion DATETIME DEFAULT CURRENT_TIMESTAMP
);


CREATE TABLE creditos_cliente(
    id_credito INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente INT NOT NULL,
    monto DECIMAL(12,2) NOT NULL,
    motivo VARCHAR(255) NOT NULL,
    usado BOOLEAN NOT NULL DEFAULT FALSE,
    fecha DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente)
);


CREATE TABLE resumen_ventas_diario(
    fecha DATE PRIMARY KEY,
    numero_ventas INT NOT NULL,
    total_ventas DECIMAL(14,2) NOT NULL
);


CREATE TABLE log_inconsistencias(
    id_log INT AUTO_INCREMENT PRIMARY KEY,
    descripcion VARCHAR(255) NOT NULL,
    referencia_id INT,
    fecha DATETIME DEFAULT CURRENT_TIMESTAMP
);


CREATE TABLE notificaciones_cumpleanos(
    id_notificacion INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente INT NOT NULL,
    fecha_generada DATE NOT NULL,
    enviada BOOLEAN NOT NULL DEFAULT FALSE,
    FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente)
);


CREATE TABLE tamano_bd_historico(
    id_registro INT AUTO_INCREMENT PRIMARY KEY,
    fecha DATETIME DEFAULT CURRENT_TIMESTAMP,
    tamano_mb DECIMAL(12,2) NOT NULL
);


CREATE TABLE actividad_sospechosa(
    id_registro INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente INT NOT NULL,
    motivo VARCHAR(255) NOT NULL,
    fecha DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente)
);


CREATE TABLE reporte_proveedores_mensual(
    id_reporte INT AUTO_INCREMENT PRIMARY KEY,
    anio INT NOT NULL,
    mes INT NOT NULL,
    id_proveedor INT NOT NULL,
    unidades_vendidas INT NOT NULL,
    ingresos_generados DECIMAL(14,2) NOT NULL,
    fecha_generado DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_proveedor) REFERENCES proveedores(id_proveedor)
);


CREATE TABLE backups_log(
    id_backup INT AUTO_INCREMENT PRIMARY KEY,
    tablas VARCHAR(500) NOT NULL,
    fecha DATETIME DEFAULT CURRENT_TIMESTAMP,
    estado VARCHAR(30) NOT NULL
);


CREATE TABLE tabla_temporal_staging(
    id INT AUTO_INCREMENT PRIMARY KEY,
    contenido VARCHAR(255),
    fecha_creacion DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- ---------- DATOS: CATEGORIAS (50 + 'General' de respaldo) ----------
INSERT INTO categorias (nombre, descripcion) VALUES
('Electronica', 'Productos relacionados con electronica.'),
('Ropa Hombre', 'Productos relacionados con ropa hombre.'),
('Ropa Mujer', 'Productos relacionados con ropa mujer.'),
('Calzado', 'Productos relacionados con calzado.'),
('Hogar', 'Productos relacionados con hogar.'),
('Cocina', 'Productos relacionados con cocina.'),
('Muebles', 'Productos relacionados con muebles.'),
('Jardineria', 'Productos relacionados con jardineria.'),
('Deportes', 'Productos relacionados con deportes.'),
('Juguetes', 'Productos relacionados con juguetes.'),
('Libros', 'Productos relacionados con libros.'),
('Papeleria', 'Productos relacionados con papeleria.'),
('Belleza', 'Productos relacionados con belleza.'),
('Cuidado Personal', 'Productos relacionados con cuidado personal.'),
('Salud', 'Productos relacionados con salud.'),
('Mascotas', 'Productos relacionados con mascotas.'),
('Automotriz', 'Productos relacionados con automotriz.'),
('Herramientas', 'Productos relacionados con herramientas.'),
('Musica', 'Productos relacionados con musica.'),
('Instrumentos Musicales', 'Productos relacionados con instrumentos musicales.'),
('Videojuegos', 'Productos relacionados con videojuegos.'),
('Computacion', 'Productos relacionados con computacion.'),
('Telefonia', 'Productos relacionados con telefonia.'),
('Fotografia', 'Productos relacionados con fotografia.'),
('Accesorios', 'Productos relacionados con accesorios.'),
('Joyeria', 'Productos relacionados con joyeria.'),
('Relojes', 'Productos relacionados con relojes.'),
('Equipaje', 'Productos relacionados con equipaje.'),
('Camping', 'Productos relacionados con camping.'),
('Pesca', 'Productos relacionados con pesca.'),
('Ciclismo', 'Productos relacionados con ciclismo.'),
('Fitness', 'Productos relacionados con fitness.'),
('Bebes', 'Productos relacionados con bebes.'),
('Ninos', 'Productos relacionados con ninos.'),
('Oficina', 'Productos relacionados con oficina.'),
('Arte y Manualidades', 'Productos relacionados con arte y manualidades.'),
('Iluminacion', 'Productos relacionados con iluminacion.'),
('Decoracion', 'Productos relacionados con decoracion.'),
('Limpieza', 'Productos relacionados con limpieza.'),
('Ferreteria', 'Productos relacionados con ferreteria.'),
('Electrodomesticos', 'Productos relacionados con electrodomesticos.'),
('Climatizacion', 'Productos relacionados con climatizacion.'),
('Seguridad', 'Productos relacionados con seguridad.'),
('Bebidas', 'Productos relacionados con bebidas.'),
('Snacks', 'Productos relacionados con snacks.'),
('Organicos', 'Productos relacionados con organicos.'),
('Coleccionables', 'Productos relacionados con coleccionables.'),
('Regalos', 'Productos relacionados con regalos.'),
('Tecnologia Wearable', 'Productos relacionados con tecnologia wearable.'),
('Audio', 'Productos relacionados con audio.'),
('General', 'Categoria de respaldo para productos sin clasificar');

-- ---------- DATOS: PROVEEDORES (50) ----------
INSERT INTO proveedores (nombre, email_contacto, telefono_contacto) VALUES
('Distribuidora Andina', 'contacto1@distribuidor.com', '353530829'),
('Comercial del Norte', 'contacto2@comercialdel.com', '361810111'),
('Importadora Central', 'contacto3@importadorac.com', '319990608'),
('Suministros Globales', 'contacto4@suministrosg.com', '317135241'),
('Grupo Mercantil Sur', 'contacto5@grupomercant.com', '391973060'),
('Tecno Import SAS', 'contacto6@tecnoimports.com', '384602037'),
('Andes Trading', 'contacto7@andestrading.com', '302441955'),
('Fabrica Nacional', 'contacto8@fabricanacio.com', '368015764'),
('Proveedora Continental', 'contacto9@proveedoraco.com', '315037655'),
('Almacenes Union', 'contacto10@almacenesuni.com', '318122250'),
('Comercializadora Pacifico', 'contacto11@comercializa.com', '303077052'),
('Industrias Reunidas', 'contacto12@industriasre.com', '332037872'),
('Distribuciones Caribe', 'contacto13@distribucion.com', '397655194'),
('Manufacturas Bolivar', 'contacto14@manufacturas.com', '304709137'),
('Grupo Santander Logistica', 'contacto15@gruposantand.com', '303234302'),
('Comercial Los Andes', 'contacto16@comerciallos.com', '348031986'),
('Importaciones del Este', 'contacto17@importacione.com', '322976225'),
('Distribuidora Oriental', 'contacto18@distribuidor.com', '396175466'),
('Proveedora Metropolitana', 'contacto19@proveedorame.com', '384032085'),
('Suministros Express', 'contacto20@suministrose.com', '314151952'),
('Comercial Fenix', 'contacto21@comercialfen.com', '352634613'),
('Grupo Horizonte', 'contacto22@grupohorizon.com', '382053424'),
('Distribuidora Atlantico', 'contacto23@distribuidor.com', '391999941'),
('Importadora Occidente', 'contacto24@importadorao.com', '394455413'),
('Comercializadora Meridian', 'contacto25@comercializa.com', '379920785'),
('Proveedora Delta', 'contacto26@proveedorade.com', '366270514'),
('Grupo Vanguardia', 'contacto27@grupovanguar.com', '378603172'),
('Distribuidora Zenith', 'contacto28@distribuidor.com', '356029255'),
('Almacen Central Ltda', 'contacto29@almacencentr.com', '334015985'),
('Comercial Nova', 'contacto30@comercialnov.com', '332373299'),
('Suministros Prime', 'contacto31@suministrosp.com', '396037344'),
('Distribuidora Global Trade', 'contacto32@distribuidor.com', '389306674'),
('Importadora Selecta', 'contacto33@importadoras.com', '358530188'),
('Grupo Comercial Aurora', 'contacto34@grupocomerci.com', '342228106'),
('Proveedora Estelar', 'contacto35@proveedoraes.com', '319588807'),
('Distribuciones Rapidas', 'contacto36@distribucion.com', '363767604'),
('Comercial Titan', 'contacto37@comercialtit.com', '353549877'),
('Grupo Industrial Cauca', 'contacto38@grupoindustr.com', '378074924'),
('Proveedora del Valle', 'contacto39@proveedorade.com', '302302255'),
('Distribuidora Colonial', 'contacto40@distribuidor.com', '386263809'),
('Comercializadora Nexo', 'contacto41@comercializa.com', '356875018'),
('Importadora Ruta 40', 'contacto42@importadorar.com', '399332820'),
('Grupo Mayorista Sur', 'contacto43@grupomayoris.com', '398653855'),
('Distribuidora Boreal', 'contacto44@distribuidor.com', '312570280'),
('Proveedora Continental II', 'contacto45@proveedoraco.com', '348954050'),
('Comercial San Marcos', 'contacto46@comercialsan.com', '312017864'),
('Distribuidora Austral', 'contacto47@distribuidor.com', '348476611'),
('Grupo Comercial Ibiza', 'contacto48@grupocomerci.com', '347472506'),
('Suministros del Pacifico', 'contacto49@suministrosd.com', '351378543'),
('Distribuidora La Sabana', 'contacto50@distribuidor.com', '376963698');

-- ---------- DATOS: SUCURSALES (5) ----------
INSERT INTO sucursales (nombre, ciudad) VALUES
('Sucursal Bogota Centro', 'Bogota'),
('Sucursal Medellin Poblado', 'Medellin'),
('Sucursal Cali Norte', 'Cali'),
('Sucursal Barranquilla', 'Barranquilla'),
('Sucursal Bucaramanga', 'Bucaramanga');

INSERT INTO usuarios_sucursal (usuario_bd, id_sucursal) VALUES ('support_user', 1);

-- ---------- DATOS: PRODUCTOS (50) ----------
INSERT INTO productos (id_categoria, id_proveedor, nombre, descripcion, precio, costo, stock, stock_minimo, peso_kg, ubicacion, sku, fecha_creacion, activo) VALUES
(11, 40, 'Audifonos Bluetooth 1', 'Audifonos Bluetooth, ideal para uso diario. Calidad garantizada.', 65.43, 51.25, 10, 12, 4.835, 'Bodega B - Pasillo 8 - Estante 1', 'SKU-0001-559', '2026-02-03 19:00:00', 1),
(9, 28, 'Camiseta Basica 2', 'Camiseta Basica, ideal para uso diario. Calidad garantizada.', 540.86, 346.27, 212, 14, 4.627, 'Bodega A - Pasillo 4 - Estante 2', 'SKU-0002-280', '2026-06-12 05:00:00', 1),
(1, 32, 'Pantalon Jean 3', 'Pantalon Jean, ideal para uso diario. Calidad garantizada.', 478.94, 333.28, 0, 3, 7.357, 'Bodega A - Pasillo 6 - Estante 2', 'SKU-0003-567', '2025-05-24 15:00:00', 1),
(26, 26, 'Zapatillas Running 4', 'Zapatillas Running, ideal para uso diario. Calidad garantizada.', 217.01, 162.6, 14, 15, 11.818, 'Bodega A - Pasillo 8 - Estante 2', 'SKU-0004-448', '2025-10-25 11:00:00', 1),
(37, 10, 'Sofa 3 Puestos 5', 'Sofa 3 Puestos, ideal para uso diario. Calidad garantizada.', 528.0, 216.96, 1, 3, 7.407, 'Bodega C - Pasillo 3 - Estante 6', 'SKU-0005-455', '2025-10-24 01:00:00', 1),
(8, 32, 'Sarten Antiadherente 6', 'Sarten Antiadherente, ideal para uso diario. Calidad garantizada.', 717.4, 397.28, 11, 12, 9.021, 'Bodega D - Pasillo 12 - Estante 3', 'SKU-0006-948', '2025-09-08 07:00:00', 1),
(14, 34, 'Silla de Oficina 7', 'Silla de Oficina, ideal para uso diario. Calidad garantizada.', 310.14, 147.89, 468, 3, 3.647, 'Bodega C - Pasillo 11 - Estante 1', 'SKU-0007-630', '2026-02-22 07:00:00', 1),
(15, 35, 'Manguera de Jardin 8', 'Manguera de Jardin, ideal para uso diario. Calidad garantizada.', 405.77, 218.92, 325, 10, 9.482, 'Bodega D - Pasillo 4 - Estante 2', 'SKU-0008-857', '2025-07-13 05:00:00', 1),
(32, 23, 'Balon de Futbol 9', 'Balon de Futbol, ideal para uso diario. Calidad garantizada.', 730.4, 293.75, 404, 11, 2.404, 'Bodega D - Pasillo 10 - Estante 3', 'SKU-0009-927', '2025-08-23 01:00:00', 1),
(24, 6, 'Muneca de Trapo 10', 'Muneca de Trapo, ideal para uso diario. Calidad garantizada.', 137.65, 92.08, 100, 13, 7.526, 'Bodega D - Pasillo 10 - Estante 1', 'SKU-0010-768', '2026-03-04 16:00:00', 0),
(43, 8, 'Novela de Misterio 11', 'Novela de Misterio, ideal para uso diario. Calidad garantizada.', 807.78, 364.36, 384, 9, 2.224, 'Bodega A - Pasillo 11 - Estante 3', 'SKU-0011-920', '2025-08-24 00:00:00', 1),
(48, 6, 'Cuaderno Universitario 12', 'Cuaderno Universitario, ideal para uso diario. Calidad garantizada.', 413.94, 291.3, 65, 3, 10.868, 'Bodega D - Pasillo 11 - Estante 2', 'SKU-0012-773', '2026-03-02 08:00:00', 1),
(9, 2, 'Labial Mate 13', 'Labial Mate, ideal para uso diario. Calidad garantizada.', 26.17, 10.63, 332, 6, 11.21, 'Bodega B - Pasillo 7 - Estante 2', 'SKU-0013-128', '2026-04-22 06:00:00', 1),
(16, 49, 'Crema Hidratante 14', 'Crema Hidratante, ideal para uso diario. Calidad garantizada.', 363.76, 236.64, 4, 7, 10.783, 'Bodega D - Pasillo 11 - Estante 5', 'SKU-0014-946', '2025-05-15 20:00:00', 1),
(10, 34, 'Termometro Digital 15', 'Termometro Digital, ideal para uso diario. Calidad garantizada.', 482.5, 206.67, 397, 8, 9.335, 'Bodega B - Pasillo 3 - Estante 2', 'SKU-0015-584', '2025-10-15 13:00:00', 1),
(4, 21, 'Correa para Perro 16', 'Correa para Perro, ideal para uso diario. Calidad garantizada.', 518.83, 274.52, 247, 6, 0.776, 'Bodega A - Pasillo 4 - Estante 3', 'SKU-0016-890', '2026-07-08 20:00:00', 1),
(2, 49, 'Aceite de Motor 17', 'Aceite de Motor, ideal para uso diario. Calidad garantizada.', 459.26, 358.13, 166, 19, 2.473, 'Bodega D - Pasillo 5 - Estante 4', 'SKU-0017-619', '2026-04-23 14:00:00', 1),
(17, 36, 'Taladro Electrico 18', 'Taladro Electrico, ideal para uso diario. Calidad garantizada.', 523.36, 357.64, 229, 7, 4.769, 'Bodega B - Pasillo 6 - Estante 1', 'SKU-0018-538', '2026-07-22 06:00:00', 1),
(8, 50, 'Parlante Portatil 19', 'Parlante Portatil, ideal para uso diario. Calidad garantizada.', 140.66, 66.01, 12, 14, 11.614, 'Bodega A - Pasillo 4 - Estante 6', 'SKU-0019-507', '2025-05-31 21:00:00', 1),
(43, 15, 'Guitarra Acustica 20', 'Guitarra Acustica, ideal para uso diario. Calidad garantizada.', 121.12, 68.78, 263, 15, 2.429, 'Bodega C - Pasillo 6 - Estante 1', 'SKU-0020-119', '2026-03-07 19:00:00', 1),
(46, 2, 'Control de Videojuegos 21', 'Control de Videojuegos, ideal para uso diario. Calidad garantizada.', 293.67, 156.82, 151, 19, 1.443, 'Bodega A - Pasillo 4 - Estante 1', 'SKU-0021-371', '2026-04-11 11:00:00', 1),
(12, 18, 'Mouse Inalambrico 22', 'Mouse Inalambrico, ideal para uso diario. Calidad garantizada.', 687.71, 303.53, 434, 11, 6.486, 'Bodega D - Pasillo 9 - Estante 5', 'SKU-0022-817', '2026-03-14 10:00:00', 1),
(45, 12, 'Cargador USB-C 23', 'Cargador USB-C, ideal para uso diario. Calidad garantizada.', 223.89, 173.0, 480, 3, 9.639, 'Bodega B - Pasillo 2 - Estante 5', 'SKU-0023-168', '2026-04-15 09:00:00', 1),
(22, 36, 'Camara Instantanea 24', 'Camara Instantanea, ideal para uso diario. Calidad garantizada.', 406.36, 170.02, 5, 7, 11.264, 'Bodega A - Pasillo 3 - Estante 3', 'SKU-0024-285', '2026-05-17 03:00:00', 1),
(34, 49, 'Cinturon de Cuero 25', 'Cinturon de Cuero, ideal para uso diario. Calidad garantizada.', 153.6, 86.32, 344, 8, 9.664, 'Bodega A - Pasillo 5 - Estante 1', 'SKU-0025-118', '2025-08-17 20:00:00', 1),
(13, 33, 'Anillo de Plata 26', 'Anillo de Plata, ideal para uso diario. Calidad garantizada.', 464.97, 192.53, 54, 16, 6.596, 'Bodega C - Pasillo 7 - Estante 5', 'SKU-0026-804', '2026-05-10 05:00:00', 1),
(46, 47, 'Reloj Analogo 27', 'Reloj Analogo, ideal para uso diario. Calidad garantizada.', 442.25, 256.21, 177, 4, 0.27, 'Bodega C - Pasillo 11 - Estante 6', 'SKU-0027-541', '2026-06-06 11:00:00', 0),
(25, 33, 'Maleta de Viaje 28', 'Maleta de Viaje, ideal para uso diario. Calidad garantizada.', 422.74, 269.86, 10, 12, 1.975, 'Bodega C - Pasillo 8 - Estante 1', 'SKU-0028-472', '2026-03-12 19:00:00', 1),
(3, 20, 'Carpa para 4 Personas 29', 'Carpa para 4 Personas, ideal para uso diario. Calidad garantizada.', 130.93, 91.06, 12, 15, 6.083, 'Bodega A - Pasillo 4 - Estante 2', 'SKU-0029-193', '2026-04-15 10:00:00', 1),
(38, 3, 'Cana de Pescar 30', 'Cana de Pescar, ideal para uso diario. Calidad garantizada.', 255.31, 160.62, 8, 10, 7.925, 'Bodega D - Pasillo 12 - Estante 5', 'SKU-0030-882', '2026-03-14 13:00:00', 1),
(10, 19, 'Bicicleta Montanera 31', 'Bicicleta Montanera, ideal para uso diario. Calidad garantizada.', 592.61, 291.04, 22, 19, 8.833, 'Bodega A - Pasillo 9 - Estante 2', 'SKU-0031-946', '2025-09-10 18:00:00', 1),
(46, 44, 'Banda de Resistencia 32', 'Banda de Resistencia, ideal para uso diario. Calidad garantizada.', 778.98, 382.65, 0, 3, 11.518, 'Bodega A - Pasillo 7 - Estante 4', 'SKU-0032-742', '2026-08-18 16:00:00', 1),
(16, 32, 'Panal Desechable 33', 'Panal Desechable, ideal para uso diario. Calidad garantizada.', 195.91, 109.2, 35, 19, 1.194, 'Bodega D - Pasillo 9 - Estante 1', 'SKU-0033-358', '2025-07-10 10:00:00', 1),
(16, 47, 'Rompecabezas Infantil 34', 'Rompecabezas Infantil, ideal para uso diario. Calidad garantizada.', 455.67, 303.79, 332, 17, 4.652, 'Bodega C - Pasillo 8 - Estante 6', 'SKU-0034-885', '2026-08-04 17:00:00', 1),
(13, 5, 'Organizador de Escritorio 35', 'Organizador de Escritorio, ideal para uso diario. Calidad garantizada.', 394.58, 241.88, 333, 12, 1.688, 'Bodega D - Pasillo 8 - Estante 1', 'SKU-0035-375', '2025-09-18 09:00:00', 1),
(44, 32, 'Set de Pinceles 36', 'Set de Pinceles, ideal para uso diario. Calidad garantizada.', 224.37, 119.89, 237, 17, 1.51, 'Bodega C - Pasillo 9 - Estante 2', 'SKU-0036-187', '2025-12-29 12:00:00', 1),
(5, 33, 'Lampara de Mesa 37', 'Lampara de Mesa, ideal para uso diario. Calidad garantizada.', 691.23, 387.4, 137, 15, 11.352, 'Bodega A - Pasillo 4 - Estante 1', 'SKU-0037-245', '2025-08-10 20:00:00', 1),
(24, 9, 'Cuadro Decorativo 38', 'Cuadro Decorativo, ideal para uso diario. Calidad garantizada.', 491.81, 243.33, 143, 6, 2.853, 'Bodega A - Pasillo 8 - Estante 4', 'SKU-0038-262', '2026-08-26 21:00:00', 1),
(26, 20, 'Detergente Liquido 39', 'Detergente Liquido, ideal para uso diario. Calidad garantizada.', 508.8, 292.24, 10, 13, 0.121, 'Bodega A - Pasillo 6 - Estante 4', 'SKU-0039-300', '2025-08-28 12:00:00', 1),
(19, 17, 'Juego de Llaves 40', 'Juego de Llaves, ideal para uso diario. Calidad garantizada.', 260.09, 152.03, 445, 5, 5.194, 'Bodega C - Pasillo 5 - Estante 1', 'SKU-0040-204', '2026-08-01 15:00:00', 1),
(10, 16, 'Licuadora 41', 'Licuadora, ideal para uso diario. Calidad garantizada.', 686.63, 388.56, 161, 9, 9.443, 'Bodega D - Pasillo 7 - Estante 1', 'SKU-0041-996', '2025-11-17 19:00:00', 1),
(6, 4, 'Ventilador de Pie 42', 'Ventilador de Pie, ideal para uso diario. Calidad garantizada.', 648.09, 373.72, 314, 7, 3.506, 'Bodega B - Pasillo 1 - Estante 5', 'SKU-0042-274', '2025-12-29 23:00:00', 1),
(20, 17, 'Camara de Seguridad 43', 'Camara de Seguridad, ideal para uso diario. Calidad garantizada.', 733.15, 296.92, 133, 15, 3.68, 'Bodega D - Pasillo 9 - Estante 6', 'SKU-0043-222', '2026-06-03 16:00:00', 1),
(14, 33, 'Cerveza Artesanal 44', 'Cerveza Artesanal, ideal para uso diario. Calidad garantizada.', 669.89, 362.85, 112, 17, 11.958, 'Bodega B - Pasillo 8 - Estante 4', 'SKU-0044-660', '2026-05-22 05:00:00', 0),
(22, 36, 'Papas Fritas 45', 'Papas Fritas, ideal para uso diario. Calidad garantizada.', 61.92, 40.98, 132, 9, 9.021, 'Bodega D - Pasillo 7 - Estante 4', 'SKU-0045-863', '2025-12-03 06:00:00', 1),
(22, 49, 'Miel Organica 46', 'Miel Organica, ideal para uso diario. Calidad garantizada.', 46.06, 29.51, 12, 14, 1.202, 'Bodega D - Pasillo 4 - Estante 4', 'SKU-0046-761', '2026-01-11 23:00:00', 1),
(2, 9, 'Figura de Accion 47', 'Figura de Accion, ideal para uso diario. Calidad garantizada.', 37.65, 17.74, 458, 18, 5.929, 'Bodega D - Pasillo 2 - Estante 4', 'SKU-0047-559', '2026-04-23 09:00:00', 1),
(10, 34, 'Taza Personalizada 48', 'Taza Personalizada, ideal para uso diario. Calidad garantizada.', 521.73, 388.9, 16, 17, 0.116, 'Bodega A - Pasillo 3 - Estante 2', 'SKU-0048-760', '2025-08-27 03:00:00', 1),
(41, 17, 'Smartwatch 49', 'Smartwatch, ideal para uso diario. Calidad garantizada.', 377.89, 213.66, 3, 6, 6.341, 'Bodega D - Pasillo 10 - Estante 2', 'SKU-0049-367', '2026-05-05 17:00:00', 0),
(35, 20, 'Teclado Mecanico 50', 'Teclado Mecanico, ideal para uso diario. Calidad garantizada.', 622.64, 398.57, 161, 10, 2.894, 'Bodega D - Pasillo 4 - Estante 1', 'SKU-0050-821', '2025-09-30 03:00:00', 0);

-- Actualiza el contador de productos por categoria (evita recalcular con trigger,
-- porque los triggers todavia no existen en este punto del proyecto)
UPDATE categorias SET total_productos = 1 WHERE id_categoria = 1;
UPDATE categorias SET total_productos = 2 WHERE id_categoria = 2;
UPDATE categorias SET total_productos = 1 WHERE id_categoria = 3;
UPDATE categorias SET total_productos = 1 WHERE id_categoria = 4;
UPDATE categorias SET total_productos = 1 WHERE id_categoria = 5;
UPDATE categorias SET total_productos = 1 WHERE id_categoria = 6;
UPDATE categorias SET total_productos = 2 WHERE id_categoria = 8;
UPDATE categorias SET total_productos = 2 WHERE id_categoria = 9;
UPDATE categorias SET total_productos = 4 WHERE id_categoria = 10;
UPDATE categorias SET total_productos = 1 WHERE id_categoria = 11;
UPDATE categorias SET total_productos = 1 WHERE id_categoria = 12;
UPDATE categorias SET total_productos = 2 WHERE id_categoria = 13;
UPDATE categorias SET total_productos = 2 WHERE id_categoria = 14;
UPDATE categorias SET total_productos = 1 WHERE id_categoria = 15;
UPDATE categorias SET total_productos = 3 WHERE id_categoria = 16;
UPDATE categorias SET total_productos = 1 WHERE id_categoria = 17;
UPDATE categorias SET total_productos = 1 WHERE id_categoria = 19;
UPDATE categorias SET total_productos = 1 WHERE id_categoria = 20;
UPDATE categorias SET total_productos = 3 WHERE id_categoria = 22;
UPDATE categorias SET total_productos = 2 WHERE id_categoria = 24;
UPDATE categorias SET total_productos = 1 WHERE id_categoria = 25;
UPDATE categorias SET total_productos = 2 WHERE id_categoria = 26;
UPDATE categorias SET total_productos = 1 WHERE id_categoria = 32;
UPDATE categorias SET total_productos = 1 WHERE id_categoria = 34;
UPDATE categorias SET total_productos = 1 WHERE id_categoria = 35;
UPDATE categorias SET total_productos = 1 WHERE id_categoria = 37;
UPDATE categorias SET total_productos = 1 WHERE id_categoria = 38;
UPDATE categorias SET total_productos = 1 WHERE id_categoria = 41;
UPDATE categorias SET total_productos = 2 WHERE id_categoria = 43;
UPDATE categorias SET total_productos = 1 WHERE id_categoria = 44;
UPDATE categorias SET total_productos = 1 WHERE id_categoria = 45;
UPDATE categorias SET total_productos = 3 WHERE id_categoria = 46;
UPDATE categorias SET total_productos = 1 WHERE id_categoria = 48;

-- ---------- DATOS: CLIENTES (50) ----------
INSERT INTO clientes (nombre, apellido, email, contrasena, direccion_envio, ciudad, fecha_nacimiento, fecha_registro) VALUES
('Juan', 'Gomez', 'juan.gomez1@correo.com', '$2y$10$hashfake001exampleexampleexampleexamp', 'Calle 50 # 64-87', 'Pereira', '2003-05-25', '2026-01-26 15:00:00'),
('Maria', 'Rodriguez', 'maria.rodriguez2@correo.com', '$2y$10$hashfake002exampleexampleexampleexamp', 'Calle 109 # 48-30', 'Manizales', '2005-10-11', '2025-10-05 14:00:00'),
('Carlos', 'Perez', 'carlos.perez3@correo.com', '$2y$10$hashfake003exampleexampleexampleexamp', 'Calle 108 # 47-88', 'Pereira', '1996-10-01', '2025-11-21 13:00:00'),
('Ana', 'Martinez', 'ana.martinez4@correo.com', '$2y$10$hashfake004exampleexampleexampleexamp', 'Calle 130 # 9-27', 'Manizales', '1996-04-28', '2026-03-03 05:00:00'),
('Luis', 'Lopez', 'luis.lopez5@correo.com', '$2y$10$hashfake005exampleexampleexampleexamp', 'Calle 120 # 29-34', 'Cartagena', '2001-11-18', '2025-04-27 17:00:00'),
('Laura', 'Garcia', 'laura.garcia6@correo.com', '$2y$10$hashfake006exampleexampleexampleexamp', 'Calle 48 # 29-63', 'Pereira', '1966-09-14', '2025-01-16 08:00:00'),
('Andres', 'Hernandez', 'andres.hernandez7@correo.com', '$2y$10$hashfake007exampleexampleexampleexamp', 'Calle 101 # 7-28', 'Bogota', '1970-07-31', '2025-07-19 11:00:00'),
('Sofia', 'Diaz', 'sofia.diaz8@correo.com', '$2y$10$hashfake008exampleexampleexampleexamp', 'Calle 16 # 24-51', 'Manizales', '1963-05-06', '2026-05-25 10:00:00'),
('Diego', 'Torres', 'diego.torres9@correo.com', '$2y$10$hashfake009exampleexampleexampleexamp', 'Calle 43 # 43-25', 'Cali', '1967-01-17', '2025-05-27 11:00:00'),
('Valentina', 'Ramirez', 'valentina.ramirez10@correo.com', '$2y$10$hashfake010exampleexampleexampleexamp', 'Calle 80 # 86-93', 'Pereira', '1985-04-21', '2025-06-21 07:00:00'),
('Miguel', 'Sanchez', 'miguel.sanchez11@correo.com', '$2y$10$hashfake011exampleexampleexampleexamp', 'Calle 28 # 1-11', 'Cartagena', '2003-04-07', '2025-07-14 09:00:00'),
('Camila', 'Castro', 'camila.castro12@correo.com', '$2y$10$hashfake012exampleexampleexampleexamp', 'Calle 144 # 98-27', 'Pereira', '1986-05-02', '2025-07-02 10:00:00'),
('Javier', 'Ortiz', 'javier.ortiz13@correo.com', '$2y$10$hashfake013exampleexampleexampleexamp', 'Calle 13 # 91-61', 'Barranquilla', '1985-01-03', '2025-06-17 06:00:00'),
('Daniela', 'Rojas', 'daniela.rojas14@correo.com', '$2y$10$hashfake014exampleexampleexampleexamp', 'Calle 83 # 47-95', 'Manizales', '2006-11-13', '2025-07-24 05:00:00'),
('Ricardo', 'Morales', 'ricardo.morales15@correo.com', '$2y$10$hashfake015exampleexampleexampleexamp', 'Calle 104 # 6-49', 'Bogota', '1979-09-07', '2026-07-16 04:00:00'),
('Paula', 'Vargas', 'paula.vargas16@correo.com', '$2y$10$hashfake016exampleexampleexampleexamp', 'Calle 50 # 96-9', 'Ibague', '1987-04-05', '2025-12-13 02:00:00'),
('Sergio', 'Jimenez', 'sergio.jimenez17@correo.com', '$2y$10$hashfake017exampleexampleexampleexamp', 'Calle 12 # 34-96', 'Bucaramanga', '1991-05-07', '2026-09-13 13:00:00'),
('Natalia', 'Reyes', 'natalia.reyes18@correo.com', '$2y$10$hashfake018exampleexampleexampleexamp', 'Calle 17 # 4-30', 'Medellin', '1978-02-13', '2025-08-18 04:00:00'),
('Fernando', 'Cruz', 'fernando.cruz19@correo.com', '$2y$10$hashfake019exampleexampleexampleexamp', 'Calle 111 # 64-17', 'Manizales', '1997-09-30', '2025-11-10 14:00:00'),
('Gabriela', 'Mendoza', 'gabriela.mendoza20@correo.com', '$2y$10$hashfake020exampleexampleexampleexamp', 'Calle 39 # 78-31', 'Bucaramanga', '1988-02-14', '2025-09-11 17:00:00'),
('Oscar', 'Suarez', 'oscar.suarez21@correo.com', '$2y$10$hashfake021exampleexampleexampleexamp', 'Calle 21 # 66-26', 'Pereira', '1960-07-24', '2026-01-06 23:00:00'),
('Isabella', 'Rios', 'isabella.rios22@correo.com', '$2y$10$hashfake022exampleexampleexampleexamp', 'Calle 17 # 84-5', 'Manizales', '1973-01-05', '2025-10-19 07:00:00'),
('Alejandro', 'Guerrero', 'alejandro.guerrero23@correo.com', '$2y$10$hashfake023exampleexampleexampleexamp', 'Calle 110 # 14-10', 'Cartagena', '1969-08-29', '2026-02-16 09:00:00'),
('Mariana', 'Medina', 'mariana.medina24@correo.com', '$2y$10$hashfake024exampleexampleexampleexamp', 'Calle 108 # 64-91', 'Manizales', '1997-06-07', '2026-05-03 23:00:00'),
('Pedro', 'Aguilar', 'pedro.aguilar25@correo.com', '$2y$10$hashfake025exampleexampleexampleexamp', 'Calle 118 # 80-87', 'Barranquilla', '1961-01-11', '2024-11-06 09:00:00'),
('Carolina', 'Nino', 'carolina.nino26@correo.com', '$2y$10$hashfake026exampleexampleexampleexamp', 'Calle 76 # 38-36', 'Ibague', '1991-03-30', '2025-12-30 13:00:00'),
('Jorge', 'Cardenas', 'jorge.cardenas27@correo.com', '$2y$10$hashfake027exampleexampleexampleexamp', 'Calle 67 # 26-57', 'Barranquilla', '1997-06-01', '2026-01-19 08:00:00'),
('Lucia', 'Pena', 'lucia.pena28@correo.com', '$2y$10$hashfake028exampleexampleexampleexamp', 'Calle 73 # 75-25', 'Bucaramanga', '2004-03-14', '2026-01-03 05:00:00'),
('Manuel', 'Salazar', 'manuel.salazar29@correo.com', '$2y$10$hashfake029exampleexampleexampleexamp', 'Calle 130 # 68-30', 'Medellin', '1967-02-17', '2026-08-11 09:00:00'),
('Sara', 'Vega', 'sara.vega30@correo.com', '$2y$10$hashfake030exampleexampleexampleexamp', 'Calle 2 # 61-30', 'Manizales', '1985-09-17', '2025-11-21 05:00:00'),
('Felipe', 'Contreras', 'felipe.contreras31@correo.com', '$2y$10$hashfake031exampleexampleexampleexamp', 'Calle 31 # 7-25', 'Ibague', '1955-12-21', '2026-03-03 10:00:00'),
('Elena', 'Fuentes', 'elena.fuentes32@correo.com', '$2y$10$hashfake032exampleexampleexampleexamp', 'Calle 96 # 66-23', 'Manizales', '1970-05-31', '2024-11-06 12:00:00'),
('Ivan', 'Molina', 'ivan.molina33@correo.com', '$2y$10$hashfake033exampleexampleexampleexamp', 'Calle 28 # 82-77', 'Ibague', '1986-06-18', '2026-08-10 01:00:00'),
('Monica', 'Delgado', 'monica.delgado34@correo.com', '$2y$10$hashfake034exampleexampleexampleexamp', 'Calle 88 # 19-6', 'Barranquilla', '1992-09-16', '2025-01-11 13:00:00'),
('Rodrigo', 'Paredes', 'rodrigo.paredes35@correo.com', '$2y$10$hashfake035exampleexampleexampleexamp', 'Calle 53 # 2-42', 'Pereira', '1965-04-05', '2026-03-11 17:00:00'),
('Patricia', 'Cabrera', 'patricia.cabrera36@correo.com', '$2y$10$hashfake036exampleexampleexampleexamp', 'Calle 80 # 10-27', 'Bogota', '1958-02-03', '2025-03-04 21:00:00'),
('Cesar', 'Franco', 'cesar.franco37@correo.com', '$2y$10$hashfake037exampleexampleexampleexamp', 'Calle 17 # 53-13', 'Pereira', '1966-01-04', '2026-04-11 16:00:00'),
('Adriana', 'Bravo', 'adriana.bravo38@correo.com', '$2y$10$hashfake038exampleexampleexampleexamp', 'Calle 137 # 12-84', 'Cali', '1982-10-17', '2025-12-13 23:00:00'),
('Hector', 'Navarro', 'hector.navarro39@correo.com', '$2y$10$hashfake039exampleexampleexampleexamp', 'Calle 73 # 86-40', 'Pereira', '2005-04-26', '2025-02-14 01:00:00'),
('Veronica', 'Cortes', 'veronica.cortes40@correo.com', '$2y$10$hashfake040exampleexampleexampleexamp', 'Calle 107 # 54-3', 'Bucaramanga', '1967-07-04', '2025-08-12 13:00:00'),
('Raul', 'Ibarra', 'raul.ibarra41@correo.com', '$2y$10$hashfake041exampleexampleexampleexamp', 'Calle 104 # 27-1', 'Pereira', '1998-03-02', '2026-05-24 10:00:00'),
('Claudia', 'Leon', 'claudia.leon42@correo.com', '$2y$10$hashfake042exampleexampleexampleexamp', 'Calle 104 # 74-47', 'Manizales', '1959-07-23', '2026-05-07 12:00:00'),
('Martin', 'Rincon', 'martin.rincon43@correo.com', '$2y$10$hashfake043exampleexampleexampleexamp', 'Calle 14 # 71-19', 'Pereira', '2002-12-14', '2024-12-19 01:00:00'),
('Silvia', 'Zapata', 'silvia.zapata44@correo.com', '$2y$10$hashfake044exampleexampleexampleexamp', 'Calle 130 # 22-19', 'Bucaramanga', '1990-07-16', '2025-04-02 07:00:00'),
('Victor', 'Quintero', 'victor.quintero45@correo.com', '$2y$10$hashfake045exampleexampleexampleexamp', 'Calle 18 # 14-50', 'Manizales', '1960-07-04', '2025-11-13 08:00:00'),
('Diana', 'Duarte', 'diana.duarte46@correo.com', '$2y$10$hashfake046exampleexampleexampleexamp', 'Calle 12 # 62-41', 'Bogota', '1969-11-20', '2025-08-16 10:00:00'),
('Julio', 'Peralta', 'julio.peralta47@correo.com', '$2y$10$hashfake047exampleexampleexampleexamp', 'Calle 42 # 82-29', 'Ibague', '1982-11-28', '2026-02-28 21:00:00'),
('Renata', 'Beltran', 'renata.beltran48@correo.com', '$2y$10$hashfake048exampleexampleexampleexamp', 'Calle 47 # 73-28', 'Bogota', '1983-01-16', '2026-04-10 00:00:00'),
('Emilio', 'Escobar', 'emilio.escobar49@correo.com', '$2y$10$hashfake049exampleexampleexampleexamp', 'Calle 92 # 16-20', 'Barranquilla', '1962-07-07', '2026-08-05 19:00:00'),
('Ximena', 'Mora', 'ximena.mora50@correo.com', '$2y$10$hashfake050exampleexampleexampleexamp', 'Calle 10 # 86-42', 'Medellin', '1983-12-06', '2025-06-07 19:00:00');

-- ---------- DATOS: VENTAS (50) ----------
-- El total se deja en 0 y se recalcula al final, tras insertar detalle_ventas
INSERT INTO ventas (id_cliente, id_sucursal, fecha_venta, estado, metodo_pago, fecha_pago) VALUES
(41, 3, '2026-09-22 12:00:00', 'Pendiente de Pago', NULL, NULL),
(28, 4, '2026-09-18 12:00:00', 'Pendiente de Pago', NULL, NULL),
(12, 1, '2026-09-22 12:00:00', 'Pendiente de Pago', NULL, NULL),
(29, 5, '2026-09-18 12:00:00', 'Pendiente de Pago', NULL, NULL),
(26, 1, '2026-03-06 00:27:00', 'Entregado', 'Efectivo contra entrega', '2026-03-06 00:39:00'),
(29, 5, '2026-09-22 10:02:00', 'Procesando', 'PSE', '2026-09-22 10:13:00'),
(47, 3, '2026-09-01 13:05:00', 'Cancelado', NULL, NULL),
(4, 5, '2026-08-17 09:01:00', 'Enviado', 'Tarjeta de Credito', '2026-08-17 10:20:00'),
(47, 1, '2026-04-03 12:18:00', 'Entregado', 'PSE', '2026-04-03 13:46:00'),
(47, 2, '2026-05-29 16:48:00', 'Entregado', 'Efectivo contra entrega', '2026-05-29 17:09:00'),
(21, 5, '2026-08-28 03:16:00', 'Enviado', 'Tarjeta Debito', '2026-08-28 03:43:00'),
(38, 3, '2026-08-30 06:20:00', 'Pagado', 'Efectivo contra entrega', '2026-08-30 06:25:00'),
(13, 2, '2025-09-08 02:59:00', 'Enviado', 'Efectivo contra entrega', '2025-09-08 04:26:00'),
(21, 4, '2026-05-22 02:49:00', 'Entregado', 'Tarjeta de Credito', '2026-05-22 04:11:00'),
(24, 4, '2026-09-14 17:44:00', 'Pagado', 'Tarjeta de Credito', '2026-09-14 18:17:00'),
(35, 4, '2026-06-15 01:24:00', 'Cancelado', NULL, NULL),
(24, 5, '2026-08-04 09:48:00', 'Entregado', 'Tarjeta de Credito', '2026-08-04 10:45:00'),
(15, 2, '2026-07-22 13:52:00', 'Pagado', 'Efectivo contra entrega', '2026-07-22 14:32:00'),
(41, 5, '2026-09-15 20:46:00', 'Pendiente de Pago', NULL, NULL),
(1, 1, '2026-03-06 00:39:00', 'Entregado', 'Tarjeta Debito', '2026-03-06 01:33:00'),
(33, 3, '2026-08-18 16:14:00', 'Entregado', 'Tarjeta de Credito', '2026-08-18 16:17:00'),
(4, 1, '2026-06-01 14:06:00', 'Pagado', 'Efectivo contra entrega', '2026-06-01 15:15:00'),
(15, 4, '2026-08-23 22:08:00', 'Pagado', 'PSE', '2026-08-23 22:55:00'),
(40, 4, '2025-10-19 13:59:00', 'Entregado', 'PSE', '2025-10-19 15:30:00'),
(10, 4, '2025-07-24 03:09:00', 'Entregado', 'Efectivo contra entrega', '2025-07-24 04:01:00'),
(17, 1, '2026-09-24 06:57:00', 'Entregado', 'Efectivo contra entrega', '2026-09-24 08:14:00'),
(42, 5, '2026-09-17 11:31:00', 'Procesando', 'PSE', '2026-09-17 11:53:00'),
(1, 1, '2026-06-11 15:25:00', 'Entregado', 'PSE', '2026-06-11 15:56:00'),
(11, 1, '2025-09-05 09:39:00', 'Cancelado', NULL, NULL),
(36, 2, '2026-05-02 03:33:00', 'Entregado', 'Tarjeta Debito', '2026-05-02 05:18:00'),
(40, 2, '2026-01-17 15:19:00', 'Procesando', 'Tarjeta de Credito', '2026-01-17 17:13:00'),
(47, 4, '2026-07-15 21:24:00', 'Cancelado', NULL, NULL),
(28, 4, '2026-08-22 10:14:00', 'Entregado', 'Tarjeta de Credito', '2026-08-22 10:48:00'),
(15, 1, '2026-08-28 03:59:00', 'Entregado', 'Efectivo contra entrega', '2026-08-28 05:31:00'),
(4, 3, '2026-07-23 02:27:00', 'Pendiente de Pago', NULL, NULL),
(44, 5, '2026-01-30 03:59:00', 'Entregado', 'PSE', '2026-01-30 04:10:00'),
(33, 1, '2026-08-26 08:53:00', 'Entregado', 'PSE', '2026-08-26 09:14:00'),
(48, 3, '2026-07-18 10:38:00', 'Entregado', 'PSE', '2026-07-18 11:27:00'),
(41, 5, '2026-07-24 02:44:00', 'Procesando', 'Tarjeta de Credito', '2026-07-24 04:34:00'),
(2, 4, '2026-02-02 08:56:00', 'Cancelado', NULL, NULL),
(20, 2, '2026-07-27 11:04:00', 'Enviado', 'PSE', '2026-07-27 11:23:00'),
(3, 1, '2026-01-15 08:59:00', 'Entregado', 'PSE', '2026-01-15 09:44:00'),
(10, 1, '2025-07-12 11:44:00', 'Entregado', 'Tarjeta de Credito', '2025-07-12 13:14:00'),
(5, 1, '2026-05-04 23:52:00', 'Entregado', 'Tarjeta de Credito', '2026-05-05 01:45:00'),
(49, 4, '2026-08-21 01:13:00', 'Entregado', 'Tarjeta de Credito', '2026-08-21 01:18:00'),
(3, 1, '2026-04-18 04:06:00', 'Cancelado', NULL, NULL),
(9, 1, '2026-04-22 17:18:00', 'Cancelado', NULL, NULL),
(21, 3, '2026-05-19 23:22:00', 'Enviado', 'Efectivo contra entrega', '2026-05-20 01:22:00'),
(19, 1, '2026-05-18 00:49:00', 'Cancelado', NULL, NULL),
(39, 5, '2025-12-05 20:47:00', 'Procesando', 'Tarjeta de Credito', '2025-12-05 22:28:00');

-- ---------- DATOS: DETALLE_VENTAS ----------
-- Cada una de las 50 ventas recibe entre 1 y 3 lineas de detalle.
INSERT INTO detalle_ventas (id_producto, id_venta, cantidad, precio_unitario_congelado) VALUES
(28, 1, 5, 422.74),
(23, 2, 1, 223.89),
(31, 2, 5, 592.61),
(46, 3, 5, 46.06),
(6, 3, 3, 717.4),
(1, 4, 5, 65.43),
(49, 5, 1, 377.89),
(32, 6, 1, 778.98),
(12, 7, 4, 413.94),
(33, 8, 5, 195.91),
(17, 8, 2, 459.26),
(14, 9, 2, 363.76),
(8, 10, 1, 405.77),
(45, 11, 5, 61.92),
(41, 12, 3, 686.63),
(21, 12, 1, 293.67),
(26, 13, 1, 464.97),
(42, 14, 1, 648.09),
(20, 15, 3, 121.12),
(35, 16, 5, 394.58),
(41, 17, 2, 686.63),
(9, 18, 5, 730.4),
(35, 18, 1, 394.58),
(39, 18, 3, 508.8),
(34, 19, 4, 455.67),
(10, 19, 5, 137.65),
(11, 20, 4, 807.78),
(30, 20, 3, 255.31),
(9, 21, 4, 730.4),
(22, 21, 2, 687.71),
(18, 22, 5, 523.36),
(20, 22, 2, 121.12),
(16, 23, 3, 518.83),
(47, 23, 5, 37.65),
(11, 24, 3, 807.78),
(16, 24, 2, 518.83),
(47, 25, 1, 37.65),
(43, 26, 1, 733.15),
(10, 27, 2, 137.65),
(47, 28, 4, 37.65),
(20, 28, 3, 121.12),
(41, 29, 1, 686.63),
(25, 30, 4, 153.6),
(26, 31, 4, 464.97),
(33, 32, 3, 195.91),
(41, 32, 4, 686.63),
(17, 33, 5, 459.26),
(1, 34, 2, 65.43),
(48, 34, 4, 521.73),
(38, 35, 4, 491.81),
(48, 35, 2, 521.73),
(42, 36, 5, 648.09),
(50, 36, 2, 622.64),
(42, 37, 4, 648.09),
(8, 37, 4, 405.77),
(41, 38, 1, 686.63),
(16, 39, 2, 518.83),
(26, 39, 3, 464.97),
(46, 39, 4, 46.06),
(2, 40, 5, 540.86),
(34, 41, 2, 455.67),
(44, 41, 3, 669.89),
(43, 41, 1, 733.15),
(32, 42, 1, 778.98),
(35, 43, 2, 394.58),
(13, 44, 5, 26.17),
(37, 45, 4, 691.23),
(46, 46, 5, 46.06),
(31, 46, 1, 592.61),
(24, 47, 3, 406.36),
(34, 47, 4, 455.67),
(30, 48, 2, 255.31),
(14, 48, 4, 363.76),
(8, 49, 5, 405.77),
(47, 49, 3, 37.65),
(17, 50, 4, 459.26),
(18, 50, 4, 523.36);

-- ---------- ACTUALIZAR TOTAL DE CADA VENTA ----------
UPDATE ventas SET total = 2113.7 WHERE id_venta = 1;
UPDATE ventas SET total = 3186.94 WHERE id_venta = 2;
UPDATE ventas SET total = 2382.5 WHERE id_venta = 3;
UPDATE ventas SET total = 327.15 WHERE id_venta = 4;
UPDATE ventas SET total = 377.89 WHERE id_venta = 5;
UPDATE ventas SET total = 778.98 WHERE id_venta = 6;
UPDATE ventas SET total = 1655.76 WHERE id_venta = 7;
UPDATE ventas SET total = 1898.07 WHERE id_venta = 8;
UPDATE ventas SET total = 727.52 WHERE id_venta = 9;
UPDATE ventas SET total = 405.77 WHERE id_venta = 10;
UPDATE ventas SET total = 309.6 WHERE id_venta = 11;
UPDATE ventas SET total = 2353.56 WHERE id_venta = 12;
UPDATE ventas SET total = 464.97 WHERE id_venta = 13;
UPDATE ventas SET total = 648.09 WHERE id_venta = 14;
UPDATE ventas SET total = 363.36 WHERE id_venta = 15;
UPDATE ventas SET total = 1972.9 WHERE id_venta = 16;
UPDATE ventas SET total = 1373.26 WHERE id_venta = 17;
UPDATE ventas SET total = 5572.98 WHERE id_venta = 18;
UPDATE ventas SET total = 2510.93 WHERE id_venta = 19;
UPDATE ventas SET total = 3997.05 WHERE id_venta = 20;
UPDATE ventas SET total = 4297.02 WHERE id_venta = 21;
UPDATE ventas SET total = 2859.04 WHERE id_venta = 22;
UPDATE ventas SET total = 1744.74 WHERE id_venta = 23;
UPDATE ventas SET total = 3461.0 WHERE id_venta = 24;
UPDATE ventas SET total = 37.65 WHERE id_venta = 25;
UPDATE ventas SET total = 733.15 WHERE id_venta = 26;
UPDATE ventas SET total = 275.3 WHERE id_venta = 27;
UPDATE ventas SET total = 513.96 WHERE id_venta = 28;
UPDATE ventas SET total = 686.63 WHERE id_venta = 29;
UPDATE ventas SET total = 614.4 WHERE id_venta = 30;
UPDATE ventas SET total = 1859.88 WHERE id_venta = 31;
UPDATE ventas SET total = 3334.25 WHERE id_venta = 32;
UPDATE ventas SET total = 2296.3 WHERE id_venta = 33;
UPDATE ventas SET total = 2217.78 WHERE id_venta = 34;
UPDATE ventas SET total = 3010.7 WHERE id_venta = 35;
UPDATE ventas SET total = 4485.73 WHERE id_venta = 36;
UPDATE ventas SET total = 4215.44 WHERE id_venta = 37;
UPDATE ventas SET total = 686.63 WHERE id_venta = 38;
UPDATE ventas SET total = 2616.81 WHERE id_venta = 39;
UPDATE ventas SET total = 2704.3 WHERE id_venta = 40;
UPDATE ventas SET total = 3654.16 WHERE id_venta = 41;
UPDATE ventas SET total = 778.98 WHERE id_venta = 42;
UPDATE ventas SET total = 789.16 WHERE id_venta = 43;
UPDATE ventas SET total = 130.85 WHERE id_venta = 44;
UPDATE ventas SET total = 2764.92 WHERE id_venta = 45;
UPDATE ventas SET total = 822.91 WHERE id_venta = 46;
UPDATE ventas SET total = 3041.76 WHERE id_venta = 47;
UPDATE ventas SET total = 1965.66 WHERE id_venta = 48;
UPDATE ventas SET total = 2141.8 WHERE id_venta = 49;
UPDATE ventas SET total = 3930.48 WHERE id_venta = 50;

-- ---------- ACTUALIZAR CAMPOS DERIVADOS EN CLIENTES ----------
UPDATE clientes SET total_gastado = 4511.01, fecha_ultima_compra = '2026-06-11 15:25:00', nivel_lealtad = 'Bronce', activo = 1 WHERE id_cliente = 1;
UPDATE clientes SET total_gastado = 0.0, fecha_ultima_compra = NULL, nivel_lealtad = 'Bronce', activo = 1 WHERE id_cliente = 2;
UPDATE clientes SET total_gastado = 778.98, fecha_ultima_compra = '2026-01-15 08:59:00', nivel_lealtad = 'Bronce', activo = 1 WHERE id_cliente = 3;
UPDATE clientes SET total_gastado = 7767.81, fecha_ultima_compra = '2026-08-17 09:01:00', nivel_lealtad = 'Bronce', activo = 1 WHERE id_cliente = 4;
UPDATE clientes SET total_gastado = 130.85, fecha_ultima_compra = '2026-05-04 23:52:00', nivel_lealtad = 'Bronce', activo = 1 WHERE id_cliente = 5;
UPDATE clientes SET total_gastado = 0.0, fecha_ultima_compra = NULL, nivel_lealtad = 'Bronce', activo = 0 WHERE id_cliente = 6;
UPDATE clientes SET total_gastado = 0.0, fecha_ultima_compra = NULL, nivel_lealtad = 'Bronce', activo = 0 WHERE id_cliente = 7;
UPDATE clientes SET total_gastado = 0.0, fecha_ultima_compra = NULL, nivel_lealtad = 'Bronce', activo = 1 WHERE id_cliente = 8;
UPDATE clientes SET total_gastado = 0.0, fecha_ultima_compra = NULL, nivel_lealtad = 'Bronce', activo = 0 WHERE id_cliente = 9;
UPDATE clientes SET total_gastado = 826.81, fecha_ultima_compra = '2025-07-24 03:09:00', nivel_lealtad = 'Bronce', activo = 0 WHERE id_cliente = 10;
UPDATE clientes SET total_gastado = 0.0, fecha_ultima_compra = NULL, nivel_lealtad = 'Bronce', activo = 0 WHERE id_cliente = 11;
UPDATE clientes SET total_gastado = 2382.5, fecha_ultima_compra = '2026-09-22 12:00:00', nivel_lealtad = 'Bronce', activo = 1 WHERE id_cliente = 12;
UPDATE clientes SET total_gastado = 464.97, fecha_ultima_compra = '2025-09-08 02:59:00', nivel_lealtad = 'Bronce', activo = 0 WHERE id_cliente = 13;
UPDATE clientes SET total_gastado = 0.0, fecha_ultima_compra = NULL, nivel_lealtad = 'Bronce', activo = 0 WHERE id_cliente = 14;
UPDATE clientes SET total_gastado = 9535.5, fecha_ultima_compra = '2026-08-28 03:59:00', nivel_lealtad = 'Bronce', activo = 1 WHERE id_cliente = 15;
UPDATE clientes SET total_gastado = 0.0, fecha_ultima_compra = NULL, nivel_lealtad = 'Bronce', activo = 1 WHERE id_cliente = 16;
UPDATE clientes SET total_gastado = 733.15, fecha_ultima_compra = '2026-09-24 06:57:00', nivel_lealtad = 'Bronce', activo = 1 WHERE id_cliente = 17;
UPDATE clientes SET total_gastado = 0.0, fecha_ultima_compra = NULL, nivel_lealtad = 'Bronce', activo = 0 WHERE id_cliente = 18;
UPDATE clientes SET total_gastado = 0.0, fecha_ultima_compra = NULL, nivel_lealtad = 'Bronce', activo = 1 WHERE id_cliente = 19;
UPDATE clientes SET total_gastado = 3654.16, fecha_ultima_compra = '2026-07-27 11:04:00', nivel_lealtad = 'Bronce', activo = 1 WHERE id_cliente = 20;
UPDATE clientes SET total_gastado = 2923.35, fecha_ultima_compra = '2026-08-28 03:16:00', nivel_lealtad = 'Bronce', activo = 1 WHERE id_cliente = 21;
UPDATE clientes SET total_gastado = 0.0, fecha_ultima_compra = NULL, nivel_lealtad = 'Bronce', activo = 1 WHERE id_cliente = 22;
UPDATE clientes SET total_gastado = 0.0, fecha_ultima_compra = NULL, nivel_lealtad = 'Bronce', activo = 1 WHERE id_cliente = 23;
UPDATE clientes SET total_gastado = 1736.62, fecha_ultima_compra = '2026-09-14 17:44:00', nivel_lealtad = 'Bronce', activo = 1 WHERE id_cliente = 24;
UPDATE clientes SET total_gastado = 0.0, fecha_ultima_compra = NULL, nivel_lealtad = 'Bronce', activo = 0 WHERE id_cliente = 25;
UPDATE clientes SET total_gastado = 377.89, fecha_ultima_compra = '2026-03-06 00:27:00', nivel_lealtad = 'Bronce', activo = 1 WHERE id_cliente = 26;
UPDATE clientes SET total_gastado = 0.0, fecha_ultima_compra = NULL, nivel_lealtad = 'Bronce', activo = 1 WHERE id_cliente = 27;
UPDATE clientes SET total_gastado = 5483.24, fecha_ultima_compra = '2026-09-18 12:00:00', nivel_lealtad = 'Bronce', activo = 1 WHERE id_cliente = 28;
UPDATE clientes SET total_gastado = 1106.13, fecha_ultima_compra = '2026-09-22 10:02:00', nivel_lealtad = 'Bronce', activo = 1 WHERE id_cliente = 29;
UPDATE clientes SET total_gastado = 0.0, fecha_ultima_compra = NULL, nivel_lealtad = 'Bronce', activo = 1 WHERE id_cliente = 30;
UPDATE clientes SET total_gastado = 0.0, fecha_ultima_compra = NULL, nivel_lealtad = 'Bronce', activo = 1 WHERE id_cliente = 31;
UPDATE clientes SET total_gastado = 0.0, fecha_ultima_compra = NULL, nivel_lealtad = 'Bronce', activo = 0 WHERE id_cliente = 32;
UPDATE clientes SET total_gastado = 8512.46, fecha_ultima_compra = '2026-08-26 08:53:00', nivel_lealtad = 'Bronce', activo = 1 WHERE id_cliente = 33;
UPDATE clientes SET total_gastado = 0.0, fecha_ultima_compra = NULL, nivel_lealtad = 'Bronce', activo = 0 WHERE id_cliente = 34;
UPDATE clientes SET total_gastado = 0.0, fecha_ultima_compra = NULL, nivel_lealtad = 'Bronce', activo = 1 WHERE id_cliente = 35;
UPDATE clientes SET total_gastado = 614.4, fecha_ultima_compra = '2026-05-02 03:33:00', nivel_lealtad = 'Bronce', activo = 1 WHERE id_cliente = 36;
UPDATE clientes SET total_gastado = 0.0, fecha_ultima_compra = NULL, nivel_lealtad = 'Bronce', activo = 1 WHERE id_cliente = 37;
UPDATE clientes SET total_gastado = 2353.56, fecha_ultima_compra = '2026-08-30 06:20:00', nivel_lealtad = 'Bronce', activo = 1 WHERE id_cliente = 38;
UPDATE clientes SET total_gastado = 3930.48, fecha_ultima_compra = '2025-12-05 20:47:00', nivel_lealtad = 'Bronce', activo = 1 WHERE id_cliente = 39;
UPDATE clientes SET total_gastado = 5320.88, fecha_ultima_compra = '2026-01-17 15:19:00', nivel_lealtad = 'Bronce', activo = 1 WHERE id_cliente = 40;
UPDATE clientes SET total_gastado = 7241.44, fecha_ultima_compra = '2026-09-22 12:00:00', nivel_lealtad = 'Bronce', activo = 1 WHERE id_cliente = 41;
UPDATE clientes SET total_gastado = 275.3, fecha_ultima_compra = '2026-09-17 11:31:00', nivel_lealtad = 'Bronce', activo = 1 WHERE id_cliente = 42;
UPDATE clientes SET total_gastado = 0.0, fecha_ultima_compra = NULL, nivel_lealtad = 'Bronce', activo = 0 WHERE id_cliente = 43;
UPDATE clientes SET total_gastado = 4485.73, fecha_ultima_compra = '2026-01-30 03:59:00', nivel_lealtad = 'Bronce', activo = 1 WHERE id_cliente = 44;
UPDATE clientes SET total_gastado = 0.0, fecha_ultima_compra = NULL, nivel_lealtad = 'Bronce', activo = 1 WHERE id_cliente = 45;
UPDATE clientes SET total_gastado = 0.0, fecha_ultima_compra = NULL, nivel_lealtad = 'Bronce', activo = 0 WHERE id_cliente = 46;
UPDATE clientes SET total_gastado = 1133.29, fecha_ultima_compra = '2026-05-29 16:48:00', nivel_lealtad = 'Bronce', activo = 1 WHERE id_cliente = 47;
UPDATE clientes SET total_gastado = 686.63, fecha_ultima_compra = '2026-07-18 10:38:00', nivel_lealtad = 'Bronce', activo = 1 WHERE id_cliente = 48;
UPDATE clientes SET total_gastado = 2764.92, fecha_ultima_compra = '2026-08-21 01:13:00', nivel_lealtad = 'Bronce', activo = 1 WHERE id_cliente = 49;
UPDATE clientes SET total_gastado = 0.0, fecha_ultima_compra = NULL, nivel_lealtad = 'Bronce', activo = 0 WHERE id_cliente = 50;

-- ---------- DATOS: TASAS DE CAMBIO ----------
INSERT INTO tasas_cambio (moneda, tasa_a_cop) VALUES ('USD', 4000.0000), ('EUR', 4300.0000);

-- ---------- DATOS: PROMOCIONES (5, para probar preguntas de negocio y eventos) ----------
INSERT INTO promociones (id_producto, fecha_inicio, fecha_fin, descuento_pct, activa) VALUES
(4, '2026-07-29', '2026-08-28', 20, 0),
(1, '2026-09-22', '2026-10-07', 30, 1),
(5, '2026-10-07', '2026-10-22', 20, 1),
(27, '2026-10-12', '2026-10-27', 10, 1),
(41, '2026-10-17', '2026-11-01', 15, 1);

-- ---------- DATOS: CARRITOS (8, algunos abandonados hace +72h) ----------
INSERT INTO carritos (id_cliente, fecha_creacion, estado) VALUES
(20, '2026-09-16 07:00:00', 'Abandonado'),
(26, '2026-09-18 14:00:00', 'Abandonado'),
(15, '2026-09-15 15:00:00', 'Abandonado'),
(26, '2026-09-19 06:00:00', 'Abandonado'),
(14, '2026-09-27 01:00:00', 'Activo'),
(50, '2026-09-27 07:00:00', 'Activo'),
(31, '2026-09-26 00:00:00', 'Activo'),
(10, '2026-09-26 13:00:00', 'Convertido');

INSERT INTO carrito_items (id_carrito, id_producto, cantidad, fecha_agregado) VALUES
(1, 19, 3, '2026-09-24 19:00:00'),
(1, 49, 2, '2026-09-19 22:00:00'),
(2, 18, 3, '2026-09-19 11:00:00'),
(3, 17, 1, '2026-09-17 05:00:00'),
(3, 28, 1, '2026-09-21 12:00:00'),
(3, 44, 2, '2026-09-22 06:00:00'),
(4, 20, 2, '2026-09-18 08:00:00'),
(4, 21, 3, '2026-09-25 16:00:00'),
(4, 31, 3, '2026-09-19 18:00:00'),
(5, 20, 2, '2026-09-26 06:00:00'),
(6, 37, 2, '2026-09-24 12:00:00'),
(7, 23, 1, '2026-09-27 06:00:00'),
(7, 41, 1, '2026-09-25 23:00:00'),
(7, 38, 3, '2026-09-21 05:00:00'),
(8, 39, 3, '2026-09-24 10:00:00'),
(8, 7, 1, '2026-09-23 12:00:00');

-- ---------- DATOS: RESENAS (solo de pares cliente-producto que si compraron) ----------
INSERT INTO resenas (id_producto, id_cliente, calificacion, comentario, fecha) VALUES
(13, 5, 3, 'El producto llegó con un defecto menor.', '2026-01-16 12:00:00'),
(10, 42, 4, 'Justo lo que necesitaba, volveria a comprar.', '2026-08-17 12:00:00'),
(16, 15, 3, 'Es correcto, pero esperaba mejor calidad.', '2026-07-29 12:00:00'),
(37, 49, 4, 'Cumple con lo prometido, lo recomiendo.', '2026-02-24 12:00:00'),
(26, 13, 5, 'Muy buen producto, llegó en perfecto estado.', '2026-01-27 12:00:00'),
(9, 15, 4, 'Excelente calidad, superó mis expectativas.', '2026-01-22 12:00:00'),
(16, 40, 4, 'Muy buen producto, llegó en perfecto estado.', '2026-01-18 12:00:00'),
(1, 15, 5, 'Muy buen producto, llegó en perfecto estado.', '2025-12-24 12:00:00'),
(42, 21, 4, 'Excelente calidad, superó mis expectativas.', '2026-07-06 12:00:00'),
(8, 33, 3, 'Es correcto, pero esperaba mejor calidad.', '2025-12-12 12:00:00'),
(34, 20, 4, 'Cumple con lo prometido, lo recomiendo.', '2026-01-31 12:00:00'),
(42, 33, 5, 'Buena relación calidad-precio.', '2026-08-19 12:00:00'),
(8, 47, 5, 'Cumple con lo prometido, lo recomiendo.', '2026-09-12 12:00:00'),
(48, 15, 5, 'Excelente calidad, superó mis expectativas.', '2026-04-10 12:00:00'),
(41, 48, 3, 'El producto llegó con un defecto menor.', '2026-01-08 12:00:00');

-- ---------- DATOS: REFERIDOS (3, de ejemplo) ----------
INSERT INTO referidos (id_cliente_referidor, id_cliente_referido, fecha) VALUES
(31, 32, '2026-07-15 12:00:00'),
(3, 14, '2026-02-26 12:00:00'),
(41, 9, '2026-04-06 12:00:00');

-- ---------- DATOS: VISTAS_PRODUCTO (120, para que la pregunta 18 tenga sentido) ----------
INSERT INTO vistas_producto (id_producto, id_cliente, fecha_vista) VALUES
(7, NULL, '2026-03-24 02:00:00'),
(31, NULL, '2025-12-18 06:00:00'),
(19, 28, '2026-05-21 19:00:00'),
(4, NULL, '2026-05-01 01:00:00'),
(32, 33, '2026-05-10 20:00:00'),
(23, NULL, '2025-10-26 21:00:00'),
(8, 21, '2025-09-27 03:00:00'),
(9, 41, '2026-08-14 11:00:00'),
(26, NULL, '2026-03-03 19:00:00'),
(37, 20, '2026-08-03 12:00:00'),
(3, 31, '2025-11-19 15:00:00'),
(4, NULL, '2025-12-22 17:00:00'),
(25, 41, '2025-10-17 14:00:00'),
(45, 44, '2026-08-16 06:00:00'),
(3, 30, '2025-11-11 07:00:00'),
(7, 3, '2026-02-24 09:00:00'),
(42, 9, '2026-04-21 19:00:00'),
(46, 20, '2026-06-24 23:00:00'),
(3, 28, '2025-12-11 16:00:00'),
(38, NULL, '2026-08-30 21:00:00'),
(37, 8, '2025-08-26 23:00:00'),
(37, 26, '2026-02-11 10:00:00'),
(1, 39, '2025-11-27 15:00:00'),
(10, 27, '2025-12-21 09:00:00'),
(6, 14, '2026-07-11 16:00:00'),
(1, 1, '2025-10-11 15:00:00'),
(8, NULL, '2026-08-13 06:00:00'),
(8, 2, '2026-05-08 13:00:00'),
(37, 47, '2025-09-11 07:00:00'),
(4, 48, '2025-09-26 14:00:00'),
(10, NULL, '2026-08-15 03:00:00'),
(41, 32, '2026-02-03 15:00:00'),
(17, NULL, '2026-08-31 14:00:00'),
(3, 1, '2025-10-28 15:00:00'),
(40, 20, '2026-04-20 13:00:00'),
(39, 32, '2025-11-20 11:00:00'),
(21, 37, '2025-09-19 22:00:00'),
(31, 10, '2026-07-30 01:00:00'),
(42, 27, '2026-01-26 00:00:00'),
(50, NULL, '2026-05-10 18:00:00'),
(22, 4, '2025-11-12 16:00:00'),
(46, NULL, '2025-11-24 02:00:00'),
(39, NULL, '2026-09-20 08:00:00'),
(39, NULL, '2025-12-01 23:00:00'),
(16, 44, '2026-03-18 17:00:00'),
(50, NULL, '2026-02-08 03:00:00'),
(45, 17, '2026-05-12 23:00:00'),
(11, 49, '2025-08-23 11:00:00'),
(19, NULL, '2025-12-09 08:00:00'),
(18, NULL, '2025-12-20 15:00:00'),
(50, NULL, '2026-04-02 19:00:00'),
(6, 32, '2026-03-16 06:00:00'),
(49, NULL, '2026-05-31 03:00:00'),
(39, 26, '2026-01-31 14:00:00'),
(14, NULL, '2025-12-01 12:00:00'),
(25, 6, '2025-12-27 01:00:00'),
(50, 26, '2025-12-04 20:00:00'),
(17, NULL, '2026-01-03 02:00:00'),
(31, 13, '2026-06-23 06:00:00'),
(13, 45, '2026-05-02 01:00:00'),
(37, 26, '2025-08-23 20:00:00'),
(10, 32, '2026-03-20 09:00:00'),
(24, 6, '2026-07-10 02:00:00'),
(39, 18, '2026-01-04 17:00:00'),
(2, 14, '2025-12-11 21:00:00'),
(38, 17, '2025-08-25 04:00:00'),
(28, 29, '2025-08-30 18:00:00'),
(39, NULL, '2026-05-20 11:00:00'),
(22, 12, '2026-03-18 10:00:00'),
(2, 36, '2026-03-21 14:00:00'),
(30, 5, '2025-11-24 16:00:00'),
(26, NULL, '2025-10-01 10:00:00'),
(17, 15, '2025-11-03 10:00:00'),
(43, 12, '2026-02-10 07:00:00'),
(24, NULL, '2025-09-23 05:00:00'),
(12, 17, '2026-03-31 11:00:00'),
(36, NULL, '2026-09-03 04:00:00'),
(33, NULL, '2025-10-30 21:00:00'),
(4, 21, '2025-09-06 12:00:00'),
(13, 20, '2025-11-29 18:00:00'),
(29, NULL, '2026-08-04 21:00:00'),
(21, 25, '2026-07-26 01:00:00'),
(31, 29, '2026-05-28 08:00:00'),
(44, NULL, '2026-01-30 14:00:00'),
(13, NULL, '2026-07-09 05:00:00'),
(5, NULL, '2026-03-19 13:00:00'),
(9, NULL, '2026-08-09 00:00:00'),
(2, 29, '2026-04-07 02:00:00'),
(15, 41, '2026-03-24 08:00:00'),
(22, 4, '2026-06-26 14:00:00'),
(29, 10, '2026-02-15 08:00:00'),
(18, 16, '2026-07-10 12:00:00'),
(18, 19, '2026-04-09 07:00:00'),
(17, 21, '2026-02-05 21:00:00'),
(8, 33, '2026-08-28 16:00:00'),
(43, NULL, '2025-12-14 21:00:00'),
(19, 49, '2026-06-16 01:00:00'),
(28, NULL, '2026-05-28 05:00:00'),
(7, 27, '2026-07-06 11:00:00'),
(47, NULL, '2026-07-15 16:00:00'),
(2, 33, '2026-04-05 20:00:00'),
(9, 34, '2026-05-04 07:00:00'),
(24, 27, '2026-06-08 04:00:00'),
(37, 12, '2026-01-03 05:00:00'),
(46, 39, '2026-08-18 10:00:00'),
(39, NULL, '2025-09-03 04:00:00'),
(12, 40, '2025-10-19 14:00:00'),
(41, NULL, '2025-12-03 03:00:00'),
(13, 45, '2025-09-16 20:00:00'),
(27, NULL, '2026-08-29 20:00:00'),
(23, 41, '2026-01-18 10:00:00'),
(1, 49, '2026-01-26 08:00:00'),
(43, 12, '2025-12-13 01:00:00'),
(3, 24, '2025-12-06 17:00:00'),
(1, 29, '2026-01-06 10:00:00'),
(8, 16, '2026-04-15 14:00:00'),
(25, 4, '2026-05-01 09:00:00'),
(47, 33, '2026-09-13 20:00:00'),
(35, 16, '2026-08-13 05:00:00'),
(40, 7, '2026-04-21 04:00:00');
