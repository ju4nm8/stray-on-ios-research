# DECISIONS — decisiones técnicas y motivos

1. **Team ID de firma = `<APPLE_TEAM_ID>`**, no `<CERT_COMMON_NAME_ID>`.
   `<CERT_COMMON_NAME_ID>` aparece solo en el Common Name del certificado. El Team ID real (campo OU y
   `TeamIdentifier` de `codesign`) y el que Xcode muestra como "Personal Team" es `<APPLE_TEAM_ID>`.

2. **Original intocable.** Todo se hace sobre `work/Stray.app`, un clon APFS (`cp -c`) verificado por
   hash contra el manifiesto. El original nunca se escribe. Ejecutar la copia en el Mac escribe solo
   dentro de `work/`.

3. **Perfil por `make_profile.sh` de upstream**, con App ID propio `com.ju4nm8.strayios`. No se reutiliza
   la identidad de Stray. El perfil de memoria (`increased-memory-limit`) se genera aparte en `work/T_mem/`.

4. **Stub de descriptor `Hk_project.uproject`** en `Documents/stray/` del contenedor. Es un JSON mínimo
   (`FileVersion` y un comentario) que sustituye a un fichero que el bundle original no tiene. **No es
   contenido del juego.** Se añadió para comprobar si el motor sale por esa ruta. Su efecto sobre el
   modo de arranque está sin verificar (ver `PROJECT_STATUS.md`, bloqueo 1).

5. **Correcciones de shim en rama propia** (`stray-ios-compat`, commits `e3dfe26`, `d9e58dd`, `b59bcc7`).
   Se hicieron en el clon de upstream, con atribución MIT intacta, sin push. Upstream `main` sin cambios.

6. **No se falsifica el hardware ni los datos de ICU.** Se descartó devolver un `Device Type` de Mac
   para forzar la rama de macOS, y crear datos ICU a partir del binario. Ambas cosas son modificar la
   identidad del entorno para hacer pasar una comprobación; se documentan como opciones, no se aplican.

7. **Pruebas cortas y con cierre explícito.** Cada lanzamiento dura 45 s, se comprueba que el proceso
   sigue vivo y se termina por PID (`--kill` cuando el bucle de error no responde). Tras cada prueba se
   confirma que no queda proceso.

8. **Logs de diagnóstico temporales retirados** antes de confirmar (`SHIM DEBUG appparent`). El commit
   `d9e58dd` no los contiene.

9. **Pendiente, no hecho:** sacar los `.pak` del bundle (~6.8 GB, 7.8 GB total) para reducir la
   instalación; corregir la versión mostrada (`1.0 (1)` frente a `1.5 (99)`).
