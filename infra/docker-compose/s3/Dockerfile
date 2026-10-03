# VektralForge — RustFS con el CLI `rc` dentro
#
# RustFS publica el servidor y el CLI como dos artefactos separados: `rc` vive
# en github.com/rustfs/cli, con su propio ciclo de releases, y NO viaja dentro
# de la imagen del servidor. `mc` sí lo hacía, y en ese detalle se apoyaba todo
# `init_users.sh`: la credencial raíz entra al contenedor por la TUBERÍA de
# `docker exec -i` y no por argv ni por el entorno (#54, #55).
#
# Sin `rc` dentro quedaban dos caminos, y los dos deshacen ese trabajo: pasar la
# credencial en la línea de comandos o ponerla en el entorno del contenedor. Por
# eso el CLI se hornea aquí. Tampoco servía ejecutarlo en el host: el proyecto
# publica binarios de Linux (amd64 y arm64), no de macOS.
ARG RUSTFS_VERSION=1.0.0-rc.6
ARG RC_VERSION=0.1.34

# La descarga va en una etapa aparte para que la imagen final no necesite curl
# ni tar durante el build y no arrastre nada del proceso.
#
# Aquí no se ejecuta `rc` como comprobación a propósito: en una construcción
# cruzada eso exigiría QEMU y ataría el build multi-arco a tenerlo. La
# integridad ya la garantiza el sha256.
FROM alpine:3.22 AS cli
ARG RC_VERSION
ARG TARGETARCH
# sha256 de los dos artefactos oficiales, verificados antes de extraer. El
# proyecto fija dependencias por SHA desde el #61, y una descarga sin comprobar
# al principio de la cadena de suministro sería el eslabón más débil de todos.
ARG RC_SHA256_amd64=ff4631d5a6f472a46e64f0f0b5371b9d545b01bed22a2049188462699bd6d819
ARG RC_SHA256_arm64=d43aa94d640fbc02f9296ecc26a0c7f6292f1c1c0ebcf6c877886a30c78f9d39
RUN set -eu; \
    apk add --no-cache curl tar; \
    case "$TARGETARCH" in \
      amd64) sha="$RC_SHA256_amd64" ;; \
      arm64) sha="$RC_SHA256_arm64" ;; \
      *) echo "arquitectura no contemplada: $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /tmp/rc.tgz \
      "https://github.com/rustfs/cli/releases/download/v${RC_VERSION}/rustfs-cli-linux-${TARGETARCH}-v${RC_VERSION}.tar.gz"; \
    printf '%s  /tmp/rc.tgz\n' "$sha" | sha256sum -c -; \
    tar xzf /tmp/rc.tgz -C /tmp; \
    install -D -m 0755 /tmp/rc /out/rc

FROM rustfs/rustfs:${RUSTFS_VERSION}
# `rc` es un binario estático (static-pie), así que no depende de la libc de la
# imagen base.
COPY --from=cli /out/rc /usr/local/bin/rc
