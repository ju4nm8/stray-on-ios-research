# Borrador para Reddit — r/macgaming

**Título: ¿Alguien ha investigado cómo ejecutar la versión de macOS de Stray en un iPhone? Estoy atascado con el renderizado**

Hola. Estoy trabajando en un experimento para ver si la versión original de Stray para macOS Apple Silicon puede ejecutarse en un iPhone, usando [macos-on-ios-public](https://github.com/zorrobyte/macos-on-ios-public) como base de compatibilidad.

Ya conseguí que abra desde la pantalla de inicio de iOS y llegue a un nivel 3D real en mi iPhone 17 Pro Max. También puedo correr, saltar, maullar y seguir avanzando, pero la parte visual sigue bastante rota.

Estos son los problemas principales:

- El gato es invisible, aunque sus acciones sí responden dentro del juego.
- No aparecen partes del mapa ni algunos elementos del entorno.
- Faltan texturas y materiales o se muestran de forma incorrecta.
- La iluminación y la exposición son inconsistentes; algunas zonas quedan demasiado oscuras.
- Todavía no sé si el problema está principalmente en los skeletal meshes/skin cache de UE4, en la compatibilidad con Metal, en los shaders/materiales, en el resource streaming, en GFur o en otra parte.

Hay zonas donde sí se renderiza la geometría estática del escenario, así que intento entender por qué esa parte funciona mientras el gato y otros elementos no. He estado revisando la ruta de skeletal meshes de Unreal, GPU skinning, materiales masked, stencil/LOD dithering, Early Z y compatibilidad de formatos/capacidades de Metal, pero todavía no tengo una causa confirmada.

Como referencia, las pruebas cortas más recientes dieron unos 52–53 FPS de mediana durante aproximadamente 94 segundos. Son solo datos de telemetría de sesiones cortas; el juego está lejos de estar completo y no estoy diciendo que ya sea totalmente jugable.

Agradecería mucho ideas de gente que conozca el Metal RHI de Unreal Engine, el renderizado de skeletal meshes, GPU skinning, variantes de shaders o manejo de recursos en iOS/Metal. Incluso una sugerencia para aislar el problema sería de mucha ayuda.

Notas y registros del proyecto: https://github.com/ju4nm8/stray-on-ios-research

Es un experimento personal de compatibilidad que todavía está en desarrollo, no un port nativo de iOS. No estoy compartiendo archivos ni recursos del juego.
