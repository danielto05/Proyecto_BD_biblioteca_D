-- 02_roles.sql: datos base del sistema (los 4 perfiles de la seccion 4 del proyecto)
-- Se ejecuta despues de 01_esquema.sql (orden alfabetico en postgres/init/).
SET search_path TO biblioteca, public;

INSERT INTO rol (nombre, descripcion) VALUES
  ('lector',        'Consulta el catalogo y su propio historial de prestamos'),
  ('bibliotecario', 'Gestiona libros y lectores, registra prestamos y devoluciones'),
  ('administrador', 'Crea, edita y desactiva cuentas de bibliotecario'),
  ('auditor',       'Consulta los reportes agregados (solo lectura)');
