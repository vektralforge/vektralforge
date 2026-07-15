"""
setup_superset_arclim.py — Dashboard ARClim Riesgo Climático Chile
"""

import json

from superset import db
from superset.connectors.sqla.models import SqlaTable
from superset.models.core import Database
from superset.models.dashboard import Dashboard
from superset.models.slice import Slice

# ── 1. Conexión Trino ─────────────────────────────────────────────────────────
trino_db = db.session.query(Database).filter_by(database_name="Trino").first()
if not trino_db:
    trino_db = Database(
        database_name="Trino",
        sqlalchemy_uri="trino://trino@trino:8080/delta",
    )
    db.session.add(trino_db)
    db.session.flush()
    print("✓ Conexión Trino creada")
else:
    print(f"✓ Conexión Trino encontrada (id={trino_db.id})")

# ── 2. Datasets ARClim ────────────────────────────────────────────────────────
arclim_datasets = {}
for nombre in ["arclim_indicadores", "arclim_series"]:
    tbl = (
        db.session.query(SqlaTable)
        .filter_by(table_name=nombre, database_id=trino_db.id)
        .first()
    )
    if not tbl:
        tbl = SqlaTable(table_name=nombre, schema="bronze", database_id=trino_db.id)
        db.session.add(tbl)
        db.session.flush()
        print(f"  ✓ Dataset creado: {nombre}")
    else:
        print(f"  (ya existe) {nombre}")
    arclim_datasets[nombre] = tbl

db.session.commit()

# Sincronizar columnas
print("→ Sincronizando columnas ARClim desde Trino...")
for nombre, tbl in arclim_datasets.items():
    try:
        tbl.fetch_metadata()
        db.session.merge(tbl)
        print(f"  ✓ {nombre}: columnas sincronizadas")
    except Exception as e:
        print(f"  ⚠ {nombre}: {e}")
db.session.commit()


# ── 3. Helper upsert chart ────────────────────────────────────────────────────
def upsert_chart(name, viz_type, dataset_id, params):
    chart = db.session.query(Slice).filter_by(slice_name=name).first()
    params_json = json.dumps(params)
    if not chart:
        chart = Slice(
            slice_name=name,
            viz_type=viz_type,
            datasource_type="table",
            datasource_id=dataset_id,
            params=params_json,
        )
        db.session.add(chart)
        print(f"  ✓ Chart creado: {name}")
    else:
        chart.params = params_json
        chart.datasource_id = dataset_id
        print(f"  (actualizado) {name}")
    db.session.flush()
    return chart


# ── 4. Catálogo indicadores ───────────────────────────────────────────────────
chart_catalogo = upsert_chart(
    name="ARClim — Catálogo de Indicadores",
    viz_type="table",
    dataset_id=arclim_datasets["arclim_indicadores"].id,
    params={
        "viz_type": "table",
        "groupby": ["code", "name", "units"],
        "metrics": [],
        "order_desc": False,
        "row_limit": 100,
        "page_length": 20,
        "include_search": True,
    },
)

# ── 5. Line charts por indicador ──────────────────────────────────────────────
INDICADORES = {
    "hot_days": "Días Calurosos (> 30°C)",
    "consecutive_days_over_25C": "Olas de Calor (> 25°C consecutivos)",
    "frost_days": "Días con Helada (< 0°C)",
}

COMUNAS_FILTRO = ["Santiago", "Valparaíso", "Concepción", "Temuco", "Punta Arenas"]
charts_arclim = [chart_catalogo]

for ind_code, ind_nombre in INDICADORES.items():
    chart = upsert_chart(
        name=f"ARClim — {ind_nombre} por Capital Regional",
        viz_type="echarts_timeseries_line",
        dataset_id=arclim_datasets["arclim_series"].id,
        params={
            "viz_type": "echarts_timeseries_line",
            "x_axis": "anio_serie",
            "metrics": [
                {
                    "expressionType": "SIMPLE",
                    "column": {"column_name": "valor_medio", "type": "DOUBLE"},
                    "aggregate": "AVG",
                    "label": f"Promedio {ind_nombre}",
                    "optionName": f"metric_{ind_code}",
                }
            ],
            "groupby": ["nombre"],
            "adhoc_filters": [
                {
                    "clause": "WHERE",
                    "comparator": ind_code,
                    "expressionType": "SIMPLE",
                    "filterOptionName": f"filter_{ind_code}",
                    "operator": "==",
                    "subject": "indicador",
                },
                {
                    "clause": "WHERE",
                    "comparator": COMUNAS_FILTRO,
                    "expressionType": "SIMPLE",
                    "filterOptionName": "filter_comunas",
                    "operator": "IN",
                    "subject": "nombre",
                },
            ],
            "time_grain_sqla": "P1Y",
            "row_limit": 10000,
            "x_axis_title": "Año",
            "y_axis_title": "Días/año",
            "rich_tooltip": True,
            "show_legend": True,
            "zoomable": True,
            "seriesType": "line",
            "color_scheme": "supersetColors",
        },
    )
    charts_arclim.append(chart)

