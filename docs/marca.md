# VektralForge — Marca e Imagotipo

**Versión 1.0 · Concepto elegido: "Vektor Slash"** (Concepto B: geometría y rampa terracota originales; sistema tipográfico y neutros del informe)
Proyecto: vektralforge.org · Lakehouse Open Source Stack (Airflow · Spark · Delta Lake · MinIO · Trino · OpenBao sobre K3s)

Este documento es la referencia canónica de la identidad visual del proyecto. Se publica junto a los archivos SVG en el repositorio para que la comunidad pueda usar la marca de forma consistente.

---

## 1. Concepto

El imagotipo de VektralForge se compone de un **isotipo** (el símbolo) y un **logotipo** (el wordmark "VektralForge"). Pueden usarse juntos (bloqueo horizontal o apilado) o el isotipo por separado.

**Isotipo "Vektor Slash":** tres paralelogramos inclinados 15° sobre un eje horizontal común, de altura ascendente y separados por rendijas iguales. La lectura es triple:

- **Vector**: la inclinación y el crecimiento de izquierda a derecha expresan dirección, flujo y progreso del dato.
- **Capas**: las tres barras son los tres estratos del lakehouse: almacenamiento (MinIO/Delta), cómputo (Spark/Trino) y servicio/orquestación (Airflow, con OpenBao como base transversal de secretos).
- **Forja**: el color, no la forma, aporta la fragua: la rampa terracota (óxido oscuro → cobre → arcilla incandescente) es metal templándose de la base a la punta.

El **eje base** en Slate Steel es la plataforma común (K3s) sobre la que se apoya todo el stack.

**Personalidad:** técnica, sobria, cálida. Rompe deliberadamente con el "mar de azul" del sector (Snowflake, Kubernetes, Dremio) y evita las metáforas gastadas de copo, cristal, hexágono y timón.

---

## 2. Construcción geométrica

El isotipo se define en un espacio de **200 × 200 unidades**. Todas las coordenadas son exactas y no deben redibujarse a ojo.

| Elemento | Puntos (x,y) | Notas |
|---|---|---|
| Barra 1 (base) | 40,140 · 62,140 · 72.7,100 · 50.7,100 | altura 40 |
| Barra 2 (intermedia) | 74,140 · 96,140 · 112.6,78 · 90.6,78 | altura 62 |
| Barra 3 (servicio) | 108,140 · 130,140 · 152.5,56 · 130.5,56 | altura 84 |
| Eje base | línea de (34,146.5) a (158,146.5) | grosor 2, extremos redondeados |

Reglas: anchura de barra = 22 u; rendija entre barras = 12 u; inclinación = 15° (desplazamiento horizontal ≈ 0,268 × altura); las tres barras comparten la línea de suelo y = 140; el eje queda 6,5 u por debajo y sobresale 6 u a cada lado del conjunto.

Caja del símbolo (sin fondo): x 34–158, y 56–147,5 → proporción ≈ 4:3.

### 2.1. SVG maestro (color, sobre transparente)

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="34 56 124 91.5" role="img" aria-label="VektralForge">
  <title>VektralForge</title>
  <polygon points="40,140 62,140 72.7,100 50.7,100"    fill="#7E3A1E"/>
  <polygon points="74,140 96,140 112.6,78 90.6,78"     fill="#B4552D"/>
  <polygon points="108,140 130,140 152.5,56 130.5,56"  fill="#D2703F"/>
  <path d="M 34 146.5 L 158 146.5" stroke="#5B7076" stroke-width="2" stroke-linecap="round" fill="none"/>
</svg>
```

### 2.2. SVG monocromo (una tinta)

Sustituir los tres `fill` y el `stroke` por un único color: `#0E1418` sobre fondos claros, `#F4F1EC` sobre fondos oscuros.

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="34 56 124 91.5" role="img" aria-label="VektralForge">
  <g fill="currentColor" stroke="currentColor">
    <polygon points="40,140 62,140 72.7,100 50.7,100"/>
    <polygon points="74,140 96,140 112.6,78 90.6,78"/>
    <polygon points="108,140 130,140 152.5,56 130.5,56"/>
    <path d="M 34 146.5 L 158 146.5" stroke-width="2" stroke-linecap="round"/>
  </g>
