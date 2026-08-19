# Tests de jobs Spark

Vacío por ahora. Los jobs crean la SparkSession a nivel de módulo, así que
importarlos para probar sus funciones puras —`_valor_a_float`,
`_construir_filas`— intentaría levantar Spark.

Para hacerlos testeables hay que mover el código de ejecución dentro de
`if __name__ == "__main__":`. Es un refactor pequeño y esas funciones se
prueban sin Spark en absoluto.
