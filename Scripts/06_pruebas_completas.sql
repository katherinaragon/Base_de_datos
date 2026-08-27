-- =====================================================================
-- PROYECTO BD: GYMCONNECT - GUION MAESTRO DE PRUEBAS
-- Archivo: 07_pruebas_completas.sql
-- Motor: MySQL / MariaDB
--
-- Notas del grupo:
-- Script maestro de pruebas integrales para validación de la lógica de negocio.
-- Verifica en orden todos los objetos programables y reglas de negocio (RN):
--   - BLOQUE 0: Inventario general de objetos creados
--   - BLOQUE 1: Vistas gerenciales (3)
--   - BLOQUE 2: Funciones definidas por el usuario (1)
--   - BLOQUE 3: Procedimientos almacenados y transacción explícita (3)
--   - BLOQUE 4: Triggers de auditoría, validación y actualización (8)
--   - BLOQUE 5: Limpieza y verificación de estado final
--
-- NOTA IMPORTANTE: Algunas pruebas están diseñadas para FALLAR a propósito 
-- (evidencia de control de reglas de negocio RN-01, RN-04, RN-10, RN-07).
-- =====================================================================

USE gymconnect_db;


-- =====================================================================
-- BLOQUE 0 - INVENTARIO DE OBJETOS
-- =====================================================================

-- PRUEBA 0.1 - Conteo de objetos creados por tipo
SELECT
  (SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = 'gymconnect_db' AND table_type = 'BASE TABLE')          AS tablas,
  (SELECT COUNT(*) FROM information_schema.views
    WHERE table_schema = 'gymconnect_db')                                         AS vistas,
  (SELECT COUNT(*) FROM information_schema.routines
    WHERE routine_schema = 'gymconnect_db' AND routine_type = 'PROCEDURE')        AS procedimientos,
  (SELECT COUNT(*) FROM information_schema.routines
    WHERE routine_schema = 'gymconnect_db' AND routine_type = 'FUNCTION')         AS funciones,
  (SELECT COUNT(*) FROM information_schema.triggers
    WHERE trigger_schema = 'gymconnect_db')                                       AS triggers;

-- PRUEBA 0.2 - Listado detallado de objetos del esquema
SELECT 'VISTA' AS tipo, table_name AS nombre
  FROM information_schema.views      WHERE table_schema   = 'gymconnect_db'
UNION ALL
SELECT routine_type, routine_name
  FROM information_schema.routines   WHERE routine_schema = 'gymconnect_db'
UNION ALL
SELECT 'TRIGGER', trigger_name
  FROM information_schema.triggers   WHERE trigger_schema = 'gymconnect_db'
 ORDER BY tipo, nombre;


-- =====================================================================
-- BLOQUE 1 - VISTAS GERENCIALES
-- =====================================================================

-- PRUEBA 1.1 - vista_membresias_activas
SELECT * FROM vista_membresias_activas
 ORDER BY dias_restantes;

-- PRUEBA 1.2 - vista_ocupacion_clases
SELECT * FROM vista_ocupacion_clases
 ORDER BY fecha_sesion, hora_inicio
 LIMIT 15;

-- PRUEBA 1.3 - vista_ingresos_por_plan
SELECT * FROM vista_ingresos_por_plan
 ORDER BY periodo DESC, ingresos_totales DESC;


-- =====================================================================
-- BLOQUE 2 - FUNCIONALIDAD DE FUNCIONES
-- =====================================================================

-- PRUEBA 2.1 - Llamada directa a fn_edad_cliente
SELECT fn_edad_cliente('1995-05-20') AS edad_calculada;

-- PRUEBA 2.2 - Uso de fn_edad_cliente dentro de una consulta estructurada
SELECT CONCAT(nombres, ' ', apellidos)              AS cliente,
       fecha_nacimiento,
       fn_edad_cliente(fecha_nacimiento)            AS edad,
       CASE
           WHEN fn_edad_cliente(fecha_nacimiento) < 25 THEN 'Joven'
           WHEN fn_edad_cliente(fecha_nacimiento) < 45 THEN 'Adulto'
           ELSE 'Adulto mayor'
       END                                          AS rango_etario
  FROM cliente
 ORDER BY edad DESC
 LIMIT 12;


