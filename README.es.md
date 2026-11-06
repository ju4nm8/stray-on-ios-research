# Stray en iOS — bitácora de investigación

> ¿Es posible ejecutar la build original de **Stray para macOS Apple Silicon** en un iPhone?
>
> Este repositorio documenta un experimento personal de compatibilidad basado en [macos-on-ios-public](https://github.com/zorrobyte/macos-on-ios-public). Es una bitácora técnica, no un port, instalador ni una afirmación de que el juego ya sea completamente jugable.

**Último experimento: Run 6 alcanza un túnel 3D reconocible, con tuberías texturizadas, estructuras de concreto, cables, vegetación, cielo y efectos atmosféricos. El interior del túnel sigue demasiado oscuro, el gato no está claramente confirmado y, aunque los valores de los sticks llegan al shim, todavía no se ha verificado el movimiento ni las acciones dentro del juego.**

[English README](README.md) · [Historial técnico](docs/MILESTONES.md) · [Arquitectura](docs/ARCHITECTURE.md) · [Problemas pendientes](docs/KNOWN-ISSUES.md)

---

## ¿Qué estamos haciendo?

Este proyecto registra el trabajo necesario para ejecutar un binario nativo ARM64 de macOS dentro de un contenedor de aplicación iOS, utilizando la infraestructura de compatibilidad y los shims del proyecto upstream. El ejecutable de Stray sigue siendo la build original de macOS; el trabajo se ha concentrado en la conversión del bundle, compatibilidad con APIs de macOS, detección de plataforma, rutas de recursos, descubrimiento de GPU mediante IOKit y diferencias de Metal.

Esto **no** es un port nativo de Stray, una redistribución del juego, un bypass de DRM ni una prueba de que cualquier juego de Mac pueda ejecutarse en iOS.

## Resultado actual

Entorno de prueba:
- MacBook Air M4, 16 GB de memoria unificada.
- iPhone 17 Pro Max.
- Los overlays mostraron iOS 27.3 beta durante las grabaciones.
- Build para Mac de la generación Unreal Engine 4.27.
- Metal en la GPU Apple del iPhone.
- Para la prueba más reciente se conectó un mando PS4 DualShock 4 al iPhone.

### Fase G — interfaz inicial

Observaciones de fase G:
- El lanzamiento funciona mediante `devicectl` cuando recibe la ruta del proyecto y `-basedir`.
- El adaptador IOKit expone la estructura de descriptor de GPU que Unreal espera, basada en la GPU real del iPhone.
- Unreal supera el camino anterior con la lista de descriptores vacía.
- Hooks específicos de Metal traducen solicitudes observadas de `MTLStorageModeManaged` de macOS a `Shared` de iOS.
- La carga de una biblioteca Metal aparece como correcta en el log.
- Stray muestra el aviso de autosave y la interfaz de calibración de brillo.
- El overlay/log reporta alrededor de 59–62 FPS durante parte de esta sesión corta. No es un benchmark.
- El proceso termina con código 0 después de pasar a segundo plano; no fue el crash anterior de validación Metal.

### Seguimiento — mando y primer intento de cargar una escena

En una grabación posterior:
- El usuario informa que un mando PS4 DualShock 4 conectado permitió avanzar más allá de la calibración de brillo y navegar por la interfaz.
- La grabación muestra un menú de Stray con Resume, Settings y Quit, seguido de una transición a una vista 3D.
- La escena 3D todavía no se representa correctamente: predominan superficies azules/lavadas y artefactos gráficos evidentes. No se distingue claramente al gato ni una escena jugable reconocible; por tanto, **esto todavía no demuestra gameplay funcional**.
- El overlay muestra aproximadamente 19–31 FPS, unos 3.37–3.42 GB de memoria de aplicación y alrededor de 123–184 MB de memoria disponible. Son lecturas de una grabación corta, no un benchmark controlado ni un diagnóstico de presión de memoria.
- La grabación está en vertical (1320 × 2868); no demuestra que se haya corregido la presentación horizontal ni la relación de aspecto.

Más detalle: [notas del mando y primer intento de carga](docs/GAMEPAD-AND-FIRST-LOAD.md), [seguimiento del renderizado (Runs 4–6)](docs/RENDERING-FOLLOW-UP.md) y [compatibilidad con Metal](docs/METAL-COMPATIBILITY.md).

## Lo que falta

1. Diagnosticar el cierre al abrir desde el icono de SpringBoard. La falta de argumentos es plausible, pero no está confirmada.
2. Corregir la presentación y validar dimensiones tanto en vertical como en horizontal mediante UIKit, `CAMetalLayer.drawableSize`, viewport de Unreal y rotación.
3. Resolver la oscuridad del interior y verificar que se renderice toda la escena, especialmente el gato y el suelo; iluminación/exposición, profundidad/culling, materiales, shaders, streaming y cámara/frustum siguen pendientes de prueba.
4. Demostrar gameplay real: personaje y mundo visibles, movimiento, cámara y acciones usando el mando.
5. Probar estabilidad prolongada, temperatura, memoria, audio y ciclo segundo plano/primer plano.

Consulta [problemas pendientes](docs/KNOWN-ISSUES.md) y [plan de pantalla/entrada](docs/DISPLAY-AND-INPUT.md).

## Atribución y distribución

Este trabajo se basa en [zorrobyte/macos-on-ios-public](https://github.com/zorrobyte/macos-on-ios-public). Consulta [UPSTREAM.md](UPSTREAM.md) y su [licencia MIT original](https://github.com/zorrobyte/macos-on-ios-public/blob/main/LICENSE). Esta bitácora no relicencia código upstream ni reclama su autoría.

No subas ejecutables de Stray, PAK, recursos extraídos, certificados, perfiles de aprovisionamiento, identificadores del dispositivo ni paquetes de la aplicación convertida. Este experimento es independiente y no está afiliado ni respaldado por Annapurna Interactive, BlueTwelve Studio o Apple.
