"""
setup_superset_dashboard.py
Configura completamente en Superset via API REST:
  - Conexión Trino
  - Datasets de indicadores
  - Charts individuales y comparativos
  - Dashboard Indicadores Financieros Chile

Ejecutar dentro del contenedor Superset:
  docker exec docker-compose-superset-1 bash -c "cd /app && python3 -c \"import sys; sys.path.insert(0, '/app'); from superset.app import create_app; app = create_app(); app.app_context().push(); exec(open('/tmp/setup_superset_dashboard.py').read())\"""
"""

import json

from superset import db
from superset.models.core import Database
from superset.connectors.sqla.models import SqlaTable
from superset.models.slice import Slice
from superset.models.dashboard import Dashboard

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

# ── 2. Datasets ───────────────────────────────────────────────────────────────
tablas_config = {
    "indicadores_uf": {"label": "UF", "unidad": "CLP"},
    "indicadores_dolar": {"label": "Dólar", "unidad": "CLP"},
    "indicadores_euro": {"label": "Euro", "unidad": "CLP"},
    "indicadores_utm": {"label": "UTM", "unidad": "CLP"},
    "indicadores_tpm": {"label": "TPM", "unidad": "%"},
    "indicadores_todos": {"label": "Todos", "unidad": "varios"},
}

datasets = {}
for nombre, meta in tablas_config.items():
    tbl = (
        db.session.query(SqlaTable)
        .filter_by(
            table_name=nombre,
            database_id=trino_db.id,
        )
        .first()
    )
    if not tbl:
        tbl = SqlaTable(
            table_name=nombre,
            schema="bronze",
            database_id=trino_db.id,
        )
        db.session.add(tbl)
        db.session.flush()
        print(f"  ✓ Dataset creado: {nombre}")
    else:
        print(f"  (ya existe) {nombre}")
    datasets[nombre] = tbl

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


# ── 4. Charts individuales por indicador ──────────────────────────────────────
charts_individuales = []

for nombre_tabla, meta in tablas_config.items():
    if nombre_tabla == "indicadores_todos":
        continue

    label = meta["label"]
    unidad = meta["unidad"]

    params = {
        "viz_type": "echarts_timeseries_line",
        "x_axis": "fecha",
        "metrics": [
            {
                "expressionType": "SIMPLE",
                "column": {"column_name": "valor", "type": "DOUBLE"},
                "aggregate": "MAX",
                "label": f"Valor {label}",
                "optionName": f"metric_{label}",
            }
        ],
        "groupby": [],
        "time_grain_sqla": "P1D",
        "row_limit": 10000,
        "x_axis_title": "Fecha",
        "y_axis_title": f"Valor ({unidad})",
        "rich_tooltip": True,
        "show_legend": True,
        "zoomable": True,
        "seriesType": "line",
        "color_scheme": "supersetColors",
    }

    chart = upsert_chart(
        name=f"{label} — Serie Histórica 2026",
        viz_type="echarts_timeseries_line",
        dataset_id=datasets[nombre_tabla].id,
        params=params,
    )
    charts_individuales.append(chart)

db.session.commit()

# ── 5. Chart comparativo ──────────────────────────────────────────────────────
params_comp = {
    "viz_type": "echarts_timeseries_line",
    "x_axis": "fecha",
    "metrics": [
        {
            "expressionType": "SIMPLE",
            "column": {"column_name": "valor", "type": "DOUBLE"},
            "aggregate": "MAX",
            "label": "Valor",
            "optionName": "metric_valor",
        }
    ],
    "groupby": ["indicador"],
    "adhoc_filters": [
        {
            "clause": "WHERE",
            "comparator": ["UF", "DOLAR", "EURO"],
            "expressionType": "SIMPLE",
            "filterOptionName": "filter_indicador",
            "operator": "IN",
            "subject": "indicador",
        }
    ],
    "time_grain_sqla": "P1D",
    "row_limit": 50000,
    "x_axis_title": "Fecha",
    "y_axis_title": "Valor (CLP)",
    "rich_tooltip": True,
    "show_legend": True,
    "zoomable": True,
    "seriesType": "line",
    "color_scheme": "supersetColors",
}

