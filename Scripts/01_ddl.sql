
-- 0. CREACION DE LA BASE DE DATOS  

CREATE DATABASE gymconnect_db  
USE gymconnect_db;


-- 1. Scripts de creación de todas las tablas
--Victor Manuel

CREATE TABLE rol_empleado (
    id_rol  INT AUTO_INCREMENT PRIMARY KEY,
    nombre_rol  VARCHAR(40)  NOT NULL,
    descripcion VARCHAR(150) NULL,
    CONSTRAINT uq_rol_nombre UNIQUE (nombre_rol)
);

CREATE TABLE zona (
    id_zona          INT AUTO_INCREMENT PRIMARY KEY,
    nombre_zona      VARCHAR(60) NOT NULL,
    piso             TINYINT     NOT NULL,
    capacidad_maxima INT         NOT NULL,
    CONSTRAINT uq_zona_nombre_piso UNIQUE (nombre_zona, piso),
    CONSTRAINT ck_zona_piso        CHECK (piso BETWEEN 1 AND 3),
    CONSTRAINT ck_zona_capacidad   CHECK (capacidad_maxima > 0)
);


CREATE TABLE membresia_plan (
    id_plan         INT AUTO_INCREMENT PRIMARY KEY,
    nombre_plan     VARCHAR(50)    NOT NULL,
    duracion_meses  INT            NOT NULL,
    precio          DECIMAL(10,2)  NOT NULL,
    descripcion     VARCHAR(200)   NULL,
    CONSTRAINT uq_plan_nombre     UNIQUE (nombre_plan),
    CONSTRAINT ck_plan_duracion   CHECK (duracion_meses > 0),
    CONSTRAINT ck_plan_precio     CHECK (precio > 0)
);


CREATE TABLE clase (
    id_clase         INT AUTO_INCREMENT PRIMARY KEY,
    nombre_clase     VARCHAR(50) NOT NULL,
    descripcion      VARCHAR(200) NULL,
    nivel_intensidad ENUM('bajo','medio','alto') NOT NULL,
    CONSTRAINT uq_clase_nombre UNIQUE (nombre_clase)
);


CREATE TABLE cliente (
    id_cliente        INT AUTO_INCREMENT PRIMARY KEY,
    numero_documento  VARCHAR(15)  NOT NULL,
    nombres           VARCHAR(60)  NOT NULL,
    apellidos         VARCHAR(60)  NOT NULL,
    correo            VARCHAR(100) NOT NULL,
    telefono          VARCHAR(15)  NULL,
    fecha_nacimiento  DATE         NOT NULL,
    fecha_registro    DATE         NOT NULL DEFAULT (CURRENT_DATE),
    genero            ENUM('M','F','Otro') NULL,
    estado            ENUM('activo','inactivo') NOT NULL DEFAULT 'activo',
    CONSTRAINT uq_cliente_documento UNIQUE (numero_documento),
    CONSTRAINT uq_cliente_correo    UNIQUE (correo),
    CONSTRAINT ck_cliente_nacimiento CHECK (fecha_nacimiento >= '1900-01-01')
);


CREATE TABLE empleado (
    id_empleado         INT AUTO_INCREMENT PRIMARY KEY,
    numero_documento    VARCHAR(15)   NOT NULL,
    nombres             VARCHAR(60)   NOT NULL,
    apellidos           VARCHAR(60)   NOT NULL,
    correo              VARCHAR(100)  NOT NULL,
    telefono            VARCHAR(15)   NULL,
    fecha_contratacion  DATE          NOT NULL DEFAULT (CURRENT_DATE),
    salario             DECIMAL(10,2) NOT NULL,
    id_rol              INT           NOT NULL,
    id_supervisor       INT           NULL,
    estado              ENUM('activo','inactivo') NOT NULL DEFAULT 'activo',
    CONSTRAINT uq_empleado_documento UNIQUE (numero_documento),
    CONSTRAINT uq_empleado_correo    UNIQUE (correo),
    CONSTRAINT ck_empleado_salario   CHECK (salario > 0),
      CONSTRAINT fk_empleado_rol
        FOREIGN KEY (id_rol) REFERENCES rol_empleado(id_rol)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_empleado_supervisor
        FOREIGN KEY (id_supervisor) REFERENCES empleado(id_empleado)
        ON DELETE SET NULL ON UPDATE CASCADE
);


CREATE INDEX idx_empleado_rol ON empleado(id_rol);


CREATE TABLE entrenador (
    id_empleado          INT PRIMARY KEY,
    especialidad         VARCHAR(60) NOT NULL,
    numero_certificacion VARCHAR(30) NOT NULL,
    fecha_certificacion  DATE        NOT NULL,
    anios_experiencia    INT         NOT NULL DEFAULT 0,
    CONSTRAINT uq_entrenador_certificacion UNIQUE (numero_certificacion),
    CONSTRAINT ck_entrenador_experiencia CHECK (anios_experiencia >= 0),
    CONSTRAINT fk_entrenador_empleado
        FOREIGN KEY (id_empleado) REFERENCES empleado(id_empleado)
        ON DELETE CASCADE ON UPDATE CASCADE
);


