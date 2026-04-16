FROM apache/hive:4.0.0

# Agregar driver PostgreSQL JDBC para Hive Metastore
USER root
ADD https://jdbc.postgresql.org/download/postgresql-42.7.3.jar /opt/hive/lib/postgresql-42.7.3.jar
RUN chmod 644 /opt/hive/lib/postgresql-42.7.3.jar

# Limitar memoria JVM de Hive Metastore para entorno PoC local
# Sin este límite, la JVM intenta usar hasta 25% de la RAM total del host
ENV HADOOP_HEAPSIZE=256
ENV HADOOP_OPTS="-Xmx256m -Xms128m"

USER hive
