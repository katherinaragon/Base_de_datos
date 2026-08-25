
USE gymconnect_db;


-- 1. VISTAS (3)

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


-- 2. FUNCION (1)


DELIMITER $$
CREATE FUNCTION fn_edad_cliente(p_fecha_nacimiento DATE)
RETURNS INT
DETERMINISTIC
BEGIN
    RETURN TIMESTAMPDIFF(YEAR, p_fecha_nacimiento, CURDATE());
END$$
DELIMITER ;


SELECT
    CONCAT(nombres, ' ', apellidos) AS cliente,
    fecha_nacimiento,
    fn_edad_cliente(fecha_nacimiento) AS edad_calculada
FROM cliente
ORDER BY edad_calculada DESC
LIMIT 10;

-- 3. TRIGGERS

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
                SET MESSAGE_TEXT = 'RN-01: el cliente ya tiene una membresia activa vigente.';
        END IF;
    END IF;
END$$
DELIMITER ;


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
                SET MESSAGE_TEXT = 'RN-01: el cliente ya tiene una membresia activa vigente.';
        END IF;
    END IF;
END$$
DELIMITER ;



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
            SET MESSAGE_TEXT = 'RN-04: la sesion ya alcanzo su cupo maximo de asistentes.';
    END IF;
END$$
DELIMITER ;



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
            SET MESSAGE_TEXT = 'RN-10: el entrenador ya tiene una sesion asignada que se traslapa con este horario.';
    END IF;
END$$
DELIMITER ;


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
            SET MESSAGE_TEXT = 'RN-02: solo un empleado con rol Entrenador puede registrarse como entrenador.';
    END IF;
END$$
DELIMITER ;


DELIMITER $$
CREATE TRIGGER trg_empleado_valida_supervisor
BEFORE UPDATE ON empleado
FOR EACH ROW
BEGIN
    IF NEW.id_supervisor = NEW.id_empleado THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RN-07: un empleado no puede ser su propio supervisor.';
    END IF;
END$$
DELIMITER ;


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


-- 4. PROCEDIMIENTOS 

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


