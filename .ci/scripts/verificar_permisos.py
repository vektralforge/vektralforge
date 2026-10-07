"""Controles de permisos de la cuenta de servicio del pipeline.

Lo ejecuta `.ci/scripts/verificar_permisos.sh` DENTRO del contenedor de Airflow,
que es donde vive el perfil de boto3 con la credencial de vf-pipeline. Por eso
aquí no se lee ningún secreto: boto3 lo toma de AWS_SHARED_CREDENTIALS_FILE.

El razonamiento de por qué los controles van en este orden, y por qué un
NoSuchBucket cuenta como fallo, está en la cabecera del guion que lo invoca.
"""

import os
import sys
import uuid

import boto3
from botocore.config import Config
from botocore.exceptions import ClientError

ENDPOINT = os.environ.get("S3_ENDPOINT", "http://rustfs:9000")
ESPERADA = os.environ["CUENTA_ESPERADA"]
BUCKETS = ("raw", "bronze", "silver", "gold", "checkpoints")
# Solo vf-pipeline tiene este: politica-logs-airflow.json, que init_users.sh une
# a la de datos para esta cuenta y no para las otras dos.
LOGS = "airflow-logs"
PERMITIDOS = (*BUCKETS, LOGS)
# Un nombre que no existe: los negativos que necesitan un bucket lo usan para no
# poder destruir nada aunque la política esté mal y la operación se autorice.
FUERA = "vf-control-negativo-inexistente"

s3 = boto3.client(
    "s3",
    endpoint_url=ENDPOINT,
    region_name="us-east-1",
    config=Config(
        signature_version="s3v4",
        s3={"addressing_style": "path"},
        retries={"max_attempts": 1},
    ),
)

fallos = 0
avisos = 0

# Códigos que cuentan como denegación real. Un NoSuchBucket NO está aquí a
# propósito: significa que la petición pasó la autorización y llegó a buscar.
DENEGADO = ("AccessDenied", "403", "InvalidAccessKeyId", "SignatureDoesNotMatch")


def marcar(ok, etiqueta, detalle=""):
    global fallos
    if not ok:
        fallos += 1
    print(f"  {'✓' if ok else '✗'} {etiqueta}{': ' + detalle if detalle else ''}")


def avisar(etiqueta, detalle):
    """Ni aprobado ni suspenso: el backend se comporta distinto a lo esperado
    pero la propiedad que importa se sostiene. Se imprime en cada ejecución para
    que la divergencia no se olvide, y no rompe el objetivo de make."""
    global avisos
    avisos += 1
    print(f"  ⚠ {etiqueta}: {detalle}")


def codigo(error):
    return error.response.get("Error", {}).get("Code", "?")


def debe_funcionar(etiqueta, fn):
    try:
        fn()
    except ClientError as e:
        marcar(False, etiqueta, f"denegado ({codigo(e)})")
    except Exception as e:  # noqa: BLE001 — cualquier fallo aquí invalida la prueba
        marcar(False, etiqueta, f"{type(e).__name__}: {e}")
    else:
        marcar(True, etiqueta)


def debe_denegarse(etiqueta, fn, deshacer=None):
    try:
        fn()
    except ClientError as e:
        c = codigo(e)
        if c in DENEGADO:
            marcar(True, etiqueta)
        else:
            marcar(
                False, etiqueta, f"{c} — la petición se autorizó y falló por otra razón"
            )
    except Exception as e:  # noqa: BLE001
        marcar(False, etiqueta, f"{type(e).__name__}: {e}")
    else:
        marcar(False, etiqueta, "PERMITIDO")
        if deshacer:
            try:
                deshacer()
                print("      (deshecho)")
            except Exception as e:  # noqa: BLE001
                print(f"      (no se pudo deshacer: {e})")


print(f"\n  Endpoint: {ENDPOINT}")

