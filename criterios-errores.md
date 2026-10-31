# Criterios por tipo de error

Principio: **normalizar sí, adivinar no.** Se corrige lo que se puede arreglar de forma mecánica y sin ambigüedad; todo lo demás se rechaza y queda en `carga.rechazo_carga` con archivo, línea, contenido y motivo.

## Los 14 errores de los archivos del curso

La línea 1 de cada archivo es el encabezado.

| # | Archivo, línea | Error | Decisión | Motivo registrado | Justificación |
|---|---|---|---|---|---|
| 1 | libros, 2 | ISBN `9780000000001` ya existe en el catálogo | Rechazar | isbn ya existe en el catálogo | El título dice "edición duplicada": no se puede saber si es otra edición o un error. |
| 2 | libros, 3 | título vacío | Rechazar | título vacío | Dato obligatorio que no se puede inventar. |
| 3 | libros, 4 | año = `dos` | Rechazar | año no numérico | No hay conversión mecánica de una palabra a un año. |
| 4 | libros, 5 | año = `MCMXLIX` (número romano) | Rechazar | año no numérico | Convertir romanos no es una corrección segura. |
| 5 | libros, 6 | 7 columnas en vez de 6 | Rechazar | tiene 7 columnas, se esperaban 6 | No se sabe cuál columna sobra. |
| 6 | libros, 7 | autor vacío | Rechazar | autor vacío | Obligatorio. |
| 7 | libros, 8 | ISBN vacío | Rechazar | isbn vacío | Es la clave de negocio del libro. |
| 8 | libros, 9 | ejemplares = `-3` | Rechazar | ejemplares negativo | No existen copias negativas. |
| 9 | lectores, 2 | documento `1000000001` ya existe | Rechazar | documento ya existe | Identificador único. |
| 10 | lectores, 3 | correo vacío | Rechazar | correo vacío | El esquema exige correo: la notificación de mora debe mostrarlo. |
| 11 | lectores, 4 | correo sin `@` | Rechazar | correo inválido | No se puede adivinar el correo correcto. |
| 12 | lectores, 5 | teléfono `tres-cero-cero` | Rechazar | teléfono inválido | Se mantiene un criterio simple: dato inválido, se rechaza. El esquema también lo exige (`CHECK`). |
| 13 | lectores, 6 | documento vacío | Rechazar | documento vacío | Identificador obligatorio. |
| 14 | lectores, 7 | nombres vacíos | Rechazar | nombres vacíos | Obligatorio. |

## Correcciones automáticas (no se rechaza)

| Caso | Qué se hace |
|---|---|
| Espacios al inicio o al final de cualquier campo | `trim` |
| Correo con mayúsculas | `lower` antes de validar y de comparar duplicados |
| ISBN escrito con guiones (`978-0000000103`) | se quitan los guiones antes de validar |
| Categoría que no existe todavía | se crea y se usa su clave |

## Reglas adicionales del grupo

| Regla | Motivo registrado |
|---|---|
| ISBN repetido dentro del mismo archivo (se conserva la primera aparición válida) | isbn repetido en el archivo |
| Documento o correo repetido dentro del mismo archivo | documento repetido en el archivo / correo repetido en el archivo |
| Correo ya usado por otra cuenta | correo ya registrado |
| Ejemplares no numérico (por ejemplo `dos` en esa columna) | ejemplares no numérico |
| Documento de longitud fuera de 6 a 15 dígitos | documento no numérico o de longitud inválida |
| Año fuera de 1450 a 2100 | año fuera de rango |
| ISBN que no tiene 13 dígitos | isbn no tiene 13 dígitos |

## Errores del CSV propio (`libros_propio.csv`)

| Línea | Error | Decisión | Motivo registrado |
|---|---|---|---|
| 7 | Mismo ISBN dos veces en el archivo | Rechazar la segunda aparición | isbn repetido en el archivo |
| 8 | Año 2101 | Rechazar | año fuera de rango |
| 9 | ISBN de 12 dígitos | Rechazar | isbn no tiene 13 dígitos |