-- =====================================================================
-- BLOQUE 3 - PROCEDIMIENTOS ALMACENADOS Y TRANSACCIONES
-- =====================================================================

-- PRUEBA 3.1 - sp_registrar_pago (Caso Exitoso)
SET @mem := (SELECT MIN(id_membresia_cliente) FROM membresia_cliente);
CALL sp_registrar_pago(@mem, 88888, 'efectivo', @resultado);
SELECT @mem AS membresia_usada, @resultado AS resultado;

-- PRUEBA 3.2 - sp_registrar_pago (Manejador de error: Membresía Inexistente)
CALL sp_registrar_pago(99999, 50000, 'efectivo', @resultado);
SELECT @resultado AS resultado;

-- PRUEBA 3.3 - sp_registrar_pago (Manejador de error: Monto Inválido)
SET @mem := (SELECT MIN(id_membresia_cliente) FROM membresia_cliente);
CALL sp_registrar_pago(@mem, -100, 'efectivo', @resultado);
SELECT @resultado AS resultado;

-- PRUEBA 3.4 - sp_inscribir_cliente_clase (Caso Exitoso)
INSERT INTO horario_clase (id_clase, numero_sesion, fecha_sesion, hora_inicio, hora_fin,
                            id_zona, id_empleado, cupo_maximo)
SELECT 1,
       COALESCE(MAX(numero_sesion), 0) + 1,
       '2027-01-10', '09:00:00', '10:00:00',
       9,
       (SELECT MIN(id_empleado) FROM entrenador),
       20
  FROM horario_clase
 WHERE id_clase = 1;

SET @sesion := (SELECT numero_sesion FROM horario_clase WHERE fecha_sesion = '2027-01-10');
SET @cli    := (SELECT MIN(id_cliente) FROM cliente);

CALL sp_inscribir_cliente_clase(@cli, 1, @sesion, @resultado);
SELECT @cli AS cliente, @sesion AS sesion, @resultado AS resultado;

-- PRUEBA 3.5 - sp_inscripcion_con_pago (Transacción Explicita Exitosa - Atomicidad)
SET @cliente_libre := (SELECT c.id_cliente
                         FROM cliente c
                        WHERE NOT EXISTS (SELECT 1 FROM membresia_cliente m
                                           WHERE m.id_cliente = c.id_cliente
                                             AND m.estado = 'activa')
                        LIMIT 1);

CALL sp_inscripcion_con_pago(@cliente_libre, 2, CURDATE(), 'tarjeta', @resultado);
SELECT @cliente_libre AS cliente, @resultado AS resultado;

-- PRUEBA 3.5b - Verificación de inserción en ambas tablas (membresía y pago)
SELECT mc.id_membresia_cliente,
       mc.id_cliente,
       mc.fecha_inicio,
       mc.fecha_fin,
       mc.estado,
       mc.precio_pagado,
       p.id_pago,
       p.monto,
       p.estado_pago
  FROM membresia_cliente mc
  LEFT JOIN pago p ON p.id_membresia_cliente = mc.id_membresia_cliente
 WHERE mc.fecha_inicio = CURDATE();

-- PRUEBA 3.6 - sp_inscripcion_con_pago (Transacción Revertida por error - Rollback)
SELECT COUNT(*) AS membresias_antes FROM membresia_cliente;

SET @cliente_ocupado := (SELECT id_cliente FROM membresia_cliente
                          WHERE estado = 'activa' LIMIT 1);

CALL sp_inscripcion_con_pago(@cliente_ocupado, 1, CURDATE(), 'efectivo', @resultado);
SELECT @cliente_ocupado AS cliente, @resultado AS resultado;