CREATE TABLE equipo (
    id_equipo          INT AUTO_INCREMENT PRIMARY KEY,
    codigo_inventario  VARCHAR(20) NOT NULL,
    nombre_equipo      VARCHAR(60) NOT NULL,
    tipo_equipo        ENUM('cardio','fuerza','funcional','otro') NOT NULL,
    fecha_adquisicion  DATE NOT NULL,
    estado             ENUM('operativo','mantenimiento','fuera_de_servicio')
                        NOT NULL DEFAULT 'operativo',
    id_zona            INT NOT NULL,
    CONSTRAINT uq_equipo_codigo UNIQUE (codigo_inventario),
    CONSTRAINT fk_equipo_zona
        FOREIGN KEY (id_zona) REFERENCES zona(id_zona)
        ON DELETE RESTRICT ON UPDATE CASCADE
);


CREATE TABLE horario_clase (
    id_clase      INT  NOT NULL,
    numero_sesion INT  NOT NULL,
    fecha_sesion  DATE NOT NULL,
    hora_inicio   TIME NOT NULL,
    hora_fin      TIME NOT NULL,
    id_zona       INT  NOT NULL,
    id_empleado   INT  NOT NULL,  
    cupo_maximo   INT  NOT NULL,
    PRIMARY KEY (id_clase, numero_sesion),
    CONSTRAINT uq_horario_zona_fecha_hora UNIQUE (id_zona, fecha_sesion, hora_inicio),
    CONSTRAINT ck_horario_horas CHECK (hora_fin > hora_inicio),
    CONSTRAINT ck_horario_cupo  CHECK (cupo_maximo > 0),
    CONSTRAINT fk_horario_clase
        FOREIGN KEY (id_clase) REFERENCES clase(id_clase)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_horario_zona
        FOREIGN KEY (id_zona) REFERENCES zona(id_zona)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_horario_entrenador
        FOREIGN KEY (id_empleado) REFERENCES entrenador(id_empleado)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE INDEX idx_horario_fecha ON horario_clase(fecha_sesion);

CREATE TABLE membresia_cliente (
    id_membresia_cliente INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente     INT NOT NULL,
    id_plan        INT NOT NULL,
    fecha_inicio   DATE NOT NULL,
    fecha_fin      DATE NOT NULL,
    estado         ENUM('activa','vencida','cancelada') NOT NULL DEFAULT 'activa',
    precio_pagado  DECIMAL(10,2) NOT NULL,
    CONSTRAINT uq_membresia_cliente_plan_fecha UNIQUE (id_cliente, id_plan, fecha_inicio),
    CONSTRAINT ck_membresia_fechas CHECK (fecha_fin > fecha_inicio),
    CONSTRAINT ck_membresia_precio CHECK (precio_pagado > 0),
    CONSTRAINT fk_membresia_cliente
        FOREIGN KEY (id_cliente) REFERENCES cliente(id_cliente)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_membresia_plan
        FOREIGN KEY (id_plan) REFERENCES membresia_plan(id_plan)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE INDEX idx_membresia_estado ON membresia_cliente(estado);

CREATE TABLE asistencia (
    id_asistencia   INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente      INT NOT NULL,
    id_clase        INT NOT NULL,
    numero_sesion   INT NOT NULL,
    fecha_registro  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_asistencia_cliente_sesion UNIQUE (id_cliente, id_clase, numero_sesion),
    CONSTRAINT fk_asistencia_cliente
        FOREIGN KEY (id_cliente) REFERENCES cliente(id_cliente)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_asistencia_horario
        FOREIGN KEY (id_clase, numero_sesion) REFERENCES horario_clase(id_clase, numero_sesion)
        ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX idx_asistencia_cliente ON asistencia(id_cliente);

CREATE TABLE pago (
    id_pago               INT AUTO_INCREMENT PRIMARY KEY,
    id_membresia_cliente  INT NOT NULL,
    fecha_pago            DATE NOT NULL DEFAULT (CURRENT_DATE),
    monto                 DECIMAL(10,2) NOT NULL,
    metodo_pago           ENUM('efectivo','tarjeta','transferencia') NOT NULL,
    estado_pago           ENUM('completado','pendiente','rechazado') NOT NULL DEFAULT 'completado',
    CONSTRAINT ck_pago_monto CHECK (monto > 0),
    CONSTRAINT fk_pago_membresia
        FOREIGN KEY (id_membresia_cliente) REFERENCES membresia_cliente(id_membresia_cliente)
        ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX idx_pago_fecha ON pago(fecha_pago);


CREATE TABLE auditoria (
    id_auditoria         INT AUTO_INCREMENT PRIMARY KEY,
    tabla_afectada        VARCHAR(50) NOT NULL,
    operacion             ENUM('INSERT','UPDATE','DELETE') NOT NULL,
    usuario_bd            VARCHAR(100) NOT NULL,
    fecha_operacion        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    id_registro_afectado   INT NULL,
    valores_anteriores     JSON NULL,
    valores_nuevos         JSON NULL
);

