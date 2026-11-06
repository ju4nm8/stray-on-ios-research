# Stray en iOS — bitácora de investigación

> ¿Es posible ejecutar la build original de **Stray para macOS Apple Silicon** en un iPhone?
>
> Estoy documentando un experimento personal de compatibilidad basado en [macos-on-ios-public](https://github.com/zorrobyte/macos-on-ios-public). Esta es una bitácora de ingeniería, no un port nativo de iOS, un instalador ni una afirmación de que el juego ya sea completamente jugable.

**Última actualización — 6 de noviembre de 2026:** Ya puedo abrir Stray directamente desde su icono en la pantalla de inicio de iOS. En Run 6 también conseguí llegar a un túnel 3D reconocible, con tuberías texturizadas, estructuras de concreto, cables, vegetación, cielo y efectos atmosféricos. El interior sigue demasiado oscuro y todavía no he verificado claramente al gato ni el gameplay completo. El problema anterior de apertura desde el icono ya no está vigente.

[English README](README.md) · [Historial técnico](docs/MILESTONES.md) · [Arquitectura](docs/ARCHITECTURE.md) · [Problemas pendientes](docs/KNOWN-ISSUES.md)

---

## Qué estoy haciendo

Estoy probando si la build original ARM64 de macOS de Stray puede ejecutarse dentro de un contenedor de aplicación iOS mediante la infraestructura de compatibilidad y los shims del proyecto upstream. El ejecutable sigue siendo el binario original de macOS. Mi trabajo se ha centrado en la conversión del bundle, la compatibilidad con APIs de macOS, las rutas de recursos, la detección de plataforma de Unreal, el descubrimiento de GPU mediante IOKit, Metal, el renderizado y la entrada.

Esto **no** es un port nativo de iOS, una redistribución de Stray, un bypass de DRM ni una prueba de que cualquier juego de Mac pueda ejecutarse en iOS.

## Estado actual

### Lo que ya he comprobado

- Ya puedo abrir Stray directamente desde su icono en la pantalla de inicio de iOS. La apertura directa ya no es un bloqueo actual.
- La aplicación ha llegado a los menús de Stray y ha cargado un nivel 3D en el iPhone 17 Pro Max físico.
- Las capturas de Run 6 muestran un túnel reconocible, con tuberías texturizadas, estructuras de concreto, cables/conducciones, vegetación, cielo y efectos atmosféricos.
- El shim de GPU Family de AppKit se compiló, firmó e instaló antes de Run 4. En las ejecuciones posteriores no aparece el mismo error fatal de texture view de UE4 en los fragmentos de log disponibles. Es una señal positiva, aunque todavía no he demostrado la causalidad con una prueba A/B controlada.
- En Run 6, los logs de VGC registraron valores no nulos en los sticks analógicos. Esto confirma que los valores llegan a la ruta de polling del shim, pero no demuestra que Unreal los aplique al movimiento o a la cámara.

### Lo que sigue pendiente

- El interior del túnel se ve mucho más oscuro que el exterior.
- No he confirmado claramente la presencia del gato en las capturas más recientes.
- Todavía no he demostrado movimiento completo del personaje, control de cámara y acciones durante una sesión de gameplay sostenida.
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

- `docs/MILESTONES.md` registra la conversión, la adaptación de almacenamiento de Metal, la interfaz inicial y las pruebas de renderizado hasta Run 6.
- `docs/METAL-COMPATIBILITY.md` documenta la adaptación Managed/Shared y la investigación posterior de GPU Family.
- `docs/RENDERING-FOLLOW-UP.md` recoge Runs 4–6 y los cambios de configuración.
- `docs/DISPLAY-AND-INPUT.md` registra el trabajo de viewport y controles.
- `docs/KNOWN-ISSUES.md` contiene la matriz de verificación actual.

## Próximas pruebas

1. Mejorar la iluminación/exposición del túnel sin romper la escena que ya se renderiza.
2. Capturar claramente al gato y comprobar que siga visible durante el juego.
3. Verificar movimiento, cámara y acciones del DualShock 4 de extremo a extremo en Unreal, no solamente en el polling del shim.
4. Revisar la presentación horizontal y comparar las dimensiones de UIKit, el drawable de Metal y el viewport de Unreal.
5. Hacer una sesión más larga y registrar frame time, memoria, temperatura, audio y ciclo de vida de la aplicación.

## Proyecto upstream, atribución y distribución

Este trabajo se basa en [zorrobyte/macos-on-ios-public](https://github.com/zorrobyte/macos-on-ios-public). Consulta [UPSTREAM.md](UPSTREAM.md) y la [licencia MIT original](https://github.com/zorrobyte/macos-on-ios-public/blob/main/LICENSE). No reclamo la autoría de la infraestructura de compatibilidad upstream.

No publico el ejecutable de Stray, archivos PAK, recursos extraídos, bundles convertidos, material de firma, perfiles de aprovisionamiento, identificadores del dispositivo ni logs privados. Este es un experimento independiente y no está afiliado ni respaldado por Annapurna Interactive, BlueTwelve Studio, Apple ni el mantenedor del proyecto upstream.