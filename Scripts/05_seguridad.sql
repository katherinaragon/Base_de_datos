

USE gymconnect_db;


-- 1. ROLES Y USUARIOS CON PRIVILEGIOS DIFERENCIADOS


CREATE ROLE rol_administrador;
GRANT ALL PRIVILEGES ON gymconnect_db.* TO rol_administrador;

CREATE ROLE rol_consulta;

GRANT SELECT, INSERT, UPDATE ON gymconnect_db.* TO rol_consulta;
REVOKE INSERT, UPDATE ON gymconnect_db.* FROM rol_consulta;

CREATE USER 'admin_gym'@'localhost' IDENTIFIED BY 'AdminGym#2026';
GRANT rol_administrador TO 'admin_gym'@'localhost';
SET DEFAULT ROLE rol_administrador FOR 'admin_gym'@'localhost';


CREATE USER 'consulta_gym'@'localhost' IDENTIFIED BY 'ConsultaGym#2026';
GRANT rol_consulta TO 'consulta_gym'@'localhost';
SET DEFAULT ROLE rol_consulta FOR 'consulta_gym'@'localhost';

FLUSH PRIVILEGES;


-- 2. PRUEBA DE ACCESO DENEGADO


--
mysql -u consulta_gym -p'ConsultaGym#2026' gymconnect_db DELETE FROM cliente WHERE id_cliente = 1;


-- intento de lectura con el mismo usuario SI debe
SELECT * FROM cliente LIMIT 5;   -- se ejecuta sin error


-- 3. RESPALDO (BACKUP) Y RESTAURACION (RESTORE)

mysqldump -u admin_gym -pAdminGym#2026 --routines --triggers \ --single-transaction gymconnect_db > backup_gymconnect_20260819.sql

mysql -u admin_gym -pAdminGym#2026 -e "CREATE DATABASE IF NOT EXISTS gymconnect_db;"
mysql -u admin_gym -pAdminGym#2026 gymconnect_db < backup_gymconnect_20260819.sql


mysql -u admin_gym -pAdminGym#2026 gymconnect_db \ -e "SELECT COUNT(*) FROM cliente; SELECT COUNT(*) FROM pago;"


