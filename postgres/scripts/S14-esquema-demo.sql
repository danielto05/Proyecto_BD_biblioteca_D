-- S14. Esquema mínimo para la demo de carga desde CSV
-- (referencia del profesor; cada grupo carga en SU esquema biblioteca-v2)
--
-- Uso (desde entorno-docker/, con este archivo copiado en postgres/scripts/):
--   docker compose exec postgres psql -U curso -d curso -f /scripts/S14-esquema-demo.sql
--
-- Se puede correr cuantas veces se quiera: borra y recrea el esquema
-- "carga_demo" completo. Después se cargan los CSV con
-- S14-carga-libros.sql y S14-carga-lectores.sql.

\set ON_ERROR_STOP on

DROP SCHEMA IF EXISTS carga_demo CASCADE;
CREATE SCHEMA carga_demo;
SET search_path TO carga_demo;

-- ---------------------------------------------------------------
-- Tablas finales: una por archivo, con las mismas columnas del CSV.
-- Las restricciones son la última línea de defensa: la validación de
-- la carga debe atrapar ANTES todo lo que estas tablas rechazarían.
-- ---------------------------------------------------------------

CREATE TABLE libro (
    isbn                    varchar(13)   PRIMARY KEY CHECK (isbn ~ '^[0-9]{13}$'),
    titulo                  varchar(200)  NOT NULL CHECK (titulo <> ''),
    autor                   varchar(120)  NOT NULL CHECK (autor <> ''),
    categoria               varchar(40)   NOT NULL CHECK (categoria <> ''),
    anio_publicacion        smallint      NOT NULL CHECK (anio_publicacion BETWEEN 1450 AND 2100),
    ejemplares_disponibles  integer       NOT NULL CHECK (ejemplares_disponibles >= 0)
);

CREATE TABLE lector (
    documento  varchar(15)   PRIMARY KEY CHECK (documento ~ '^[0-9]{6,15}$'),
    nombres    varchar(80)   NOT NULL CHECK (nombres <> ''),
    apellidos  varchar(80)   NOT NULL CHECK (apellidos <> ''),
    correo     varchar(120)  NOT NULL UNIQUE CHECK (correo ~ '^[^@ ]+@[^@ ]+\.[^@ ]+$'),
    telefono   varchar(15)   NOT NULL CHECK (telefono ~ '^[0-9]{7,15}$')
);

-- Bitácora de filas rechazadas: persiste entre cargas.
CREATE TABLE rechazo_carga (
    id         integer      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    archivo    text         NOT NULL,
    linea      integer      NOT NULL,
    contenido  text         NOT NULL,
    motivo     text         NOT NULL,
    fecha      timestamptz  NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------
-- Tablas de paso (staging): todo es texto y nada tiene restricciones,
-- para que ninguna fila del archivo se pierda antes de revisarla.
-- Cada carga las vacía y las vuelve a llenar.
-- ---------------------------------------------------------------

-- Una fila por línea del archivo, sin partir en columnas
CREATE TABLE stg_linea (
    n      integer  GENERATED ALWAYS AS IDENTITY,  -- número de línea del archivo
    linea  text
);

CREATE TABLE stg_libro (
    linea_csv               integer,
    contenido               text,
    num_campos              integer,
    isbn                    text,
    titulo                  text,
    autor                   text,
    categoria               text,
    anio_publicacion        text,
    ejemplares_disponibles  text,
    motivo                  text      -- NULL = la fila pasó la validación
);

CREATE TABLE stg_lector (
    linea_csv   integer,
    contenido   text,
    num_campos  integer,
    documento   text,
    nombres     text,
    apellidos   text,
    correo      text,
    telefono    text,
    motivo      text
);
