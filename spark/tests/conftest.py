"""Pone spark/jobs en el sys.path.

Es lo que hace Python al ejecutar un script: su directorio entra como sys.path[0].
Dentro del contenedor, `spark-submit /opt/spark/jobs/bronze_arclim.py` resuelve
así el `import transformaciones`, y los tests replican esa misma resolución.
"""

import sys
from pathlib import Path

JOBS_DIR = Path(__file__).parent.parent / "jobs"
if str(JOBS_DIR) not in sys.path:
    sys.path.insert(0, str(JOBS_DIR))
