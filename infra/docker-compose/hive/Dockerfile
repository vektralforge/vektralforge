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
#
# La base y el generador son los mismos que usan las imágenes de Airflow y de
# Spark: los tres hablan con MinIO por S3A y necesitan las mismas propiedades.
COPY infra/docker-compose/comun/core-site.xml.base /opt/hadoop/etc/hadoop/core-site.xml.base
COPY infra/docker-compose/comun/credenciales_minio.sh /opt/vektralforge/bin/credenciales_minio.sh
COPY infra/docker-compose/hive/docker-entrypoint.sh /opt/hive/docker-entrypoint.sh
# chmod 755 y no `chmod +x`. Estos archivos llegan al contexto de build con
# permisos 700, y `+x` sobre 700 deja 711: el kernel ejecuta el archivo, pero
# el intérprete del shebang necesita LEERLO, y sin o+r falla con un
# «bash: ...: Permission denied» que parece un problema de ejecución y no lo es.
RUN chmod 755 /opt/hive/docker-entrypoint.sh \
              /opt/vektralforge/bin/credenciales_minio.sh && \
    chmod 644 /opt/hadoop/etc/hadoop/core-site.xml.base && \
    chown hive:hive /opt/hadoop/etc/hadoop

# La imagen trae su propio hive-site.xml con once propiedades — entre ellas
# hive.metastore.warehouse.dir. El entrypoint INSERTA en él las propiedades JDO;
# no lo reemplaza. Se guarda una copia intacta como base para que el arranque
# sea idempotente: sin ella, un reinicio insertaría el bloque una segunda vez.
#
# El hive-site.xml de la imagen es de root:root 644 y el entrypoint corre como
# hive: sobrescribirlo con `>` trunca el archivo, y truncar exige permiso sobre
# el ARCHIVO, no sobre el directorio. Sin este chown el metastore muere en el
# arranque con «Permission denied» y el resto del stack falla después con un
# UnknownHostException que no apunta a la causa.
RUN cp /opt/hive/conf/hive-site.xml /opt/hive/conf/hive-site.xml.base && \
    chown hive:hive /opt/hive/conf \
                    /opt/hive/conf/hive-site.xml \
                    /opt/hive/conf/hive-site.xml.base && \
    chmod 644 /opt/hive/conf/hive-site.xml.base

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

# Las comprobaciones van DETRÁS del `USER` a propósito. Antes iban delante,
# como root, y por eso dieron verde sobre una imagen que no arrancaba: root se
# salta la comprobación de lectura con la que fallaba el usuario real. Una
# prueba que corre con más privilegios que el sistema que verifica no prueba
# ese sistema. Y escriben en el destino REAL, no en /tmp, para que además
# comprueben que el directorio es escribible por ese usuario.

RUN printf 'clave-de-prueba' > /tmp/s && \
    MINIO_ACCESS_KEY=prueba MINIO_ENDPOINT=http://minio:9000 \
    MINIO_SECRET_KEY_FILE=/tmp/s \
    VF_CORE_SITE=/opt/hadoop/etc/hadoop/core-site.xml \
    VF_CORE_SITE_BASE=/opt/hadoop/etc/hadoop/core-site.xml.base \
      /opt/vektralforge/bin/credenciales_minio.sh && \
    rm -f /tmp/s && \
    grep -q "<name>fs.s3a.secret.key</name>" /opt/hadoop/etc/hadoop/core-site.xml && \
    grep -q "<name>fs.s3a.impl</name>" /opt/hadoop/etc/hadoop/core-site.xml && \
    rm -f /opt/hadoop/etc/hadoop/core-site.xml && \
    echo "credenciales_minio.sh genera un core-site.xml completo"

ENTRYPOINT ["/opt/hive/docker-entrypoint.sh"]
