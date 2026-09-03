# Marquez solo publica imágenes amd64. En Apple Silicon corre bajo emulación.
FROM --platform=linux/amd64 marquezproject/marquez:latest

# La imagen oficial usa WORKDIR /usr/src/app y arranca con ./entrypoint.sh
COPY marquez.yml.template /usr/src/app/marquez.yml.template
COPY docker-entrypoint.sh /usr/src/app/docker-entrypoint.sh
# Modo absoluto: `+x` sobre un archivo que llega en 700 deja 711, y el
# intérprete del shebang necesita leerlo. Aquí no se nota porque el
# contenedor corre como root, pero es la misma trampa.
RUN chmod 755 /usr/src/app/docker-entrypoint.sh

# El entrypoint genera este archivo al arrancar, a partir del .env
ENV MARQUEZ_CONFIG=/usr/src/app/marquez.yml
ENV MARQUEZ_CONFIG_TEMPLATE=/usr/src/app/marquez.yml.template

ENTRYPOINT ["/usr/src/app/docker-entrypoint.sh"]
CMD ["./entrypoint.sh"]
