# VektralForge — Hive Metastore
#
# Catálogo compartido entre Spark y Trino. Al compartirlo, Hive deja de ser un
# mero almacén de metadatos: valida y crea rutas en el object store al gestionar
# esquemas y tablas externas, así que necesita el conector S3A.

# ── Etapa 1: resolver el conector S3A con Maven ──────────────────────────────
FROM maven:3.9-eclipse-temurin-17 AS jars

# DEBE coincidir con el Hadoop que trae apache/hive:4.0.0, que es 3.3.6 —
# distinto del 3.4.2 de Spark 4.1. Ya no se comprueba a ojo: la etapa final
# falla si el JAR de hadoop-common de la imagen no lleva esta misma versión.
#
# Hadoop 3.3.x usa el AWS SDK v1 (com.amazonaws), no el v2 de Spark. Maven
# resuelve la versión correcta a partir de hadoop-aws.
ARG HADOOP_VERSION=3.3.6

WORKDIR /build
RUN printf '%s\n' \
  '<project xmlns="http://maven.apache.org/POM/4.0.0">' \
  '  <modelVersion>4.0.0</modelVersion>' \
  '  <groupId>org.vektralforge</groupId>' \
  '  <artifactId>metastore-s3-jars</artifactId>' \
  '  <version>1.0</version>' \
  '  <dependencies>' \
  "    <dependency><groupId>org.apache.hadoop</groupId><artifactId>hadoop-aws</artifactId><version>${HADOOP_VERSION}</version></dependency>" \
  '  </dependencies>' \
  '</project>' > pom.xml

RUN mvn -q -B dependency:copy-dependencies \
      -DoutputDirectory=/jars \
      -DincludeScope=runtime \
    && ls -1 /jars

# ── Etapa 2 ──────────────────────────────────────────────────────────────────
# 4.0.0 no es comodidad, es un techo: la 4.0.1 elimina el método Thrift
# `get_table` y el cliente Hive 2.3.10 que Spark lleva embebido lo necesita.
# Comprobado subiendo a 4.2.1 y viendo fallar todas las escrituras con
# «Invalid method name: 'get_table'». Ver la nota del README.
FROM apache/hive:4.0.0

# El ARG de la etapa anterior no cruza sola la frontera de la etapa.
ARG HADOOP_VERSION=3.3.6

USER root

ADD https://jdbc.postgresql.org/download/postgresql-42.7.3.jar /opt/hive/lib/postgresql-42.7.3.jar
RUN chmod 644 /opt/hive/lib/postgresql-42.7.3.jar

# Los JAR van a common/lib, que está en el classpath por defecto. En tools/lib
# no siempre se cargan.
COPY --from=jars /jars/ /opt/hadoop/share/hadoop/common/lib/
RUN chmod 644 /opt/hadoop/share/hadoop/common/lib/*.jar

# La configuración de S3 se genera al arrancar, no se versiona con credenciales.
# Las propiedades pasadas por -D en HADOOP_CLIENT_OPTS llegan a la JVM pero no
# al Configuration de Hadoop, que lee de core-site.xml.
COPY infra/docker-compose/hive/core-site.xml.template /opt/hadoop/etc/hadoop/core-site.xml.template
COPY infra/docker-compose/hive/docker-entrypoint.sh /opt/hive/docker-entrypoint.sh
RUN chmod +x /opt/hive/docker-entrypoint.sh && \
    chown hive:hive /opt/hadoop/etc/hadoop

# El bundle del AWS SDK carga muchas clases; 256 MB se queda corto.
ENV HADOOP_HEAPSIZE=512
ENV HADOOP_OPTS="-Xmx512m -Xms256m"

# Verificación en tiempo de build: el comentario del ARG decía «DEBE coincidir»
# y nadie lo comprobaba. Si la imagen de Hive cambia de Hadoop, el fallo ocurre
# aquí y no al primer CREATE TABLE contra S3.
RUN jar=$(find /opt -name "hadoop-common-*.jar" -print -quit) && \
    echo "hadoop-common de la imagen: $(basename "$jar")" && \
    basename "$jar" | grep -q "^hadoop-common-${HADOOP_VERSION}" || { \
      echo "ERROR: la imagen trae $(basename "$jar") y ARG HADOOP_VERSION=${HADOOP_VERSION}." >&2; \
      echo "       hadoop-aws y hadoop-common desalineados rompen S3A." >&2; \
      exit 1; }

USER hive

ENTRYPOINT ["/opt/hive/docker-entrypoint.sh"]
