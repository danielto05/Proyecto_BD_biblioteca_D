# Mapeo CSV → esquema

Todas las tablas están en el esquema `biblioteca`. La bitácora de rechazos está en `carga.rechazo_carga`.

## Libros (`libros_semilla.csv`)

Columnas: `isbn, titulo, autor, categoria, anio_publicacion, ejemplares_disponibles`

| Columna del CSV | Destino | Transformación | Regla de validación (motivo) |
|---|---|---|---|
| `isbn` | `libro.isbn` | `trim`; se quitan los guiones | no vacío (`isbn vacío`); 13 dígitos (`isbn no tiene 13 dígitos`); no existe en `libro` (`isbn ya existe en el catálogo`); no repetido antes en el archivo (`isbn repetido en el archivo`) |
| `titulo` | `libro.titulo` | `trim` | no vacío (`título vacío`) |
| `autor` | `libro.autor` | `trim` | no vacío (`autor vacío`) |
| `categoria` | `categoria.nombre` → `libro.id_categoria` | alta con `ON CONFLICT (nombre) DO NOTHING` y búsqueda de la clave por nombre | no vacía (`categoría vacía`), porque `id_categoria` es NOT NULL |
| `anio_publicacion` | `libro.anio_publicacion` | `::integer` | solo dígitos (`año no numérico`); entre 1450 y 2100 (`año fuera de rango`) |
| `ejemplares_disponibles` | `ejemplar` (una fila por copia) | `generate_series(1, n)`; `codigo = isbn-n`; `estado = 'disponible'` | entero de hasta 4 dígitos (`ejemplares no numérico`); mayor o igual a 0 (`ejemplares negativo`) |
| *(no viene en el CSV)* | `libro.editorial`, `libro.activo` | `NULL` y valor por defecto `true` | n/a |
| *(estructura)* | todo el archivo | n/a | exactamente 6 columnas (`tiene N columnas, se esperaban 6`) |

## Lectores (`lectores_semilla.csv`)

Columnas: `documento, nombres, apellidos, correo, telefono`. Todos se cargan en `cuenta`.

| Columna del CSV | Destino | Transformación | Regla de validación (motivo) |
|---|---|---|---|
| `documento` | `cuenta.documento` y `cuenta.usuario` | `trim` | no vacío (`documento vacío`); 6 a 15 dígitos (`documento no numérico o de longitud inválida`); no existe en `cuenta` (`documento ya existe`); no repetido en el archivo (`documento repetido en el archivo`) |
| `nombres` | `cuenta.nombres` | `trim` | no vacío (`nombres vacíos`) |
| `apellidos` | `cuenta.apellidos` | `trim` | no vacío (`apellidos vacíos`) |
| `correo` | `cuenta.correo` | `lower(trim(...))` | no vacío (`correo vacío`); formato con `@` y dominio (`correo inválido`); no registrado (`correo ya registrado`); no repetido en el archivo (`correo repetido en el archivo`) |
| `telefono` | `cuenta.telefono` | `trim` | no vacío (`teléfono vacío`); 7 a 10 dígitos (`teléfono inválido`) |
| *(no viene en el CSV)* | `cuenta.id_rol` | id del rol `lector` (creado en `02_roles.sql`) | si el rol no existe, la carga se detiene con un mensaje claro |
| *(no viene en el CSV)* | `cuenta.contrasena` | `crypt(documento, gen_salt('bf'))` (bcrypt con sal), nunca en texto plano | n/a |
| *(no viene en el CSV)* | `cuenta.id_usuario_creador`, `fecha_creacion`, `activa` | `NULL`, `now()` y `true` por defecto | n/a |
| *(estructura)* | todo el archivo | n/a | exactamente 5 columnas |
