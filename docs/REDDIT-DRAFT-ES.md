# Borrador para Reddit — r/macgaming

**Título:** Ya puedo abrir la build original de Stray para macOS desde el icono de iOS en un iPhone 17 Pro Max

Estoy experimentando con el trabajo de compatibilidad macOS-en-iOS de [zorrobyte/macos-on-ios-public](https://github.com/zorrobyte/macos-on-ios-public), usando la build original de Stray para macOS Apple Silicon.

He trabajado en las rutas del bundle y los recursos, la detección de plataforma Mac de Unreal, el descubrimiento de GPU mediante IOKit y varios problemas de compatibilidad con Metal. Ahora puedo abrir Stray directamente desde su icono en la pantalla de inicio de iOS y llegar a un túnel 3D reconocible en mi iPhone 17 Pro Max.

El resultado todavía está incompleto:
- El túnel se ve, con tuberías texturizadas, estructuras de concreto, cables, vegetación, cielo y efectos atmosféricos.
- El interior del túnel sigue demasiado oscuro.
- Todavía no he confirmado claramente al gato en las capturas más recientes.
- Mis logs de VGC muestran que los valores de los sticks llegan al shim, pero aún no he verificado el movimiento del personaje, la cámara ni los botones de acción dentro de Unreal.
- Las muestras cortas de Run 6 variaron aproximadamente entre 38 y 56 FPS. No son resultados de benchmark.

Esto **no significa que Stray ya sea completamente jugable**, no es un port nativo de iOS y no estoy distribuyendo el juego ni sus recursos. Estoy documentando el trabajo de compatibilidad y los problemas de ingeniería que todavía faltan por resolver.

Bitácora: https://github.com/ju4nm8/stray-on-ios-research

Me interesan opiniones de personas que conozcan el Metal RHI de Unreal para Mac, el tamaño de vistas UIKit/CAMetalLayer, las variantes de shaders o la integración de controles mediante GameController.