SELECT COUNT(*) AS membresias_despues FROM membresia_cliente;


-- =====================================================================
-- BLOQUE 4 - TRIGGERS Y REGLAS DE NEGOCIO
-- =====================================================================

-- PRUEBA 4.1 - Auditoría de Operaciones en Tabla Pago (RN-11)
SELECT 'ANTES' AS momento, COUNT(*) AS registros_en_auditoria FROM auditoria;

INSERT INTO pago (id_membresia_cliente, fecha_pago, monto, metodo_pago, estado_pago)
SELECT MIN(id_membresia_cliente), CURDATE(), 123456, 'efectivo', 'completado'
  FROM membresia_cliente;

UPDATE pago SET monto = 654321
 WHERE monto = 123456 AND fecha_pago = CURDATE();

DELETE FROM pago
 WHERE monto = 654321 AND fecha_pago = CURDATE();

SELECT id_auditoria, tabla_afectada, operacion, usuario_bd,
       fecha_hora, id_registro_afectado,
       valores_anteriores, valores_nuevos
  FROM auditoria
 ORDER BY id_auditoria;

-- PRUEBA 4.2 - Validación: Segunda Membresía Activa (RN-01) [DEBE FALLAR]
SELECT mc.id_cliente,
       CONCAT(c.nombres, ' ', c.apellidos) AS cliente,
       mc.id_membresia_cliente, mc.estado, mc.fecha_fin
  FROM membresia_cliente mc
  JOIN cliente c ON c.id_cliente = mc.id_cliente
 WHERE mc.estado = 'activa'
 ORDER BY mc.id_cliente
 LIMIT 1;

INSERT INTO membresia_cliente (id_cliente, id_plan, fecha_inicio, fecha_fin, estado, precio_pagado)
SELECT id_cliente, 1, CURDATE(), DATE_ADD(CURDATE(), INTERVAL 1 MONTH), 'activa', 120000
  FROM membresia_cliente
 WHERE estado = 'activa'
 ORDER BY id_cliente
 LIMIT 1;

SELECT id_cliente, COUNT(*) AS membresias_activas
  FROM membresia_cliente
 WHERE estado = 'activa'
 GROUP BY id_cliente
 ORDER BY id_cliente
 LIMIT 1;

-- PRUEBA 4.3 - Actualización Automática: Pago Rechazado (RN-12)
INSERT INTO membresia_cliente (id_cliente, id_plan, fecha_inicio, fecha_fin, estado, precio_pagado)
SELECT c.id_cliente, 1, CURDATE(), DATE_ADD(CURDATE(), INTERVAL 1 MONTH), 'activa', 99999
  FROM cliente c
 WHERE NOT EXISTS (SELECT 1 FROM membresia_cliente m
                    WHERE m.id_cliente = c.id_cliente AND m.estado = 'activa')
 LIMIT 1;

SELECT 'ANTES del pago rechazado' AS momento,
       id_membresia_cliente, id_cliente, estado
  FROM membresia_cliente
 WHERE precio_pagado = 99999;

SET @mem_prueba := (SELECT id_membresia_cliente FROM membresia_cliente
                     WHERE precio_pagado = 99999 LIMIT 1);

INSERT INTO pago (id_membresia_cliente, fecha_pago, monto, metodo_pago, estado_pago)
VALUES (@mem_prueba, CURDATE(), 99999, 'tarjeta', 'rechazado');

SELECT 'DESPUÉS del pago rechazado' AS momento,
       id_membresia_cliente, id_cliente, estado
  FROM membresia_cliente
 WHERE precio_pagado = 99999;

-- PRUEBA 4.4 - Validación: Control de Cupo Máximo (RN-04) [DEBE FALLAR]
INSERT INTO horario_clase (id_clase, numero_sesion, fecha_sesion, hora_inicio, hora_fin,
                            id_zona, id_empleado, cupo_maximo)
