"""Tests de las transformaciones de los jobs bronze.

Sin Spark y sin red: son las funciones que convierten una respuesta de API en
filas, y toda la aritmética que puede estar mal sin que nada se caiga. Los
errores que cubren no son hipotéticos —la banda de incertidumbre estuvo un año
llena de nulos y de valores que no significaban nada—.
"""

import pytest

from transformaciones import (
    filas_indicadores,
    filas_series,
    limpiar_columna,
    percentil,
    valor_a_float,
)

# ── valor_a_float ─────────────────────────────────────────────────────────────


@pytest.mark.parametrize(
    ("entrada", "esperado"),
    [
        (None, None),
        (5, 5.0),
        (5.5, 5.5),
        (0, 0.0),
        ("36.345,67", 36345.67),  # formato chileno: punto de miles, coma decimal
        ("1.234", 1234.0),
        ("980,5", 980.5),
        ("", None),
        ("no es un número", None),
        ([], None),
    ],
)
def test_valor_a_float(entrada, esperado):
    assert valor_a_float(entrada) == esperado


def test_un_cero_no_se_confunde_con_ausencia():
    """0.0 es falsy: si en algún sitio se comprueba con `if valor:` en vez de
    `is not None`, una TPM de 0 desaparece."""
    assert valor_a_float(0) is not None
    assert valor_a_float("0,0") == 0.0


# ── filas_indicadores ─────────────────────────────────────────────────────────

RESPUESTA = {
    "nombre": "Dólar observado",
    "unidad_medida": "Pesos",
    "serie": [
        {"fecha": "2026-05-01T00:00:00.000Z", "valor": 950.5},
        {"fecha": "2026-04-30T00:00:00.000Z", "valor": "948,2"},
    ],
}


def test_filas_indicadores_aplana_la_serie():
    filas = filas_indicadores(RESPUESTA, "dolar", "2026-05-01", "2026", "05")
    assert len(filas) == 2
    assert filas[0]["fecha"] == "2026-05-01", "la hora ISO debe recortarse"
    assert filas[0]["valor"] == 950.5
    assert filas[1]["valor"] == 948.2, "el formato chileno se convierte"
    assert filas[0]["indicador"] == "DOLAR"
    assert filas[0]["nombre"] == "Dólar observado"
    assert filas[0]["fecha_proceso"] == "2026-05-01"
    assert filas[0]["anio"] == 2026
    assert filas[0]["mes"] == 5


def test_una_serie_vacia_no_es_un_error():
    """El IPC se publica una vez al mes: una serie vacía es un hecho del mundo,
    no un fallo."""
    assert filas_indicadores({"serie": []}, "ipc", "2026-05-01", "2026", "05") == []
    assert filas_indicadores({}, "ipc", "2026-05-01", "2026", "05") == []


# ── limpiar_columna ───────────────────────────────────────────────────────────


@pytest.mark.parametrize(
    ("atributo", "columna"),
    [
        ("$CLIMA$hot_days$annual$delta", "clima_hot_days_anual_delta"),
        ("$CLIMA$mean_temperature$annual$present", "clima_mean_temperature_anual_present"),
        (
            "$CLIMA$consecutive_days_over_25C$annual$future",
            "clima_consecutive_days_over_25c_anual_future",
        ),
        ("NOM_COMUNA", "nom_comuna"),
        ("REGION", "region"),
    ],
)
def test_limpiar_columna(atributo, columna):
    assert limpiar_columna(atributo) == columna


def test_no_queda_ningun_caracter_que_delta_rechace():
    for attr in ("$CLIMA$x$annual$delta", "$raro$", "A$B"):
        assert "$" not in limpiar_columna(attr)


# ── percentil ─────────────────────────────────────────────────────────────────


def test_percentil_sin_datos_o_con_uno():
    assert percentil([], 10) is None
    assert percentil([None, None], 90) is None
    assert percentil([7.5], 10) == 7.5


def test_percentil_interpola_como_numpy():
    # numpy.percentile(range(1, 21), 10) == 2.9 ; (…, 90) == 18.1
    valores = list(range(1, 21))
    assert percentil(valores, 10) == pytest.approx(2.9)
    assert percentil(valores, 50) == pytest.approx(10.5)
    assert percentil(valores, 90) == pytest.approx(18.1)


def test_percentil_ignora_nulos_y_no_depende_del_orden():
    assert percentil([3, None, 1, 2], 50) == pytest.approx(2.0)
    assert percentil([2, 1, 3], 50) == percentil([3, 2, 1], 50)


# ── filas_series ──────────────────────────────────────────────────────────────


def serie(años, medias, modelos):
    return {
        "13101": {
            "nombre": "Santiago",
            "indicadores": {"hot_days": {"years": años, "mean": medias, "series": modelos}},
        }
    }


def test_una_fila_por_anio_con_banda_sobre_los_modelos():
    filas = filas_series(
        serie([1970, 1971], [10.0, 20.0], [[1, 11], [10, 20], [19, 29]]),
        "2026-08-31",
        "2026",
        "08",
    )
    assert len(filas) == 2
    assert [f["anio_serie"] for f in filas] == [1970, 1971]
    assert filas[0]["valor_medio"] == 10.0
    assert filas[0]["modelos"] == 3
    assert filas[0]["valor_p10"] == pytest.approx(2.8)
    assert filas[0]["valor_p90"] == pytest.approx(17.2)
    assert filas[0]["cod_comuna"] == "13101"
    assert filas[0]["escenario"] == "ssp585"


def test_la_banda_encierra_la_media_en_todos_los_anios():
    """La regresión que motivó esto: p10 y p90 no seguían la serie, eran once
    percentiles de un solo modelo metidos en los once primeros años."""
    años = list(range(1970, 2070))
    medias = [float(a - 1900) for a in años]
    modelos = [[m + (a - 1900) for a in años] for m in (-5, 0, 5)]
    filas = filas_series(serie(años, medias, modelos), "2026-08-31", "2026", "08")

    assert len(filas) == 100
    assert all(f["valor_p10"] is not None for f in filas), "ningún año sin banda"
    for f in filas:
        assert f["valor_p10"] <= f["valor_medio"] <= f["valor_p90"]


def test_un_modelo_mas_corto_no_rompe_ni_cuenta_de_mas():
    filas = filas_series(
        serie([1970, 1971, 1972], [1.0, 2.0, 3.0], [[1, 2, 3], [5, 6]]),
        "2026-08-31",
        "2026",
        "08",
    )
    assert [f["modelos"] for f in filas] == [2, 2, 1]
    assert filas[2]["valor_p10"] == 3.0


def test_sin_modelos_la_banda_es_nula_pero_la_media_sobrevive():
    filas = filas_series(serie([1970], [42.0], []), "2026-08-31", "2026", "08")
    assert filas[0]["valor_medio"] == 42.0
    assert filas[0]["valor_p10"] is None
    assert filas[0]["modelos"] == 0


def test_sin_series_no_hay_filas():
    assert filas_series({}, "2026-08-31", "2026", "08") == []
