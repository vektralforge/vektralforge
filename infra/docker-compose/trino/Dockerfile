# VektralForge — Trino
#
# La imagen es la de arriba sin cambios de versión: lo único que añade este
# Dockerfile es un entrypoint que renderiza los catálogos.
#
# Por qué hace falta: Trino solo resuelve `${ENV:VARIABLE}` en sus archivos de
# configuración, así que la clave de MinIO tenía que vivir en el entorno del
# contenedor —y aparecer en `docker inspect` y en `docker compose config`—. El
# resto del stack ya la recibe como archivo montado; esto pone a Trino en la
# misma línea.
FROM trinodb/trino:483

USER root

# El entrypoint escribe los catálogos en /etc/trino/catalog, que deja de ser un
# bind mount del repositorio: ahora el repositorio se monta como plantilla, de
# solo lectura, y el catálogo real vive en la capa de escritura del contenedor.
# Renombrar exige permiso sobre el DIRECTORIO, de ahí el chown.
RUN id trino > /dev/null 2>&1 || { \
      echo "ERROR: la imagen de Trino ya no trae el usuario 'trino'." >&2; exit 1; }

COPY infra/docker-compose/trino/docker-entrypoint.sh /opt/vektralforge/bin/docker-entrypoint.sh
#
# Y se vacía: hasta ahora el bind mount del repositorio TAPABA los catálogos de
# ejemplo que trae la imagen (tpch y compañía). Al dejar de montar encima
# volverían a estar activos sin que nadie lo hubiera pedido.
# chmod 755 y no `chmod +x`. Estos archivos llegan al contexto de build con
# permisos 700, y `+x` sobre 700 deja 711: el kernel ejecuta el archivo, pero
# el intérprete del shebang necesita LEERLO, y sin o+r falla con un
# «bash: ...: Permission denied» que parece un problema de ejecución y no lo es.
RUN chmod 755 /opt/vektralforge/bin/docker-entrypoint.sh && \
    mkdir -p /etc/trino/catalog /etc/trino/catalog-plantilla && \
    rm -f /etc/trino/catalog/*.properties && \
    chown -R trino:trino /etc/trino/catalog /etc/trino/catalog-plantilla /opt/vektralforge

USER trino

# Detrás de `USER trino`: como root la comprobación pasaría aunque el usuario
# real no pudiera ejecutar nada.
RUN test -x /usr/lib/trino/bin/run-trino || { \
      echo "ERROR: la imagen de Trino ya no trae /usr/lib/trino/bin/run-trino." >&2; \
      exit 1; } && \
    test -r /opt/vektralforge/bin/docker-entrypoint.sh || { \
      echo "ERROR: el entrypoint no es legible por el usuario trino." >&2; \
      exit 1; } && \
    echo "lanzador de la imagen base presente y entrypoint legible"

ENTRYPOINT ["/opt/vektralforge/bin/docker-entrypoint.sh"]
