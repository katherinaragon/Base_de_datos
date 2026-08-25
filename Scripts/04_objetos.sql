-- =====================================================================
-- PROYECTO BD: GYMCONNECT - PROGRAMACIÓN DE OBJETOS DE BASE DE DATOS
-- Archivo: 04_objetos.sql
-- Motor: MySQL / MariaDB
--
-- Notas del grupo:
-- Este script define la capa de lógica de negocio almacenada: Vistas,
-- Función de usuario, Triggers de validación/auditoría/actualización,
-- Procedimientos Almacenados y Transacción Explicita (numeral 7.2).
-- Debe ejecutarse inmediatamente después de 01_ddl.sql y 02_inserts.sql.
--
--                          Integrantes:
--                    Katherin Aragón Calderon
--                      Victor Manuel Aragón
--                      Julio Cesar Villegas
--                      Oscar Esteban Lopez
--                      Juan Pablo Giraldo
-- =====================================================================

USE gymconnect_db;

-- =====================================================================
-- 1. VISTAS GERENCIALES (3 vistas)
-- =====================================================================

-- 1.1 vista_membresias_activas
-- Propósito: Consolida cliente, membresia_plan y membresia_cliente
-- para proporcionar un reporte directo de miembros activos y sus días restantes.
DROP VIEW IF EXISTS vista_membresias_activas;
CREATE VIEW vista_membresias_activas AS
SELECT
    mc.id_membresia_cliente,
    c.id_cliente,
    CONCAT(c.nombres, ' ', c.apellidos) AS cliente,
    mp.nombre_plan,
    mc.fecha_inicio,
    mc.fecha_fin,
    DATEDIFF(mc.fecha_fin, CURDATE()) AS dias_restantes,
    mc.precio_pagado
FROM membresia_cliente mc
JOIN cliente c        ON c.id_cliente = mc.id_cliente
JOIN membresia_plan mp ON mp.id_plan = mc.id_plan
WHERE mc.estado = 'activa';

-- 1.2 vista_ocupacion_clases
-- Propósito: Integra clase, horario_clase, zona, entrenador,
-- empleado y asistencia para evaluar la ocupación y cupos disponibles en cada sesión.
DROP VIEW IF EXISTS vista_ocupacion_clases;
CREATE VIEW vista_ocupacion_clases AS
SELECT
    cl.nombre_clase,
    hc.id_clase,
    hc.numero_sesion,
    hc.fecha_sesion,
    hc.hora_inicio,
    z.nombre_zona,
    CONCAT(e.nombres, ' ', e.apellidos) AS entrenador,
    hc.cupo_maximo,
    COUNT(a.id_asistencia) AS asistentes_registrados,
    hc.cupo_maximo - COUNT(a.id_asistencia) AS cupos_disponibles
FROM horario_clase hc
JOIN clase cl        ON cl.id_clase = hc.id_clase
JOIN zona z           ON z.id_zona = hc.id_zona
JOIN entrenador tr    ON tr.id_empleado = hc.id_empleado
JOIN empleado e       ON e.id_empleado = tr.id_empleado
LEFT JOIN asistencia a ON a.id_clase = hc.id_clase AND a.numero_sesion = hc.numero_sesion
GROUP BY hc.id_clase, hc.numero_sesion, cl.nombre_clase, hc.fecha_sesion, hc.hora_inicio,
         z.nombre_zona, entrenador, hc.cupo_maximo;

-- 1.3 vista_ingresos_por_plan
-- Propósito: Agrupa los pagos completados por plan y período (YYYY-MM)
-- para el seguimiento de ingresos dentro del módulo financiero.
DROP VIEW IF EXISTS vista_ingresos_por_plan;
CREATE VIEW vista_ingresos_por_plan AS
SELECT
    mp.nombre_plan,
    DATE_FORMAT(p.fecha_pago, '%Y-%m') AS periodo,
    COUNT(p.id_pago)     AS numero_pagos,
    SUM(p.monto)         AS ingresos_totales
FROM pago p
JOIN membresia_cliente mc ON mc.id_membresia_cliente = p.id_membresia_cliente
JOIN membresia_plan mp    ON mp.id_plan = mc.id_plan
WHERE p.estado_pago = 'completado'
GROUP BY mp.nombre_plan, DATE_FORMAT(p.fecha_pago, '%Y-%m');


-- =====================================================================
-- 2. FUNCIONES DEFINIDAS POR EL USUARIO (1 función)
-- =====================================================================

