# Proyecto de Base de Datos para un E-commerce

## Descripción

Este proyecto diseña e implementa el núcleo de una base de datos relacional para una tienda en línea. Cubre la definición del modelo de datos (productos, categorías, proveedores, clientes, ventas y su detalle), un dataset de prueba coherente para validar todo lo demás, 20 consultas analíticas para responder preguntas de negocio, 20 funciones definidas por el usuario, un esquema de seguridad basado en roles, 20 triggers para automatizar reglas de integridad, 20 eventos programados para tareas de mantenimiento y 20 procedimientos almacenados para operaciones transaccionales complejas. El objetivo es que la base de datos no solo almacene información, sino que además la valide, la audite y reaccione automáticamente ante los cambios del negocio.

## Integrantes

- Juan Esteban Cardenas Rivera

## Instrucciones de Ejecución

Los scripts deben ejecutarse **en este orden exacto**, contra un servidor **MySQL 8.0 o superior** (varias funciones, triggers y consultas usan CTEs, funciones de ventana y roles que no existen en versiones anteriores):

1. **`01_Esquema_y_Datos.sql`** — Crea la base de datos `ecommerce`, todas las tablas del proyecto y carga el dataset de ejemplo (50 registros en cada tabla principal, más datos de apoyo en las tablas secundarias). Ejecutarlo primero es obligatorio: todo lo demás depende de que el esquema y los datos ya existan.

2. **`02_Consultas_Avanzadas.sql`** — Las 20 consultas de análisis y reporteo. Se pueden ejecutar en cualquier momento después del paso 1; no crean ni modifican tablas, solo consultan.

3. **`03_Funciones.sql`** — Las 20 funciones definidas por el usuario (UDFs). Varios triggers, eventos y procedimientos posteriores dependen de que estas funciones ya existan.

4. **`07_Procedimientos_Almacenados.sql`** — Los 20 procedimientos almacenados. **Se ejecuta antes que el paso 5** aunque su número de archivo sea el 7, porque `04_Seguridad.sql` otorga permisos de ejecución sobre uno de estos procedimientos y necesita que ya exista.

5. **`04_Seguridad.sql`** — Roles, usuarios y permisos (GRANT/REVOKE).

6. **`05_Triggers.sql`** — Crea la tabla de auditoría `log_cambios_precio` y los 20 triggers.

7. **`06_Eventos.sql`** — Crea la tabla `reporte_ventas_semanales`, activa el programador de eventos de MySQL (`event_scheduler`) y define los 20 eventos programados.

### Resumen del orden real de ejecución

```
01_Esquema_y_Datos.sql
02_Consultas_Avanzadas.sql
03_Funciones.sql
07_Procedimientos_Almacenados.sql
04_Seguridad.sql
05_Triggers.sql
06_Eventos.sql
```

### Notas importantes antes de ejecutar

- Si el servidor tiene el binary log activado, puede ser necesario ejecutar una sola vez `SET GLOBAL log_bin_trust_function_creators = 1;` antes de `03_Funciones.sql`.
- Los eventos programados no se ejecutan solos: `06_Eventos.sql` activa `event_scheduler`, pero si tu servidor lo tiene deshabilitado por configuración, confírmalo con `SHOW VARIABLES LIKE 'event_scheduler';`.
- Los datos se insertan **antes** de crear los triggers a propósito: si los triggers ya existieran durante la carga masiva de datos, dispararían recálculos automáticos que chocarían con los valores que `01_Esquema_y_Datos.sql` ya calcula explícitamente (totales de venta, stock, contadores por categoría, etc.).
- Algunos requerimientos del enunciado piden funcionalidad que MySQL no puede resolver de forma nativa con SQL puro (por ejemplo, auditar intentos de login fallidos o backups reales desde un evento). En esos casos, el script correspondiente deja la aproximación funcional más cercana y explica en un comentario qué se necesitaría fuera de la base de datos para resolverlo por completo.
