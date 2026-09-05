# VektralForge — imagen de Airflow
#
# Airflow 3.3.0 · Python 3.12 · pyspark 4.1.3 · Delta 4.1.0 · OpenLineage 1.52.0
#
# SparkSubmitOperator ejecuta spark-submit desde este contenedor, así que el
# driver corre aquí y necesita los MISMOS JAR que el cluster. Se resuelven con
# Maven por el mismo motivo que en el Dockerfile de Spark: la versión del AWS
# SDK v2 la hereda hadoop-aws de su POM padre y fijarla a mano es frágil.

# ── Etapa 1: resolver los JAR con Maven ──────────────────────────────────────
FROM maven:3.9-eclipse-temurin-17 AS jars

# Deben coincidir con infra/docker-compose/spark/Dockerfile.
ARG DELTA_VERSION=4.1.0
# Desde Delta 4.1 el artefacto lleva la versión de Spark en el nombre
# (delta-spark_4.0, _4.1, _4.2). Se usa la explícita en vez de la genérica
# para que un desajuste falle al resolver el POM y no en tiempo de ejecución.
ARG SPARK_MINOR=4.1
ARG SCALA_BINARY=2.13
ARG HADOOP_VERSION=3.4.2
ARG OPENLINEAGE_VERSION=1.52.0

WORKDIR /build

RUN printf '%s\n' \
  '<project xmlns="http://maven.apache.org/POM/4.0.0">' \
  '  <modelVersion>4.0.0</modelVersion>' \
  '  <groupId>org.vektralforge</groupId>' \
  '  <artifactId>driver-jars</artifactId>' \
  '  <version>1.0</version>' \
  '  <dependencies>' \
  "    <dependency><groupId>io.delta</groupId><artifactId>delta-spark_${SPARK_MINOR}_${SCALA_BINARY}</artifactId><version>${DELTA_VERSION}</version></dependency>" \
  "    <dependency><groupId>org.apache.hadoop</groupId><artifactId>hadoop-aws</artifactId><version>${HADOOP_VERSION}</version></dependency>" \
  "    <dependency><groupId>io.openlineage</groupId><artifactId>openlineage-spark_${SCALA_BINARY}</artifactId><version>${OPENLINEAGE_VERSION}</version></dependency>" \
  '  </dependencies>' \
  '</project>' > pom.xml

RUN mvn -q -B dependency:copy-dependencies \
      -DoutputDirectory=/jars \
      -DincludeScope=runtime \
      -DexcludeGroupIds=org.apache.spark,org.scala-lang \
    && ls -1 /jars

# ── Etapa 2: imagen final ────────────────────────────────────────────────────
FROM apache/airflow:3.3.1-python3.12

ARG AIRFLOW_VERSION=3.3.0
ARG PYTHON_VERSION=3.12
ARG CONSTRAINTS_URL=https://raw.githubusercontent.com/apache/airflow/constraints-${AIRFLOW_VERSION}/constraints-${PYTHON_VERSION}.txt

# spark-submit requiere una JVM; curl se usa más abajo.
USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends default-jre-headless curl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

USER airflow

COPY airflow/requirements.txt /tmp/requirements.txt

# El --constraint evita que pip reemplace dependencias de la imagen base.
RUN pip install --no-cache-dir -r /tmp/requirements.txt --constraint "${CONSTRAINTS_URL}"

# pyspark-client (Spark Connect) llega vía constraints y sobrescribe el paquete
# pyspark, que necesitamos completo para spark-submit y delta-spark.
RUN pip uninstall -y pyspark-client pyspark && \
    pip install --no-cache-dir pyspark==4.1.3 delta-spark==4.1.0

# pip instala pyspark desde el tarball fuente y sus scripts quedan sin permiso
# de ejecución.
RUN find /home/airflow/.local -name "spark-*" -path "*/bin/*" -exec chmod +x {} \; && \
    find /home/airflow/.local/lib -path "*pyspark/bin/*" -type f -exec chmod +x {} \;