-- fn_edad_cliente: Calcula la edad exacta en años a partir de la fecha de nacimiento.
DROP FUNCTION IF EXISTS fn_edad_cliente;
DELIMITER $$
CREATE FUNCTION fn_edad_cliente(p_fecha_nacimiento DATE)
RETURNS INT
DETERMINISTIC
BEGIN
    RETURN TIMESTAMPDIFF(YEAR, p_fecha_nacimiento, CURDATE());
END$$
DELIMITER ;

-- Demostración de uso de la función en una consulta SELECT (Requisito 7.2):
SELECT
    CONCAT(nombres, ' ', apellidos) AS cliente,
    fecha_nacimiento,
    fn_edad_cliente(fecha_nacimiento) AS edad_calculada
FROM cliente
ORDER BY edad_calculada DESC
LIMIT 10;


-- =====================================================================
-- 3. TRIGGERS Y REGLAS DE NEGOCIO (8 triggers)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 3.1 VALIDACIÓN COMPLEJA - RN-01: Evitar membresías activas simultáneas
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_membresia_valida_activa_ins;
DELIMITER $$
CREATE TRIGGER trg_membresia_valida_activa_ins
BEFORE INSERT ON membresia_cliente
FOR EACH ROW
BEGIN
    DECLARE v_activas INT;
    IF NEW.estado = 'activa' THEN
        SELECT COUNT(*) INTO v_activas
        FROM membresia_cliente
        WHERE id_cliente = NEW.id_cliente AND estado = 'activa';
        IF v_activas > 0 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'RN-01: El cliente ya tiene una membresia activa vigente.';
        END IF;
    END IF;
END$$
DELIMITER ;

DROP TRIGGER IF EXISTS trg_membresia_valida_activa_upd;
DELIMITER $$
CREATE TRIGGER trg_membresia_valida_activa_upd
BEFORE UPDATE ON membresia_cliente
FOR EACH ROW
BEGIN
    DECLARE v_activas INT;
    IF NEW.estado = 'activa' AND OLD.estado <> 'activa' THEN
        SELECT COUNT(*) INTO v_activas
        FROM membresia_cliente
        WHERE id_cliente = NEW.id_cliente AND estado = 'activa'
          AND id_membresia_cliente <> NEW.id_membresia_cliente;
        IF v_activas > 0 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'RN-01: El cliente ya tiene una membresia activa vigente.';
        END IF;
    END IF;
END$$
DELIMITER ;

-- ---------------------------------------------------------------------
-- 3.2 VALIDACIÓN COMPLEJA - RN-04: Control de cupo máximo en sesiones
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_asistencia_valida_cupo;
DELIMITER $$
CREATE TRIGGER trg_asistencia_valida_cupo
BEFORE INSERT ON asistencia
FOR EACH ROW
BEGIN
    DECLARE v_cupo INT;
    DECLARE v_ocupados INT;
    SELECT cupo_maximo INTO v_cupo
    FROM horario_clase
    WHERE id_clase = NEW.id_clase AND numero_sesion = NEW.numero_sesion;

    SELECT COUNT(*) INTO v_ocupados
    FROM asistencia
    WHERE id_clase = NEW.id_clase AND numero_sesion = NEW.numero_sesion;

    IF v_ocupados >= v_cupo THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RN-04: La sesion ya alcanzo su cupo maximo de asistentes.';
    END IF;
END$$
DELIMITER ;

-- ---------------------------------------------------------------------
-- 3.3 VALIDACIÓN COMPLEJA - RN-10: Evitar cruce de horarios en entrenadores
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_horario_valida_traslape;
DELIMITER $$
CREATE TRIGGER trg_horario_valida_traslape
BEFORE INSERT ON horario_clase
FOR EACH ROW
BEGIN
    DECLARE v_choques INT;
    SELECT COUNT(*) INTO v_choques
    FROM horario_clase
    WHERE id_empleado = NEW.id_empleado
      AND fecha_sesion = NEW.fecha_sesion
      AND hora_inicio < NEW.hora_fin
      AND hora_fin > NEW.hora_inicio;

    IF v_choques > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RN-10: El entrenador ya tiene una sesion asignada que se traslapa con este horario.';
    END IF;
END$$
DELIMITER ;