</svg>
```

(Con `currentColor` el símbolo hereda el color del texto en web/documentación.)

---

## 3. Versiones del imagotipo

| Versión | Uso principal | Archivo |
|---|---|---|
| Horizontal, modo oscuro | Web, dashboards, README en tema oscuro | `vektralforge-AB-logo-horizontal-dark.svg` |
| Horizontal, modo claro | Documentación, presentaciones, papelería | `vektralforge-AB-logo-horizontal-light.svg` |
| Horizontal, monocromo | Serigrafía, grabado, marca de agua, fax/one-color | `vektralforge-AB-logo-horizontal-mono.svg` |
| Apilada | Formatos cuadrados, avatares con texto, merchandising | ver `vektralforge-AB-lamina.svg` |
| Isotipo transparente | Uso general del símbolo | `vektralforge-AB-isotipo-transparente.svg` |
| Isotipo sobre oscuro (con caja rx 16) | Avatar GitHub/Docker Hub, app icon | `vektralforge-AB-isotipo-dark.svg` |
| Isotipo sobre claro (con caja) | Avatar en plataformas de fondo claro | `vektralforge-AB-isotipo-light.svg` |
| Isotipo monocromo | Favicon monocromo, iconografía de UI | `vektralforge-AB-isotipo-mono.svg` |

**Bloqueo horizontal:** isotipo a la izquierda, altura del isotipo = 1,5 × altura de mayúscula del wordmark; separación isotipo–texto = 0,5 × altura del isotipo; tagline "LAKEHOUSE OPEN SOURCE STACK" opcional bajo el wordmark, alineado a su borde izquierdo.

**Bloqueo apilado:** isotipo centrado sobre el wordmark; separación vertical = 0,25 × altura del isotipo.

**Wordmark:** "Vektral" en color de tinta (Forge Oat sobre oscuro / Anvil Ink sobre claro) y "Forge" en Clay Ember (`#D2703F`) sobre fondo oscuro o en Copper Forge (`#B4552D`) sobre fondo claro, para mantener contraste. En monocromo, todo en una tinta.

---

## 4. Área de protección y tamaños mínimos

- **Área de protección:** un margen libre igual a la anchura de una barra (22 u en el espacio maestro, ≈ 18 % de la anchura del símbolo) alrededor de todo el imagotipo. Nada (texto, otros logos, bordes) debe invadirlo.
- **Tamaño mínimo del isotipo:** 16 px de ancho en pantalla (favicon); 8 mm en impresión.
- **Tamaño mínimo del bloqueo horizontal:** 120 px de ancho en pantalla; 30 mm en impresión. Por debajo, usar solo el isotipo.
- **Favicon:** exportar el isotipo transparente a 16, 32, 48 px (`.ico`) y 180 px (`apple-touch-icon.png`), y `512 px` para PWA/manifest, siempre en la versión color; en tamaños ≤ 24 px la rampa se percibe como un solo naranja, lo cual es aceptable.

---

## 5. Color

Paleta principal (dark-mode-first). Todos los valores CMYK y Pantone son aproximaciones y deben calibrarse en imprenta.

| Nombre | HEX | RGB | CMYK aprox. | Pantone aprox. | Rol |
|---|---|---|---|---|---|
| **Rust Base** | `#7E3A1E` | 126 58 30 | 0 54 76 51 | 1615 C | Barra 1 (base) · óxido/metal frío |
| **Copper Forge** | `#B4552D` | 180 85 45 | 0 53 75 29 | 7580 C | Barra 2 · "Forge" del wordmark en modo claro |
| **Clay Ember** | `#D2703F` | 210 112 63 | 0 47 70 18 | 7578 C | Barra 3 (punta del vector) · "Forge" en modo oscuro · acento principal de UI |
| **Steel Axis** | `#5B7076` | 91 112 118 | 23 5 0 54 | 5477 C | Eje base del isotipo · bordes en modo oscuro |
| **Anvil Ink** | `#0E1418` | 14 20 24 | 42 17 0 91 | Black 6 C | Fondo oscuro · tinta en modo claro |
| **Slate Steel** | `#4A5560` | 74 85 96 | 23 11 0 62 | Cool Gray 10 C | Eje en modo claro · texto secundario |
| **Forge Oat** | `#F4F1EC` | 244 241 236 | 0 1 3 4 | Warm Gray 1 C | Fondo claro · tinta en modo oscuro |
| **Signal Teal** | `#2CC6C6` | 44 198 198 | 78 0 0 22 | 3252 C | Acento frío de UI (enlaces, estados) · nunca en el logo |

**Rampa del isotipo:** Rust Base → Copper Forge → Clay Ember, siempre en ese orden (de la barra baja a la alta): el metal se calienta hacia la punta del vector. No invertir. Los tres tonos son los del boceto original del Concepto B y no se sustituyen por la paleta Ember/Amber del informe, que queda reservada a ilustración y material promocional si se desea más energía.

**Contraste (WCAG 2.x, calculado):**
- Forge Oat sobre Anvil Ink: 16,5:1 (AAA), y viceversa.
- Clay Ember sobre Anvil Ink: 5,4:1 (AA para texto normal; ideal para el "Forge" del wordmark y enlaces en modo oscuro).
- Copper Forge sobre Forge Oat: 4,4:1 (AA para texto grande y elementos de UI; para texto pequeño de acento en modo claro usar Rust Base, 7,4:1).
- Clay Ember sobre Forge Oat: 3,0:1: solo texto grande o gráficos; nunca texto pequeño en modo claro.
- Steel Axis sobre Anvil Ink: 3,6:1: suficiente como elemento gráfico (eje), no como texto.

