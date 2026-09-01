# VektralForge — imagen de Airflow
#
# Airflow 3.3.0 · Python 3.12 · pyspark 4.0.0 · Delta 4.0.0 · OpenLineage 1.52.0
#
# SparkSubmitOperator ejecuta spark-submit desde este contenedor, así que el
# driver corre aquí y necesita los MISMOS JAR que el cluster. Se resuelven con
# Maven por el mismo motivo que en el Dockerfile de Spark: la versión del AWS
# SDK v2 la hereda hadoop-aws de su POM padre y fijarla a mano es frágil.

# ── Etapa 1: resolver los JAR con Maven ──────────────────────────────────────
FROM maven:3-eclipse-temurin-26 AS jars

# Deben coincidir con infra/docker-compose/spark/Dockerfile.
ARG DELTA_VERSION=4.0.0
ARG SCALA_BINARY=2.13
ARG HADOOP_VERSION=3.4.1
ARG OPENLINEAGE_VERSION=1.52.0

WORKDIR /build

RUN printf '%s\n' \
  '<project xmlns="http://maven.apache.org/POM/4.0.0">' \
  '  <modelVersion>4.0.0</modelVersion>' \
  '  <groupId>org.vektralforge</groupId>' \
  '  <artifactId>driver-jars</artifactId>' \
  '  <version>1.0</version>' \
  '  <dependencies>' \
  "    <dependency><groupId>io.delta</groupId><artifactId>delta-spark_${SCALA_BINARY}</artifactId><version>${DELTA_VERSION}</version></dependency>" \
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
FROM apache/airflow:3.3.0-python3.12

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
    pip install --no-cache-dir pyspark==4.0.0 delta-spark==4.0.0

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

RUN airflow version && \
    java -version && \
    python -c "import pyspark, delta; assert pyspark.__version__.startswith('4.0'), pyspark.__version__; print('pyspark', pyspark.__version__, 'delta OK')" && \
    PYSPARK_JARS=$(python -c "import pyspark, os; print(os.path.join(os.path.dirname(pyspark.__file__), 'jars'))") && \
    ls "$PYSPARK_JARS" | grep -q "^hadoop-aws-" && \
    ls "$PYSPARK_JARS" | grep -q "delta-spark_2.13" && \
    ls "$PYSPARK_JARS" | grep -q "^bundle-" && \
    ls "$PYSPARK_JARS" | grep -q "^openlineage-spark_2.13-" && \
    test -f "$SPARK_CONF_DIR/spark-defaults.conf" && \
    echo "JARs de Delta, AWS SDK v2 y OpenLineage presentes"
