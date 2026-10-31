-- S14. Carga de libros desde CSV: tabla de paso, validación y rechazos
-- (referencia del profesor; requiere haber corrido S14-esquema-demo.sql)
--
-- Uso (desde entorno-docker/, con los CSV en postgres/scripts/datos/):
--   docker compose exec postgres psql -U curso -d curso \
--     -v archivo=/scripts/datos/libros_semilla_con_errores.csv \
--     -f /scripts/S14-carga-libros.sql
--
-- Sin "-v archivo=..." carga /scripts/datos/libros_semilla.csv.
-- Todo corre en una transacción: si algo falla, no queda nada a medias.

\set ON_ERROR_STOP on
\if :{?archivo}
\else
    \set archivo /scripts/datos/libros_semilla.csv
\endif

SET search_path TO carga_demo;

BEGIN;

TRUNCATE stg_linea, stg_libro RESTART IDENTITY;

-- 1. Leer el archivo tal cual: una fila por línea.
--    FORMAT text con el separador por defecto (tabulador) deja cada línea
--    entera en una sola columna, así que ni una fila con columnas de más
--    detiene la lectura. Funciona porque los CSV del curso no traen
--    comas dentro de comillas.
COPY stg_linea (linea) FROM :'archivo' WITH (FORMAT text);
DELETE FROM stg_linea WHERE n = 1;          -- la línea 1 es el encabezado

-- 2. Partir cada línea en sus campos (todavía como texto)
INSERT INTO stg_libro (linea_csv, contenido, num_campos, isbn, titulo, autor,
                       categoria, anio_publicacion, ejemplares_disponibles)
SELECT n, linea,
       array_length(string_to_array(linea, ','), 1),
       trim(split_part(linea, ',', 1)),
       trim(split_part(linea, ',', 2)),
       trim(split_part(linea, ',', 3)),
       trim(split_part(linea, ',', 4)),
       trim(split_part(linea, ',', 5)),
       trim(split_part(linea, ',', 6))
FROM stg_linea;

-- 3. Validar: la primera regla que falla da el motivo del rechazo.
--    El CASE se evalúa en orden, así que los ::integer solo se intentan
--    cuando la regla anterior ya comprobó que el texto es numérico.
UPDATE stg_libro SET motivo = CASE
    WHEN num_campos <> 6                          THEN 'tiene ' || num_campos || ' columnas, se esperaban 6'
    WHEN isbn = ''                                THEN 'isbn vacío'
    WHEN isbn !~ '^[0-9]{13}$'                    THEN 'isbn no tiene 13 dígitos'
    WHEN titulo = ''                              THEN 'título vacío'
    WHEN autor = ''                               THEN 'autor vacío'
    WHEN categoria = ''                           THEN 'categoría vacía'
    WHEN anio_publicacion !~ '^[0-9]{1,4}$'       THEN 'año no numérico'
    WHEN anio_publicacion::integer NOT BETWEEN 1450 AND 2100
                                                  THEN 'año fuera de rango'
    WHEN ejemplares_disponibles !~ '^-?[0-9]{1,6}$'
                                                  THEN 'ejemplares no numérico'
    WHEN ejemplares_disponibles::integer < 0      THEN 'ejemplares negativo'
    WHEN EXISTS (SELECT 1 FROM libro l WHERE l.isbn = stg_libro.isbn)
                                                  THEN 'isbn ya existe en el catálogo'
END;

-- 4. Duplicados dentro del mismo archivo: se queda la primera aparición
UPDATE stg_libro SET motivo = 'isbn repetido en el archivo (línea '
       || (SELECT min(s2.linea_csv) FROM stg_libro s2
           WHERE s2.isbn = stg_libro.isbn AND s2.motivo IS NULL) || ')'
WHERE motivo IS NULL
  AND EXISTS (SELECT 1 FROM stg_libro s2
              WHERE s2.isbn = stg_libro.isbn
                AND s2.motivo IS NULL
                AND s2.linea_csv < stg_libro.linea_csv);

-- 5. Pasar las filas válidas a la tabla final (ahora sí, con su tipo)
INSERT INTO libro (isbn, titulo, autor, categoria, anio_publicacion, ejemplares_disponibles)
SELECT isbn, titulo, autor, categoria,
       anio_publicacion::smallint, ejemplares_disponibles::integer
FROM stg_libro
WHERE motivo IS NULL;

-- 6. Dejar constancia de las rechazadas
INSERT INTO rechazo_carga (archivo, linea, contenido, motivo)
SELECT :'archivo', linea_csv, contenido, motivo
FROM stg_libro
WHERE motivo IS NOT NULL;

COMMIT;

-- Resumen de la carga
SELECT count(*) FILTER (WHERE motivo IS NULL)     AS cargadas,
       count(*) FILTER (WHERE motivo IS NOT NULL) AS rechazadas
FROM stg_libro;

SELECT linea_csv AS linea, motivo, contenido
FROM stg_libro
WHERE motivo IS NOT NULL
ORDER BY linea_csv;
