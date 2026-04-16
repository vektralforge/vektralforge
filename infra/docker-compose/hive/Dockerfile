FROM apache/hive:4.0.0

# Agregar driver PostgreSQL JDBC para Hive Metastore
# Requerido para conectar con PostgreSQL como backend del metastore
USER root
ADD https://jdbc.postgresql.org/download/postgresql-42.7.3.jar /opt/hive/lib/postgresql-42.7.3.jar
RUN chmod 644 /opt/hive/lib/postgresql-42.7.3.jar

USER hive
