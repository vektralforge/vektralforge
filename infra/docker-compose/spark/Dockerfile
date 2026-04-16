FROM apache/spark:3.5.3

# Instalar Python y pip
USER root
RUN apt-get update -q && \
    apt-get install -y -q python3-pip curl && \
    rm -rf /var/lib/apt/lists/*

# Instalar delta-spark compatible con Spark 3.5.x (NO 4.0.0 — esa requiere Spark 4.x)
RUN pip3 install delta-spark==3.2.0 --quiet

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
RUN mkdir -p /home/spark/.ivy2/cache /home/spark/.ivy2/jars && \
    chmod -R 777 /home/spark && \
    mkdir -p /opt/spark/jobs && \
    chmod 777 /opt/spark/jobs

USER spark
