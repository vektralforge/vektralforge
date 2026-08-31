"""Transformaciones puras de los jobs bronze.

Todo lo que convierte una respuesta de API en filas vive aquí, y aquí no se
importa ni pyspark ni boto3: solo `math`. Esa es la razón de que exista el
módulo. Si los tests tuvieran que importar los jobs para probar estas funciones,
el CI necesitaría instalar pyspark —400 MB— para ejercitar aritmética.

Los jobs se quedan con lo que sí necesita Spark: la sesión, la lectura desde
MinIO y la escritura en Delta.
"""

from __future__ import annotations

import math


def valor_a_float(valor):
    """Convierte un valor string o numérico a float.

    mindicador.cl entrega los números en formato chileno: '36.345,67'.
    """
    if valor is None:
        return None
    if isinstance(valor, int | float):
        return float(valor)
    try:
        return float(str(valor).replace(".", "").replace(",", "."))
    except (ValueError, AttributeError):
        return None


def filas_indicadores(data, nombre, fecha, anio, mes):
    """Transforma la serie de mindicador.cl en filas planas."""
    filas = []
    for item in data.get("serie", []):
        fecha_item = item.get("fecha", "")
        # mindicador entrega ISO con hora: '2026-05-01T00:00:00.000Z'
        if "T" in fecha_item:
            fecha_item = fecha_item[:10]

        filas.append(
            {
                "fecha": fecha_item,
                "valor": valor_a_float(item.get("valor")),
                "indicador": nombre.upper(),
                "nombre": data.get("nombre", nombre),
                "unidad_medida": data.get("unidad_medida", ""),
                "fuente": "mindicador.cl",
                "fecha_proceso": fecha,
                "anio": int(anio),
                "mes": int(mes),
            }
        )
    return filas


def limpiar_columna(col: str) -> str:
    """Nombre de columna admisible en Delta a partir de un atributo de ARClim.

    Delta no admite `$` ni otros caracteres especiales en los nombres de columna,
    y ARClim los usa en todos sus atributos climáticos:
    `$CLIMA$hot_days$annual$delta` → `clima_hot_days_anual_delta`.
    """
    return col.replace("$CLIMA$", "clima_").replace("$annual$", "_anual_").replace("$", "_").lower()


def percentil(valores, p):
    """Percentil por interpolación lineal, igual que numpy.percentile.

    Se calcula a mano para no meter numpy en el job: son 20 valores por año.
    """
    limpios = [float(v) for v in valores if v is not None]
    if not limpios:
        return None
    limpios.sort()
    if len(limpios) == 1:
        return limpios[0]
    pos = (len(limpios) - 1) * (p / 100.0)
    bajo, alto = math.floor(pos), math.ceil(pos)
    if bajo == alto:
        return limpios[int(pos)]
    return limpios[bajo] + (limpios[alto] - limpios[bajo]) * (pos - bajo)


def filas_series(data, fecha, anio, mes):
    """Aplana las series de ARClim a filas, una por comuna/indicador/año.

    La banda de incertidumbre se calcula sobre los 20 modelos climáticos que
    devuelve la API, que es la presentación estándar de una proyección: para
    cada año, el p10 y el p90 del conjunto de modelos.

    NO se usa el campo `pseries` de la API. Tiene forma 20×11 —un modelo por
    fila, once percentiles por columna—, no once series anuales, y leerlo por
    posición metía los once percentiles del primer modelo en los primeros once
    años y dejaba los otros 89 en nulo.
    """
    filas = []
    for cod_comuna, info in data.items():
        nombre = info.get("nombre", "")
        for indicador, serie in info.get("indicadores", {}).items():
            years = serie.get("years", [])
            means = serie.get("mean", [])
            modelos = serie.get("series", [])

            for idx_y, year in enumerate(years):
                del_anio = [m[idx_y] for m in modelos if idx_y < len(m)]
                filas.append(
                    {
                        "cod_comuna": str(cod_comuna),
                        "nombre": nombre,
                        "indicador": indicador,
                        "anio_serie": int(year),
                        "valor_medio": float(means[idx_y]) if idx_y < len(means) else None,
                        "valor_p10": percentil(del_anio, 10),
                        "valor_p90": percentil(del_anio, 90),
                        "modelos": len([v for v in del_anio if v is not None]),
                        "escenario": "ssp585",
                        "fecha_carga": fecha,
                        "anio": int(anio),
                        "mes": int(mes),
                    }
                )
    return filas