chart_comp = upsert_chart(
    name="UF vs Dólar vs Euro — Comparativo 2026",
    viz_type="echarts_timeseries_line",
    dataset_id=datasets["indicadores_todos"].id,
    params=params_comp,
)

# ── 6. Chart tabla último valor ───────────────────────────────────────────────
params_tabla = {
    "viz_type": "table",
    "metrics": [
        {
            "expressionType": "SIMPLE",
            "column": {"column_name": "valor", "type": "DOUBLE"},
            "aggregate": "MAX",
            "label": "Último valor",
            "optionName": "metric_ultimo",
        }
    ],
    "groupby": ["indicador", "nombre"],
    "order_desc": True,
    "row_limit": 10,
    "page_length": 10,
    "color_pn": True,
}

chart_tabla = upsert_chart(
    name="Último Valor por Indicador",
    viz_type="table",
    dataset_id=datasets["indicadores_todos"].id,
    params=params_tabla,
)


# ── 7. Big numbers ────────────────────────────────────────────────────────────
def big_number(label, indicador_val):
    return upsert_chart(
        name=f"{label} — Valor Actual",
        viz_type="big_number_total",
        dataset_id=datasets["indicadores_todos"].id,
        params={
            "viz_type": "big_number_total",
            "metric": {
                "expressionType": "SIMPLE",
                "column": {"column_name": "valor", "type": "DOUBLE"},
                "aggregate": "MAX",
                "label": f"{label} hoy",
                "optionName": f"metric_{label}",
            },
            "subheader": f"Valor {label} más reciente",
            "y_axis_format": ",.2f",
            "adhoc_filters": [
                {
                    "clause": "WHERE",
                    "comparator": indicador_val,
                    "expressionType": "SIMPLE",
                    "filterOptionName": f"filter_{label}",
                    "operator": "==",
                    "subject": "indicador",
                }
            ],
        },
    )


chart_uf_num = big_number("UF", "UF")
chart_dolar_num = big_number("Dólar", "DOLAR")
chart_euro_num = big_number("Euro", "EURO")
db.session.commit()

# ── 8. Dashboard ──────────────────────────────────────────────────────────────
todos_charts = [
    chart_uf_num,
    chart_dolar_num,
    chart_euro_num,
    chart_comp,
    chart_tabla,
] + charts_individuales


def cid(c):
    return c.id or 0


