# VektralForge — imagen de Airflow
#
# La versión de Airflow vive AQUÍ, en la etiqueta de la imagen base, y no se
# reinstala desde requirements.txt. Los providers sí se instalan, sujetos al
# archivo de constraints que Airflow publica para cada versión.

FROM apache/airflow:3.3.0-python3.12

# Mantener sincronizados con la etiqueta de arriba: el archivo de constraints
# es específico por versión de Airflow y de Python.
ARG AIRFLOW_VERSION=3.3.0
ARG PYTHON_VERSION=3.12
ARG CONSTRAINTS_URL=https://raw.githubusercontent.com/apache/airflow/constraints-${AIRFLOW_VERSION}/constraints-${PYTHON_VERSION}.txt

# spark-submit requiere una JVM. Se instala como root y se vuelve a airflow.
USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends default-jre-headless \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
ENV JAVA_HOME=/usr/lib/jvm/default-java

USER airflow

COPY airflow/requirements.txt /tmp/requirements.txt

# El --constraint evita que pip reemplace dependencias de la imagen base y deje
# un Airflow inconsistente. No es opcional al instalar sobre la imagen oficial.
RUN pip install --no-cache-dir -r /tmp/requirements.txt --constraint "${CONSTRAINTS_URL}"

RUN find /home/airflow/.local -name "spark-*" -path "*/bin/*" -exec chmod +x {} \; && \
    find /home/airflow/.local/lib -path "*pyspark/bin/*" -type f -exec chmod +x {} \;

# Comprobación en tiempo de build: si algún provider quedó a medias, el fallo
# ocurre aquí y no cuarenta segundos después de levantar el stack.
RUN airflow version && \
    python -c "import airflow.providers.openlineage, airflow.providers.fab" && \
    java -version
