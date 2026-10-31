SET search_path TO biblioteca, public;

BEGIN;

TRUNCATE prestamo, devolucion RESTART IDENTITY CASCADE;

INSERT INTO prestamo (id_usuario_lector, id_usuario_registra, id_ejemplar, fecha_prestamo, fecha_limite, estado)
VALUES 
  ((SELECT id_usuario FROM cuenta WHERE documento = '1000000001'), (SELECT id_usuario FROM cuenta LIMIT 1), 1, CURRENT_DATE - 20, CURRENT_DATE - 6, 'devuelto'),
  ((SELECT id_usuario FROM cuenta WHERE documento = '1000000002'), (SELECT id_usuario FROM cuenta LIMIT 1), 2, CURRENT_DATE - 19, CURRENT_DATE - 5, 'prestado'),
  ((SELECT id_usuario FROM cuenta WHERE documento = '1000000003'), (SELECT id_usuario FROM cuenta LIMIT 1), 3, CURRENT_DATE - 29, CURRENT_DATE - 15, 'prestado');

INSERT INTO devolucion (id_prestamo, id_usuario_registra, fecha_devolucion, estado_ejemplar)
VALUES 
  (1, (SELECT id_usuario FROM cuenta LIMIT 1), CURRENT_DATE - 7, 'bueno');

COMMIT;
