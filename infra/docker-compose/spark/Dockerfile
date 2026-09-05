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

# ── Credenciales de MinIO: archivos, no variables de entorno ─────────────────
#
# Antes llegaban como AWS_ACCESS_KEY_ID y AWS_SECRET_ACCESS_KEY, que es lo que
# resuelve EnvironmentVariableCredentialsProvider. Funcionaba, pero un
# `docker inspect` sobre spark-master o spark-worker enseñaba la clave, igual
# que `docker compose config` y el /proc/<pid>/environ de cualquier proceso del
# contenedor. Ahora el entrypoint la lee del secreto montado y la escribe en
# core-site.xml (600), que es donde SimpleAWSCredentialsProvider la busca.
#
# El INI del SDK se genera también aquí: los jobs de spark/jobs/ tienen un
# cliente boto3 a nivel de módulo, y ese módulo se importa en los executors al
# deserializar cualquier función definida en él.
COPY infra/docker-compose/comun/core-site.xml.base /opt/vektralforge/conf/core-site.xml.base
COPY infra/docker-compose/comun/credenciales_minio.sh /opt/vektralforge/bin/credenciales_minio.sh
COPY infra/docker-compose/spark/docker-entrypoint.sh /opt/vektralforge/bin/docker-entrypoint.sh

# /opt/spark/conf es de root en la imagen base y el contenedor corre como
# spark. El entrypoint escribe en un temporal y renombra, y renombrar exige
# permiso sobre el DIRECTORIO: sin este chown el arranque muere con «Permission
# denied». Es exactamente el fallo que costó un arranque en el #47 con
# hive-site.xml.
# chmod 755 y no `chmod +x`. Estos archivos llegan al contexto de build con
# permisos 700, y `+x` sobre 700 deja 711: el kernel ejecuta el archivo, pero
# el intérprete del shebang necesita LEERLO, y sin o+r falla con un
# «bash: ...: Permission denied» que parece un problema de ejecución y no lo es.
RUN chmod 755 /opt/vektralforge/bin/credenciales_minio.sh \
              /opt/vektralforge/bin/docker-entrypoint.sh && \
    chmod 644 /opt/vektralforge/conf/core-site.xml.base && \
    mkdir -p /opt/vektralforge/aws && \
    chown -R spark:spark /opt/spark/conf /opt/vektralforge/aws && \
    chmod 700 /opt/vektralforge/aws

ENV VF_CORE_SITE=/opt/spark/conf/core-site.xml
ENV VF_CORE_SITE_BASE=/opt/vektralforge/conf/core-site.xml.base
ENV VF_AWS_CREDENTIALS=/opt/vektralforge/aws/credentials
ENV AWS_SHARED_CREDENTIALS_FILE=/opt/vektralforge/aws/credentials

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

# Estas dos comprobaciones van DETRÁS de `USER spark`, a propósito. Antes iban
# delante, como root, y por eso dieron verde sobre una imagen que no arrancaba:
# root se salta la comprobación de lectura que hace fallar al usuario real.
# Una prueba que corre con más privilegios que el sistema que verifica no
# prueba ese sistema.

# El entrypoint encadena el de la imagen base en vez de sustituirlo. Si algún
# día la base deja de traerlo, esto lo dice ahora y no en el primer arranque.
RUN test -x /opt/entrypoint.sh || { \
      echo "ERROR: apache/spark ya no trae /opt/entrypoint.sh." >&2; \
      echo "       docker-entrypoint.sh lo encadena; revisar antes de subir." >&2; \
      exit 1; } && \
    echo "entrypoint de la imagen base presente"

# El generador de credenciales, ejecutado con una clave falsa y con el usuario
# con el que va a correr de verdad. También se escribe donde va a escribir.
RUN printf 'clave-de-prueba' > /tmp/s && \
    MINIO_ACCESS_KEY=prueba MINIO_SECRET_KEY_FILE=/tmp/s \
      /opt/vektralforge/bin/credenciales_minio.sh && \
    rm -f /tmp/s && \
    grep -q "<name>fs.s3a.secret.key</name>" /opt/spark/conf/core-site.xml && \
    grep -q "^\\[default\\]$" /opt/vektralforge/aws/credentials && \
    rm -f /opt/spark/conf/core-site.xml /opt/vektralforge/aws/credentials && \
    echo "credenciales_minio.sh genera core-site.xml y el INI del SDK"

ENTRYPOINT ["/opt/vektralforge/bin/docker-entrypoint.sh"]
