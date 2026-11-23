# Stray en iOS — Investigación de Compatibilidad Técnica

> ¿Puede ejecutarse la versión original de Stray para macOS Apple Silicon dentro de una aplicación iOS en un iPhone físico?

**Este es un experimento independiente de compatibilidad que sigue incompleto. No es un port oficial de iOS y el juego todavía no es visualmente jugable.**

[Estado del dispositivo y revisión comunitaria](COMMUNITY-REVIEW.md) · [Estado del proyecto](PROJECT_STATUS.md) · [Hoja de ruta](ROADMAP.md) · [Arquitectura](docs/ARCHITECTURE.md) · [Bloqueos actuales](docs/CURRENT_BLOCKERS.md)

## Resultado actual — 2026-11-23

La aplicación adaptada ya se instala y se inicia en un iPhone 17 Pro Max con iOS 27.3. Muestra elementos de interfaz y menús, y reconoce un DualShock 4.

La presentación 3D sigue fallando:
- La escena del menú/título de Stray no muestra visiblemente al gato de ojos blancos, el logotipo de Stray ni el fondo esperado. La pantalla queda negra salvo por los elementos de interfaz.
- Al iniciar la partida no aparece visiblemente el mundo 3D.
- La aplicación aparece inicialmente en vertical; al girar a horizontal la imagen queda extremadamente estirada.
- Los controles táctiles minimalistas y sensibles a la conexión de un mando todavía deben implementarse y probarse.

Se ha observado carga de bibliotecas Metal, creación de render encoders, presentación de drawables y command buffers completados. Estos eventos no demuestran que la geometría de la escena de Unreal ni la imagen final se estén renderizando correctamente.

El último exit code 9 reportado ocurrió porque el usuario cerró manualmente la aplicación. **No fue un crash.**

Consulta [COMMUNITY-REVIEW.md](COMMUNITY-REVIEW.md) para ver las observaciones, la ayuda técnica solicitada y los límites seguros de publicación.

## En qué necesitamos ayuda

1. Orientación UIKit, geometría de ventanas/vistas, dimensiones de CAMetalLayer y viewport de Unreal.
2. UE4 Metal RHI, render passes, shaders/pipeline state, draw calls e inspección de render targets.
3. Cámara, carga de niveles, meshes, materiales, texturas, iluminación y postprocesado.
4. Integración de GameController / DualShock 4 y controles táctiles minimalistas.

Son bienvenidas las revisiones técnicas y los hallazgos reproducibles. Utiliza la [plantilla de revisión técnica](.github/ISSUE_TEMPLATE/technical-review.yml).

## Límites de publicación

Este repositorio puede contener código de investigación original, logs sanitizados, fragmentos de configuración, notas técnicas y pequeños bancos de prueba, siempre después de revisar su procedencia y privacidad.

No debe contener ejecutables de Stray, bundles de la aplicación, archivos PAK/UCAS/UTOC, recursos extraídos, texturas, modelos, audio, certificados de Apple, perfiles de aprovisionamiento, claves privadas, credenciales, tokens ni identificadores privados del dispositivo. El código de terceros solo puede redistribuirse cuando su licencia lo permita y se conserven los avisos requeridos.

Quienes revisen el proyecto deben poseer una copia legítima del juego y utilizar sus propios archivos locales. Consulta [UPSTREAM.md](UPSTREAM.md), [PUBLISHING-SCOPE.md](PUBLISHING-SCOPE.md) y [CONTRIBUTING.md](CONTRIBUTING.md).

## Estado de desarrollo

| Área | Estado |
|---|---|
| Instalación y arranque de la app | Verificado en iPhone físico |
| Interfaz y menús | Visibles |
| Reconocimiento del DualShock 4 | Observado |
| Orientación horizontal / relación de aspecto | Incorrecta |
| Escena 3D del menú de Stray | No se renderiza visiblemente |
| Mundo 3D del gameplay | No se renderiza visiblemente |
| Controles táctiles | Incompletos / planeados |
| Audio | Sin verificar |
| Rendimiento sostenido y temperatura | Sin verificar |

Ninguna etapa se considera completada únicamente porque la aplicación arranque o porque se completen command buffers de Metal. El renderizado 3D debe confirmarse visualmente en el dispositivo físico.

## Proyecto upstream

La infraestructura de compatibilidad deriva de [zorrobyte/macos-on-ios-public](https://github.com/zorrobyte/macos-on-ios-public). Este repositorio distingue la infraestructura heredada de la investigación específica de Stray y no reclama propiedad sobre el juego ni sus recursos.
