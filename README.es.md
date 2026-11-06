# Stray en iOS — bitácora de investigación

> ¿Es posible ejecutar la build original de **Stray para macOS Apple Silicon** en un iPhone?
>
> Estoy documentando un experimento personal de compatibilidad basado en [macos-on-ios-public](https://github.com/zorrobyte/macos-on-ios-public). Esta es una bitácora de ingeniería, no un port nativo de iOS, un instalador ni una afirmación de que el juego ya sea completamente jugable.

**Última actualización — 6 de noviembre de 2026:** Ya puedo abrir Stray directamente desde su icono en iOS y avanzar dentro del juego. Comprobé manualmente que los controles responden correctamente: puedo correr, saltar, maullar y continuar con la secuencia aunque el gato no aparezca visualmente. Run 9 probó una nueva configuración gráfica y registró una muestra breve de unos 62 FPS, pero siguen faltando recursos del escenario y hay errores importantes de iluminación/renderizado. El bloqueo principal es la integridad visual: el gato invisible y otros elementos que todavía no se dibujan correctamente, no la entrada.

[English README](README.md) · [Historial técnico](docs/MILESTONES.md) · [Arquitectura](docs/ARCHITECTURE.md) · [Problemas pendientes](docs/KNOWN-ISSUES.md)

---

## Qué estoy haciendo

Estoy probando si la build original ARM64 de macOS de Stray puede ejecutarse dentro de un contenedor de aplicación iOS mediante la infraestructura de compatibilidad y los shims del proyecto upstream. El ejecutable sigue siendo el binario original de macOS. Mi trabajo se ha centrado en la conversión del bundle, la compatibilidad con APIs de macOS, las rutas de recursos, la detección de plataforma de Unreal, el descubrimiento de GPU mediante IOKit, Metal, el renderizado y la entrada.

Esto **no** es un port nativo de iOS, una redistribución de Stray, un bypass de DRM ni una prueba de que cualquier juego de Mac pueda ejecutarse en iOS.

## Estado actual

### Lo que ya he comprobado

- Ya puedo abrir Stray directamente desde su icono en la pantalla de inicio de iOS. La apertura directa ya no es un bloqueo actual.
- La aplicación ha llegado a los menús de Stray y ha cargado un nivel 3D en el iPhone 17 Pro Max físico.
- En Run 9 desplegué `Engine_run9.ini` en el contenedor de datos de la app y volví a abrir la build instalada. Metal siguió renderizando; una muestra breve del log registró unos 62 FPS, 1,43 GB de memoria de app, 6,77 GB disponibles y estado térmico nominal. Es una muestra puntual, no un benchmark ni una prueba de 60 FPS sostenidos.
- Comprobé manualmente que los controles sí funcionan dentro del juego: correr, saltar, maullar y otras acciones responden, y puedo seguir avanzando por la partida aunque el mesh visual del gato no aparezca.
- La captura de Run 9 se obtuvo con `devicectl`. El intento alternativo con `screencapture` de macOS falló porque no pudo crear una imagen desde la pantalla.
- Las capturas de Run 6 muestran un túnel reconocible, con tuberías texturizadas, estructuras de concreto, cables/conducciones, vegetación, cielo y efectos atmosféricos.
- El shim de GPU Family de AppKit se compiló, firmó e instaló antes de Run 4. En las ejecuciones posteriores no aparece el mismo error fatal de texture view de UE4 en los fragmentos de log disponibles. Es una señal positiva, aunque todavía no he demostrado la causalidad con una prueba A/B controlada.
- En Run 6, los logs de VGC registraron valores no nulos en los sticks analógicos. Esto confirma que los valores llegan a la ruta de polling del shim, pero no demuestra que Unreal los aplique al movimiento o a la cámara.

### Lo que sigue pendiente

- La escena sigue teniendo errores importantes de iluminación/exposición, zonas demasiado oscuras o desiguales y renderizado incompleto de objetos del entorno.
- El gato sigue sin aparecer en las capturas, aunque sus acciones dentro del juego sí responden. El renderizado del mesh esquelético continúa sin resolverse.
- La investigación apunta a la ruta de meshes esqueléticos/dinámicos; materiales enmascarados, stencil/LOD dithering, Early Z, skinning y GFur son hipótesis de trabajo. Ninguna es todavía una causa raíz demostrada.
- Todavía falta buena parte del contenido visual del nivel o se dibuja incorrectamente. La calidad mejora entre ejecuciones, pero aún es pobre.
- Las muestras de Run 6 variaron aproximadamente entre 38 y 56 FPS, con unos 2,8 GB de memoria de app, 5,3–5,4 GB disponibles y estado térmico `fair`. Son muestras cortas, no un benchmark.
- Tengo capturas en horizontal, pero aún debo verificar de forma deliberada los límites de UIKit, `CAMetalLayer.drawableSize`, las dimensiones del viewport de Unreal y la rotación.
- Faltan pruebas de estabilidad prolongada, audio y ciclo de segundo plano/primer plano.

## Entorno y método de pruebas

- MacBook Air M4, 16 GB de memoria unificada.
- iPhone 17 Pro Max.
- En grabaciones anteriores, el overlay mostraba iOS 27.3 beta; lo registro como la versión que aparecía durante esas capturas, no como confirmación de la versión de todas las pruebas posteriores.
- Build original de Stray para macOS, basada en Unreal Engine 4.
- Metal sobre la GPU Apple del iPhone.
- Mando PS4 DualShock 4 conectado durante las pruebas de control.

Distingo entre cambios de código, compilaciones, instalaciones, experimentos de configuración y resultados comprobados realmente en el teléfono. No trato los FPS del overlay ni las capturas cortas como benchmarks o como prueba de que el juego ya sea completamente jugable.

## Historial técnico

- `docs/MILESTONES.md` registra la conversión, la adaptación de almacenamiento de Metal, la interfaz inicial y las pruebas de renderizado hasta Run 9.
- `docs/METAL-COMPATIBILITY.md` documenta la adaptación Managed/Shared y la investigación posterior de GPU Family.
- `docs/RENDERING-FOLLOW-UP.md` recoge Runs 4–9 y los cambios de configuración.
- `docs/DISPLAY-AND-INPUT.md` registra el trabajo de viewport y controles.
- `docs/KNOWN-ISSUES.md` contiene la matriz de verificación actual.

## Próximas pruebas

1. Corregir el mesh invisible del gato y recuperar el resto de la geometría/materiales que faltan.
2. Corregir iluminación, exposición, sombras y demás defectos visuales sin perder lo que ya se renderiza.
3. Conservar los controles que ya funcionan; volver a investigar la entrada solamente si aparece una regresión reproducible.
4. Revisar la presentación horizontal y comparar las dimensiones de UIKit, el drawable de Metal y el viewport de Unreal.
5. Probar estabilidad, frame pacing, audio y ciclo de vida en sesiones largas cuando el renderizado esté más completo.

## Proyecto upstream, atribución y distribución

Este trabajo se basa en [zorrobyte/macos-on-ios-public](https://github.com/zorrobyte/macos-on-ios-public). Consulta [UPSTREAM.md](UPSTREAM.md) y la [licencia MIT original](https://github.com/zorrobyte/macos-on-ios-public/blob/main/LICENSE). No reclamo la autoría de la infraestructura de compatibilidad upstream.

No publico el ejecutable de Stray, archivos PAK, recursos extraídos, bundles convertidos, material de firma, perfiles de aprovisionamiento, identificadores del dispositivo ni logs privados. Este es un experimento independiente y no está afiliado ni respaldado por Annapurna Interactive, BlueTwelve Studio, Apple ni el mantenedor del proyecto upstream.