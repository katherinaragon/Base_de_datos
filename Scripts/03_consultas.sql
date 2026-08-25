-- =====================================================================
-- PROYECTO BD: GYMCONNECT - CONSULTAS SQL Y REPORTES
-- Archivo: 03_consultas.sql
-- Motor: MySQL/MariaDB
--
-- Notas del grupo:
-- Este script contiene las 20 consultas requeridas para la entrega final 
-- (numeral 7.1). Se deben ejecutar secuencialmente tras cargar 01_ddl.sql 
-- y 02_inserts.sql. 
--
--                           Integrantes:
--                    Katherin Aragón Calderon
--                      Victor Manuel Aragón
--                      Julio Cesar Villegas
--                      Oscar Esteban Lopez
--                      Juan Pablo Giraldo
-- =====================================================================

USE gymconnect_db;

-- =====================================================================
-- BLOQUE 1. INNER JOIN DE 3 O MÁS TABLAS (4 consultas)
-- =====================================================================

-- Consulta 1
-- Listar cada sesión de clase programada junto con el nombre 
-- de la clase, la zona donde se realiza y el entrenador encargado.

SELECT
cl.nombre_clase,
hc.numero_sesion,
hc.fecha_sesion,
hc.hora_inicio,
z.nombre_zona,
CONCAT(e.nombres, ' ', e.apellidos) AS entrenador
FROM horario_clase hc
INNER JOIN clase cl ON cl.id_clase =hc.id_clase
INNER JOIN zona z  ON z.id_zona =hc.id_zona
INNER JOIN entrenador tr ON tr.id_empleado =hc.id_empleado
INNER JOIN empleado e ON e.id_empleado =tr.id_empleado
ORDER BY hc.fecha_sesion, hc.hora_inicio;

-- Consulta 2
-- Mostrar el historial de asistencia de los clientes, indicando 
-- el nombre del cliente, la clase a la que asistió y la fecha de la sesión.

SELECT
CONCAT(c.nombres, ' ', c.apellidos) AS cliente,
cl.nombre_clase,
hc.fecha_sesion,
a.fecha_registro AS fecha_asistencia
FROM asistencia a
INNER JOIN cliente c  ON c.id_cliente = a.id_cliente
INNER JOIN horario_clase hc ON hc.id_clase = a.id_clase AND hc.numero_sesion = a.numero_sesion
INNER JOIN clase cl  ON cl.id_clase = hc.id_clase
ORDER BY hc.fecha_sesion;

-- Consulta 3
-- Detallar cada pago registrado, mostrando el cliente que lo realizó, 
-- el plan de membresía asociado y el monto pagado.

SELECT
p.id_pago,
CONCAT(c.nombres, ' ',c.apellidos) AS cliente,
mp.nombre_plan,
p.fecha_pago,
p.monto,
p.metodo_pago,
p.estado_pago
FROM pago p
INNER JOIN membresia_cliente mc ON mc.id_membresia_cliente =p.id_membresia_cliente
INNER JOIN cliente c   ON c.id_cliente =mc.id_cliente
INNER JOIN membresia_plan mp ON mp.id_plan =mc.id_plan
ORDER BY p.fecha_pago DESC;

-- Consulta 4
-- Listar cada empleado con el nombre de su rol y el nombre 
-- de su supervisor directo (relación recursiva).

SELECT
CONCAT(e.nombres, ' ', e.apellidos) AS empleado,
r.nombre_rol,
CONCAT(s.nombres, ' ', s.apellidos) AS supervisor
FROM empleado e
INNER JOIN rol_empleado r ON r.id_rol = e.id_rol
LEFT  JOIN empleado s     ON s.id_empleado = e.id_supervisor
ORDER BY r.nombre_rol, empleado;


-- =====================================================================
-- BLOQUE 2. LEFT JOIN / RIGHT JOIN (2 consultas)
-- =====================================================================

-- Consulta 5
-- Listar todas las zonas del gimnasio con el detalle de sus equipos, 
-- incluyendo áreas que aún no tienen equipos asignados.

SELECT
    z.nombre_zona,
    z.piso,
    eq.nombre_equipo,
    eq.estado
FROM zona z
LEFT JOIN equipo eq ON eq.id_zona = z.id_zona
ORDER BY z.piso, z.nombre_zona;

-- Consulta 6
-- Listar todos los clientes registrados junto con sus membresías, 
-- incluyendo aquellos que todavía no han adquirido ningún plan.

SELECT
    CONCAT(c.nombres, ' ', c.apellidos) AS cliente,
    c.fecha_registro,
    mc.estado AS estado_membresia,
    mc.fecha_inicio
