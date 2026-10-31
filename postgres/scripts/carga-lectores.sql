-- carga-lectores.sql
-- Carga un CSV de lectores en biblioteca.cuenta (con el rol 'lector').
-- Patron: tabla de paso -> validacion -> tabla final -> bitacora de rechazos.
--
-- Uso (desde la carpeta del proyecto, con el contenedor arriba):
--   docker compose exec postgres psql -U curso -d curso -f /scripts/carga-lectores.sql
--   docker compose exec postgres psql -U curso -d curso \
--     -v archivo=/scripts/datos/lectores_semilla_con_errores.csv -f /scripts/carga-lectores.sql
--
-- Columnas esperadas del CSV (con encabezado en la linea 1):
--   documento,nombres,apellidos,correo,telefono

\set ON_ERROR_STOP on
\if :{?archivo}
\else
  \set archivo '/scripts/datos/lectores_semilla.csv'
\endif

SET search_path TO biblioteca, public;

BEGIN;

-- El rol 'lector' debe existir (lo crea postgres/init/02_roles.sql)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM rol WHERE nombre = 'lector') THEN
    RAISE EXCEPTION 'Falta el rol lector en la tabla rol: revisa postgres/init/02_roles.sql';
  END IF;
END $$;

-- Bitacora de rechazos (la misma que usa carga-libros.sql)
CREATE SCHEMA IF NOT EXISTS carga;
CREATE TABLE IF NOT EXISTS carga.rechazo_carga (
  id_rechazo integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  fecha      timestamp NOT NULL DEFAULT now(),
  archivo    text      NOT NULL,
  linea      integer   NOT NULL,
  contenido  text,
  motivo     text      NOT NULL
);

-- Leer el archivo tal cual, una fila por linea.
CREATE TEMP TABLE stg_linea (
  n     integer GENERATED ALWAYS AS IDENTITY,
  linea text
) ON COMMIT DROP;

COPY stg_linea (linea) FROM :'archivo' WITH (FORMAT text);
DELETE FROM stg_linea WHERE n = 1 OR trim(linea) = '';   -- encabezado y lineas en blanco

-- Partir cada linea en sus campos (todavia como texto).
-- El correo se normaliza a minusculas; el resto, con trim.
CREATE TEMP TABLE stg_lector ON COMMIT DROP AS
SELECT n                                              AS linea_csv,
       linea                                          AS contenido,
       array_length(string_to_array(linea, ','), 1)   AS num_campos,
       trim(split_part(linea, ',', 1))                AS documento,
       trim(split_part(linea, ',', 2))                AS nombres,
       trim(split_part(linea, ',', 3))                AS apellidos,
       lower(trim(split_part(linea, ',', 4)))         AS correo,
       trim(split_part(linea, ',', 5))                AS telefono,
       NULL::text                                     AS motivo
FROM stg_linea;

--Validar: la primera regla que falla da el motivo.
UPDATE stg_lector SET motivo = CASE
  WHEN num_campos <> 5                                  THEN 'tiene ' || num_campos || ' columnas, se esperaban 5'
  WHEN documento = ''                                   THEN 'documento vacío'
  WHEN documento !~ '^[0-9]{6,15}$'                     THEN 'documento no numérico o de longitud inválida'
  WHEN nombres = ''                                     THEN 'nombres vacíos'
  WHEN apellidos = ''                                   THEN 'apellidos vacíos'
  WHEN correo = ''                                      THEN 'correo vacío'
  WHEN correo !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'           THEN 'correo inválido'
  WHEN telefono = ''                                    THEN 'teléfono vacío'
  WHEN telefono !~ '^[0-9]{7,10}$'                      THEN 'teléfono inválido'
  WHEN EXISTS (SELECT 1 FROM cuenta c WHERE c.documento = stg_lector.documento)
                                                        THEN 'documento ya existe'
  WHEN EXISTS (SELECT 1 FROM cuenta c WHERE lower(c.correo) = stg_lector.correo)
                                                        THEN 'correo ya registrado'
END;

--Duplicados dentro del mismo archivo: se conserva la primera aparicion valida.
UPDATE stg_lector s SET motivo = CASE
  WHEN EXISTS (SELECT 1 FROM stg_lector p
               WHERE p.documento = s.documento AND p.linea_csv < s.linea_csv AND p.motivo IS NULL)
       THEN 'documento repetido en el archivo'
  WHEN EXISTS (SELECT 1 FROM stg_lector p
               WHERE p.correo = s.correo AND p.linea_csv < s.linea_csv AND p.motivo IS NULL)
       THEN 'correo repetido en el archivo'
END
WHERE s.motivo IS NULL
  AND EXISTS (SELECT 1 FROM stg_lector p
              WHERE (p.documento = s.documento OR p.correo = s.correo)
                AND p.linea_csv < s.linea_csv AND p.motivo IS NULL);

--Pasar las filas validas a cuenta.
-- usuario = documento; contrasena inicial = documento con hash bcrypt (nunca en texto plano).
INSERT INTO cuenta (id_rol, usuario, documento, contrasena, nombres, apellidos, correo, telefono)
SELECT (SELECT id_rol FROM rol WHERE nombre = 'lector'),
       s.documento, s.documento, crypt(s.documento, gen_salt('bf')),
       s.nombres, s.apellidos, s.correo, s.telefono
FROM stg_lector s
WHERE s.motivo IS NULL;

--Registrar las filas rechazadas en la bitacora.
INSERT INTO carga.rechazo_carga (archivo, linea, contenido, motivo)
SELECT :'archivo', linea_csv, contenido, motivo
FROM stg_lector
WHERE motivo IS NOT NULL;

-- Resumen de esta carga
SELECT count(*) FILTER (WHERE motivo IS NULL)     AS cargadas,
       count(*) FILTER (WHERE motivo IS NOT NULL) AS rechazadas
FROM stg_lector;

SELECT linea_csv AS linea, motivo, left(contenido, 60) AS contenido
FROM stg_lector
WHERE motivo IS NOT NULL
ORDER BY linea_csv;

COMMIT;
