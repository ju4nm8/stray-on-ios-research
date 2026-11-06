# Stray en iOS — bitácora de investigación

> ¿Es posible ejecutar la build original de **Stray para macOS Apple Silicon** en un iPhone?
>
> Estoy documentando un experimento personal de compatibilidad basado en [macos-on-ios-public](https://github.com/zorrobyte/macos-on-ios-public). Esta es una bitácora de ingeniería, no un port nativo de iOS, un instalador ni una afirmación de que el juego ya sea completamente jugable.

**Última actualización — 6 de noviembre de 2026:** Ya puedo abrir Stray directamente desde su icono en iOS. En la última sesión de Antigravity, la app se volvió a firmar, se instaló y se ejecutó en el iPhone físico; los command buffers de Metal terminaron correctamente y las capturas mostraron un nivel 3D activo. En Runs 7–8 todavía no se ve claramente al gato. El bloqueo actual está en el renderizado del personaje esquelético, no en la apertura de la app ni en el renderizado básico de la geometría estática.

[English README](README.md) · [Historial técnico](docs/MILESTONES.md) · [Arquitectura](docs/ARCHITECTURE.md) · [Problemas pendientes](docs/KNOWN-ISSUES.md)

---

## Qué estoy haciendo

Estoy probando si la build original ARM64 de macOS de Stray puede ejecutarse dentro de un contenedor de aplicación iOS mediante la infraestructura de compatibilidad y los shims del proyecto upstream. El ejecutable sigue siendo el binario original de macOS. Mi trabajo se ha centrado en la conversión del bundle, la compatibilidad con APIs de macOS, las rutas de recursos, la detección de plataforma de Unreal, el descubrimiento de GPU mediante IOKit, Metal, el renderizado y la entrada.

Esto **no** es un port nativo de iOS, una redistribución de Stray, un bypass de DRM ni una prueba de que cualquier juego de Mac pueda ejecutarse en iOS.

## Estado actual

### Lo que ya he comprobado

- Ya puedo abrir Stray directamente desde su icono en la pantalla de inicio de iOS. La apertura directa ya no es un bloqueo actual.
- La aplicación ha llegado a los menús de Stray y ha cargado un nivel 3D en el iPhone 17 Pro Max físico.
- En la última sesión, los render encoders y command buffers de Metal estuvieron activos en el dispositivo; el log de Run 8 registró una muestra de unos 40 FPS, 3,0 GB de memoria de app, 5,2 GB disponibles y estado térmico nominal. Es una muestra corta, no un benchmark.
- Run 7 mostró un escenario 3D detallado de patio/túnel y una transición breve de la máscara de botones del mando (`0x0001`); eso no demuestra que una acción dentro del juego haya funcionado.
- Las capturas de Run 6 muestran un túnel reconocible, con tuberías texturizadas, estructuras de concreto, cables/conducciones, vegetación, cielo y efectos atmosféricos.
- El shim de GPU Family de AppKit se compiló, firmó e instaló antes de Run 4. En las ejecuciones posteriores no aparece el mismo error fatal de texture view de UE4 en los fragmentos de log disponibles. Es una señal positiva, aunque todavía no he demostrado la causalidad con una prueba A/B controlada.
- En Run 6, los logs de VGC registraron valores no nulos en los sticks analógicos. Esto confirma que los valores llegan a la ruta de polling del shim, pero no demuestra que Unreal los aplique al movimiento o a la cámara.

### Lo que sigue pendiente

- El interior del túnel se ve mucho más oscuro que el exterior.
- No he confirmado el mesh esquelético del gato en las capturas más recientes. La primera captura de Phase J1 se interpretó inicialmente como si mostrara al gato/la mochila, pero las capturas posteriores y la revisión más profunda no corroboraron esa lectura; por eso mantengo su visibilidad como no verificada.
- La investigación más reciente apunta a un fallo específico de renderizado de meshes esqueléticos (y posiblemente del componente GFur asociado), mientras la geometría estática del nivel sí aparece. GPU skinning, materiales/shading y los scene proxies dinámicos siguen siendo hipótesis, no una causa raíz demostrada.
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

1. Resolver el renderizado de meshes esqueléticos y conseguir que el gato se vea claramente; validar por separado un posible fallback de GFur.
2. Mejorar la iluminación/exposición del túnel sin romper la geometría estática.
3. Verificar movimiento, cámara y acciones del DualShock 4 de extremo a extremo en Unreal, no solamente a partir de los logs de ejes o máscaras de botones.
4. Revisar la presentación horizontal y comparar las dimensiones de UIKit, el drawable de Metal y el viewport de Unreal.
5. Hacer una sesión más larga y registrar frame time, memoria, temperatura, audio y ciclo de vida de la aplicación.

## Proyecto upstream, atribución y distribución

Este trabajo se basa en [zorrobyte/macos-on-ios-public](https://github.com/zorrobyte/macos-on-ios-public). Consulta [UPSTREAM.md](UPSTREAM.md) y la [licencia MIT original](https://github.com/zorrobyte/macos-on-ios-public/blob/main/LICENSE). No reclamo la autoría de la infraestructura de compatibilidad upstream.

No publico el ejecutable de Stray, archivos PAK, recursos extraídos, bundles convertidos, material de firma, perfiles de aprovisionamiento, identificadores del dispositivo ni logs privados. Este es un experimento independiente y no está afiliado ni respaldado por Annapurna Interactive, BlueTwelve Studio, Apple ni el mantenedor del proyecto upstream.