cred = boto3.Session().get_credentials()
identidad = cred.access_key if cred else None
print(f"  Identidad: {identidad}\n")
if identidad != ESPERADA:
    # Con la raíz los positivos pasarían y los negativos fallarían, pero por el
    # motivo equivocado. Mejor no correr la prueba que informar de algo que no
    # se midió.
    print(f"  ✗ Se esperaba {ESPERADA}. Abortado: la prueba no mediría la política.")
    sys.exit(1)

clave = f"_control_permisos/{uuid.uuid4().hex}.txt"

print("  Controles positivos — esto DEBE funcionar")
debe_funcionar(
    "PutObject en bronze",
    lambda: s3.put_object(Bucket="bronze", Key=clave, Body=b"control"),
)
debe_funcionar(
    "GetObject del objeto escrito", lambda: s3.get_object(Bucket="bronze", Key=clave)
)
debe_funcionar(
    "ListBucket en bronze",
    lambda: s3.list_objects_v2(Bucket="bronze", Prefix="_control_permisos/"),
)
debe_funcionar(
    "GetBucketLocation en bronze", lambda: s3.get_bucket_location(Bucket="bronze")
)
for b in BUCKETS:
    debe_funcionar(
        f"ListBucket en {b}", lambda b=b: s3.list_objects_v2(Bucket=b, MaxKeys=1)
    )

# Las cuatro operaciones de multipart, que son las que usa S3A para escribir
# Delta. Se aborta en vez de completarse: así se ejercita AbortMultipartUpload y
# no queda objeto.
mpu = {}
debe_funcionar(
    "CreateMultipartUpload en bronze",
    lambda: mpu.update(s3.create_multipart_upload(Bucket="bronze", Key=clave + ".mpu")),
)
if mpu.get("UploadId"):
    uid = mpu["UploadId"]
    debe_funcionar(
        "UploadPart",
        lambda: s3.upload_part(
            Bucket="bronze",
            Key=clave + ".mpu",
            UploadId=uid,
            PartNumber=1,
            Body=b"x" * 1024,
        ),
    )
    debe_funcionar(
        "ListMultipartUploads", lambda: s3.list_multipart_uploads(Bucket="bronze")
    )
    debe_funcionar(
        "ListParts",
        lambda: s3.list_parts(Bucket="bronze", Key=clave + ".mpu", UploadId=uid),
    )
    debe_funcionar(
        "AbortMultipartUpload",
        lambda: s3.abort_multipart_upload(
            Bucket="bronze", Key=clave + ".mpu", UploadId=uid
        ),
    )

debe_funcionar(
    "DeleteObject del objeto de prueba",
    lambda: s3.delete_object(Bucket="bronze", Key=clave),
)

# Logs de Airflow: leer, escribir y listar, que es lo que hace el S3TaskHandler.
# La clave es FIJA y se sobrescribe en cada ejecución: la cuenta no puede borrar
# en este bucket, así que una clave aleatoria dejaría un objeto huérfano por
# cada pasada.
CLAVE_LOGS = "_control_permisos/ultimo.txt"
debe_funcionar(
    f"PutObject en {LOGS}",
    lambda: s3.put_object(Bucket=LOGS, Key=CLAVE_LOGS, Body=b"control"),
)
debe_funcionar(
    f"GetObject en {LOGS}", lambda: s3.get_object(Bucket=LOGS, Key=CLAVE_LOGS)
)
debe_funcionar(
    f"ListBucket en {LOGS}",
    lambda: s3.list_objects_v2(Bucket=LOGS, Prefix="_control_permisos/"),
)


