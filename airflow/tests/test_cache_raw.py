"""Tests del cache en raw/.

raw/ es la zona de aterrizaje y también el cache: lo ya descargado para una
fecha no se vuelve a pedir. Sin estos tests, un `except` mal puesto o un cambio
de nombre de clave desactivan el cache en silencio — el pipeline sigue
funcionando, solo que vuelve a machacar APIs públicas de terceros en cada
ejecución, que es justo lo que no se nota hasta que te bloquean.
"""

import json

import pytest
import requests


class S3Falso:
    """Lo mínimo de la interfaz de boto3 que usa el cache."""

    def __init__(self, objetos=None):
        self.objetos = dict(objetos or {})
        self.heads = []
        self.subidas = []

    def head_object(self, Bucket, Key):  # noqa: N803  (firma de boto3)
        self.heads.append(Key)
        if Key not in self.objetos:
            raise ClienteError(f"404 en {Key}")
        return {"ContentLength": 1}

    def get_object(self, Bucket, Key):  # noqa: N803
        if Key not in self.objetos:
            raise ClienteError(f"404 en {Key}")
        cuerpo = json.dumps(self.objetos[Key]).encode("utf-8")
        return {"Body": _Cuerpo(cuerpo), "ContentLength": len(cuerpo)}

    def put_object(self, Bucket, Key, Body, **kw):  # noqa: N803
        self.subidas.append(Key)
        self.objetos[Key] = json.loads(Body.decode("utf-8"))


class ClienteError(Exception):
    """Sustituye a botocore ClientError; el código solo hace `except Exception`."""


class _Cuerpo:
    def __init__(self, datos):
        self._datos = datos

    def read(self):
        return self._datos


# ── _existe_en_raw ────────────────────────────────────────────────────────────


@pytest.mark.parametrize(
    "modulo",
    ["dag_indicadores_financieros", "dag_arclim_riesgo_climatico"],
)
def test_existe_en_raw_distingue_presente_de_ausente(modulos_dag, modulo):
    m = modulos_dag[modulo]
    s3 = S3Falso({"algo/fecha=2026-01-15/x.json": {}})
    assert m._existe_en_raw(s3, "algo/fecha=2026-01-15/x.json") is True
    assert m._existe_en_raw(s3, "algo/fecha=2026-01-15/no-esta.json") is False


# ── Indicadores: resumen.json como marca de fecha completa ────────────────────


PREFIJO = "indicadores/fecha=2026-01-15"
RESUMEN = {
    "fecha": "2026-01-15",
    "fuente": "mindicador.cl",
    "indicadores": {"uf": {"registros": 3}},
}


def test_cache_caliente_no_toca_la_api(modulos_dag, monkeypatch):
    """Con resumen.json presente no debe crearse ni una sesión HTTP."""
    m = modulos_dag["dag_indicadores_financieros"]
    s3 = S3Falso({f"{PREFIJO}/resumen.json": RESUMEN})
    monkeypatch.setattr(m, "_s3_client", lambda: s3)

    def prohibido():
        raise AssertionError("con el cache caliente no debe abrirse una sesión HTTP")

    monkeypatch.setattr(m, "crear_sesion", prohibido)

    salida = m.extract_indicadores(ds="2026-01-15", params={})

    assert salida == RESUMEN, "el XCom debe ser idéntico al de una descarga real"
    assert s3.subidas == [], "un cache hit no reescribe raw/"


def test_forzar_descarga_ignora_el_cache(modulos_dag, monkeypatch):
    """El parámetro existe para poder refrescar de verdad; si no saliera a la
    API, no serviría de nada."""
    m = modulos_dag["dag_indicadores_financieros"]
    s3 = S3Falso({f"{PREFIJO}/resumen.json": RESUMEN})
    monkeypatch.setattr(m, "_s3_client", lambda: s3)

    pedidas = []

    class SesionSinRed:
        def get(self, url, params=None, timeout=None):
            pedidas.append(url)
            raise requests.ConnectionError("sin red")

    monkeypatch.setattr(m, "crear_sesion", lambda: SesionSinRed())

    with pytest.raises(m.ErrorAPI):
        m.extract_indicadores(ds="2026-01-15", params={"forzar_descarga": True})

    assert pedidas, "con forzar_descarga tiene que salir a la API"


def test_un_diario_que_no_se_puede_descargar_tumba_la_tarea(modulos_dag, monkeypatch):
    """Antes se tragaba el error y reaparecía mucho después como parquet
    ausente, con un mensaje que no señalaba la causa."""
    m = modulos_dag["dag_indicadores_financieros"]
    monkeypatch.setattr(m, "_s3_client", lambda: S3Falso())

    class SesionSinRed:
        def get(self, url, params=None, timeout=None):
            raise requests.ConnectionError("sin red")

    monkeypatch.setattr(m, "crear_sesion", lambda: SesionSinRed())

    with pytest.raises(m.ErrorAPI) as exc:
        m.extract_indicadores(ds="2026-01-15", params={})

    # El mensaje nombra los indicadores, no solo "falló algo".
    assert "UF" in str(exc.value)


# ── ARClim: indicadores que /series/ no sirve ─────────────────────────────────


def test_no_se_piden_los_indicadores_que_arclim_no_sirve(modulos_dag):
    """total_precipitation y dry_days devuelven 500 en /datos/ y en /series/, en
    las tres variantes. Pedirlos no solo pierde el dato: un solo atributo de
    total_precipitation hace fallar entera la petición de /datos/, que es lo que
    obligaba a recortar la lista de atributos."""
    m = modulos_dag["dag_arclim_riesgo_climatico"]
    for ind in ("total_precipitation", "dry_days"):
        assert ind in m.INDICADORES_NO_DISPONIBLES
        assert ind not in m.INDICADORES
    assert m.INDICADORES, "no pueden quedarse fuera todos"