FROM cliente c
LEFT JOIN membresia_cliente mc ON mc.id_cliente = c.id_cliente
ORDER BY cliente;


-- =====================================================================
-- BLOQUE 3. AGREGACIÓN CON GROUP BY Y HAVING (4 consultas)
-- =====================================================================

-- Consulta 7
-- Identificar las zonas que tienen más de 3 equipos registrados, 
-- mostrando el conteo total por zona.

SELECT
    z.nombre_zona,
    COUNT(eq.id_equipo) AS total_equipos
FROM zona z
INNER JOIN equipo eq ON eq.id_zona = z.id_zona
GROUP BY z.id_zona, z.nombre_zona
HAVING COUNT(eq.id_equipo) > 3
ORDER BY total_equipos DESC;

-- Consulta 8
-- Identificar los clientes recurrentes que registran más de 2 
-- asistencias a clases grupales.

SELECT
    CONCAT(c.nombres, ' ', c.apellidos) AS cliente,
    COUNT(a.id_asistencia) AS total_asistencias
FROM cliente c
INNER JOIN asistencia a ON a.id_cliente = c.id_cliente
GROUP BY c.id_cliente, cliente
HAVING COUNT(a.id_asistencia) > 2
ORDER BY total_asistencias DESC;

-- Consulta 9
-- Calcular el ingreso total por método de pago, mostrando 
-- únicamente los métodos que superan $2.000.000 en recaudación efectiva.

SELECT
    metodo_pago,
    COUNT(*)   AS numero_pagos,
    SUM(monto) AS ingreso_total
FROM pago
WHERE estado_pago = 'completado'
GROUP BY metodo_pago
HAVING SUM(monto) > 2000000
ORDER BY ingreso_total DESC;

-- Consulta 10
-- Calcular el promedio de asistentes por sesión dictada para cada 
-- entrenador, filtrando quienes promedian 1 o más alumnos.

SELECT
    CONCAT(e.nombres, ' ', e.apellidos) AS entrenador,
    COUNT(DISTINCT hc.id_clase, hc.numero_sesion) AS sesiones_dictadas,
    ROUND(COUNT(a.id_asistencia) / COUNT(DISTINCT hc.id_clase, hc.numero_sesion), 2) AS promedio_asistentes
FROM horario_clase hc
INNER JOIN entrenador tr ON tr.id_empleado = hc.id_empleado
INNER JOIN empleado e    ON e.id_empleado = tr.id_empleado
LEFT  JOIN asistencia a  ON a.id_clase = hc.id_clase AND a.numero_sesion = hc.numero_sesion
GROUP BY e.id_empleado, entrenador
HAVING promedio_asistentes >= 1
ORDER BY promedio_asistentes DESC;


-- =====================================================================
-- BLOQUE 4. SUBCONSULTAS EN WHERE Y EN FROM (3 consultas)
-- =====================================================================

-- Consulta 11 (Subconsulta en WHERE)
-- Listar los pagos individuales cuyo monto es estrictamente 
-- superior al promedio general de pagos.

SELECT
    p.id_pago,
    p.monto,
    p.fecha_pago
FROM pago p
WHERE p.monto > (SELECT AVG(monto) FROM pago)
ORDER BY p.monto DESC;

-- Consulta 12 (Subconsulta en WHERE)
-- Listar los planes de membresía con una tarifa superior al 
-- promedio global de los planes del gimnasio.

SELECT
    nombre_plan,
    precio
FROM membresia_plan
WHERE precio > (SELECT AVG(precio) FROM membresia_plan)
ORDER BY precio DESC;

-- Consulta 13 (Subconsulta en FROM)
-- Obtener las 3 zonas con mayor concentración de clases a partir 
-- de una tabla derivada con el conteo de sesiones por zona.

SELECT
    zona_sesiones.nombre_zona,
    zona_sesiones.total_sesiones
FROM (
    SELECT z.nombre_zona, COUNT(*) AS total_sesiones
    FROM horario_clase hc
    INNER JOIN zona z ON z.id_zona = hc.id_zona
    GROUP BY z.nombre_zona
) AS zona_sesiones
ORDER BY zona_sesiones.total_sesiones DESC
LIMIT 3;


-- =====================================================================
-- BLOQUE 5. FUNCIONES DE FECHA Y DE CADENA (2 consultas)
-- =====================================================================

-- Consulta 14 (Funciones de fecha)
-- Mostrar la edad actual de los clientes y su antigüedad en meses 
-- calculadas mediante funciones nativas.

