# Stray en iOS — bitácora de investigación

> ¿Es posible ejecutar la build original de **Stray para macOS Apple Silicon** en un iPhone?
>
> Estoy documentando un experimento personal de compatibilidad basado en [macos-on-ios-public](https://github.com/zorrobyte/macos-on-ios-public). Esto es una bitácora de ingeniería, no un port nativo de iOS, un instalador ni una afirmación de que el juego esté completo o sea totalmente jugable.

**Última actualización — 9 de noviembre de 2026:** Ya puedo abrir Stray directamente desde el icono de iOS y llegar a un nivel 3D en mi iPhone 17 Pro Max. También comprobé manualmente que responden acciones del juego: puedo correr, saltar, maullar y seguir avanzando aunque el gato no aparezca visualmente. Las pruebas cortas más recientes (Runs 16–17) registraron medianas de aproximadamente 52–53 FPS durante unos 94 segundos, con estado térmico nominal según los logs. Son resultados alentadores, pero no un benchmark de rendimiento sostenido. El resultado visual todavía está lejos de estar completo: el gato, partes del escenario y algunos materiales faltan o se renderizan incorrectamente, y la iluminación/exposición siguen dando problemas.

[English README](README.md) · [Historial técnico](docs/MILESTONES.md) · [Arquitectura](docs/ARCHITECTURE.md) · [Problemas conocidos](docs/KNOWN-ISSUES.md)

---

## Qué estoy intentando hacer

Estoy probando si la build ARM64 original de macOS de Stray puede ejecutarse dentro de un contenedor de aplicación iOS usando la infraestructura de compatibilidad y los shims del proyecto upstream. El ejecutable sigue siendo el binario original de macOS. Mi trabajo incluye conversión del bundle, compatibilidad con APIs de macOS, rutas de recursos, detección de plataforma de Unreal, descubrimiento de GPU mediante IOKit, Metal, renderizado y entrada.

Esto **no** es un port nativo de iOS, una redistribución de Stray, un bypass de DRM ni una prueba de que cualquier juego de Mac pueda ejecutarse en iOS. Es un experimento de compatibilidad que sigue sin terminar.

## Estado actual

### Lo que he comprobado

- Stray abre directamente desde su icono en la pantalla de inicio de mi iPhone 17 Pro Max físico.
- El juego llega a los menús y carga un nivel 3D.
- Probé manualmente acciones dentro del juego: correr, saltar, maullar y continuar la secuencia responden aunque el mesh visual del gato no aparezca.
- Se renderizan partes estáticas del entorno. Capturas anteriores muestran secciones de un túnel/patio con tuberías, estructuras de concreto, cables, vegetación, cielo y efectos atmosféricos.
- Runs 16 y 17 registraron medianas de aproximadamente 52 y 53 FPS, respectivamente, durante unos 94 segundos. Los logs reportan estado térmico nominal en esas muestras. Esto no demuestra rendimiento sostenido, frame pacing ni estabilidad en sesiones largas.
- Los archivos PAK originales del proyecto pudieron abrirse en los logs de las pruebas recientes. Eso confirma que el proceso pudo acceder a los archivos, pero no demuestra que todos los recursos se hayan cargado o renderizado correctamente.
- El shim de GPU Family de AppKit se compiló, firmó e instaló antes de Run 4. Las ejecuciones posteriores avanzaron sin el mismo error fatal de texture view de UE4 en los fragmentos de log disponibles. Es una señal positiva, pero no he demostrado la causalidad con una prueba A/B controlada.

### Lo que sigue fallando o no está claro

- **El gato es invisible.** Las acciones del juego responden, pero su mesh visual no aparece en las capturas.
- Falta una cantidad importante de geometría y contenido visual del nivel, o se renderiza incorrectamente.
- Hay materiales y texturas incompletos, ausentes o mostrados de forma incorrecta en partes de la escena.
- La iluminación y la exposición son inconsistentes; algunas zonas están demasiado oscuras o se ven mal.
- El renderizado de meshes esqueléticos/dinámicos es una de las principales sospechas, pero todavía no he aislado la causa raíz.
- Falta verificar deliberadamente el viewport horizontal y la relación entre los límites de UIKit, `CAMetalLayer.drawableSize` y el viewport de Unreal.
- Todavía no he probado de forma adecuada la estabilidad en sesiones largas, el audio ni el ciclo de segundo plano/primer plano.
- Los FPS más recientes son observaciones de pruebas cortas. No deben interpretarse como prueba de una experiencia estable entre 50 y 60 FPS.

## Posibles causas que estoy investigando

Son hipótesis, no diagnósticos confirmados:

- La creación del scene proxy o la ruta de renderizado de meshes esqueléticos de Unreal en esta implementación de Metal.
- GPU skinning y comportamiento del skin cache.
- Materiales masked, subsurface u otras variantes de materiales/shaders que podrían comportarse distinto en la GPU del iPhone.
- Stencil y LOD dithering, Early Z/profundidad y decisiones de visibilidad/culling.
- GFur u otras rutas de geometría dinámica/plugins.
- Reporte de capacidades de Metal o compatibilidad de formatos y texture views.
- Streaming de recursos, formatos de textura, selección de mipmaps o rutas de carga.
- Iluminación, exposición, sombras y postprocesado que quizá no se adapten bien a este entorno.
- Desajustes entre el tamaño del viewport/drawable o la orientación.

Durante la inspección encontré el mesh del gato y recursos relacionados dentro de los datos originales del juego, así que la ausencia del archivo fuente no es por ahora la explicación principal. Eso tampoco demuestra que el juego esté cargando y enlazando esos recursos correctamente en tiempo de ejecución.

## Entorno de pruebas

- MacBook Air M4, 16 GB de memoria unificada.
- iPhone 17 Pro Max.
- Build original de Stray para macOS Apple Silicon, basada en Unreal Engine 4.
- Metal sobre la GPU Apple del iPhone.
- Capa de compatibilidad: [zorrobyte/macos-on-ios-public](https://github.com/zorrobyte/macos-on-ios-public).

Intento separar los cambios de código, compilaciones, instalaciones, experimentos de configuración y resultados que realmente observé en el teléfono. Los logs cortos, los FPS del overlay y la apertura correcta de los PAK no son prueba de renderizado completo ni de que el juego ya sea jugable.

## En qué me vendría bien ayuda

Me interesa recibir aportes de personas que conozcan el Metal RHI de Unreal Engine, el renderizado de skeletal meshes, GPU skinning, variantes de materiales/shaders, capacidades de Metal, resource streaming o el tamaño de UIKit/CAMetalLayer/viewport.

En concreto, busco ideas para entender por qué se renderiza geometría estática del entorno mientras el mesh esquelético del gato y partes del escenario no aparecen. También serían útiles propuestas de pruebas pequeñas y controladas o instrumentación que ayude a acotar el problema.

## Notas del proyecto

- [Historial técnico](docs/MILESTONES.md)
- [Pruebas de renderizado](docs/RENDERING-FOLLOW-UP.md)
- [Problemas conocidos y matriz de verificación](docs/KNOWN-ISSUES.md)
- [Notas de compatibilidad con Metal](docs/METAL-COMPATIBILITY.md)
- [Arquitectura](docs/ARCHITECTURE.md)

## Proyecto upstream, atribución y distribución

Este trabajo se basa en [zorrobyte/macos-on-ios-public](https://github.com/zorrobyte/macos-on-ios-public). Consulta [UPSTREAM.md](UPSTREAM.md) y la [licencia MIT original](https://github.com/zorrobyte/macos-on-ios-public/blob/main/LICENSE). No reclamo la autoría de la infraestructura de compatibilidad upstream.

No publico el ejecutable de Stray, archivos PAK, recursos extraídos, bundles convertidos, material de firma, perfiles de aprovisionamiento, identificadores del dispositivo ni logs privados. Este es un experimento independiente y no está afiliado ni respaldado por Annapurna Interactive, BlueTwelve Studio, Apple ni el mantenedor del proyecto upstream.
