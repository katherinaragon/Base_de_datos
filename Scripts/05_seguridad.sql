-- =====================================================================
-- PROYECTO BD: GYMCONNECT - SEGURIDAD, AUDITORÍA Y RESPALDOS
-- Archivo: 05_seguridad.sql
-- Motor: MySQL / MariaDB
--
-- Notas del grupo:
-- Este script configura la capa de seguridad mediante roles y usuarios 
-- con privilegios diferenciados (GRANT/REVOKE). Asimismo, incluye la 
-- documentación técnica y comandos para pruebas de acceso denegado, 
-- respaldo (backup) y restauración (restore) de la base de datos.
-- Debe ejecutarse con un usuario administrador (root/DBA).
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
-- 1. ROLES Y USUARIOS CON PRIVILEGIOS DIFERENCIADOS
-- =====================================================================

-- 1.1 Rol de Administración
-- Otorga control total sobre el esquema (Lectura, Escritura, DDL y DCL).
DROP ROLE IF EXISTS rol_administrador;
CREATE ROLE rol_administrador;
GRANT ALL PRIVILEGES ON gymconnect_db.* TO rol_administrador;

-- 1.2 Rol de Consulta
-- Diseñado para personal operativo/recepción que solo requiere lectura.
-- Se asignan permisos y se revocan los de escritura para evidenciar GRANT/REVOKE.
DROP ROLE IF EXISTS rol_consulta;
CREATE ROLE rol_consulta;

GRANT SELECT, INSERT, UPDATE ON gymconnect_db.* TO rol_consulta;
REVOKE INSERT, UPDATE ON gymconnect_db.* FROM rol_consulta;

-- 1.3 Usuario Administrador del Sistema
DROP USER IF EXISTS 'admin_gym'@'localhost';
CREATE USER 'admin_gym'@'localhost' IDENTIFIED BY 'AdminGym#2026';
GRANT rol_administrador TO 'admin_gym'@'localhost';
SET DEFAULT ROLE rol_administrador FOR 'admin_gym'@'localhost';

-- 1.4 Usuario Operativo / Reportes
DROP USER IF EXISTS 'consulta_gym'@'localhost';
CREATE USER 'consulta_gym'@'localhost' IDENTIFIED BY 'ConsultaGym#2026';
GRANT rol_consulta TO 'consulta_gym'@'localhost';
SET DEFAULT ROLE rol_consulta FOR 'consulta_gym'@'localhost';

FLUSH PRIVILEGES;


-- =====================================================================
-- 2. GUÍA Y EVIDENCIA DE PRUEBAS DE SEGURIDAD (ACCESO DENEGADO)
-- =====================================================================
-- Las siguientes pruebas se deben validar conectándose como 'consulta_gym':
--
-- Command-line:
--   mysql -u consulta_gym -p'ConsultaGym#2026' gymconnect_db
--
-- Prueba A (Intento de modificación - Debe ser Denegado):
--   DELETE FROM cliente WHERE id_cliente = 1;
-- 
-- Resultado esperado / Evidencia:
--   ERROR 1142 (42000): DELETE command denied to user 'consulta_gym'@'localhost' for table `gymconnect_db`.`cliente`
--
-- Prueba B (Lectura de datos - Debe ser Exitoso):
--   SELECT * FROM cliente LIMIT 5;


-- =====================================================================
-- 3. PROCEDIMIENTO DE BACKUP Y RESTORE (CLI DEL SISTEMA OPERATIVO)
-- =====================================================================
-- Instrucciones ejecutables desde la terminal (Bash/CMD) del servidor:

-- 3.1 Generación del Respaldo Completo (Estructura + Objetos + Datos):
--   mysqldump -u admin_gym -pAdminGym#2026 --routines --triggers --single-transaction gymconnect_db > backup_gymconnect_20260819.sql
--
--   * --routines: Exporta funciones y procedimientos almacenados.
--   * --triggers: Incluye los disparadores definidos.
--   * --single-transaction: Garantiza consistencia sin bloquear tablas InnoDB.

-- 3.2 Restauración de la Base de Datos:
--   mysql -u admin_gym -pAdminGym#2026 -e "CREATE DATABASE IF NOT EXISTS gymconnect_db;"
--   mysql -u root -p gymconnect_db < backup_gymconnect_20260819.sql

-- 3.3 Verificación Integridad Post-Restauración:
--   mysql -u admin_gym -pAdminGym#2026 gymconnect_db -e "SELECT COUNT(*) FROM cliente; SELECT COUNT(*) FROM pago;"

