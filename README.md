# Tempo

Utilidad de captura de pantalla para macOS pensada para un flujo concreto: **capturar, anotar
rápido y arrastrar la imagen a un chat de IA** (ChatGPT, Claude, o cualquier otra aplicación
que acepte imágenes) sin pasos intermedios.

No integra ninguna API de inteligencia artificial. La conexión con el modelo ocurre donde ya
estás trabajando: arrastrando la miniatura, o pegando con ⌘V.

Nativa (Swift, AppKit y SwiftUI), sin dependencias externas, sin cuentas, sin nube y sin
telemetría. Todo se queda en tu Mac.

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5-orange)](https://swift.org)
[![Licencia MIT](https://img.shields.io/badge/licencia-MIT-blue)](LICENSE)

---

## Instalación rápida

```bash
git clone https://github.com/Jairoalejo456/tempo.git
cd tempo
xcodebuild -project Tempo.xcodeproj -scheme Tempo -configuration Release build
cp -R ~/Library/Developer/Xcode/DerivedData/Tempo-*/Build/Products/Release/Tempo.app /Applications/
open /Applications/Tempo.app
```

No hace falta cuenta de desarrollador: el proyecto se firma de forma ad-hoc por omisión. La
primera vez, macOS pedirá el permiso de **Grabación de pantalla**; concédelo y vuelve a abrir la
aplicación.

Tempo vive en la barra de menús. Pulsa `⌥⇧⌘S` para capturar una región y empezar.

---

## El flujo

1. Pulsas un atajo global y capturas la pantalla completa o una región.
2. Aparece una **miniatura flotante** en la esquina inferior derecha, por encima de todo lo
   demás y sin robarte el foco.
3. Desde ahí puedes:
   - **Arrastrarla** directamente al navegador o a una app de escritorio. Una vez entregada, la
     miniatura se desvanece sola; si el arrastre se cancela, se queda donde estaba.
   - **Hacer clic** para abrir el editor y anotarla.
   - **Cerrarla** con la ✕ que aparece al pasar el ratón por encima.
4. En el editor anotas y terminas con **Copiar** (⌘C) o **Guardar** (⌘S). Si no necesitas
   anotar nada, el clic derecho sobre la miniatura ofrece copiar, guardar o descartar
   directamente.
5. Si cierras el editor sin descartar (⌘W o Esc), la captura **vuelve a ser miniatura** y
   sigue disponible para arrastrarla más tarde.

Y si una captura se retira antes de tiempo, sigue estando en **Capturas recientes**, en el menú
de la barra.

## Varias capturas a la vez

Cuando tomas varias sin cerrarlas, se agrupan en un **mazo** en la esquina: se ve la de encima,
las esquinas de las de detrás asomando y un contador con el total.

- **Arrastrar el mazo entrega todas las capturas**, no sólo la de encima. Es lo cómodo para
  llevar varias pantallas de contexto a un chat de una vez.
- **Un clic** abre el editor con todas. A la derecha aparece una **tira de miniaturas** para
  elegir sobre cuál trabajar; la captura elegida ocupa el lienzo entero.
- Cada captura conserva **lo suyo**: sus anotaciones, su propio historial de deshacer, su zoom
  y su numeración de contadores. Editar una nunca toca a las demás.
- `⌥↑` y `⌥↓` saltan a la captura anterior o siguiente.
- **Copiar** y **Guardar** actúan sobre la captura activa. El botón de al lado ofrece
  **copiarlas todas juntas** en una sola imagen —apiladas verticalmente, ideal para pegar todo
  el contexto de una vez— o **guardarlas por separado**, un archivo por captura.

---

## Requisitos

- **macOS 14 o posterior.** Desarrollado y probado en macOS 26.6, Apple Silicon.
- **Xcode 16 o posterior** (probado con Xcode 26.6).
- Ninguna dependencia externa ni gestor de paquetes.

## Compilar y ejecutar

Abre `Tempo.xcodeproj` en Xcode y pulsa ⌘R, o compila desde la terminal como en la instalación
rápida de arriba.

Copia el `.app` a `/Applications` y añádela a **Ajustes del Sistema › General › Ítems de
inicio** si quieres que arranque con el Mac. Instalarla ahí importa: macOS liga el permiso de
grabación de pantalla a la ruta y a la identidad de la app, así que ejecutarla desde la carpeta
de compilación obligaría a reconceder el permiso más a menudo.

### Icono

El icono se dibuja vectorialmente a partir del símbolo de la marca, en todos los tamaños, para
que se vea nítido igual en el Dock que a 16 px en la barra de menús:

```bash
swift Tools/generate-icon.swift light Tempo/Resources/Assets.xcassets/AppIcon.appiconset
```

Cambia `light` por `dark` para la variante sobre azul marino. Si prefieres partir de un PNG
propio de 1024×1024, usa `Tools/make-appicon.sh logo-1024.png`.

### Firma

Por omisión el proyecto se firma de forma **ad‑hoc**: se compila y se ejecuta sin necesidad de
ninguna cuenta de desarrollador.

Si tienes un certificado de desarrollo, merece la pena usarlo: macOS asocia el permiso de
grabación de pantalla a la identidad de la app, así que **no tendrás que volver a concederlo
cada vez que recompiles**. Para ello crea `Config/Local.xcconfig` (está ignorado por git):

```
CODE_SIGN_IDENTITY = Apple Development
DEVELOPMENT_TEAM = TU_TEAM_ID
```

Tu Team ID es el campo `OU` del certificado:

```bash
security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject
```

---

## Permisos de macOS

Tempo necesita **Grabación de pantalla**:

> Ajustes del Sistema › Privacidad y seguridad › Grabación de pantalla → activar *Tempo*

La primera vez que arranca, la app lo solicita automáticamente. Si lo concedes con la app ya
abierta, **ciérrala y vuelve a abrirla** para que el sistema aplique el cambio.

No necesita permiso de Accesibilidad: los atajos globales usan `RegisterEventHotKey`, que el
sistema entrega directamente a la aplicación.

Puedes comprobar el estado desde el menú de la barra superior, o ejecutando:

```bash
open -n /Applications/Tempo.app --args --self-check ~/Desktop/informe.txt
```

---

## Atajos

### Globales (funcionan con cualquier aplicación en primer plano)

| Acción | Atajo por omisión |
|---|---|
| Capturar la pantalla completa | `⌥⇧⌘F` |
| Seleccionar y capturar una región | `⌥⇧⌘S` |

Ambos se pueden cambiar en **Ajustes › Atajos** (⌘,): haz clic en el atajo y pulsa la
combinación que quieras. Esc cancela y `⌫` restablece el original.

Durante la selección de región la pantalla se atenúa y el cursor pasa a ser una cruz: arrastra
para definir la zona y verás su tamaño en píxeles. `Esc` o clic derecho cancelan, y un clic sin
arrastre también.

### Editor

| Herramienta | Tecla |
|---|---|
| Puntero (mover y hacer zoom) | `V` |
| Recortar el encuadre | `K` (`↩` confirma) |
| Flecha | `A` |
| Rectángulo | `R` |
| Elipse / círculo | `O` |
| Texto | `T` |
| Lápiz | `P` |
| Blur (censura) | `B` |
| Contador numerado | `C` |

| Acción | Atajo |
|---|---|
| Mover lo seleccionado | flechas (`⇧` = 10 px) |
| Renumerar el contador seleccionado | teclear el número (`⌫` corrige) |
| Seguir con la misma herramienta | `⌥` al soltar |
| Eliminar lo seleccionado | `⌫` |
| Quitar la selección | `Esc` |
| Captura anterior / siguiente | `⌥↑` / `⌥↓` |
| Acercar / Alejar | `⌘+` / `⌘−` (o `⌃` + rueda) |
| Ajustar a la ventana | `⌘0` |
| Tamaño real | `⌘1` |
| Deshacer / Rehacer | `⌘Z` / `⇧⌘Z` |
| Borrar la última anotación | `⌫` |
| Elegir color | `1` … `8` (salvo con un contador seleccionado) |
| Ajuste de la herramienta activa | `[` / `]` |
| Copiar con anotaciones | `⌘C` |
| Guardar como PNG | `⌘S` |
| Volver a la miniatura | `⌘W` o `Esc` |
| Descartar la captura | `⇧⌘⌫` |

Todos los atajos están visibles en la propia interfaz: la tecla de cada herramienta aparece en
su botón, y el botón **?** de la barra abre la lista completa.

Con `⇧` mantenido al dibujar: cuadrados y círculos perfectos, y flechas en ángulos de 45°.

---

## Recortar

Con la herramienta **Recortar** (`K`) ajustas el encuadre sin volver a capturar: arrastra los
tiradores o dibuja un encuadre nuevo, y confirma con `↩` (`Esc` cancela). Se muestra el tamaño
resultante en píxeles reales y unas guías en tercios.

El recorte se hace sobre los píxeles nativos, así que una captura Retina recortada **sigue
siendo Retina**. Las anotaciones se desplazan con el recorte y las que quedan fuera se
descartan; todo ello en una sola operación de deshacer, que devuelve también los píxeles
quitados.

## El puntero

El editor abre siempre en modo **puntero** (`V`): mirar una captura y moverse por ella no debe
ensuciarla con una anotación accidental al primer clic. Con el puntero activo:

- **Arrastrar** desplaza la captura.
- **La rueda del ratón** acerca y aleja alrededor del cursor; con `⌃` pulsado, también. Con
  trackpad, dos dedos desplazan y el pellizco hace zoom.
- **Doble clic** vuelve a ajustar la captura a la ventana.

El porcentaje de zoom se muestra en la barra; pulsarlo también reajusta.

## Ajustes

Se abren con `⌘,` o desde el menú de la barra superior.

- **General** — qué ocurre al pulsar Guardar (preguntar siempre, o guardar directo sin diálogo)
  y en qué carpeta. Guardando directo, la captura se escribe al instante con un nombre con
  fecha y hora, y nunca se sobrescribe una anterior. Cuando se pregunta, el panel se abre en
  esa carpeta y recuerda la última que uses.
- **Atajos** — los dos atajos globales, editables, más la lista de atajos del editor.
- **Al arrastrar** — si la miniatura se retira sola al soltarla en otra aplicación. Desactívalo
  si quieres llevar la misma captura a varios sitios seguidos.
- **Al copiar** — puedes reducir la imagen al copiarla. Los chats de IA reescalan las imágenes
  por su cuenta a bastante menos de lo que mide una captura Retina, así que enviar el original
  es mandar datos que nadie va a mirar. **Guardar en disco conserva siempre el tamaño completo.**
- **Historial** — las capturas recientes se guardan en este Mac para poder recuperarlas si las
  descartas sin querer, y se borran solas pasados los días que elijas (una semana por omisión).
  Se abren desde **Capturas recientes** en el menú de la barra. No hay nube ni sincronización:
  puedes desactivarlo o vaciarlo cuando quieras.
- **Acerca de** — versión y compilación, y acceso directo a los ajustes de privacidad de macOS.

Tempo vive en la barra de menús, pero es una aplicación normal: aparece en Spotlight, en
Launchpad y en la carpeta Aplicaciones. Al abrirla desde ahí estando ya en marcha, muestra los
ajustes, para que hacer clic tenga una respuesta visible. Si prefieres que además ocupe sitio
en el Dock de forma permanente, actívalo en **Ajustes › General › Mostrar el icono en el Dock**.

## Todo lo que dibujas sigue siendo editable

Las anotaciones no quedan estampadas sobre la captura. Con el **puntero** (`V`) puedes volver a
cualquiera de ellas:

- **Clic** para seleccionarla. Las formas huecas se agarran por su contorno, así que puedes
  elegir lo que haya dentro de un rectángulo grande; el blur, que está relleno, se agarra por
  cualquier punto.
- **Arrastrar** para moverla, o las **flechas del teclado** para ajustarla al píxel (`⇧` da
  pasos de diez).
- **Ocho tiradores** para cambiar el tamaño; con `⇧` se mantiene la proporción.
- **Tirador circular superior** para girarla; con `⇧` salta de 15 en 15 grados.
- Una **flecha** se reorienta moviendo sus extremos, que es más directo que girarla.
- **`⌫`** para eliminarla, o el botón de papelera de la barra.
- Cambiar de **color o grosor** con algo seleccionado lo aplica a esa anotación, entera.

Al seleccionar algo, la barra pasa a mostrar **sus** propiedades: si eliges un texto azul, la
paleta marca azul. Así el siguiente ajuste que toques no le cambia de paso algo que no querías,
y lo que dibujes después continúa con ese estilo.

**Doble clic** sobre un texto entra a reescribirlo, aunque el cursor caiga sobre uno de sus
tiradores.

Al terminar de colocar cualquier elemento, la herramienta vuelve sola al puntero y el elemento
queda seleccionado, listo para ajustarlo. Si prefieres encadenar varios seguidos —varios
contadores, varios trazos— mantén **⌥** al soltar el ratón y la herramienta sigue activa.

### Contadores con el número que quieras

Los contadores se numeran solos al ponerlos, pero no estás atado a ese orden. Selecciona uno y
**teclea el número**: cambia al instante, sin cuadros ni confirmaciones. Los dígitos seguidos
se componen —`2` y luego `5` dan 25— y `⌫` corrige el último. Toda la secuencia cuenta como un
solo deshacer. También está el control **N.º** de la barra, si prefieres el ratón.
Si tienes el 1, 2 y 3 y quieres que el siguiente sea el 8, lo pones y ya está; a partir de ahí
la numeración automática continúa desde el mayor que exista.

Un arrastre completo —mover, redimensionar o girar— cuenta como **una sola** operación de
deshacer, no una por cada movimiento del ratón.

El deslizador sustituye a los tres tamaños fijos cuando la herramienta activa —o la anotación
seleccionada— es un blur o un trazo a lápiz, así que la barra no crece por tenerlo.

## Herramientas del editor

- **Flecha**, **rectángulo** y **elipse** con color y tres tamaños.
- **Lápiz** con color y un **deslizador de grosor** continuo, de 1 a 24 puntos.
- **Texto**: haz clic donde quieras y escribe. El bloque nace **centrado en el punto que has
  pulsado** y el texto se reparte en varias líneas dentro de su caja, así que nunca se sale de
  la captura por larga que sea la frase. `↩` confirma, `⌥↩` añade una línea, `Esc` cancela, y un
  clic fuera también lo da por bueno.

  Con un texto seleccionado, los tiradores **laterales** cambian la anchura de la caja —el texto
  se reparte de nuevo— y los de las **esquinas**, el cuerpo de letra. **Doble clic** vuelve a
  abrirlo para corregirlo o añadir más. Cambiar el color mientras escribes repinta **todo** lo
  escrito, no sólo lo que teclees a partir de ahí.
- **Blur**: difumina la región seleccionada para censurar datos sensibles. Su **intensidad** se
  ajusta con el deslizador de la barra, que aparece al elegir la herramienta o al seleccionar
  un blur ya puesto.
- **Contadores**: círculos numerados que se autoincrementan (1, 2, 3…). Al deshacer, la
  numeración vuelve atrás sola.

**Copiar** deja la imagen final en el portapapeles (PNG y TIFF) y cierra la captura: ya puedes
pegarla con ⌘V. **Guardar** abre el panel nativo de macOS; si lo cancelas, la captura sigue
intacta y disponible.

---

## Estructura del proyecto

```
Tempo/
├── App/          Ciclo de vida, menús, coordinación del flujo y sesiones de captura
├── Capture/      ScreenCaptureKit y capa de selección de región
├── Models/       Anotaciones, colores, imagen capturada y estado del editor (undo/redo)
├── Editor/       Ventana del editor, lienzo, barra de herramientas y renderizador
├── Thumbnail/    Panel flotante y arrastre a otras aplicaciones
├── Preferences/  Ventana de ajustes y grabador de atajos
├── Services/     Atajos globales, ajustes, exportación (portapapeles/disco) y avisos
└── Resources/    Catálogo de recursos e icono de la app
TempoTests/     Pruebas del núcleo (42 pruebas)
Tools/            Utilidades de desarrollo
```

### Legibilidad sobre cualquier fondo

Cada anotación se dibuja en dos pasadas: primero un **contorno de contraste** y encima la
anotación. El color del contorno se elige por oposición a la luminancia del propio trazo —uno
oscuro se rodea de claro y uno claro de oscuro—, así que siempre hay un salto de contraste,
tanto sobre una ventana blanca como sobre una interfaz en modo oscuro. Incluso un texto negro
sobre fondo negro sigue leyéndose.

Sobre fondos donde el color ya destaca, el contorno pasa desapercibido y no ensucia la captura.
El blur es la excepción: no lleva contorno, porque no es un trazo sino la propia imagen
difuminada.

Puedes comprobarlo tú mismo:

```bash
open -n /Applications/Tempo.app --args --contrast-check ~/Desktop/contraste.png
```

Genera todas las herramientas, en los ocho colores, sobre bandas que van del blanco al negro.

### Decisiones técnicas

- **Un solo renderizador.** `AnnotationRenderer` dibuja tanto en el lienzo como en la imagen
  exportada, sobre el mismo sistema de coordenadas. Lo que ves es exactamente lo que se copia
  o se guarda; no hay dos caminos que puedan divergir.
- **Coordenadas lógicas.** Las anotaciones viven en puntos, no en píxeles. Al exportar se
  escala por el factor Retina de la pantalla de origen, así que una captura en un monitor 2×
  se guarda a resolución completa sin que el editor tenga que saber nada de ello.
- **La sesión es la dueña de la captura.** La miniatura y el editor son sólo dos formas de
  mostrar la misma sesión, por eso cerrar el editor nunca destruye el trabajo.
- **El giro se guarda aparte de la forma.** Cada anotación se define sin girar y el ángulo se
  aplica al dibujar, al buscar qué se ha pulsado y al colocar los tiradores. Así la geometría
  de cada herramienta sigue siendo sencilla y el giro funciona igual en todas.
- **`RegisterEventHotKey` (Carbon)** para los atajos globales, en lugar de monitores de
  eventos: es la vía que no exige permiso de Accesibilidad.
- **`SCScreenshotManager` (ScreenCaptureKit)** para capturar, excluyendo siempre la propia
  aplicación del filtro para que la miniatura y la capa de selección no salgan en la imagen.
- **Sin sandbox**, para que el panel de guardar y el arrastre funcionen sin restricciones en
  un uso personal.
- **Los atajos guardan el código físico de la tecla**, no el carácter, así que siguen
  funcionando aunque se cambie la distribución del teclado; para mostrarlos se traducen con la
  distribución activa, de modo que un teclado español enseña la tecla correcta.

---

## Pruebas

```bash
xcodebuild -project Tempo.xcodeproj -scheme Tempo test
```

Cubren el estado del editor (historial, numeración automática, descarte de gestos vacíos), el
renderizado de todas las herramientas, la conservación de la resolución Retina, la conversión
de coordenadas entre AppKit y ScreenCaptureKit, y la salida a portapapeles y disco.

Para comprobar el camino real —captura de pantalla incluida— en este Mac:

```bash
open -n /Applications/Tempo.app --args --self-check ~/Desktop/informe.txt
```

Conviene lanzarlo con `open` y volcar el informe a un archivo: macOS atribuye los permisos de
privacidad al proceso que lanza la aplicación, así que ejecutar el binario directamente desde
una terminal heredaría los permisos de la terminal y daría un falso negativo.

Comprueba el permiso, hace una captura completa y una de región, aplica las siete herramientas,
verifica la numeración de contadores y el historial, compone a resolución nativa, copia al
portapapeles y escribe un PNG en disco.

Para probar el editor completo sin conceder ningún permiso, con una captura de ejemplo:

```bash
open -n /Applications/Tempo.app --args --demo                         # miniatura flotante
open -n /Applications/Tempo.app --args --demo --editor                # y además el editor
open -n /Applications/Tempo.app --args --demo --editor --annotated    # con anotaciones de ejemplo
open -n /Applications/Tempo.app --args --demo --editor --stack 4      # cuatro capturas apiladas
```

Para capturar la pantalla desde la propia aplicación (útil para revisar su interfaz, ya que
sólo Tempo tiene el permiso de grabación):

```bash
open -n /Applications/Tempo.app --args --screenshot ~/Desktop/captura.png [--include-self]
```

`--include-self` desactiva la exclusión de las ventanas de Tempo, que en uso normal impide que
la miniatura salga dentro de tus propias capturas.

Y para revisar de un vistazo cómo se dibuja cada herramienta, sin necesidad de capturar nada:

```bash
/ruta/a/Tempo.app/Contents/MacOS/Tempo --render-sample ~/Desktop/muestra.png
```

---

## Contribuir

Las contribuciones son bienvenidas. En [CONTRIBUTING.md](CONTRIBUTING.md) están las
instrucciones para poner el proyecto en marcha, cómo está organizado el código, las dos ideas
de diseño que conviene respetar al tocarlo, y una lista de cosas pendientes por si buscas por
dónde empezar.

Antes de abrir un pull request:

```bash
xcodebuild -project Tempo.xcodeproj -scheme Tempo test
```

## Licencia

[MIT](LICENSE). Úsalo, cámbialo y compártelo como quieras.

## Privacidad

Todo ocurre en local. Las capturas no se suben a ningún sitio, no hay cuentas, no hay
telemetría y no hay nada sincronizado.

El historial de capturas recientes, si lo dejas activado, guarda las imágenes en la carpeta de
soporte de la aplicación dentro de tu usuario, y las borra solas pasados los días configurados.
Puedes desactivarlo o vaciarlo desde **Ajustes › General**.

Los archivos temporales que se crean para poder arrastrar la imagen viven en el directorio
temporal del sistema y caducan a las 24 horas. **No se borran al cerrar la captura**: al soltar
una imagen, muchas aplicaciones no se quedan con una copia sino con la ruta del archivo, y lo
leen más tarde —al enviar el mensaje—; si desapareciera antes, la imagen se vería como no
disponible.

## Limitaciones conocidas

- No se pueden seleccionar varias anotaciones a la vez ni agruparlas.
- Las capturas del mazo no se pueden reordenar.
- No hay reconocimiento de texto (OCR) ni captura de una ventana concreta.
- No hay capas: el orden de dibujo es el orden en que se crearon.
- No hay captura de ventana concreta ni con retardo, ni captura con scroll.
- Los atajos del editor son fijos; sólo los dos globales son configurables.
- La app no está notarizada: es para uso personal en este Mac.