SELECT 1,
       COALESCE(MAX(numero_sesion), 0) + 1,
       '2027-01-15', '07:00:00', '08:00:00',
       9,
       (SELECT MIN(id_empleado) FROM entrenador),
       1
  FROM horario_clase
 WHERE id_clase = 1;

INSERT INTO asistencia (id_cliente, id_clase, numero_sesion)
SELECT (SELECT MIN(id_cliente) FROM cliente), 1, numero_sesion
  FROM horario_clase
 WHERE fecha_sesion = '2027-01-15';

SELECT hc.id_clase, hc.numero_sesion, hc.cupo_maximo,
       COUNT(a.id_asistencia) AS inscritos
  FROM horario_clase hc
  LEFT JOIN asistencia a ON a.id_clase = hc.id_clase
                        AND a.numero_sesion = hc.numero_sesion
 WHERE hc.fecha_sesion = '2027-01-15'
 GROUP BY hc.id_clase, hc.numero_sesion, hc.cupo_maximo;

INSERT INTO asistencia (id_cliente, id_clase, numero_sesion)
SELECT (SELECT MAX(id_cliente) FROM cliente), 1, numero_sesion
  FROM horario_clase
 WHERE fecha_sesion = '2027-01-15';

-- PRUEBA 4.5 - Validación: Traslape de Horarios (RN-10) [DEBE FALLAR]
SELECT hc.id_clase, hc.numero_sesion, hc.fecha_sesion,
       hc.hora_inicio, hc.hora_fin, hc.id_empleado,
       CONCAT(e.nombres, ' ', e.apellidos) AS entrenador
  FROM horario_clase hc
  JOIN empleado e ON e.id_empleado = hc.id_empleado
 WHERE hc.id_clase = 1 AND hc.numero_sesion = 1;

INSERT INTO horario_clase (id_clase, numero_sesion, fecha_sesion, hora_inicio, hora_fin,
                            id_zona, id_empleado, cupo_maximo)
SELECT 2, 900, hc.fecha_sesion, '06:30:00', '07:20:00', 7, hc.id_empleado, 15
  FROM horario_clase hc
 WHERE hc.id_clase = 1 AND hc.numero_sesion = 1;

-- PRUEBA 4.6 - Validación: Auto-supervisión de Empleados (RN-07) [DEBE FALLAR]
UPDATE empleado
   SET id_supervisor = id_empleado
 WHERE id_empleado = (SELECT MIN(id_empleado) FROM (SELECT id_empleado FROM empleado) t);


-- =====================================================================
-- BLOQUE 5 - LIMPIEZA Y VERIFICACIÓN DE ESTADO FINAL
-- =====================================================================

-- 5.1 Restablecimiento de asistencias y horarios de prueba
DELETE FROM asistencia
 WHERE (id_clase, numero_sesion) IN (
       SELECT id_clase, numero_sesion FROM (
              SELECT id_clase, numero_sesion FROM horario_clase
               WHERE fecha_sesion IN ('2027-01-10', '2027-01-15')) t);

DELETE FROM horario_clase WHERE fecha_sesion IN ('2027-01-10', '2027-01-15');

-- 5.2 Eliminación de registros de pago de prueba
DELETE FROM pago WHERE monto IN (88888, 123456, 654321);

-- 5.3 Restablecimiento de membresías de prueba
DELETE FROM membresia_cliente WHERE fecha_inicio = CURDATE();

-- 5.4 Verificación final de registros
SELECT (SELECT COUNT(*) FROM cliente)           AS clientes,
       (SELECT COUNT(*) FROM empleado)          AS empleados,
       (SELECT COUNT(*) FROM membresia_cliente) AS membresias,
       (SELECT COUNT(*) FROM pago)              AS pagos,
       (SELECT COUNT(*) FROM horario_clase)     AS sesiones,
       (SELECT COUNT(*) FROM asistencia)        AS asistencias,
       (SELECT COUNT(*) FROM auditoria)         AS registros_auditoria;

