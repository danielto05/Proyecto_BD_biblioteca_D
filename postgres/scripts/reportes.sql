-- reportes.sql: Los 4 reportes oficiales del proyecto (S15)
SET search_path TO biblioteca, public;

\echo '== Reporte 1: Los libros más prestados =='
SELECT l.titulo, count(p.id_prestamo) AS prestamos
FROM libro l
JOIN ejemplar e ON e.id_libro = l.id_libro
LEFT JOIN prestamo p ON p.id_ejemplar = e.id_ejemplar
GROUP BY l.id_libro, l.titulo
ORDER BY prestamos DESC
FETCH FIRST 3 ROWS WITH TIES;

\echo '== Reporte 2: Lectores que más libros han leído =='
WITH leidos AS (
    SELECT p.id_usuario_lector, count(*) AS devueltos
    FROM prestamo p
    JOIN devolucion d ON d.id_prestamo = p.id_prestamo
    GROUP BY p.id_usuario_lector
)
SELECT c.nombres, c.apellidos, x.devueltos
FROM leidos x
JOIN cuenta c ON c.id_usuario = x.id_usuario_lector
WHERE x.devueltos = (SELECT max(devueltos) FROM leidos)
ORDER BY c.apellidos;

\echo '== Reporte 3: Lectores morosos =='
SELECT c.documento, c.nombres, c.apellidos
FROM cuenta c
WHERE EXISTS (
    SELECT 1
    FROM prestamo p
    LEFT JOIN devolucion d ON d.id_prestamo = p.id_prestamo
    WHERE p.id_usuario_lector = c.id_usuario
      AND d.id_devolucion IS NULL
      AND p.fecha_limite < CURRENT_DATE
)
ORDER BY c.apellidos;

\echo '== Reporte 4: Préstamos en mora (Lista de notificación) =='
SELECT c.nombres || ' ' || c.apellidos AS lector,
       c.correo, 
       c.telefono,
       l.titulo,
       p.fecha_limite,
       CURRENT_DATE - p.fecha_limite AS dias_mora
FROM prestamo p
JOIN cuenta c ON c.id_usuario = p.id_usuario_lector
JOIN ejemplar e ON e.id_ejemplar = p.id_ejemplar
JOIN libro l ON l.id_libro = e.id_libro
LEFT JOIN devolucion d ON d.id_prestamo = p.id_prestamo
WHERE d.id_devolucion IS NULL
  AND p.fecha_limite < CURRENT_DATE
ORDER BY dias_mora DESC;
