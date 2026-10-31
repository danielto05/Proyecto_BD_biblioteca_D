-- datos_prueba_prestamos.sql: Carga préstamos y devoluciones de prueba
SET search_path TO biblioteca, public;

BEGIN;

-- Limpiar préstamos previos para evitar duplicados en la prueba
TRUNCATE prestamo, devolucion RESTART IDENTITY CASCADE;

-- Insertar préstamos de prueba buscando IDs reales
INSERT INTO prestamo (id_usuario_lector, id_usuario_registra, id_ejemplar, fecha_prestamo, fecha_limite, estado)
VALUES 
  -- Préstamo 1: Mariana (Devuelto a tiempo)
  ((SELECT id_usuario FROM cuenta WHERE documento = '1000000001'), 
   (SELECT id_usuario FROM cuenta LIMIT 1), 
   1, CURRENT_DATE - 20, CURRENT_DATE - 6, 'devuelto'),
   
  -- Préstamo 2: Santiago (En mora hace 5 días)
  ((SELECT id_usuario FROM cuenta WHERE documento = '1000000002'), 
   (SELECT id_usuario FROM cuenta LIMIT 1), 
   2, CURRENT_DATE - 19, CURRENT_DATE - 5, 'prestado'),
   
  -- Préstamo 3: Valentina (En mora grave hace 15 días)
  ((SELECT id_usuario FROM cuenta WHERE documento = '1000000003'), 
   (SELECT id_usuario FROM cuenta LIMIT 1), 
   3, CURRENT_DATE - 29, CURRENT_DATE - 15, 'prestado');

-- Registrar la devolución del préstamo 1 para alimentar el Reporte 2
INSERT INTO devolucion (id_prestamo, id_usuario_registra, fecha_devolucion, estado_ejemplar)
VALUES 
  (1, (SELECT id_usuario FROM cuenta LIMIT 1), CURRENT_DATE - 7, 'bueno');

COMMIT;