-- ---------------------------------------------------------------------
-- 3.4 VALIDACIÓN COMPLEJA - RN-02: Restricción de rol para entrenadores
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_entrenador_valida_rol;
DELIMITER $$
CREATE TRIGGER trg_entrenador_valida_rol
BEFORE INSERT ON entrenador
FOR EACH ROW
BEGIN
    DECLARE v_rol VARCHAR(40);
    SELECT r.nombre_rol INTO v_rol
    FROM empleado e
    JOIN rol_empleado r ON r.id_rol = e.id_rol
    WHERE e.id_empleado = NEW.id_empleado;

    IF v_rol IS NULL OR v_rol <> 'Entrenador' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RN-02: Solo un empleado con rol Entrenador puede registrarse como entrenador.';
    END IF;
END$$
DELIMITER ;

-- ---------------------------------------------------------------------
-- 3.5 VALIDACIÓN COMPLEJA - RN-07: Impedir auto-supervisión en empleados
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_empleado_valida_supervisor;
DELIMITER $$
CREATE TRIGGER trg_empleado_valida_supervisor
BEFORE UPDATE ON empleado
FOR EACH ROW
BEGIN
    IF NEW.id_supervisor = NEW.id_empleado THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RN-07: Un empleado no puede ser su propio supervisor.';
    END IF;
END$$
DELIMITER ;

-- ---------------------------------------------------------------------
-- 3.6 ACTUALIZACIÓN AUTOMÁTICA - RN-12: Sincronización de pago rechazado
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_pago_actualiza_membresia;
DELIMITER $$
CREATE TRIGGER trg_pago_actualiza_membresia
AFTER INSERT ON pago
FOR EACH ROW
BEGIN
    IF NEW.estado_pago = 'rechazado' THEN
        UPDATE membresia_cliente
        SET estado = 'cancelada'
        WHERE id_membresia_cliente = NEW.id_membresia_cliente
          AND estado = 'activa';
    END IF;
END$$
DELIMITER ;

-- ---------------------------------------------------------------------
-- 3.7 AUDITORÍA INTEGRAL - RN-11: Trazabilidad de cambios sobre la tabla pago
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_pago_auditoria_insert;
DELIMITER $$
CREATE TRIGGER trg_pago_auditoria_insert
AFTER INSERT ON pago
FOR EACH ROW
BEGIN
    INSERT INTO auditoria (tabla_afectada, operacion, usuario_bd, id_registro_afectado, valores_anteriores, valores_nuevos)
    VALUES (
        'pago', 'INSERT', CURRENT_USER(), NEW.id_pago, NULL,
        JSON_OBJECT('id_pago', NEW.id_pago, 'id_membresia_cliente', NEW.id_membresia_cliente,
                     'fecha_pago', NEW.fecha_pago, 'monto', NEW.monto,
                     'metodo_pago', NEW.metodo_pago, 'estado_pago', NEW.estado_pago)
    );
END$$
DELIMITER ;

DROP TRIGGER IF EXISTS trg_pago_auditoria_update;
DELIMITER $$
CREATE TRIGGER trg_pago_auditoria_update
AFTER UPDATE ON pago
FOR EACH ROW
BEGIN
    INSERT INTO auditoria (tabla_afectada, operacion, usuario_bd, id_registro_afectado, valores_anteriores, valores_nuevos)
    VALUES (
        'pago', 'UPDATE', CURRENT_USER(), NEW.id_pago,
        JSON_OBJECT('id_pago', OLD.id_pago, 'id_membresia_cliente', OLD.id_membresia_cliente,
                     'fecha_pago', OLD.fecha_pago, 'monto', OLD.monto,
                     'metodo_pago', OLD.metodo_pago, 'estado_pago', OLD.estado_pago),
        JSON_OBJECT('id_pago', NEW.id_pago, 'id_membresia_cliente', NEW.id_membresia_cliente,
                     'fecha_pago', NEW.fecha_pago, 'monto', NEW.monto,
                     'metodo_pago', NEW.metodo_pago, 'estado_pago', NEW.estado_pago)
    );
END$$
DELIMITER ;

DROP TRIGGER IF EXISTS trg_pago_auditoria_delete;
DELIMITER $$
CREATE TRIGGER trg_pago_auditoria_delete
AFTER DELETE ON pago
FOR EACH ROW
BEGIN
    INSERT INTO auditoria (tabla_afectada, operacion, usuario_bd, id_registro_afectado, valores_anteriores, valores_nuevos)
    VALUES (
        'pago', 'DELETE', CURRENT_USER(), OLD.id_pago,
        JSON_OBJECT('id_pago', OLD.id_pago, 'id_membresia_cliente', OLD.id_membresia_cliente,
                     'fecha_pago', OLD.fecha_pago, 'monto', OLD.monto,
                     'metodo_pago', OLD.metodo_pago, 'estado_pago', OLD.estado_pago),
        NULL
    );
