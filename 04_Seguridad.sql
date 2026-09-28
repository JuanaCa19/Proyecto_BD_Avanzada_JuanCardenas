-- =====================================================================
-- 04_Seguridad.sql
-- Roles, usuarios y permisos (20 requerimientos).
-- Requiere haber corrido antes: 01_Esquema_y_Datos.sql y
-- 07_Procedimientos_Almacenados.sql (el punto 12 le da permisos de
-- ejecucion a un procedimiento, asi que debe existir primero).
--
-- Requiere MySQL 8.0+ (los ROLES no existen en MySQL 5.7 ni versiones
-- anteriores; en ese caso hay que otorgar los privilegios directamente
-- a cada usuario en vez de a un rol).
-- Ejecutar como un usuario con privilegios de administrador.
-- =====================================================================

USE ecommerce;

-- ---------------------------------------------------------------------
-- 1. Rol Administrador_Sistema con todos los privilegios
-- ---------------------------------------------------------------------
CREATE ROLE 'Administrador_Sistema';
GRANT ALL PRIVILEGES ON ecommerce.* TO 'Administrador_Sistema';


-- ---------------------------------------------------------------------
-- 2. Rol Gerente_Marketing: solo lectura a ventas y clientes
-- ---------------------------------------------------------------------
CREATE ROLE 'Gerente_Marketing';
GRANT SELECT ON ecommerce.ventas TO 'Gerente_Marketing';
GRANT SELECT ON ecommerce.clientes TO 'Gerente_Marketing';
GRANT SELECT ON ecommerce.detalle_ventas TO 'Gerente_Marketing';


-- ---------------------------------------------------------------------
-- 3. Rol Analista_Datos: solo lectura a TODO excepto tablas de auditoria
--    (las tablas log_* y auditoria quedan fuera)
-- ---------------------------------------------------------------------
CREATE ROLE 'Analista_Datos';
GRANT SELECT ON ecommerce.categorias        TO 'Analista_Datos';
GRANT SELECT ON ecommerce.proveedores       TO 'Analista_Datos';
GRANT SELECT ON ecommerce.productos         TO 'Analista_Datos';
GRANT SELECT ON ecommerce.clientes          TO 'Analista_Datos';
GRANT SELECT ON ecommerce.ventas            TO 'Analista_Datos';
GRANT SELECT ON ecommerce.detalle_ventas    TO 'Analista_Datos';
GRANT SELECT ON ecommerce.promociones       TO 'Analista_Datos';
GRANT SELECT ON ecommerce.resenas           TO 'Analista_Datos';
-- Deliberadamente NO se otorga SELECT sobre log_cambios_precio, log_clientes,
-- log_estado_pedido, log_permisos, log_intentos_login, log_ajustes_stock.


-- ---------------------------------------------------------------------
-- 4. Rol Empleado_Inventario: solo puede modificar productos (stock y ubicacion)
-- ---------------------------------------------------------------------
CREATE ROLE 'Empleado_Inventario';
GRANT SELECT ON ecommerce.productos TO 'Empleado_Inventario';
GRANT UPDATE (stock, ubicacion) ON ecommerce.productos TO 'Empleado_Inventario';


-- ---------------------------------------------------------------------
-- 5. Rol Atencion_Cliente: ve clientes y ventas, no modifica precios
-- ---------------------------------------------------------------------
CREATE ROLE 'Atencion_Cliente';
GRANT SELECT ON ecommerce.clientes TO 'Atencion_Cliente';
GRANT SELECT ON ecommerce.ventas TO 'Atencion_Cliente';
GRANT SELECT ON ecommerce.detalle_ventas TO 'Atencion_Cliente';
GRANT UPDATE (estado) ON ecommerce.ventas TO 'Atencion_Cliente';
-- No se otorga ningun privilegio sobre productos.precio


-- ---------------------------------------------------------------------
-- 6. Rol Auditor_Financiero: solo lectura a ventas, productos y logs de precios
-- ---------------------------------------------------------------------
CREATE ROLE 'Auditor_Financiero';
GRANT SELECT ON ecommerce.ventas TO 'Auditor_Financiero';
GRANT SELECT ON ecommerce.productos TO 'Auditor_Financiero';
GRANT SELECT ON ecommerce.log_cambios_precio TO 'Auditor_Financiero';


