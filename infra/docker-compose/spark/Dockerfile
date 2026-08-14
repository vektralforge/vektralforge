FROM apache/spark:3.5.3

# Instalar Python y pip
USER root
RUN apt-get update -q && \
    apt-get install -y -q python3-pip curl && \
    rm -rf /var/lib/apt/lists/*

# Las versiones de pyspark y delta-spark viven en spark/requirements.txt,
# alineadas con esta imagen base: Spark 3.5.x, Scala 2.12, Delta 3.2.0.
COPY spark/requirements.txt /tmp/requirements.txt
RUN pip3 install --no-cache-dir -r /tmp/requirements.txt

# Descargar JARs directamente a /opt/spark/jars/
# delta-spark_2.12:3.2.0 — compatible con Spark 3.5.x + Scala 2.12
RUN curl -L -o /opt/spark/jars/delta-spark_2.12-3.2.0.jar \
      https://repo1.maven.org/maven2/io/delta/delta-spark_2.12/3.2.0/delta-spark_2.12-3.2.0.jar && \
    curl -L -o /opt/spark/jars/delta-storage-3.2.0.jar \
      https://repo1.maven.org/maven2/io/delta/delta-storage/3.2.0/delta-storage-3.2.0.jar && \
    curl -L -o /opt/spark/jars/hadoop-aws-3.3.4.jar \
      https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-aws/3.3.4/hadoop-aws-3.3.4.jar && \
    curl -L -o /opt/spark/jars/aws-java-sdk-bundle-1.12.262.jar \
      https://repo1.maven.org/maven2/com/amazonaws/aws-java-sdk-bundle/1.12.262/aws-java-sdk-bundle-1.12.262.jar

# Crear directorio ivy con permisos y directorio de jobs
# El contenedor corre como spark (UID 185) y su home pertenece a root en la
# imagen base. Sin este chown, Ivy no puede escribir en ~/.ivy2.
# /opt/spark/jobs no se prepara aquí: llega como volumen de solo lectura desde
# el Compose, y el montaje sobrescribe los permisos de la imagen.
RUN mkdir -p /home/spark/.ivy2/cache /home/spark/.ivy2/jars && \
    chown -R spark:spark /home/spark && \
    chmod -R 755 /home/spark

USER spark
