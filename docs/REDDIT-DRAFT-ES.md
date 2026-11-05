# Borrador para Reddit — r/macgaming

**Título:** Conseguí que la build original de Stray para macOS llegue a la calibración de brillo en un iPhone 17 Pro Max

Estoy experimentando con el trabajo de compatibilidad macOS-en-iOS de [zorrobyte/macos-on-ios-public](https://github.com/zorrobyte/macos-on-ios-public), probándolo con la build original de Stray para macOS Apple Silicon.

Después de trabajar en rutas del bundle y recursos, detección de plataforma Mac de Unreal, el descriptor de GPU mediante IOKit y una diferencia entre los modos de almacenamiento Metal de macOS e iOS, conseguí que el juego renderice el aviso de autosave y la interfaz de calibración de brillo en un iPhone 17 Pro Max.

Algunas observaciones:
- Unreal llega a la interfaz inicial de Stray.
- El log de fase G muestra carga de una biblioteca Metal y conversiones de descriptores de texturas de Managed a Shared.
- El overlay/log reportó alrededor de 59–62 FPS durante parte de una sesión corta.
- La presentación horizontal está deformada.
- UIKit recibe eventos táctiles, pero la entrada funcional dentro del gameplay no está demostrada.
- Abrir desde el icono de SpringBoard se cierra; el lanzamiento exitoso utilizó argumentos desde Terminal.

Para ser claro: **todavía no es jugable**, no es un port de iOS y no estoy distribuyendo el juego ni sus recursos. Estoy documentando el trabajo de compatibilidad y los problemas pendientes.

Bitácora: https://github.com/ju4nm8/stray-on-ios-research

Me interesan opiniones de gente que conozca el Metal RHI de Unreal para Mac, el tamaño de vistas UIKit/CAMetalLayer o la integración de controles.
