# Stray en iOS — bitácora de investigación

> ¿Es posible ejecutar la build original de **Stray para macOS Apple Silicon** en un iPhone?
>
> Este repositorio documenta un experimento personal de compatibilidad basado en [macos-on-ios-public](https://github.com/zorrobyte/macos-on-ios-public). Es una bitácora técnica, no un port, instalador ni una afirmación de que el juego ya sea completamente jugable.

**Hito verificado actual: la build original de macOS llega a la pantalla inicial de calibración de brillo en un iPhone 17 Pro Max.** Todavía no hemos demostrado que llegue al menú principal ni que permita jugar una partida.

[English README](README.md) · [Historial técnico](docs/MILESTONES.md) · [Arquitectura](docs/ARCHITECTURE.md) · [Problemas pendientes](docs/KNOWN-ISSUES.md)

---

## ¿Qué estamos haciendo?

Este proyecto registra el trabajo necesario para ejecutar un binario nativo ARM64 de macOS dentro de un contenedor de aplicación iOS, utilizando la infraestructura de compatibilidad y los shims del proyecto upstream. El ejecutable de Stray sigue siendo la build original de macOS; el trabajo se ha concentrado en la conversión del bundle, compatibilidad con APIs de macOS, detección de plataforma, rutas de recursos, descubrimiento de GPU mediante IOKit y diferencias de Metal.

Esto **no** es un port nativo de Stray, una redistribución del juego, un bypass de DRM ni una prueba de que cualquier juego de Mac pueda ejecutarse en iOS.

## Resultado actual

Entorno de prueba:
- MacBook Air M4, 16 GB de memoria unificada.
- iPhone 17 Pro Max.
- El overlay de rendimiento mostró iOS 27.3 beta durante la grabación.
- Build para Mac de la generación Unreal Engine 4.27.
- Metal en la GPU Apple del iPhone.

Observaciones de fase G:
- El lanzamiento funciona mediante `devicectl` cuando recibe la ruta del proyecto y `-basedir`.
- El adaptador IOKit expone la estructura de descriptor de GPU que Unreal espera, basada en la GPU real del iPhone.
- Unreal supera el camino anterior con la lista de descriptores vacía.
- Hooks específicos de Metal traducen solicitudes observadas de `MTLStorageModeManaged` de macOS a `Shared` de iOS.
- La carga de una biblioteca Metal aparece como correcta en el log.
- Stray muestra el aviso de autosave y la interfaz de calibración de brillo.
- El overlay/log reporta alrededor de 59–62 FPS durante parte de esta sesión corta. No es un benchmark.
- El proceso termina con código 0 después de pasar a segundo plano; no fue el crash anterior de validación Metal.

Llegar a calibración **no** demuestra que el juego sea completamente jugable. Consulta [hitos](docs/MILESTONES.md).

## Lo que falta

1. Diagnosticar el cierre al abrir desde el icono de SpringBoard. La falta de argumentos es una hipótesis, no una causa confirmada.
2. Corregir la presentación horizontal deformada investigando UIKit, `CAMetalLayer.drawableSize`, viewport de Unreal y rotación.
3. Demostrar entrada de extremo a extremo. Se registran toques iniciales de UIKit, pero movimiento, cámara y acciones no están validados en Unreal.
4. Navegar la interfaz, llegar al menú principal e intentar gameplay.
5. Probar estabilidad prolongada, temperatura, memoria, audio y ciclo segundo plano/primer plano.

Consulta [problemas pendientes](docs/KNOWN-ISSUES.md) y [plan de pantalla/entrada](docs/DISPLAY-AND-INPUT.md).

## Atribución y distribución

Este trabajo se basa en [zorrobyte/macos-on-ios-public](https://github.com/zorrobyte/macos-on-ios-public). Consulta [UPSTREAM.md](UPSTREAM.md) y su [licencia MIT original](https://github.com/zorrobyte/macos-on-ios-public/blob/main/LICENSE). Esta bitácora no relicencia código upstream ni reclama su autoría.

No subas ejecutables de Stray, PAK, recursos extraídos, certificados, perfiles de aprovisionamiento, identificadores del dispositivo ni paquetes de la aplicación convertida. Este experimento es independiente y no está afiliado ni respaldado por Annapurna Interactive, BlueTwelve Studio o Apple.
