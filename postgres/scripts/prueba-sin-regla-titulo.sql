-- carga-libros.sql
-- Carga un CSV de libros en biblioteca.categoria, biblioteca.libro y biblioteca.ejemplar.
-- Patron: tabla de paso -> validacion -> tablas finales -> bitacora de rechazos.

\set ON_ERROR_STOP on
\if :{?archivo}
\else
  \set archivo '/scripts/datos/libros_semilla.csv'
\endif

SET search_path TO biblioteca, public;

BEGIN;


CREATE SCHEMA IF NOT EXISTS carga;
CREATE TABLE IF NOT EXISTS carga.rechazo_carga (
  id_rechazo integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  fecha      timestamp NOT NULL DEFAULT now(),
  archivo    text      NOT NULL,
  linea      integer   NOT NULL,
  contenido  text,
  motivo     text      NOT NULL
);


CREATE TEMP TABLE stg_linea (
  n     integer GENERATED ALWAYS AS IDENTITY,
  linea text
) ON COMMIT DROP;

COPY stg_linea (linea) FROM :'archivo' WITH (FORMAT text);
DELETE FROM stg_linea WHERE n = 1 OR trim(linea) = '';   -- encabezado y lineas en blanco


CREATE TEMP TABLE stg_libro ON COMMIT DROP AS
SELECT n                                                   AS linea_csv,
       linea                                               AS contenido,
       array_length(string_to_array(linea, ','), 1)        AS num_campos,
       replace(trim(split_part(linea, ',', 1)), '-', '')   AS isbn,
       trim(split_part(linea, ',', 2))                     AS titulo,
       trim(split_part(linea, ',', 3))                     AS autor,
       trim(split_part(linea, ',', 4))                     AS categoria,
       trim(split_part(linea, ',', 5))                     AS anio_publicacion,
       trim(split_part(linea, ',', 6))                     AS ejemplares_disponibles,
       NULL::text                                          AS motivo
FROM stg_linea;

UPDATE stg_libro SET motivo = CASE
  WHEN num_campos <> 6                                  THEN 'tiene ' || num_campos || ' columnas, se esperaban 6'
  WHEN isbn = ''                                        THEN 'isbn vacío'
  WHEN isbn !~ '^[0-9]{13}$'                            THEN 'isbn no tiene 13 dígitos'
  -- WHEN titulo = ''                                      THEN 'título vacío'
  WHEN autor = ''                                       THEN 'autor vacío'
  WHEN categoria = ''                                   THEN 'categoría vacía'
  WHEN anio_publicacion !~ '^[0-9]{1,4}$'               THEN 'año no numérico'
  WHEN anio_publicacion::integer NOT BETWEEN 1450 AND 2100
                                                        THEN 'año fuera de rango'
  WHEN ejemplares_disponibles !~ '^-?[0-9]{1,4}$'       THEN 'ejemplares no numérico'
  WHEN ejemplares_disponibles::integer < 0              THEN 'ejemplares negativo'
  WHEN EXISTS (SELECT 1 FROM libro l WHERE l.isbn = stg_libro.isbn)
                                                        THEN 'isbn ya existe en el catálogo'
END;


UPDATE stg_libro s SET motivo = 'isbn repetido en el archivo'
WHERE s.motivo IS NULL
  AND EXISTS (SELECT 1 FROM stg_libro p
              WHERE p.isbn = s.isbn AND p.linea_csv < s.linea_csv AND p.motivo IS NULL);


INSERT INTO categoria (nombre)
SELECT DISTINCT categoria FROM stg_libro WHERE motivo IS NULL
ON CONFLICT (nombre) DO NOTHING;


INSERT INTO libro (id_categoria, isbn, titulo, autor, anio_publicacion)
SELECT c.id_categoria, s.isbn, s.titulo, s.autor, s.anio_publicacion::integer
FROM stg_libro s
JOIN categoria c ON c.nombre = s.categoria
WHERE s.motivo IS NULL;


INSERT INTO ejemplar (id_libro, codigo, estado)
SELECT l.id_libro, v.isbn || '-' || g.n, 'disponible'
FROM (SELECT isbn, ejemplares_disponibles::integer AS copias
      FROM stg_libro WHERE motivo IS NULL) v
JOIN libro l ON l.isbn = v.isbn
CROSS JOIN LATERAL generate_series(1, v.copias) AS g(n);

INSERT INTO carga.rechazo_carga (archivo, linea, contenido, motivo)
SELECT :'archivo', linea_csv, contenido, motivo
FROM stg_libro
WHERE motivo IS NOT NULL;


SELECT count(*) FILTER (WHERE motivo IS NULL)     AS cargadas,
       count(*) FILTER (WHERE motivo IS NOT NULL) AS rechazadas
FROM stg_libro;

SELECT linea_csv AS linea, motivo, left(contenido, 60) AS contenido
FROM stg_libro
WHERE motivo IS NOT NULL
ORDER BY linea_csv;

COMMIT;
