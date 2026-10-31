# S14 / Hito 2: Esquema del proyecto en PostgreSQL y carga desde CSV

**Asignatura:** Bases de Datos (750006C), Universidad del Valle
**Módulo 4, Sesión 14** · Grupo 2

## Integrantes del equipo

| Nombre del estudiante | Código |
|---|---|
| Alejandro Valencia | 2515411-2724 |
| Nicolas Velasco | 2521994-2724 |
| Daniel Toro | 2521005-2724 |
| María Alejandra Pizarro | 2519474-2724 |

## Qué contiene este repositorio

El esquema de la biblioteca como script de arranque del entorno Docker y la carga de los CSV semilla (libros y lectores), incluidos los archivos con errores intencionales. La carga sigue el patrón **tabla de paso → validación → tabla final → bitácora de rechazos**, todo dentro de una transacción.

## Estructura

```
.
├── README.md
├── docker-compose.yml
├── postgres/
│   ├── init/
│   │   ├── 01_esquema.sql              # esquema (corre solo con la base vacía)
│   │   └── 02_roles.sql                # los 4 perfiles: lector, bibliotecario, administrador, auditor
│   └── scripts/
│       ├── carga-libros.sql
│       ├── carga-lectores.sql
│       ├── prueba-sin-regla-titulo.sql # copia de carga-libros.sql con una regla comentada
│       └── datos/                      # CSV semilla, CSV propio y CSV de la prueba
└── docs/
    └── salidas/                        # salida de psql de cada carga
```

## Guía de ejecución

### 1. Inicialización del entorno (Docker)

El esquema y los roles se ejecutan automáticamente al levantar PostgreSQL con la carpeta de datos vacía.

```bash
# Reiniciar contenedores y limpiar datos antiguos
docker compose down
rm -rf postgres/data/*        # en PowerShell: Remove-Item -Recurse -Force postgres\data\*

# Levantar PostgreSQL
docker compose up -d postgres

# Confirmar las tablas del esquema y los 4 roles
docker compose exec postgres psql -U curso -d curso -c '\dt biblioteca.*'
docker compose exec postgres psql -U curso -d curso -c 'SELECT nombre FROM biblioteca.rol;'
```

### 2. Ejecución de las cargas desde psql

Los scripts se corren a mano dentro del contenedor. Sin `-v archivo=...` cargan el CSV limpio por defecto.

```bash
# 1. Libros limpio
docker compose exec postgres psql -U curso -d curso -f /scripts/carga-libros.sql

# 2. Libros con errores a propósito
docker compose exec postgres psql -U curso -d curso \
  -v archivo=/scripts/datos/libros_semilla_con_errores.csv \
  -f /scripts/carga-libros.sql

# 3. Lectores limpio (debe ir antes del de errores: este repite un documento ya cargado)
docker compose exec postgres psql -U curso -d curso -f /scripts/carga-lectores.sql

# 4. Lectores con errores
docker compose exec postgres psql -U curso -d curso \
  -v archivo=/scripts/datos/lectores_semilla_con_errores.csv \
  -f /scripts/carga-lectores.sql

# 5. Nuestro CSV propio
docker compose exec postgres psql -U curso -d curso \
  -v archivo=/scripts/datos/libros_propio.csv \
  -f /scripts/carga-libros.sql

# 6. Ver la bitácora de rechazos
docker compose exec postgres psql -U curso -d curso \
  -c 'SELECT archivo, linea, motivo FROM carga.rechazo_carga ORDER BY id_rechazo;'
```

## Mapeo CSV → esquema propio

Todas las tablas están en el esquema `biblioteca`; la bitácora está en `carga.rechazo_carga`.

### Libros (`isbn, titulo, autor, categoria, anio_publicacion, ejemplares_disponibles`)

| Columna del CSV | Destino | Transformación | Regla de validación (motivo en bitácora) |
|---|---|---|---|
| `isbn` | `libro.isbn` | `trim`; se quitan los guiones | no vacío (`isbn vacío`); 13 dígitos (`isbn no tiene 13 dígitos`); no existe en `libro` (`isbn ya existe en el catálogo`); no repetido en el archivo (`isbn repetido en el archivo`) |
| `titulo` | `libro.titulo` | `trim` | no vacío (`título vacío`) |
| `autor` | `libro.autor` | `trim` | no vacío (`autor vacío`) |
| `categoria` | `categoria.nombre` → `libro.id_categoria` | alta con `ON CONFLICT (nombre) DO NOTHING` y búsqueda de la clave por nombre | no vacía (`categoría vacía`) |
| `anio_publicacion` | `libro.anio_publicacion` | `::integer` | solo dígitos (`año no numérico`); entre 1450 y 2100 (`año fuera de rango`) |
| `ejemplares_disponibles` | `ejemplar` (una fila por copia) | `generate_series(1, n)`; `codigo = isbn-n`; `estado = 'disponible'` | entero de hasta 4 dígitos (`ejemplares no numérico`); mayor o igual a 0 (`ejemplares negativo`) |
| *(estructura)* | todo el archivo | n/a | exactamente 6 columnas (`tiene N columnas, se esperaban 6`) |