def control_listallmybuckets():
    """s3:ListAllMyBuckets no está en la política, pero el servidor la autoriza.

    La primera versión de este control exigía AccessDenied, que es la semántica
    estricta de AWS: acción no concedida, petición denegada. Al correrlo contra
    RustFS salió PERMITIDO — y conviene decir que esa aserción nunca se comprobó
    contra MinIO antes de escribirla. MinIO filtra la lista a los buckets sobre
    los que el usuario tiene permiso en vez de denegar la llamada, así que es
    probable que el control hubiera salido rojo también con el backend anterior.

    Lo que importa no es si la llamada se autoriza, sino si REVELA algo fuera de
    la política. Eso es lo que se mide aquí: la lista devuelta no puede contener
    ningún bucket que no esté en la política. Si lo contiene, es una fuga y el
    control falla; si solo trae los de la política, es una divergencia de forma y queda
    como aviso en cada ejecución.

    Para que la distinción sea medible tiene que existir un bucket fuera de la
    política. Si no existe ninguno, el control lo dice en vez de fingir que pasó.

    MEDIDO el 2026-10-03 contra RustFS 1.0.0-rc.6: con un bucket fuera de la
    política creado con la raíz, la lista devuelta a vf-pipeline seguía trayendo
    solo los cinco. RustFS FILTRA, no revela. La divergencia es de forma
    —autoriza y filtra, en vez de denegar— y la propiedad que importa se
    sostiene. El aviso se queda para que una regresión se vea.
    """
    etiqueta = "ListAllMyBuckets"
    try:
        r = s3.list_buckets()
    except ClientError as e:
        c = codigo(e)
        if c in DENEGADO:
            marcar(True, etiqueta)
        else:
            marcar(
                False, etiqueta, f"{c} — la petición se autorizó y falló por otra razón"
            )
        return
    except Exception as e:  # noqa: BLE001
        marcar(False, etiqueta, f"{type(e).__name__}: {e}")
        return

    nombres = sorted(b["Name"] for b in r.get("Buckets", []))
    fuera = [n for n in nombres if n not in PERMITIDOS]
    if fuera:
        marcar(
            False,
            etiqueta,
            "PERMITIDO y revela buckets fuera de la política: " + ", ".join(fuera),
        )
    elif sorted(nombres) == sorted(PERMITIDOS):
        avisar(
            etiqueta,
            "permitido; la lista trae solo los de la política. Medido el "
            "2026-10-03 con un bucket fuera de ella presente: RustFS filtra",
        )
    else:
        avisar(
            etiqueta,
            f"permitido; devuelve {nombres or 'nada'}. Sin un bucket fuera de la "
            "política no se puede distinguir filtrado de fuga",
        )


print("\n  Controles negativos — esto DEBE denegarse")
debe_denegarse(
    "CreateBucket",
    lambda: s3.create_bucket(Bucket=FUERA),
    deshacer=lambda: s3.delete_bucket(Bucket=FUERA),
)
debe_denegarse("DeleteBucket", lambda: s3.delete_bucket(Bucket=FUERA))
control_listallmybuckets()
debe_denegarse(
    "ListBucket fuera de la política", lambda: s3.list_objects_v2(Bucket=FUERA)
)
debe_denegarse(
    "GetObject fuera de la política", lambda: s3.get_object(Bucket=FUERA, Key="x")
)
# Contra una clave que no existe: si la política lo permitiera, S3 respondería
# 204 sin borrar nada, y si lo deniega, AccessDenied. Así el negativo no puede
# destruir un log real aunque la política esté mal.
debe_denegarse(
    f"DeleteObject en {LOGS}",
    lambda: s3.delete_object(Bucket=LOGS, Key="_control_permisos/no-existe.txt"),
)
debe_denegarse(
    "PutBucketPolicy en bronze",
    lambda: s3.put_bucket_policy(
        Bucket="bronze", Policy='{"Version":"2012-10-17","Statement":[]}'
    ),
)

print()
if fallos:
    print(f"  ✗ {fallos} control(es) fallido(s)")
elif avisos:
    print(
        f"  ✓ La cuenta está acotada: opera sobre los objetos y nada más ({avisos} aviso(s))"
    )
else:
    print("  ✓ La cuenta está acotada: opera sobre los objetos y nada más")
print()
sys.exit(1 if fallos else 0)