position_json = {
    "DASHBOARD_VERSION_KEY": "v2",
    "ROOT_ID": {"children": ["GRID_ID"], "id": "ROOT_ID", "type": "ROOT"},
    "GRID_ID": {
        "children": ["ROW_KPI", "ROW_COMP", "ROW_SERIES1", "ROW_SERIES2"],
        "id": "GRID_ID",
        "type": "GRID",
    },
    "ROW_KPI": {
        "children": ["C_UF_NUM", "C_DOLAR_NUM", "C_EURO_NUM", "C_TABLA"],
        "id": "ROW_KPI",
        "meta": {"background": "BACKGROUND_TRANSPARENT"},
        "type": "ROW",
    },
    "C_UF_NUM": {
        "children": [],
        "id": "C_UF_NUM",
        "type": "CHART",
        "meta": {
            "chartId": cid(chart_uf_num),
            "height": 20,
            "sliceName": chart_uf_num.slice_name,
            "width": 3,
        },
    },
    "C_DOLAR_NUM": {
        "children": [],
        "id": "C_DOLAR_NUM",
        "type": "CHART",
        "meta": {
            "chartId": cid(chart_dolar_num),
            "height": 20,
            "sliceName": chart_dolar_num.slice_name,
            "width": 3,
        },
    },
    "C_EURO_NUM": {
        "children": [],
        "id": "C_EURO_NUM",
        "type": "CHART",
        "meta": {
            "chartId": cid(chart_euro_num),
            "height": 20,
            "sliceName": chart_euro_num.slice_name,
            "width": 3,
        },
    },
    "C_TABLA": {
        "children": [],
        "id": "C_TABLA",
        "type": "CHART",
        "meta": {
            "chartId": cid(chart_tabla),
            "height": 20,
            "sliceName": chart_tabla.slice_name,
            "width": 3,
        },
    },
    "ROW_COMP": {
        "children": ["C_COMP"],
        "id": "ROW_COMP",
        "meta": {"background": "BACKGROUND_TRANSPARENT"},
        "type": "ROW",
    },
    "C_COMP": {
        "children": [],
        "id": "C_COMP",
        "type": "CHART",
        "meta": {
            "chartId": cid(chart_comp),
            "height": 40,
            "sliceName": chart_comp.slice_name,
            "width": 12,
        },
    },
    "ROW_SERIES1": {
        "children": ["C_UF", "C_DOLAR", "C_EURO"],
        "id": "ROW_SERIES1",
        "meta": {"background": "BACKGROUND_TRANSPARENT"},
        "type": "ROW",
    },
    "C_UF": {
        "children": [],
        "id": "C_UF",
        "type": "CHART",
        "meta": {
            "chartId": cid(charts_individuales[0]),
            "height": 36,
            "sliceName": charts_individuales[0].slice_name,
            "width": 4,
        },
    },
    "C_DOLAR": {
        "children": [],
        "id": "C_DOLAR",
        "type": "CHART",
        "meta": {
            "chartId": cid(charts_individuales[1]),
            "height": 36,
            "sliceName": charts_individuales[1].slice_name,
            "width": 4,
        },
    },
    "C_EURO": {
        "children": [],
        "id": "C_EURO",
        "type": "CHART",
        "meta": {
            "chartId": cid(charts_individuales[2]),
            "height": 36,
            "sliceName": charts_individuales[2].slice_name,
            "width": 4,
        },
    },
    "ROW_SERIES2": {
        "children": ["C_UTM", "C_TPM"],
        "id": "ROW_SERIES2",
        "meta": {"background": "BACKGROUND_TRANSPARENT"},
        "type": "ROW",
    },
    "C_UTM": {
        "children": [],
        "id": "C_UTM",
        "type": "CHART",
        "meta": {
            "chartId": cid(charts_individuales[3]),
            "height": 36,
            "sliceName": charts_individuales[3].slice_name,
            "width": 6,
        },
    },
    "C_TPM": {
        "children": [],
        "id": "C_TPM",
        "type": "CHART",
        "meta": {
            "chartId": cid(charts_individuales[4]),
            "height": 36,
            "sliceName": charts_individuales[4].slice_name,
            "width": 6,
        },
    },
}

dashboard_title = "Indicadores Financieros Chile 2026"
dashboard = (
    db.session.query(Dashboard).filter_by(dashboard_title=dashboard_title).first()
)

if not dashboard:
    dashboard = Dashboard(
        dashboard_title=dashboard_title,
        slug="indicadores-financieros-chile",
        position_json=json.dumps(position_json),
        published=True,
    )
    dashboard.slices = todos_charts
    db.session.add(dashboard)
    print(f"\n✓ Dashboard creado: {dashboard_title}")
else:
    dashboard.position_json = json.dumps(position_json)
    dashboard.slices = todos_charts
    dashboard.published = True
    print(f"\n(actualizado) Dashboard: {dashboard_title}")

db.session.commit()

print("\n" + "=" * 60)
print("✓ Dashboard configurado exitosamente")
print(f"  Charts: {len(todos_charts)}")
print("  URL: http://localhost:8088/superset/dashboard/indicadores-financieros-chile/")
print("=" * 60)
