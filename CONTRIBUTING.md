# Contribuir a Tempo

Gracias por el interés. Tempo nació como una herramienta personal y se publica por si le sirve
a alguien más. No hay hoja de ruta ni compromisos de mantenimiento: las contribuciones son
bienvenidas y se revisan cuando hay tiempo.

## Poner el proyecto en marcha

```bash
git clone https://github.com/Jairoalejo456/tempo.git
cd tempo
open Tempo.xcodeproj      # o: xcodebuild -scheme Tempo build
```

No hay dependencias externas ni gestores de paquetes: sólo Xcode y el SDK de macOS.

Por omisión el proyecto se firma de forma **ad-hoc**, así que compila y se ejecuta sin ninguna
cuenta de desarrollador. Si tienes un certificado, crea `Config/Local.xcconfig` (ignorado por
git) con tu identidad; el `README` explica por qué merece la pena.

Para trabajar en el editor sin conceder el permiso de grabación de pantalla:

```bash
open -n /ruta/a/Tempo.app --args --demo --editor --annotated
```

## Antes de abrir un pull request

```bash
xcodebuild -project Tempo.xcodeproj -scheme Tempo test
```

Las pruebas deben pasar. Si cambias algo que se pueda ver, adjunta una captura: hay modos de
diagnóstico que ayudan a generarlas (`--render-sample`, `--contrast-check`, `--screenshot`),
descritos en el `README`.

## Cómo está organizado

```
Tempo/
├── App/          Ciclo de vida, menús, coordinación del flujo y sesiones de captura
├── Capture/      ScreenCaptureKit y capa de selección de región
├── Models/       Anotaciones, colores, imagen capturada y estado del editor
├── Editor/       Ventana del editor, lienzo, barra de herramientas y renderizador
├── Thumbnail/    Panel flotante y arrastre a otras aplicaciones
├── Preferences/  Ventana de ajustes y grabador de atajos
├── Services/     Atajos globales, ajustes, exportación, historial y avisos
└── Resources/    Catálogo de recursos e iconos
```

Hay dos ideas que conviene respetar al tocar el código:

- **Un solo renderizador.** `AnnotationRenderer` dibuja tanto en el lienzo como en la imagen
  que se exporta. Si añades una herramienta, añádela ahí y funcionará igual en pantalla y en el
  archivo. Dibujarla por separado en el lienzo es la forma segura de que acaben divergiendo.
- **La sesión es la dueña de la captura.** La miniatura y el editor son dos formas de mostrar la
  misma sesión. Cerrar una ventana nunca debe destruir el trabajo.

## Estilo

- Identificadores en inglés, comentarios y textos de interfaz en español.
- Comenta el **porqué**, no el qué. Los comentarios que explican una decisión no obvia —o un
  comportamiento del sistema que costó descubrir— valen mucho más que los que repiten el código.
- Cada corrección de un fallo debería venir con una prueba que falle sin ella.

## Qué encaja bien

Cosas pendientes que tendrían sentido, por si buscas por dónde empezar:

- Reconocimiento de texto (OCR) sobre la captura, con Vision.
- Captura de una ventana concreta, resaltándola bajo el cursor.
- Selección múltiple de anotaciones y orden de capas.
- Atajos del editor configurables, como ya lo son los globales.
- Traducción de la interfaz a otros idiomas.

## Qué no encaja

Cualquier cosa que mande las capturas fuera del equipo. Tempo no tiene cuentas, ni nube, ni
telemetría, y la idea es que siga así.