**Tokens CSS de referencia:**

```css
:root {
  --vf-rust: #7E3A1E;
  --vf-copper: #B4552D;
  --vf-clay: #D2703F;
  --vf-axis: #5B7076;
  --vf-ink: #0E1418;
  --vf-slate: #4A5560;
  --vf-oat: #F4F1EC;
  --vf-teal: #2CC6C6;
}
```

---

## 6. Tipografía

Todo el sistema es open source (SIL OFL / Apache 2.0), coherente con la naturaleza del proyecto.

| Rol | Fuente | Peso / ajustes | Uso |
|---|---|---|---|
| Wordmark y titulares display | **Space Grotesk** | Bold 700 · tracking −2 % (−0.02 em) | "VektralForge", H1 de web y portada de docs |
| Interfaz y cuerpo | **Inter** | Regular 400, Medium 500, SemiBold 600 · `font-feature-settings: "tnum"` en tablas | Web, documentación, dashboards |
| Código y etiquetas técnicas | **JetBrains Mono** | Regular 400 · tracking +2–4 % en mayúsculas | Bloques de código, tagline en versalitas, metadatos, favicons de texto |

El **tagline** ("LAKEHOUSE OPEN SOURCE STACK") se compone siempre en JetBrains Mono, mayúsculas, tracking amplio, al 60 % de opacidad de la tinta.

**Fallbacks (web y UI):** `'Space Grotesk', 'Inter', system-ui, sans-serif` y `'JetBrains Mono', 'Space Mono', ui-monospace, monospace`. **Los SVG de `logo/` y `lamina/` llevan el wordmark y el tagline convertidos a trazados** (Space Grotesk Bold y JetBrains Mono Regular, con kerning aplicado), por lo que se renderizan idénticos en cualquier equipo sin necesidad de tener las fuentes instaladas.

---

## 7. Usos incorrectos

No hacer:
- Cambiar el orden o los colores de la rampa terracota, ni aplicar degradados dentro de cada barra.
- Alterar la inclinación, la anchura o las rendijas de las barras, o eliminar el eje base.
- Rotar, reflejar, extruir, sombrear o aplicar contornos al isotipo.
- Usar Signal Teal o el azul en el isotipo o en el wordmark.
- Componer el wordmark con otra fuente o con mayúsculas.
- Colocar el imagotipo en color sobre fotografías o fondos saturados; usar la versión monocroma.
- Reducir por debajo de los tamaños mínimos o invadir el área de protección.
- Añadir "Vektor Slash", "v1" u otros sufijos al wordmark: el nombre público es únicamente **VektralForge**.

---

## 8. Estructura recomendada del repositorio de marca

```
brand/
├── marca-imagotipo.md          ← este documento
├── logo/
│   ├── vektralforge-logo-horizontal-dark.svg
│   ├── vektralforge-logo-horizontal-light.svg
│   └── vektralforge-logo-horizontal-mono.svg
├── isotipo/
│   ├── vektralforge-isotipo.svg            (transparente, color)
│   ├── vektralforge-isotipo-mono.svg
│   ├── vektralforge-isotipo-dark.svg       (con caja, avatares)
│   └── vektralforge-isotipo-light.svg
├── favicon/                                (16/32/48 .ico, 180 apple-touch, 512 png)
└── lamina/vektralforge-lamina.svg
```

Los archivos ya están organizados y nombrados según esta estructura en el paquete `vektralforge-brand.zip`; la carpeta `favicon/` incluye además `site.webmanifest` y `head-snippet.html` con las etiquetas `<link>` listas para pegar en el `<head>`.

**Licencia sugerida para los activos de marca:** CC BY 4.0 para los archivos gráficos, con la nota de que el nombre y el imagotipo identifican al proyecto y no deben usarse para sugerir afiliación o respaldo oficial sin permiso de los mantenedores.

---

## 9. Resumen ejecutivo

- **Isotipo:** Vektor Slash: tres barras a 15° de altura ascendente sobre un eje común, en rampa Rust Base → Copper Forge → Clay Ember, eje en Steel Axis.
- **Wordmark:** "VektralForge" en Space Grotesk Bold, "Forge" en Clay Ember (oscuro) / Copper Forge (claro).
- **Fondos:** Anvil Ink (prioritario) y Forge Oat.
- **Sistema tipográfico:** Space Grotesk · Inter · JetBrains Mono, todo open source.
- **Principios:** dark-mode-first, monocromo funcional a 16 px, sin azul, calor terracota como diferenciador, geometría exacta, área de protección de una barra.
