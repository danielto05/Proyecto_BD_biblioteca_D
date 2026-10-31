-- carga-libros.sql
-- Carga un CSV de libros en biblioteca.categoria, biblioteca.libro y biblioteca.ejemplar.
-- Patron: tabla de paso -> validacion -> tablas finales -> bitacora de rechazos.
--
-- Uso (desde la carpeta del proyecto, con el contenedor arriba):
--   docker compose exec postgres psql -U curso -d curso -f /scripts/carga-libros.sql
--   docker compose exec postgres psql -U curso -d curso \
--     -v archivo=/scripts/datos/libros_semilla_con_errores.csv -f /scripts/carga-libros.sql
--
-- Columnas esperadas del CSV (con encabezado en la linea 1):
--   isbn,titulo,autor,categoria,anio_publicacion,ejemplares_disponibles

\set ON_ERROR_STOP on
\if :{?archivo}
\else
  \set archivo '/scripts/datos/libros_semilla.csv'
\endif

SET search_path TO biblioteca, public;

BEGIN;

-- Bitacora de rechazos (no es parte del modelo del dominio: vive en su propio esquema)
CREATE SCHEMA IF NOT EXISTS carga;
CREATE TABLE IF NOT EXISTS carga.rechazo_carga (
  id_rechazo integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  fecha      timestamp NOT NULL DEFAULT now(),
  archivo    text      NOT NULL,
  linea      integer   NOT NULL,
  contenido  text,
  motivo     text      NOT NULL
);

-- Leer el archivo tal cual, una fila por linea (FORMAT text: el separador es el
-- tabulador, que no aparece en el CSV, asi que ninguna linea se pierde ni se rompe).
CREATE TEMP TABLE stg_linea (
  n     integer GENERATED ALWAYS AS IDENTITY,
  linea text
) ON COMMIT DROP;

COPY stg_linea (linea) FROM :'archivo' WITH (FORMAT text);
DELETE FROM stg_linea WHERE n = 1 OR trim(linea) = '';   -- encabezado y lineas en blanco

-- Partir cada linea en sus campos (todavia como texto).
-- El ISBN se normaliza quitando guiones; el resto, con trim.
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

-- Validar: la primera regla que falla da el motivo (el CASE se evalua en orden,
-- por eso los ::integer solo se intentan despues de comprobar que el texto son digitos).
UPDATE stg_libro SET motivo = CASE
  WHEN num_campos <> 6                                  THEN 'tiene ' || num_campos || ' columnas, se esperaban 6'
  WHEN isbn = ''                                        THEN 'isbn vacío'
  WHEN isbn !~ '^[0-9]{13}$'                            THEN 'isbn no tiene 13 dígitos'
  WHEN titulo = ''                                      THEN 'título vacío'
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

--Duplicados dentro del mismo archivo: se conserva la primera aparicion valida.
UPDATE stg_libro s SET motivo = 'isbn repetido en el archivo'
WHERE s.motivo IS NULL
  AND EXISTS (SELECT 1 FROM stg_libro p
              WHERE p.isbn = s.isbn AND p.linea_csv < s.linea_csv AND p.motivo IS NULL);

-- Pasar las filas validas a las tablas finales.
-- Categorias que no existan todavia.
INSERT INTO categoria (nombre)
SELECT DISTINCT categoria FROM stg_libro WHERE motivo IS NULL
ON CONFLICT (nombre) DO NOTHING;

-- Libros (la clave de la categoria se busca por nombre).
INSERT INTO libro (id_categoria, isbn, titulo, autor, anio_publicacion)
SELECT c.id_categoria, s.isbn, s.titulo, s.autor, s.anio_publicacion::integer
FROM stg_libro s
JOIN categoria c ON c.nombre = s.categoria
WHERE s.motivo IS NULL;

-- Ejemplares: una fila por copia (codigo = isbn-numero de copia, estado inicial 'disponible').
INSERT INTO ejemplar (id_libro, codigo, estado)
SELECT l.id_libro, v.isbn || '-' || g.n, 'disponible'
FROM (SELECT isbn, ejemplares_disponibles::integer AS copias
      FROM stg_libro WHERE motivo IS NULL) v
JOIN libro l ON l.isbn = v.isbn
CROSS JOIN LATERAL generate_series(1, v.copias) AS g(n);

-- Registrar las filas rechazadas en la bitacora.
INSERT INTO carga.rechazo_carga (archivo, linea, contenido, motivo)
SELECT :'archivo', linea_csv, contenido, motivo
FROM stg_libro
WHERE motivo IS NOT NULL;

-- Resumen de esta carga
SELECT count(*) FILTER (WHERE motivo IS NULL)     AS cargadas,
       count(*) FILTER (WHERE motivo IS NOT NULL) AS rechazadas
FROM stg_libro;

SELECT linea_csv AS linea, motivo, left(contenido, 60) AS contenido
FROM stg_libro
WHERE motivo IS NOT NULL
ORDER BY linea_csv;

COMMIT;