SELECT
    CONCAT(nombres, ' ', apellidos)                  AS cliente,
    fecha_nacimiento,
    TIMESTAMPDIFF(YEAR, fecha_nacimiento, CURDATE()) AS edad_anios,
    fecha_registro,
    TIMESTAMPDIFF(MONTH, fecha_registro, CURDATE())  AS antiguedad_meses
FROM cliente
ORDER BY antiguedad_meses DESC;

-- Consulta 15 (Funciones de cadena)
-- Enunciado: Generar un reporte de personal formateando nombres en mayúsculas, 
-- extrayendo el dominio de correo y calculando la longitud del nombre.
-- Nota de prueba: Aplica UPPER, SUBSTRING_INDEX y LENGTH para manipulación de texto.
SELECT
    UPPER(CONCAT(nombres, ' ', apellidos)) AS empleado_mayusculas,
    correo,
    SUBSTRING_INDEX(correo, '@', -1)       AS dominio_correo,
    LENGTH(CONCAT(nombres, apellidos))     AS longitud_nombre_completo
FROM empleado
ORDER BY empleado_mayusculas;


-- =====================================================================
-- BLOQUE 6. FUNCIÓN DE VENTANA (1 consulta)
-- =====================================================================

-- Consulta 16 (Función de ventana)
-- Generar un ranking de clientes según su volumen total de 
-- asistencias a clases grupales.

SELECT
CONCAT(c.nombres, ' ', c.apellidos) AS cliente,
COUNT(a.id_asistencia)              AS total_asistencias,
RANK() OVER (ORDER BY COUNT(a.id_asistencia) DESC) AS ranking_asistencia
FROM cliente c
INNER JOIN asistencia a ON a.id_cliente = c.id_cliente
GROUP BY c.id_cliente, cliente
ORDER BY ranking_asistencia;


-- =====================================================================
-- BLOQUE 7. CONSULTAS LIBRES DE VALOR PARA EL NEGOCIO (4 consultas)
-- =====================================================================

-- Consulta 17
-- Identificar las 5 clases grupales más concurridas según 
-- la asistencia acumulada en todas sus sesiones.

SELECT
cl.nombre_clase,
COUNT(a.id_asistencia) AS total_asistentes_acumulado
FROM clase cl
INNER JOIN horario_clase hc ON hc.id_clase = cl.id_clase
LEFT  JOIN asistencia a     ON a.id_clase = hc.id_clase AND a.numero_sesion = hc.numero_sesion
GROUP BY cl.id_clase, cl.nombre_clase
ORDER BY total_asistentes_acumulado DESC
LIMIT 5;

-- Consulta 18
-- Calcular el ingreso total recaudado por el gimnasio y el 
-- ticket promedio, considerando solo transacciones completadas.

SELECT
SUM(monto)           AS ingreso_total,
COUNT(*)             AS numero_pagos_completados,
ROUND(AVG(monto), 2) AS ticket_promedio
FROM pago
WHERE estado_pago = 'completado';

-- Consulta 19
-- Reportar los equipos que requieren mantenimiento o están fuera 
-- de servicio agrupados por zona para gestión operativa.

SELECT
z.nombre_zona,
SUM(CASE WHEN eq.estado = 'mantenimiento'    THEN 1 ELSE 0 END) AS en_mantenimiento,
SUM(CASE WHEN eq.estado ='fuera_de_servicio' THEN 1 ELSE 0 END) AS fuera_de_servicio
FROM zona z
INNER JOIN equipo eq ON eq.id_zona =z.id_zona
GROUP BY z.nombre_zona
HAVING en_mantenimiento >0 OR fuera_de_servicio > 0;

-- Consulta 20
-- Identificar clientes con membresía vencida hace más de 30 días 
-- que no registran planes activos vigentes.

SELECT
    CONCAT(c.nombres, ' ', c.apellidos) AS cliente,
    c.correo,
    mc.fecha_fin AS fecha_vencimiento,
    DATEDIFF(CURDATE(), mc.fecha_fin) AS dias_desde_vencimiento
FROM cliente c
INNER JOIN membresia_cliente mc ON mc.id_cliente = c.id_cliente
WHERE mc.estado = 'vencida'
  AND DATEDIFF(CURDATE(), mc.fecha_fin) > 30
  AND NOT EXISTS (
        SELECT 1 FROM membresia_cliente mc2
        WHERE mc2.id_cliente = c.id_cliente AND mc2.estado = 'activa'
  )
ORDER BY dias_desde_vencimiento DESC;