# ── 6. Big number futuro Santiago ─────────────────────────────────────────────
chart_stgo_future = upsert_chart(
    name="ARClim — Días Calurosos Santiago Futuro",
    viz_type="big_number_total",
    dataset_id=arclim_datasets["arclim_series"].id,
    params={
        "viz_type": "big_number_total",
        "metric": {
            "expressionType": "SIMPLE",
            "column": {"column_name": "valor_medio", "type": "DOUBLE"},
            "aggregate": "AVG",
            "label": "Días calurosos/año",
            "optionName": "metric_stgo_future",
        },
        "subheader": "Promedio días calurosos Santiago 2035-2065 (SSP5-8.5)",
        "y_axis_format": ".1f",
        "adhoc_filters": [
            {
                "clause": "WHERE",
                "comparator": "hot_days",
                "expressionType": "SIMPLE",
                "filterOptionName": "f1",
                "operator": "==",
                "subject": "indicador",
            },
            {
                "clause": "WHERE",
                "comparator": "Santiago",
                "expressionType": "SIMPLE",
                "filterOptionName": "f2",
                "operator": "==",
                "subject": "nombre",
            },
            {
                "clause": "WHERE",
                "comparator": 2035,
                "expressionType": "SIMPLE",
                "filterOptionName": "f3",
                "operator": ">=",
                "subject": "anio_serie",
            },
        ],
    },
)
charts_arclim.append(chart_stgo_future)
db.session.commit()


# ── 7. Dashboard ──────────────────────────────────────────────────────────────
def cid(c):
    return c.id or 0


position_json = {
    "DASHBOARD_VERSION_KEY": "v2",
    "ROOT_ID": {"children": ["GRID_ID"], "id": "ROOT_ID", "type": "ROOT"},
    "GRID_ID": {
        "children": ["ROW_TOP", "ROW_HOT", "ROW_OLAS", "ROW_HELADAS"],
        "id": "GRID_ID",
        "type": "GRID",
    },
    "ROW_TOP": {
        "children": ["C_STGO", "C_CAT"],
        "id": "ROW_TOP",
        "meta": {"background": "BACKGROUND_TRANSPARENT"},
        "type": "ROW",
    },
    "C_STGO": {
        "children": [],
        "id": "C_STGO",
        "type": "CHART",
        "meta": {
            "chartId": cid(chart_stgo_future),
            "height": 20,
            "sliceName": chart_stgo_future.slice_name,
            "width": 4,
        },
    },
    "C_CAT": {
        "children": [],
        "id": "C_CAT",
        "type": "CHART",
        "meta": {
            "chartId": cid(chart_catalogo),
            "height": 20,
            "sliceName": chart_catalogo.slice_name,
            "width": 8,
        },
    },
    "ROW_HOT": {
        "children": ["C_HOT"],
        "id": "ROW_HOT",
        "meta": {"background": "BACKGROUND_TRANSPARENT"},
        "type": "ROW",
    },
    "C_HOT": {
        "children": [],
        "id": "C_HOT",
        "type": "CHART",
        "meta": {
            "chartId": cid(charts_arclim[1]),
            "height": 40,
            "sliceName": charts_arclim[1].slice_name,
            "width": 12,
        },
    },
    "ROW_OLAS": {
        "children": ["C_OLAS"],
        "id": "ROW_OLAS",
        "meta": {"background": "BACKGROUND_TRANSPARENT"},
        "type": "ROW",
    },
    "C_OLAS": {
        "children": [],
        "id": "C_OLAS",
        "type": "CHART",
        "meta": {
            "chartId": cid(charts_arclim[2]),
            "height": 40,
            "sliceName": charts_arclim[2].slice_name,
            "width": 12,
        },
    },
    "ROW_HELADAS": {
        "children": ["C_HELADAS"],
        "id": "ROW_HELADAS",
        "meta": {"background": "BACKGROUND_TRANSPARENT"},
        "type": "ROW",
    },
    "C_HELADAS": {
        "children": [],
        "id": "C_HELADAS",
        "type": "CHART",
        "meta": {
            "chartId": cid(charts_arclim[3]),
            "height": 40,
            "sliceName": charts_arclim[3].slice_name,
            "width": 12,
        },
    },
}

dashboard_title = "ARClim — Riesgo Climático Chile 2026"
dashboard = (
    db.session.query(Dashboard).filter_by(dashboard_title=dashboard_title).first()
)

if not dashboard:
    dashboard = Dashboard(
        dashboard_title=dashboard_title,
        slug="arclim-riesgo-climatico-chile",
        position_json=json.dumps(position_json),
        published=True,
    )
    dashboard.slices = charts_arclim
    db.session.add(dashboard)
    print(f"\n✓ Dashboard creado: {dashboard_title}")
else:
    dashboard.position_json = json.dumps(position_json)
    dashboard.slices = charts_arclim
    dashboard.published = True
    print(f"\n(actualizado) Dashboard: {dashboard_title}")

db.session.commit()

print("\n" + "=" * 60)
print("✓ Dashboard ARClim configurado exitosamente")
print(f"  Charts: {len(charts_arclim)}")
print("  URL: http://localhost:8088/superset/dashboard/arclim-riesgo-climatico-chile/")
print("=" * 60)
