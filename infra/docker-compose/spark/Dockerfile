# VektralForge — imagen de Spark
#
# Spark 4.1.3 · Scala 2.13 · Java 17 · Python 3.12 · Delta 4.1.0 · OpenLineage 1.52.0
#
# Las versiones de Hadoop y del AWS SDK v2 NO se fijan a mano: Hadoop 3.4 migró
# del SDK v1 al v2 y el artefacto cambió de com.amazonaws:aws-java-sdk-bundle a
# software.amazon.awssdk:bundle, cuya versión hadoop-aws hereda de su POM padre.
# Fijarla a mano es la causa más común de ClassNotFoundException en S3A, así que
# aquí la resuelve Maven a partir de las coordenadas declaradas.

# ── Etapa 1: resolver los JAR con Maven ──────────────────────────────────────
FROM maven:3.9-eclipse-temurin-17 AS jars

ARG DELTA_VERSION=4.1.0
# Desde Delta 4.1 el artefacto lleva la versión de Spark en el nombre
# (delta-spark_4.0, _4.1, _4.2). Se usa la explícita en vez de la genérica
# para que un desajuste falle al resolver el POM y no en tiempo de ejecución.
ARG SPARK_MINOR=4.1
ARG SCALA_BINARY=2.13
# Debe corresponder al Hadoop que empaqueta la imagen de Spark: 4.0.0 traía
# 3.4.1 y 4.1.3 trae 3.4.2 (pom.xml de cada etiqueta). Mezclar hadoop-aws con
# los hadoop-client de otra versión rompe S3A. Dependabot no vigila este ARG.
ARG HADOOP_VERSION=3.4.2
# El soporte de Spark 4 llegó en OpenLineage 1.37.0; versiones anteriores no
# sirven aquí. Debe coincidir con infra/docker-compose/airflow/Dockerfile.
ARG OPENLINEAGE_VERSION=1.52.0

WORKDIR /build

# hadoop-aws arrastra el bundle del AWS SDK v2 en la versión correcta.
RUN printf '%s\n' \
  '<project xmlns="http://maven.apache.org/POM/4.0.0">' \
  '  <modelVersion>4.0.0</modelVersion>' \
  '  <groupId>org.vektralforge</groupId>' \
  '  <artifactId>spark-runtime-jars</artifactId>' \
  '  <version>1.0</version>' \
  '  <dependencies>' \
  "    <dependency><groupId>io.delta</groupId><artifactId>delta-spark_${SPARK_MINOR}_${SCALA_BINARY}</artifactId><version>${DELTA_VERSION}</version></dependency>" \
  "    <dependency><groupId>org.apache.hadoop</groupId><artifactId>hadoop-aws</artifactId><version>${HADOOP_VERSION}</version></dependency>" \
  "    <dependency><groupId>io.openlineage</groupId><artifactId>openlineage-spark_${SCALA_BINARY}</artifactId><version>${OPENLINEAGE_VERSION}</version></dependency>" \
  '  </dependencies>' \
  '</project>' > pom.xml

# Se excluyen las dependencias que Spark ya trae en /opt/spark/jars: duplicarlas
# provoca conflictos de classpath difíciles de diagnosticar.
RUN mvn -q -B dependency:copy-dependencies \
      -DoutputDirectory=/jars \
      -DincludeScope=runtime \
      -DexcludeGroupIds=org.apache.spark,org.scala-lang \
    && ls -1 /jars

# ── Etapa 2: imagen final ────────────────────────────────────────────────────
FROM apache/spark:4.2.0

USER root

# La imagen base trae Python 3.10 (Ubuntu 22.04), que llega a fin de vida en
# octubre de 2026. Se instala 3.12 desde deadsnakes para que coincida con el
# driver, que corre en el contenedor de Airflow: PySpark rechaza que driver y
# executors tengan versiones distintas de Python.
RUN apt-get update -q && \
    apt-get install -y -q --no-install-recommends \
      software-properties-common curl ca-certificates && \
    add-apt-repository -y ppa:deadsnakes/ppa && \
    apt-get update -q && \
    apt-get install -y -q --no-install-recommends \
      python3.12 python3.12-venv python3.12-dev && \
    curl -fsSL https://bootstrap.pypa.io/get-pip.py | python3.12 && \
    apt-get purge -y software-properties-common && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

ENV PYSPARK_PYTHON=/usr/bin/python3.12
ENV PYSPARK_DRIVER_PYTHON=/usr/bin/python3.12

# Spark ignora PYSPARK_PYTHON en algunos caminos de arranque del worker y cae
# al python3 del sistema. Se cambia el enlace para que python3 sea 3.12 y el
# intérprete no dependa de precedencias de configuración.
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1 && \
    update-alternatives --set python3 /usr/bin/python3.12

COPY spark/requirements.txt /tmp/requirements.txt
RUN python3.12 -m pip install --no-cache-dir -r /tmp/requirements.txt

COPY --from=jars /jars/ /opt/spark/jars/

# Declara el listener de OpenLineage. La URL de Marquez no va aquí: la inyecta
# el provider de OpenLineage de Airflow en cada spark-submit.
COPY infra/docker-compose/spark/spark-defaults.conf /opt/spark/conf/spark-defaults.conf

# El contenedor corre como spark (UID 185) y su home pertenece a root en la
# imagen base. Sin este chown, Ivy no puede escribir en ~/.ivy2.
RUN mkdir -p /home/spark/.ivy2/cache /home/spark/.ivy2/jars && \
    chown -R spark:spark /home/spark && \
    chmod -R 755 /home/spark

# Verificación en tiempo de build: si algo quedó desalineado, el fallo ocurre
# aquí y no en medio de un DAG.
RUN python3.12 --version && \
    python3.12 -c "import pyspark, delta; print('pyspark', pyspark.__version__)" && \
    ls /opt/spark/jars | grep -q "^hadoop-aws-" && \
    ls /opt/spark/jars | grep -q "delta-spark_4.1_2.13" && \
    ls /opt/spark/jars | grep -q "^bundle-" && \
    ls /opt/spark/jars | grep -q "^openlineage-spark_2.13-" && \
    echo "JARs de Delta, AWS SDK v2 y OpenLineage presentes"

USER spark
