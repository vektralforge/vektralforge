# VektralForge — imagen de Spark
#
# Spark 4.0.0 · Scala 2.13 · Java 17 · Python 3.12 · Delta 4.0.0
#
# Las versiones de Hadoop y del AWS SDK v2 NO se fijan a mano: Hadoop 3.4 migró
# del SDK v1 al v2 y el artefacto cambió de com.amazonaws:aws-java-sdk-bundle a
# software.amazon.awssdk:bundle, cuya versión hadoop-aws hereda de su POM padre.
# Fijarla a mano es la causa más común de ClassNotFoundException en S3A, así que
# aquí la resuelve Maven a partir de las coordenadas declaradas.

# ── Etapa 1: resolver los JAR con Maven ──────────────────────────────────────
FROM maven:3.9-eclipse-temurin-17 AS jars

ARG DELTA_VERSION=4.0.0
ARG SCALA_BINARY=2.13
ARG HADOOP_VERSION=3.4.1

WORKDIR /build

# hadoop-aws arrastra el bundle del AWS SDK v2 en la versión correcta.
RUN printf '%s\n' \
  '<project xmlns="http://maven.apache.org/POM/4.0.0">' \
  '  <modelVersion>4.0.0</modelVersion>' \
  '  <groupId>org.vektralforge</groupId>' \
  '  <artifactId>spark-runtime-jars</artifactId>' \
  '  <version>1.0</version>' \
  '  <dependencies>' \
  "    <dependency><groupId>io.delta</groupId><artifactId>delta-spark_${SCALA_BINARY}</artifactId><version>${DELTA_VERSION}</version></dependency>" \
  "    <dependency><groupId>org.apache.hadoop</groupId><artifactId>hadoop-aws</artifactId><version>${HADOOP_VERSION}</version></dependency>" \
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
FROM apache/spark:4.0.0

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
    ls /opt/spark/jars | grep -q "delta-spark_2.13" && \
    ls /opt/spark/jars | grep -q "^bundle-" && \
    echo "JARs de Delta y AWS SDK v2 presentes"

USER spark
