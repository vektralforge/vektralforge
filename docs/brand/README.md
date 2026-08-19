# Recursos de marca

Activos gráficos de VektralForge. El manual completo —concepto, construcción
geométrica, paleta, tipografía y usos incorrectos— está en
[`docs/marca.md`](../marca.md).

## Contenido

| Carpeta | Uso |
| --- | --- |
| `logo/` | Imagotipo horizontal: símbolo + wordmark + tagline |
| `isotipo/` | Solo el símbolo, para espacios reducidos |
| `lamina/` | Hoja de especificación con todas las variantes |
| `favicon/` | Iconos web, manifest y fragmento para el `<head>` |

## Qué variante usar

**`-dark`** sobre fondos oscuros, **`-light`** sobre claros, **`-mono`** cuando
solo hay una tinta disponible: impresión a un color, grabados, serigrafía.

En Markdown, GitHub permite servir la variante correcta según el tema del
lector:

```markdown
<img src="docs/brand/logo/vektralforge-logo-horizontal-dark.svg#gh-dark-mode-only" width="420">
<img src="docs/brand/logo/vektralforge-logo-horizontal-light.svg#gh-light-mode-only" width="420">
```

Por debajo de 120 px de ancho, el wordmark deja de leerse: usa el isotipo.

## El wordmark va en trazados

Los SVG no declaran `font-family`. Un archivo que dependiera de Space Grotesk
se vería en Arial en cualquier equipo sin esa fuente instalada —incluido el
renderizador de GitHub—, así que el texto está convertido a `<path>`.

La consecuencia práctica: **el texto de estos archivos no es editable**. Para
cambiar el tagline o el wordmark hay que regenerarlos desde la fuente
tipográfica, no editando el SVG.

## Uso permitido

Estos archivos están cubiertos por [`TRADEMARK.md`](../../TRADEMARK.md), **no**
por la licencia Apache 2.0 del código. En resumen: puedes usar el logo para
referirte al proyecto o enlazarlo; no puedes usarlo como marca de tu propio
producto ni modificarlo. Un fork debe retirarlo y usar un nombre distinto.

## Tipografías

| Fuente | Licencia | Uso |
| --- | --- | --- |
| Space Grotesk | SIL OFL 1.1 | Wordmark y titulares |
| JetBrains Mono | SIL OFL 1.1 | Tagline, código, metadatos |
| Inter | SIL OFL 1.1 | Texto corrido |

Las tres son libres y compatibles con Apache 2.0. Como el wordmark está
trazado, el repositorio no redistribuye ningún archivo de fuente.
