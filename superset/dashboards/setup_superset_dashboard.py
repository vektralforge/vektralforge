"""
setup_superset_dashboard.py
Crea automáticamente en Superset:
  - 6 charts de línea (uno por indicador)
  - 1 chart comparativo UF vs Dólar vs Euro
  - 1 dashboard "Indicadores Financieros Chile"

Ejecutar dentro del contenedor Superset:
  docker exec docker-compose-superset-1 python3 /tmp/setup_superset_dashboard.py
"""

from superset import create_app
from superset.extensions import db
from superset.models.core import Database
from superset.connectors.sqla.models import SqlaTable
from superset.models.slice import Slice
from superset.models.dashboard import Dashboard
import json

app = create_app()

with app.app_context():
    # ── 1. Obtener conexión Trino ─────────────────────────────────────────────
    trino_db = db.session.query(Database).filter_by(database_name="Trino").first()
    if not trino_db:
        print("✗ No se encontró la conexión Trino. Créala primero desde la UI.")
        exit(1)
    print(f"✓ Conexión Trino encontrada (id={trino_db.id})")

    # ── 2. Registrar datasets ─────────────────────────────────────────────────
    indicadores = {
        "indicadores_uf": {"nombre": "UF", "color": "#1f77b4", "unidad": "CLP"},
        "indicadores_dolar": {"nombre": "Dólar", "color": "#ff7f0e", "unidad": "CLP"},
        "indicadores_euro": {"nombre": "Euro", "color": "#2ca02c", "unidad": "CLP"},
        "indicadores_utm": {"nombre": "UTM", "color": "#d62728", "unidad": "CLP"},
        "indicadores_tpm": {"nombre": "TPM", "color": "#9467bd", "unidad": "%"},
    }

    datasets = {}
    for tabla_nombre, meta in indicadores.items():
        tbl = (
            db.session.query(SqlaTable)
            .filter_by(table_name=tabla_nombre, database_id=trino_db.id)
            .first()
        )

        if not tbl:
            tbl = SqlaTable(
                table_name=tabla_nombre,
                schema="bronze",
                database_id=trino_db.id,
            )
            db.session.add(tbl)
            db.session.flush()
            print(f"  ✓ Dataset creado: {tabla_nombre}")
        else:
            print(f"  (ya existe) {tabla_nombre}")

        datasets[tabla_nombre] = tbl

    db.session.commit()

    # ── 3. Crear charts individuales por indicador ────────────────────────────
    charts = []

    for tabla_nombre, meta in indicadores.items():
        tbl = datasets[tabla_nombre]

        # Configuración del chart Line Chart
        params = {
            "viz_type": "echarts_timeseries_line",
            "x_axis": "fecha",
            "metrics": [
                {
                    "expressionType": "SIMPLE",
                    "column": {"column_name": "valor"},
                    "aggregate": "MAX",
                    "label": f"Valor {meta['nombre']}",
                }
            ],
            "groupby": [],
            "time_grain_sqla": "P1D",
            "row_limit": 10000,
            "x_axis_title": "Fecha",
            "y_axis_title": f"Valor ({meta['unidad']})",
            "rich_tooltip": True,
            "show_legend": True,
            "zoomable": True,
            "color_scheme": "supersetColors",
        }

        chart_name = f"Indicador {meta['nombre']} — Serie Histórica"
        chart = db.session.query(Slice).filter_by(slice_name=chart_name).first()

        if not chart:
            chart = Slice(
                slice_name=chart_name,
                viz_type="echarts_timeseries_line",
                datasource_type="table",
                datasource_id=tbl.id,
                params=json.dumps(params),
                description=f"Evolución histórica del {meta['nombre']} en Chile. Fuente: mindicador.cl",
            )
            db.session.add(chart)
            print(f"  ✓ Chart creado: {chart_name}")
        else:
            chart.params = json.dumps(params)
            print(f"  (actualizado) {chart_name}")

        charts.append(chart)

    db.session.commit()

    # ── 4. Chart comparativo UF vs Dólar vs Euro ──────────────────────────────
    # Usar la vista indicadores_todos si existe, sino usar indicadores_uf
    vista_nombre = "indicadores_todos"
    vista = (
        db.session.query(SqlaTable)
        .filter_by(table_name=vista_nombre, database_id=trino_db.id)
        .first()
    )

    if not vista:
        vista = SqlaTable(
            table_name=vista_nombre,
            schema="bronze",
            database_id=trino_db.id,
        )
        db.session.add(vista)
        db.session.flush()
        print(f"  ✓ Vista comparativa creada: {vista_nombre}")

    params_comparativo = {
        "viz_type": "echarts_timeseries_line",
        "x_axis": "fecha",
        "metrics": [
            {
                "expressionType": "SIMPLE",
                "column": {"column_name": "valor"},
                "aggregate": "MAX",
                "label": "Valor",
            }
        ],
        "groupby": ["indicador"],
        "time_grain_sqla": "P1D",
        "row_limit": 50000,
        "x_axis_title": "Fecha",
        "y_axis_title": "Valor (CLP)",
        "rich_tooltip": True,
        "show_legend": True,
        "zoomable": True,
        "filters": [
            {
                "col": "indicador",
                "op": "IN",
                "val": ["UF", "DOLAR", "EURO"],
            }
        ],
    }

    chart_comp_name = "UF vs Dólar vs Euro — Comparativo"
    chart_comp = db.session.query(Slice).filter_by(slice_name=chart_comp_name).first()
    if not chart_comp:
        chart_comp = Slice(
            slice_name=chart_comp_name,
            viz_type="echarts_timeseries_line",
            datasource_type="table",
            datasource_id=vista.id,
            params=json.dumps(params_comparativo),
            description="Comparación UF, Dólar y Euro en el tiempo. Fuente: mindicador.cl",
        )
        db.session.add(chart_comp)
        print("  ✓ Chart comparativo creado")
    else:
        chart_comp.params = json.dumps(params_comparativo)
        print("  (actualizado) Chart comparativo")

    charts.append(chart_comp)
    db.session.commit()

    # ── 5. Crear dashboard ────────────────────────────────────────────────────
    dashboard_title = "Indicadores Financieros Chile"
    dashboard = (
        db.session.query(Dashboard).filter_by(dashboard_title=dashboard_title).first()
    )

    # Layout del dashboard — 2 columnas
    position_data = {
        "DASHBOARD_VERSION_KEY": "v2",
        "ROOT_ID": {"children": ["GRID_ID"], "id": "ROOT_ID", "type": "ROOT"},
        "GRID_ID": {
            "children": ["ROW_1", "ROW_2", "ROW_3"],
            "id": "GRID_ID",
            "type": "GRID",
        },
        "ROW_1": {
            "children": ["CHART_COMP"],
            "id": "ROW_1",
            "meta": {"background": "BACKGROUND_TRANSPARENT"},
            "type": "ROW",
        },
        "CHART_COMP": {
            "children": [],
            "id": "CHART_COMP",
            "meta": {
                "chartId": chart_comp.id if chart_comp.id else 0,
                "height": 50,
                "sliceName": chart_comp_name,
                "width": 12,
            },
            "type": "CHART",
        },
        "ROW_2": {
            "children": ["CHART_UF", "CHART_DOLAR", "CHART_EURO"],
            "id": "ROW_2",
            "meta": {"background": "BACKGROUND_TRANSPARENT"},
            "type": "ROW",
        },
        "CHART_UF": {
            "children": [],
            "id": "CHART_UF",
            "meta": {
                "chartId": charts[0].id if charts[0].id else 0,
                "height": 40,
                "sliceName": charts[0].slice_name,
                "width": 4,
            },
            "type": "CHART",
        },
        "CHART_DOLAR": {
            "children": [],
            "id": "CHART_DOLAR",
            "meta": {
                "chartId": charts[1].id if charts[1].id else 0,
                "height": 40,
                "sliceName": charts[1].slice_name,
                "width": 4,
            },
            "type": "CHART",
        },
        "CHART_EURO": {
            "children": [],
            "id": "CHART_EURO",
            "meta": {
                "chartId": charts[2].id if charts[2].id else 0,
                "height": 40,
                "sliceName": charts[2].slice_name,
                "width": 4,
            },
            "type": "CHART",
        },
        "ROW_3": {
            "children": ["CHART_UTM", "CHART_TPM"],
            "id": "ROW_3",
            "meta": {"background": "BACKGROUND_TRANSPARENT"},
            "type": "ROW",
        },
        "CHART_UTM": {
            "children": [],
            "id": "CHART_UTM",
            "meta": {
                "chartId": charts[3].id if charts[3].id else 0,
                "height": 40,
                "sliceName": charts[3].slice_name,
                "width": 6,
            },
            "type": "CHART",
        },
        "CHART_TPM": {
            "children": [],
            "id": "CHART_TPM",
            "meta": {
                "chartId": charts[4].id if charts[4].id else 0,
                "height": 40,
                "sliceName": charts[4].slice_name,
                "width": 6,
            },
            "type": "CHART",
        },
    }

    if not dashboard:
        dashboard = Dashboard(
            dashboard_title=dashboard_title,
            slug="indicadores-financieros-chile",
            position_json=json.dumps(position_data),
            published=True,
        )
        dashboard.slices = charts
        db.session.add(dashboard)
        print(f"\n  ✓ Dashboard creado: {dashboard_title}")
    else:
        dashboard.position_json = json.dumps(position_data)
        dashboard.slices = charts
        print(f"\n  (actualizado) Dashboard: {dashboard_title}")

    db.session.commit()

    print("\n" + "=" * 60)
    print("✓ Dashboard configurado exitosamente")
    print(
        "  URL: http://localhost:8088/superset/dashboard/indicadores-financieros-chile/"
    )
    print("=" * 60)
