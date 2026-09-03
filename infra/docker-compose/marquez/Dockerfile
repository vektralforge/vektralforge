# Marquez solo publica imágenes amd64. En Apple Silicon corre bajo emulación.
#
# 0.51.1 y no `latest`. Eran la misma imagen el día que se fijó —mismo digest,
# sha256:0721c976…— así que esto no cambia nada hoy; cambia que mañana no se
# mueva sola. `latest` hacía además que la versión no se pudiera saber sin
# entrar al contenedor a mirar el nombre del jar, y que Dependabot no tuviera
# nada que vigilar.
#
# Va junto con marquezproject/marquez-web en docker-compose.yml: la UI habla
# con la API por su REST y las dos versiones se publican en pareja. Subir una
# sola es pedir un desajuste silencioso.
FROM --platform=linux/amd64 marquezproject/marquez:0.51.1

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