# Los mismos JAR que el cluster, en el classpath del driver.
COPY --from=jars --chown=airflow:root /jars/ /tmp/extra-jars/
RUN PYSPARK_JARS=$(python -c "import pyspark, os; print(os.path.join(os.path.dirname(pyspark.__file__), 'jars'))") && \
    cp /tmp/extra-jars/*.jar "$PYSPARK_JARS/" && \
    rm -rf /tmp/extra-jars

# El driver de Spark corre en ESTE contenedor (SparkSubmitOperator usa modo
# client), así que el listener de OpenLineage se declara aquí. Se usa
# SPARK_CONF_DIR en vez del conf/ de pyspark porque esa ruta depende de dónde
# pip haya instalado el paquete.
COPY infra/docker-compose/spark/spark-defaults.conf /opt/vektralforge/spark-conf/spark-defaults.conf
ENV SPARK_CONF_DIR=/opt/vektralforge/spark-conf

# La cadena de conexión a Postgres se calcula al vuelo desde el secreto montado,
# vía AIRFLOW__DATABASE__SQL_ALCHEMY_CONN_CMD. Ver el docstring del script.
COPY infra/docker-compose/airflow/cadena_de_conexion.py /opt/vektralforge/bin/cadena_de_conexion.py

# ── Credenciales de MinIO: archivos, no variables de entorno ─────────────────
#
# En este contenedor hay dos consumidores y cada uno lee un formato distinto:
# el driver de Spark —SparkSubmitOperator usa modo client, así que corre AQUÍ—
# busca core-site.xml en SPARK_CONF_DIR, y boto3 —el de los DAGs y el de los
# jobs de spark/jobs/— lee el INI que le indica AWS_SHARED_CREDENTIALS_FILE.
#
# Antes las dos rutas se resolvían con AWS_ACCESS_KEY_ID y AWS_SECRET_ACCESS_KEY
# en el entorno de los cuatro contenedores, donde las enseñaba `docker inspect`.
COPY infra/docker-compose/comun/core-site.xml.base /opt/vektralforge/conf/core-site.xml.base
COPY infra/docker-compose/comun/credenciales_minio.sh /opt/vektralforge/bin/credenciales_minio.sh
COPY infra/docker-compose/airflow/docker-entrypoint.sh /opt/vektralforge/bin/docker-entrypoint.sh

# COPY crea los directorios intermedios como root aunque el USER sea airflow, y
# el entrypoint escribe en spark-conf/ y en aws/ al arrancar. Renombrar exige
# permiso sobre el DIRECTORIO, así que el chown va sobre ellos y no sobre los
# archivos.
USER root
# chmod 755 y no `chmod +x`. Estos archivos llegan al contexto de build con
# permisos 700, y `+x` sobre 700 deja 711: el kernel ejecuta el archivo, pero
# el intérprete del shebang necesita LEERLO, y sin o+r falla con un
# «bash: ...: Permission denied» que parece un problema de ejecución y no lo es.
RUN chmod 755 /opt/vektralforge/bin/cadena_de_conexion.py \
              /opt/vektralforge/bin/credenciales_minio.sh \
              /opt/vektralforge/bin/docker-entrypoint.sh && \
    chmod 644 /opt/vektralforge/conf/core-site.xml.base && \
    mkdir -p /opt/vektralforge/aws && \
    chown airflow:root /opt/vektralforge/spark-conf /opt/vektralforge/aws && \
    chmod 700 /opt/vektralforge/aws
USER airflow

ENV VF_CORE_SITE=/opt/vektralforge/spark-conf/core-site.xml
ENV VF_CORE_SITE_BASE=/opt/vektralforge/conf/core-site.xml.base
ENV VF_AWS_CREDENTIALS=/opt/vektralforge/aws/credentials
ENV AWS_SHARED_CREDENTIALS_FILE=/opt/vektralforge/aws/credentials

RUN airflow version && \
    java -version && \
    python -c "import pyspark, delta; assert pyspark.__version__.startswith('4.1'), pyspark.__version__; print('pyspark', pyspark.__version__, 'delta OK')" && \
    PYSPARK_JARS=$(python -c "import pyspark, os; print(os.path.join(os.path.dirname(pyspark.__file__), 'jars'))") && \
    ls "$PYSPARK_JARS" | grep -q "^hadoop-aws-" && \
    ls "$PYSPARK_JARS" | grep -q "delta-spark_4.1_2.13" && \
    ls "$PYSPARK_JARS" | grep -q "^bundle-" && \
    ls "$PYSPARK_JARS" | grep -q "^openlineage-spark_2.13-" && \
    test -f "$SPARK_CONF_DIR/spark-defaults.conf" && \
    echo "JARs de Delta, AWS SDK v2 y OpenLineage presentes"

# El script de la cadena de conexión NO debe terminar en salto de línea: Airflow
# no lo recorta y Postgres acaba buscando una base llamada "airflow\n". Costó un
# arranque fallido descubrirlo; que falle aquí y no en el `db migrate`.
#
# La URL esperada se comprueba en dos grep, principio y final por separado, y no
# en uno solo con la cadena entera. Escrita de una pieza contiene el patrón
# usuario:clave@host y detect-secrets la marca como «Basic Auth Credentials»,
# con razón: no distingue una clave real de la literal `clave-de-prueba`. Un
# `# pragma: allowlist secret` no cabe en una línea con continuación.
RUN printf 'clave-de-prueba' > /tmp/pw && \
    POSTGRES_PASSWORD_FILE=/tmp/pw POSTGRES_USER=u \
      /opt/vektralforge/bin/cadena_de_conexion.py > /tmp/salida && \
    rm -f /tmp/pw && \
    [ "$(tail -c1 /tmp/salida | od -An -c | tr -d ' ')" != "\\n" ] || { \
      echo "ERROR: cadena_de_conexion.py termina en salto de línea." >&2; exit 1; } && \
    grep -q '^postgresql+psycopg2://u:clave-de-prueba' /tmp/salida && \
    grep -q '@postgres:5432/airflow$' /tmp/salida || { \
      echo "ERROR: cadena_de_conexion.py no produce la URL esperada:" >&2; \
      sed -E 's#//([^:]+):[^@]+@#//\1:<clave>@#' /tmp/salida >&2; exit 1; } && \
    rm -f /tmp/salida && \
    echo "cadena_de_conexion.py produce una URL válida y sin salto final"

# El entrypoint encadena /entrypoint, el de la imagen de Airflow, y se declara
# detrás de dumb-init para no quedarse como PID 1 sin recoger zombis — que es
# lo que hace la imagen base. Las dos piezas se comprueban aquí: si alguna
# desaparece en una versión futura, el build lo dice y no el primer arranque.
RUN test -x /entrypoint || { \
      echo "ERROR: la imagen de Airflow ya no trae /entrypoint." >&2; exit 1; } && \
    test -x /usr/bin/dumb-init || { \
      echo "ERROR: la imagen de Airflow ya no trae dumb-init." >&2; exit 1; } && \
    echo "entrypoint y dumb-init de la imagen base presentes"

# El generador de credenciales, con una clave falsa, con el usuario con el que
# va a correr y escribiendo en el destino real: así comprueba de paso que los
# dos directorios son escribibles por `airflow`.
RUN printf 'clave-de-prueba' > /tmp/s && \
    MINIO_ACCESS_KEY=prueba MINIO_SECRET_KEY_FILE=/tmp/s \
      /opt/vektralforge/bin/credenciales_minio.sh && \
    rm -f /tmp/s && \
    grep -q "<name>fs.s3a.secret.key</name>" /opt/vektralforge/spark-conf/core-site.xml && \
    grep -q "^\\[default\\]$" /opt/vektralforge/aws/credentials && \
    rm -f /opt/vektralforge/spark-conf/core-site.xml /opt/vektralforge/aws/credentials && \
    echo "credenciales_minio.sh genera core-site.xml y el INI del SDK"

ENTRYPOINT ["/usr/bin/dumb-init", "--", "/opt/vektralforge/bin/docker-entrypoint.sh"]