-- ---------------------------------------------------------------------
-- 7-10. Crear usuarios y asignarles su rol
--       CAMBIA estas contrasenas antes de usarlas en un entorno real.
-- ---------------------------------------------------------------------
CREATE USER 'admin_user'@'localhost'     IDENTIFIED BY 'CambiaEstaClave_Admin1!';
CREATE USER 'marketing_user'@'localhost' IDENTIFIED BY 'CambiaEstaClave_Mkt1!';
CREATE USER 'inventory_user'@'localhost' IDENTIFIED BY 'CambiaEstaClave_Inv1!';
CREATE USER 'support_user'@'localhost'   IDENTIFIED BY 'CambiaEstaClave_Sup1!';

GRANT 'Administrador_Sistema' TO 'admin_user'@'localhost';
GRANT 'Gerente_Marketing'     TO 'marketing_user'@'localhost';
GRANT 'Empleado_Inventario'   TO 'inventory_user'@'localhost';
GRANT 'Atencion_Cliente'      TO 'support_user'@'localhost';

SET DEFAULT ROLE 'Administrador_Sistema' TO 'admin_user'@'localhost';
SET DEFAULT ROLE 'Gerente_Marketing'     TO 'marketing_user'@'localhost';
SET DEFAULT ROLE 'Empleado_Inventario'   TO 'inventory_user'@'localhost';
SET DEFAULT ROLE 'Atencion_Cliente'      TO 'support_user'@'localhost';


-- ---------------------------------------------------------------------
-- 11. Impedir que Analista_Datos ejecute DELETE o TRUNCATE
--     (por construccion nunca se le otorgaron; el REVOKE es explicito
--      y defensivo, por si en el futuro alguien se lo da por error)
-- ---------------------------------------------------------------------
REVOKE DELETE, DROP ON ecommerce.* FROM 'Analista_Datos';
-- TRUNCATE en MySQL requiere el privilegio DROP, por eso se revoca DROP tambien.


-- ---------------------------------------------------------------------
-- 12. Gerente_Marketing puede ejecutar procedimientos de reportes de marketing
--    (se asume que sp_GenerarReporteMensualVentas cumple ese rol; ver
--     07_Procedimientos_Almacenados.sql, que debe ejecutarse ANTES que
--     este archivo para que el GRANT de abajo no falle)
-- ---------------------------------------------------------------------
GRANT EXECUTE ON PROCEDURE ecommerce.sp_GenerarReporteMensualVentas TO 'Gerente_Marketing';


-- ---------------------------------------------------------------------
-- 13. Vista v_info_clientes_basica que oculta info sensible + acceso a Atencion_Cliente
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_info_clientes_basica AS
SELECT
    id_cliente,
    nombre,
    apellido,
    ciudad,
    fecha_registro
FROM clientes;
-- Se excluyen a proposito: email, contrasena, direccion_envio completa

GRANT SELECT ON ecommerce.v_info_clientes_basica TO 'Atencion_Cliente';


-- ---------------------------------------------------------------------
-- 14. Revocar UPDATE sobre productos.precio a Empleado_Inventario
--     (defensivo: nunca se le otorgo esa columna en el punto 4, pero se
--      deja explicito por si el esquema de privilegios cambia)
-- ---------------------------------------------------------------------
REVOKE UPDATE (precio) ON ecommerce.productos FROM 'Empleado_Inventario';


-- ---------------------------------------------------------------------
-- 15. Politica de contrasenas seguras para todos los usuarios
--     Requiere el plugin validate_password instalado en el servidor.
-- ---------------------------------------------------------------------
-- INSTALL COMPONENT 'file://component_validate_password';  -- MySQL 8.0+
SET GLOBAL validate_password.policy = 'STRONG';
SET GLOBAL validate_password.length = 8;
SET GLOBAL validate_password.mixed_case_count = 1;
SET GLOBAL validate_password.number_count = 1;
SET GLOBAL validate_password.special_char_count = 1;
-- NOTA: los nombres de estas variables cambian entre MySQL 5.7
-- (validate_password_policy, sin punto) y 8.0 (validate_password.policy,
-- con punto). Ajusta segun tu version con: SHOW VARIABLES LIKE 'validate%';