END$$
DELIMITER ;


-- =====================================================================
-- 4. PROCEDIMIENTOS ALMACENADOS (2 procedimientos)
-- =====================================================================

-- 4.1 sp_registrar_pago
-- Registra pagos asociados a una membresía controlando excepciones con HANDLER.
DROP PROCEDURE IF EXISTS sp_registrar_pago;
DELIMITER $$
CREATE PROCEDURE sp_registrar_pago(
    IN  p_id_membresia INT,
    IN  p_monto        DECIMAL(10,2),
    IN  p_metodo       ENUM('efectivo','tarjeta','transferencia'),
    OUT p_mensaje       VARCHAR(200)
)
BEGIN
    DECLARE v_existe INT DEFAULT 0;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_mensaje = 'Error: no fue posible registrar el pago (verifique el monto y la membresia).';
    END;

    SELECT COUNT(*) INTO v_existe FROM membresia_cliente WHERE id_membresia_cliente = p_id_membresia;
    IF v_existe = 0 THEN
        SET p_mensaje = 'Error: la membresia indicada no existe.';
    ELSE
        START TRANSACTION;
        INSERT INTO pago (id_membresia_cliente, monto, metodo_pago)
        VALUES (p_id_membresia, p_monto, p_metodo);
        COMMIT;
        SET p_mensaje = CONCAT('Pago registrado correctamente con id_pago = ', LAST_INSERT_ID());
    END IF;
END$$
DELIMITER ;

-- 4.2 sp_inscribir_cliente_clase
-- Procesa inscripciones capturando errores del trigger de cupos (trg_asistencia_valida_cupo).
DROP PROCEDURE IF EXISTS sp_inscribir_cliente_clase;
DELIMITER $$
CREATE PROCEDURE sp_inscribir_cliente_clase(
    IN  p_id_cliente    INT,
    IN  p_id_clase      INT,
    IN  p_numero_sesion INT,
    OUT p_resultado      VARCHAR(200)
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_resultado = 'Error: no fue posible inscribir al cliente (posible cupo lleno o sesion inexistente).';
    END;

    START TRANSACTION;
    INSERT INTO asistencia (id_cliente, id_clase, numero_sesion)
    VALUES (p_id_cliente, p_id_clase, p_numero_sesion);
    COMMIT;
    SET p_resultado = 'Inscripcion registrada correctamente.';
END$$
DELIMITER ;


-- =====================================================================
-- 5. TRANSACCION EXPLICITA (Proceso de Venta Integrado)
-- =====================================================================

-- sp_inscripcion_con_pago: Proceso atómico que crea la membresía y el pago inicial.
-- En caso de fallo en cualquier instrucción, revierte cambios manteniendo consistencia.
DROP PROCEDURE IF EXISTS sp_inscripcion_con_pago;
DELIMITER $$
CREATE PROCEDURE sp_inscripcion_con_pago(
    IN  p_id_cliente    INT,
    IN  p_id_plan       INT,
    IN  p_fecha_inicio  DATE,
    IN  p_metodo        ENUM('efectivo','tarjeta','transferencia'),
    OUT p_resultado      VARCHAR(200)
)
BEGIN
    DECLARE v_id_membresia   INT;
    DECLARE v_duracion       INT;
    DECLARE v_precio         DECIMAL(10,2);
    DECLARE v_fecha_fin      DATE;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_resultado = 'Error: la operacion fue revertida en su totalidad (ver RN-01 y demas restricciones).';
    END;

    SELECT duracion_meses, precio INTO v_duracion, v_precio
    FROM membresia_plan WHERE id_plan = p_id_plan;

    SET v_fecha_fin = DATE_ADD(p_fecha_inicio, INTERVAL v_duracion MONTH);

    START TRANSACTION;

    INSERT INTO membresia_cliente (id_cliente, id_plan, fecha_inicio, fecha_fin, estado, precio_pagado)
    VALUES (p_id_cliente, p_id_plan, p_fecha_inicio, v_fecha_fin, 'activa', v_precio);

    SET v_id_membresia = LAST_INSERT_ID();

    INSERT INTO pago (id_membresia_cliente, fecha_pago, monto, metodo_pago, estado_pago)
    VALUES (v_id_membresia, p_fecha_inicio, v_precio, p_metodo, 'completado');

    COMMIT;
    SET p_resultado = CONCAT('Inscripcion y pago registrados correctamente. id_membresia_cliente = ', v_id_membresia);
END$$
DELIMITER ;