### Lectores (`documento, nombres, apellidos, correo, telefono`): todos van a `cuenta`

| Columna del CSV | Destino | Transformación | Regla de validación (motivo en bitácora) |
|---|---|---|---|
| `documento` | `cuenta.documento` y `cuenta.usuario` | `trim` | no vacío (`documento vacío`); 6 a 15 dígitos (`documento no numérico o de longitud inválida`); no existe en `cuenta` (`documento ya existe`); no repetido en el archivo |
| `nombres` | `cuenta.nombres` | `trim` | no vacío (`nombres vacíos`) |
| `apellidos` | `cuenta.apellidos` | `trim` | no vacío (`apellidos vacíos`) |
| `correo` | `cuenta.correo` | `lower(trim(...))` | no vacío (`correo vacío`); formato válido (`correo inválido`); no registrado (`correo ya registrado`); no repetido en el archivo |
| `telefono` | `cuenta.telefono` | `trim` | 7 a 10 dígitos (`teléfono inválido`); coincide con el `CHECK` del esquema |
| *(no viene en el CSV)* | `cuenta.id_rol` | id del rol `lector` (creado en `02_roles.sql`) | si el rol no existe, la carga se detiene con un mensaje claro |
| *(no viene en el CSV)* | `cuenta.contrasena` | `crypt(documento, gen_salt('bf'))` (bcrypt con sal) | nunca en texto plano |
| *(estructura)* | todo el archivo | n/a | exactamente 5 columnas |

## Criterios por tipo de error

Principio: **normalizar sí, adivinar no.** Se corrige lo que se puede arreglar de forma mecánica; lo demás se rechaza y queda en la bitácora con archivo, línea, contenido y motivo.

### Los 14 errores de los archivos del curso

| # | Archivo, línea | Error | Decisión | Justificación |
|---|---|---|---|---|
| 1 | libros, 2 | ISBN `…001` ya existe en el catálogo | Rechazar | El título dice "edición duplicada": no se sabe si es otra edición o un error. |
| 2 | libros, 3 | título vacío | Rechazar | Dato obligatorio que no se puede inventar. |
| 3 | libros, 4 | año = `dos` | Rechazar | No hay conversión mecánica de una palabra a un año. |
| 4 | libros, 5 | año = `MCMXLIX` | Rechazar | Convertir números romanos no es una corrección segura. |
| 5 | libros, 6 | 7 columnas en vez de 6 | Rechazar | No se sabe cuál columna sobra. |
| 6 | libros, 7 | autor vacío | Rechazar | Obligatorio. |
| 7 | libros, 8 | ISBN vacío | Rechazar | Es la clave de negocio del libro. |
| 8 | libros, 9 | ejemplares = `-3` | Rechazar | No existen copias negativas. |
| 9 | lectores, 2 | documento `…001` ya existe | Rechazar | Identificador único (`UNIQUE` en `cuenta`). |
| 10 | lectores, 3 | correo vacío | Rechazar | La notificación de mora necesita el correo; el esquema lo exige. |
| 11 | lectores, 4 | correo sin `@` | Rechazar | No se puede adivinar el correo correcto. |
| 12 | lectores, 5 | teléfono `tres-cero-cero` | Rechazar | Dato inválido; el esquema también lo exige (`CHECK`). |
| 13 | lectores, 6 | documento vacío | Rechazar | Identificador obligatorio. |
| 14 | lectores, 7 | nombres vacíos | Rechazar | Obligatorio. |

### Correcciones automáticas y reglas adicionales

| Caso | Acción | Justificación |
|---|---|---|
| Espacios al inicio o al final | Corregir (`trim`) | No descartar datos válidos por formato. |
| Correo con mayúsculas | Corregir (`lower`) | Normalizar para comparar duplicados y buscar. |
| ISBN con guiones (`978-0000000103`) | Corregir (quitar guiones) | Es el mismo ISBN escrito de otra forma. |
| Categoría que no existe todavía | Crearla y usar su clave | La categoría es un dato válido del catálogo. |
| ISBN repetido dentro del mismo archivo | Conservar el primero, rechazar el resto | La copia va a la bitácora. |
| Documento o correo repetido dentro del archivo | Conservar el primero, rechazar el resto | Un documento identifica a una sola persona. |
| Correo ya usado por otra cuenta | Rechazar (`correo ya registrado`) | Cada lector debe tener su correo para las notificaciones. Regla del script; no es una restricción `UNIQUE` del esquema. |

## Preguntas del laboratorio y resultados

### 1. ¿Por qué un `COPY` directo a la tabla final no sirve para un archivo con errores?

Se probó cargando `libros_semilla_con_errores.csv` directamente en una tabla con las mismas restricciones que la tabla final:

```
ERROR:  null value in column "titulo" of relation "libro_directo" violates not-null constraint
DETAIL:  Failing row contains (9780000000033, null, Julio Cortázar, Novela, 1963, 3).
CONTEXT:  COPY libro_directo, line 3: "9780000000033,,Julio Cortázar,Novela,1963,3"
```

1. **Es todo o nada.** `COPY` es una sola sentencia: al fallar la línea 3 también se deshace la línea 2, que estaba bien.
2. **Solo se ve el primer error.** El archivo trae 8 filas malas por motivos distintos y habría que corregir y repetir 8 veces.
3. **El mensaje es del motor, no del negocio.** Además, varios errores ni llegan a la restricción: un texto en una columna `integer` falla al convertir el tipo, y una fila con una columna de más falla al partir la línea.

### 2. ¿Qué pasa si se vuelve a correr la carga limpia?

- **Libros:** las 32 filas salen rechazadas con el motivo `isbn ya existe en el catálogo`.
- **Lectores:** las 20 filas salen rechazadas con el motivo `documento ya existe`.

No se duplica nada: con solo la semilla quedan 32 libros, 94 ejemplares, 9 categorías y 20 cuentas. La carga se puede repetir sin riesgo, y cada intento queda en la bitácora.

### 3. Prueba de la última línea de defensa

**Qué se hizo.** Se copió `carga-libros.sql` a `prueba-sin-regla-titulo.sql` y se comentó la regla `WHEN titulo = '' THEN 'título vacío'` del `CASE` (el original no se tocó). Se cargó `datos/prueba_titulo_vacio.csv`, que trae 2 filas válidas, 1 con título vacío y 1 sin autor.

**Qué pasó en la base de datos.**

1. Sin la regla, la fila de título vacío pasó la validación y llegó al `INSERT` en `libro`.
2. La frenó el `CHECK` del esquema (`libro_check`, que exige título y autor no vacíos):

```
ERROR:  new row for relation "libro" violates check constraint "libro_check"
DETAIL:  Failing row contains (40, 7, 9780000000203, , Autor Tres, null, 2003, t).
```

3. El error abortó la transacción (`BEGIN ... COMMIT`) y PostgreSQL la revirtió completa.

**Resultado en los datos.**

- Ninguna fila del archivo entró a `libro`, ni siquiera las dos válidas.
- La bitácora quedó sin registros de esa carga: la fila del autor vacío, que sí tenía su regla activa, tampoco quedó registrada, porque el error ocurrió antes del paso que escribe en `carga.rechazo_carga`.
- Con la regla activa (script normal, mismo archivo) el resultado fue 2 cargadas y 2 rechazadas, con los motivos `título vacío` y `autor vacío`.

**Conclusión.** Los `CHECK` evitan que entre un dato inválido, pero no sirven como sistema de carga masiva: un solo error cancela toda la carga y se pierde la información de diagnóstico. Por eso hay que validar antes, en la tabla de paso, con motivos legibles.

## CSV propio

`postgres/scripts/datos/libros_propio.csv`: 5 libros válidos que no están en la semilla (uno con el ISBN escrito con guion, que se corrige, y una categoría nueva, `Autoayuda`) y 3 errores que no aparecen en los archivos del curso.

| Línea | Error | Motivo registrado |
|---|---|---|
| 7 | Mismo ISBN dos veces en el archivo | isbn repetido en el archivo |
| 8 | Año 2101 | año fuera de rango |
| 9 | ISBN de 12 dígitos | isbn no tiene 13 dígitos |

Resultado: 5 cargadas y 3 rechazadas.

## Decisiones de diseño

- **Bitácora fuera del modelo.** `carga.rechazo_carga` vive en un esquema aparte (`carga`) para no alterar el modelo de la biblioteca. Las tablas de paso son temporales y se borran al terminar cada carga.
- **Correo y teléfono obligatorios** en `cuenta`, con `CHECK` de formato, porque la notificación de mora debe mostrar nombre, correo y teléfono del lector.
- **Ejemplares.** El CSV trae una cantidad; el esquema guarda una fila por copia, con `codigo = isbn-número de copia` y `estado = 'disponible'`.
- **Lectores.** Se cargan en `cuenta` con el rol `lector`. El `usuario` es el documento y la contraseña inicial es el documento con hash bcrypt, nunca en texto plano.

## Archivos de salida

Los registros de consola de `psql` están en `docs/salidas/`:

| Archivo | Contenido |
|---|---|
| `01-libros-limpio.txt` | Carga limpia inicial de libros |
| `02-libros-con-errores.txt` | Detección de los 8 errores en libros |
| `03-lectores-con-errores.txt` | Detección de los 6 errores en lectores |
| `04-csv-propio.txt` | CSV propio: 5 cargadas y 3 rechazadas |
| `05-prueba-ultima-linea-defensa.txt` | Evidencia del `ROLLBACK` al comentar una regla del `CASE` |