-- ---------------------------------------------------------------------
-- 16. Asegurar que root no pueda conectarse desde conexiones remotas
-- ---------------------------------------------------------------------
-- Verifica primero que existan otras cuentas root remotas:
-- SELECT user, host FROM mysql.user WHERE user = 'root';

DROP USER IF EXISTS 'root'@'%';
-- Deja unicamente 'root'@'localhost' (y 'root'@'127.0.0.1' si tu
-- instalacion lo usa) para que root solo pueda entrar desde el propio
-- servidor.
FLUSH PRIVILEGES;


-- ---------------------------------------------------------------------
-- 17. Rol Visitante: solo puede ver la tabla productos
-- ---------------------------------------------------------------------
CREATE ROLE 'Visitante';
GRANT SELECT ON ecommerce.productos TO 'Visitante';


-- ---------------------------------------------------------------------
-- 18. Limitar consultas por hora para el rol Analista_Datos
--     Los limites de recursos en MySQL se asignan por USUARIO, no por
--     rol, asi que se aplican a cada usuario que tenga ese rol asignado.
--     Ejemplo asumiendo que existe 'analista_user'@'localhost':
-- ---------------------------------------------------------------------
-- CREATE USER 'analista_user'@'localhost' IDENTIFIED BY 'CambiaEstaClave_An1!';
-- GRANT 'Analista_Datos' TO 'analista_user'@'localhost';
-- SET DEFAULT ROLE 'Analista_Datos' TO 'analista_user'@'localhost';
ALTER USER 'admin_user'@'localhost' WITH MAX_QUERIES_PER_HOUR 0;  -- 0 = sin limite (ejemplo admin)
-- Para limitar de verdad a un usuario con rol Analista_Datos:
-- ALTER USER 'analista_user'@'localhost' WITH MAX_QUERIES_PER_HOUR 500;


-- ---------------------------------------------------------------------
-- 19. Restringir que cada usuario solo vea las ventas de su sucursal
--     MySQL NO tiene seguridad a nivel de fila (RLS) nativa como
--     PostgreSQL. La forma de lograrlo es NO dar acceso directo a la
--     tabla "ventas", sino a una VISTA que filtra usando el usuario de
--     conexion, apoyada en la tabla usuarios_sucursal (ver
--     00_extensiones_esquema.sql).
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_ventas_sucursal AS
SELECT v.*
FROM ventas v
JOIN usuarios_sucursal us
    ON us.id_sucursal = v.id_sucursal
WHERE us.usuario_bd = SUBSTRING_INDEX(CURRENT_USER(), '@', 1);

-- Se revoca el acceso directo a la tabla y se otorga solo sobre la vista:
REVOKE SELECT ON ecommerce.ventas FROM 'Atencion_Cliente';
GRANT SELECT ON ecommerce.v_ventas_sucursal TO 'Atencion_Cliente';
-- Registra a cada usuario de atencion al cliente en usuarios_sucursal, ej:
-- INSERT INTO usuarios_sucursal (usuario_bd, id_sucursal) VALUES ('support_user', 1);


-- ---------------------------------------------------------------------
-- 20. Auditar intentos de inicio de sesion fallidos
--     MySQL no dispara triggers de tabla en eventos de conexion/login
--     (los triggers solo reaccionan a INSERT/UPDATE/DELETE). Para
--     auditar logins fallidos de verdad se necesita:
--       a) El plugin MySQL Enterprise Audit (version paga), o
--       b) audit_log / general_log habilitado y luego procesado, o
--       c) Registrar el intento desde la CAPA DE APLICACION (tu backend)
--          cada vez que una autenticacion falla.
--     La tabla log_intentos_login ya existe (creada en el script 00)
--     para que tu aplicacion inserte ahi cada intento. Ejemplo de lo
--     que haria tu backend, no la base de datos, en cada login:
-- ---------------------------------------------------------------------
-- INSERT INTO log_intentos_login (usuario, exito, ip_origen)
-- VALUES ('correo@ejemplo.com', FALSE, '192.168.1.10');

-- Alternativa parcial dentro de MySQL (requiere privilegios de SUPER y
-- el plugin de auditoria activo):
-- INSTALL PLUGIN audit_log SONAME 'audit_log.so';
