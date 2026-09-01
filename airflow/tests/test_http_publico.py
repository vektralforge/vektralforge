"""Tests del cliente HTTP compartido.

Python puro: no necesitan Airflow, ni Spark, ni red. Cubren la parte del
comportamiento que no se ve al mirar un DAG parsear y que puede degradarse sin
que nadie lo note — que los errores no se disfracen de "no hay datos", que el
cliente se identifique, y que reintente lo que hay que reintentar.
"""

import pytest
import requests

from http_publico import (
    PAUSA_ENTRE_LLAMADAS,
    USER_AGENT,
    ErrorAPI,
    crear_sesion,
    get_json,
)


class RespuestaFalsa:
    def __init__(self, datos=None, error=None, json_invalido=False):
        self._datos = datos
        self._error = error
        self._json_invalido = json_invalido

    def raise_for_status(self):
        if self._error:
            raise self._error

    def json(self):
        if self._json_invalido:
            raise ValueError("Expecting value: line 1 column 1 (char 0)")
        return self._datos


class SesionFalsa:
    """Sustituye a requests.Session. get_json la recibe por parámetro, así que
    no hace falta ninguna librería de mocking."""

    def __init__(self, respuesta=None, excepcion=None):
        self.respuesta = respuesta
        self.excepcion = excepcion
        self.llamadas = []

    def get(self, url, params=None, timeout=None):
        self.llamadas.append({"url": url, "params": params, "timeout": timeout})
        if self.excepcion:
            raise self.excepcion
        return self.respuesta


# ── Identificación y reintentos ───────────────────────────────────────────────


def test_la_sesion_se_identifica():
    """Un User-Agent con URL de contacto es lo que hace que un operador te ponga
    en una lista blanca en vez de bloquearte. El de requests no dice nada."""
    sesion = crear_sesion()
    assert "vektralforge" in sesion.headers["User-Agent"]
    assert "http" in sesion.headers["User-Agent"], "falta la URL de contacto"
    assert "python-requests" not in sesion.headers["User-Agent"]


def test_la_sesion_reintenta_lo_que_debe():
    """429 y 5xx se reintentan; un 404 no se arregla reintentando."""
    reintentos = crear_sesion().get_adapter("https://ejemplo.cl").max_retries
    assert 429 in reintentos.status_forcelist
    assert 503 in reintentos.status_forcelist
    assert 404 not in reintentos.status_forcelist
    assert reintentos.total >= 1
    assert reintentos.backoff_factor > 0, "sin backoff los reintentos son un martilleo"
    assert reintentos.respect_retry_after_header, "si la API dice cuánto esperar, se le hace caso"


def test_hay_pausa_configurada_entre_llamadas():
    assert PAUSA_ENTRE_LLAMADAS > 0


def test_el_user_agent_es_el_de_la_sesion():
    assert crear_sesion().headers["User-Agent"] == USER_AGENT


# ── Errores que no se disfrazan de "no hay datos" ─────────────────────────────


def test_devuelve_el_json_cuando_todo_va_bien():
    sesion = SesionFalsa(RespuestaFalsa(datos={"serie": [1, 2, 3]}))
    assert get_json(sesion, "https://ejemplo.cl/api") == {"serie": [1, 2, 3]}


@pytest.mark.parametrize(
    "excepcion",
    [
        requests.ConnectionError("sin red"),
        requests.Timeout("se acabó el tiempo"),
        requests.RequestException("cualquier otra"),
    ],
)
def test_un_fallo_de_red_lanza_error_api(excepcion):
    """Nunca None: quien llama tiene que poder distinguir un fallo de la API de
    una respuesta legítimamente vacía. Devolver None en ambos casos es lo que
    hacía que un 429 desapareciera sin dejar rastro."""
    sesion = SesionFalsa(excepcion=excepcion)
    with pytest.raises(ErrorAPI):
        get_json(sesion, "https://ejemplo.cl/api")


def test_un_500_lanza_error_api():
    error = requests.HTTPError("500 Server Error: Internal Server Error")
    sesion = SesionFalsa(RespuestaFalsa(error=error))
    with pytest.raises(ErrorAPI) as exc:
        get_json(sesion, "https://ejemplo.cl/api/series/total_precipitation")
    # El mensaje lleva la URL: sin ella, 52 fallos en un log son indistinguibles.
    assert "total_precipitation" in str(exc.value)


def test_una_respuesta_que_no_es_json_lanza_error_api():
    sesion = SesionFalsa(RespuestaFalsa(json_invalido=True))
    with pytest.raises(ErrorAPI):
        get_json(sesion, "https://ejemplo.cl/api")


def test_error_api_no_se_confunde_con_los_errores_de_requests():
    """Quien llama captura ErrorAPI a propósito. Si heredara de RequestException,
    un `except requests.RequestException` de otro sitio se lo tragaría."""
    assert issubclass(ErrorAPI, Exception)
    assert not issubclass(ErrorAPI, requests.RequestException)


# ── Parámetros y pausa ────────────────────────────────────────────────────────


def test_pasa_params_y_timeout():
    sesion = SesionFalsa(RespuestaFalsa(datos={}))
    get_json(sesion, "https://ejemplo.cl/api", params={"attributes": "a,b"}, timeout=17)
    assert sesion.llamadas[0]["params"] == {"attributes": "a,b"}
    assert sesion.llamadas[0]["timeout"] == 17


def test_la_pausa_solo_ocurre_si_se_pide(monkeypatch):
    import http_publico

    dormido = []
    monkeypatch.setattr(http_publico.time, "sleep", lambda s: dormido.append(s))

    get_json(SesionFalsa(RespuestaFalsa(datos={})), "https://ejemplo.cl/a")
    assert dormido == [], "sin pausa pedida no debe dormir"

    get_json(SesionFalsa(RespuestaFalsa(datos={})), "https://ejemplo.cl/b", pausa=0.5)
    assert dormido == [0.5]
