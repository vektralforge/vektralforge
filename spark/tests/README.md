# Tests de los jobs Spark

> **In English.** These tests cover `spark/jobs/transformaciones.py` — the pure
> functions that turn an API response into rows. No Spark, no network, no boto3,
> which is why the CI job runs them without installing pyspark. The document
> lists what each test covers, including the percentile check against
> `numpy.percentile`, and states what is **not** covered: the Delta write and
> the Spark session itself.

Cubren `spark/jobs/transformaciones.py`: todo lo que convierte una respuesta de
API en filas. Sin Spark, sin red y sin boto3 — solo aritmética y diccionarios—,
así que el job `test-spark` del CI no necesita instalar pyspark para correrlos.

Esa es la razón de que las transformaciones vivan en su propio módulo y no
dentro de los jobs. Antes este archivo decía que había que mover el código de
ejecución a `if __name__ == "__main__":`; separar lo puro resultó mejor, porque
además de hacerlo testeable deja explícita la frontera entre lo que necesita un
cluster y lo que no.

`conftest.py` pone `spark/jobs` en el `sys.path`, que es lo que hace Python al
ejecutar un script: dentro del contenedor,
`spark-submit /opt/spark/jobs/bronze_arclim.py` resuelve así el
`import transformaciones`.

## Qué se cubre

- `valor_a_float` — el formato chileno de mindicador (`36.345,67`), los nulos y
  el cero, que es falsy y desaparece si alguien lo comprueba con `if valor:`.
- `filas_indicadores` — recorte de la fecha ISO, serie vacía como hecho normal.
- `limpiar_columna` — los `$` de ARClim, que Delta no admite en nombres de
  columna.
- `percentil` — interpolación lineal; comprobada contra `numpy.percentile` en
  500 casos aleatorios × 5 percentiles, sin discrepancias.
- `filas_series` — la banda de incertidumbre sobre los modelos climáticos. El
  test que más importa es que p10 ≤ media ≤ p90 en los cien años: la regresión
  que motivó estos tests dejaba el 89 % de la columna en nulo y el 11 % restante
  con once percentiles de un solo modelo disfrazados de serie temporal.

## Lo que todavía no se cubre

La escritura en Delta y la sesión de Spark. Para eso hace falta un Spark de
verdad; `chispa` está en `requirements-dev.txt` esperando esos tests, y hoy no
lo usa nadie.
