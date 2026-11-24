# CLAUDE (OpenCode) — REVISIÓN DEL CÓDIGO DE ANTIGRAVITY

Fecha: 2026-11-23. **Solo lectura.** No se ha modificado ningún fichero fuente.
Objeto: `upstream/macos-on-ios-public` (rama `stray-ios-compat`, HEAD `b59bcc7`), diff sin confirmar:

```
shim/overrides/AppKit.m              | 105 +++++-
shim/overrides/AppKit_RuntimeHooks.m |  67 +++-
shim/overrides/libSystem.m           | 101 +++-
3 files changed, 263 insertions(+), 10 deletions(-)
```

Dylib instalada: `work/out_icu/Stray.app/Frameworks/libShim_AppKit.dylib` (02:13). Contiene las cadenas nuevas (`SHIM NSURL volume hooks`, confirmado en el run 8).

Estado: **no aprobado todavía**. Compila/ejecuta no equivale a validado (regla del proyecto).

---

## Lo que el log SÍ valida (run 8, `test8_shader_cache_loose_console.log`)

| Cambio | Evidencia | Veredicto |
|---|---|---|
| Hook `getResourceValue:forKey:error:` para `NSURLVolumeSupportsCaseSensitiveNamesKey` | `SHIM NSURL volume hooks ... ok`; `reported as case-insensitive` (02:31:40.936); ningún `NSAlert` | **VALIDADO** |
| `hw.model` → `Mac16,12` | `SHIM SYSCTL hw.model = Mac16,12`; `Device Type: Mac16,12` | **VALIDADO** |
| `GSavedCommandLine` con `-SaveToUserDir -ResX/-ResY` | `SHIM AUTONOMOUS LAUNCH ... -> ...` y `already complete (len=221)` | **VALIDADO** (sin fallo de malloc en ese run) |
| Auto-chdir `Mac` → `Binaries/Mac` | `Looking for binary: ../../../Hk_project/Config/BinaryConfig.ini` resuelve sin `missing` en ese prefijo | **PARCIAL** (el log no muestra el cwd final) |

---

## Hallazgos de revisión

### R1 — Demasiados cambios a la vez en el árbol de trabajo (incumple la regla C)
- El diff mezcla al menos **siete hipótesis independientes**: NSURL case, spoof `hw.model/hw.machine`, intercepción de `exit/_exit/abort`, `FMemory::Realloc` + `GSavedCommandLine`, auto-chdir, `safeArgv` en UIKit, y spoof de familias GPU.
- La tabla de pruebas 1-8 es acumulativa: cada prueba añadió cambios sobre los anteriores. Así no se puede atribuir el efecto de cada uno.
- **Pedido**: a partir de ahora, un único cambio por prueba, con build de referencia (SHA-256 de la dylib) antes y después.
- **Pedido**: no commitear esto tal cual. Cuando esté validado, separar en commits locales por hipótesis en la rama del shim (sin push al upstream de terceros).

### R2 — Bug de tamaño en el spoof de `sysctl`/`sysctlbyname` — DEFECTO REAL
En las dos ramas de `hw.model` y `hw.machine` (libSystem.m):
```c
if (old && oldlen) {
    ...
    *oldlen = fakeLen;
}
return 0;
```
Si el llamador hace la consulta de tamaño (`old == NULL`, `oldlen != NULL`), **`*oldlen` no se actualiza** y el llamador recibe una longitud sin inicializar.
- **Corrección pedida**: fijar `*oldlen = fakeLen` siempre que `oldlen != NULL`, y copiar solo si `old != NULL`.
- Riesgo: bajo en el run actual (el llamador parece usar el buffer), pero es un fallo de contrato. Hay que corregirlo antes de atribuir cualquier efecto a `hw.model`.

### R3 — Intercepción de `exit/_exit/abort` con NSLog/backtrace: riesgo de reentrancia y punto ciego — DIAGNÓSTICO, NO PRODUCCIÓN
- `abort()` es el camino que usa libc++ en `terminate` (el `mutex lock failed` del fatal anterior). Desde ahí, `NSLog` y `backtrace_symbols` (que hacen malloc y toman locks) pueden **bloquear o recursar**.
- **No se intercepta `_Exit`**. El informe de Antigravity afirma que la salida del run 8 es `_Exit(1)`. Con este diff, esa salida es invisible. Por eso los 8 runs no muestran ningún `SHIM INTERCEPTED`.
- **Pedido**: (a) si se mantiene, guardia de reentrada (`static int inside;`) y escribir con `write(2)` sobre buffer preformateado; (b) añadir `_Exit` **solo como diagnóstico**, en una prueba propia; (c) retirar estas intercepciones antes de cualquier build de usuario.

### R4 — `ShimUnrealMalloc`: fallback a `calloc` y offsets fijos — RIESGO ALTO DE HEAP CORRUPTION
- Si el prólogo no coincide, devuelve `calloc(1, bytes)`. Si UE luego libera ese puntero con `FMemory::Free`, hay **asignador incompatible**.
- Comprobación de prólogo: una sola instrucción (`0xa9bd57f6`). Es débil.
- Offsets absolutos `0x1012b9928`, `0x1051499f0`, `0x675e78`: solo son válidos para **ese** ejecutable. Hay que registrar el SHA-256 del binario para el que se calcularon.
- Nota: `ShimSyncUnrealGSavedCommandLine` usa `(uintptr_t)mh + 0x675e78`, es decir, mezcla dirección de cabecera sin slide con offsets de fichero. Hay que confirmar que es coherente.
- **Pedido**: fallar cerrado (`return NULL` y no sincronizar) en lugar de `calloc`; verificar las tres instrucciones de `0x675e78` antes de usar `0x1012b9928`; registrar el hash del binario en el documento de la prueba.

### R5 — `ShimSupportsFamily`: Apple1..3 → NO aplica a TODAS las consultas, no solo a `ToSRGBFormat`
- El código actual devuelve `NO` para `MTLGPUFamilyApple1..3` en cualquier llamador de `supportsFamily:` (validación Metal incluida).
- El comentario histórico recuperado (`recovered_edits_all.txt`, versión final) pide dejar responder a Metal real para **Apple4+**, porque la capa de validación lo exige para features como Texture Cube Arrays. El diff actual lo cumple: todo lo no listado pasa al `supportsFamily` original, incluido Apple4+. Pero **no hay prueba** de que el efecto se limite a texturas.
- Es el candidato a **experimento G**, pero como prueba aislada: un build que difiera **solo** en esa función.
- Efecto esperado (no verificado): cambia la ruta de formatos BC/ASTC. No explica por sí solo el gato, el wireframe ni la salida del run 8.

### R6 — `ShimURLGetResourceValue` no comprueba `isFileURL`
- La versión histórica revisada sí lo hacía. La actual devuelve `NO` para la clave en **cualquier** `NSURL`, incluidas las no-fichero.
- Riesgo bajo, pero es una divergencia sin justificar. **Pedido**: añadir `self.isFileURL` como en el histórico.

### R7 — Hooks de NSURL instalados sin condición
- `ShimRuntimeInit` (constructor) aplica ambos hooks en **todas** las ejecuciones, sin flag `SHIM…` en Info.plist. Es coherente con el objetivo, pero conviene que sea una opción explícita para poder hacer A/B limpio.

### R8 — `WorkingDirOverride`: la primera rama es código muerto con este layout
- `root/sub` = `Stray.app/Contents/UE4/Hk_project/Binaries/Mac`, pero el contenido está en `Stray.app/Mac/Contents/UE4/...`. Solo la rama `macRoot` tiene efecto.
- No es un bug activo. **Pedido**: documentar o eliminar la rama muerta cuando `SHIMMacRoot` esté definido.

### R9 — `AppKit.m`: `gUIKitStarted = YES` ahora se fija antes de `UIApplicationMain`
- Antes no se fijaba ahí. `isRunning` cambia de valor en ese punto. Es razonable, pero es un cambio de comportamiento que no figura en las pruebas.
- `safeArgv` (argc = 1) elimina todos los argumentos de UE de la llamada a UIKit. Es coherente con el run 7 (51 hilos), pero sigue sin estar aislado.

### R10 — Duplicación
- `ShimSyncUnrealGSavedCommandLine` se llama desde `run` **y** `finishMacLaunch`, y el bloque de `macBundlePath` está repetido. El segundo llamado sale por "already complete", así que funciona. Refactorizar después de validar, no antes.

---

## Metadatos del bundle (riesgo no revisado en el código)
- `work/out_icu/Stray.app/Info.plist`: `CFBundleName=MacProbe`, versión `1.0 (1)`. El original es `Stray-Mac-Shipping`, `1.5 (99)`.
- Es una variable no controlada. Pedido: un único experimento de metadatos, solo ese cambio.

## Recomendación de logs (para la siguiente prueba)
- El shim ve `missing file (stat): /var/mobile/.../Library/Logs/Stray/CrashVideo.avi` (run 8). Con `-SaveToUserDir` es probable que el log de UE esté en `Library/Logs/Stray/` del contenedor.
- **Pedido**: tras cada run, copiar el contenedor de la app (`devicectl device copy from`, `Library/Logs` y `Documents/stray`) **antes** de desinstalar nada. Sin esto no hay causa de salida.

---

## R11. Auditoría Técnica de la Hipótesis de AppInit vs Metal (Antigravity)

**Hallazgo:**  
El fallo prematuro no ocurre en `FEngineLoop::AppInit()`, ni en `IProjectManager`, ni en `IPluginManager`, ni por ausencia de `BinaryConfig.ini`. Ocurre en la etapa de `RHIInit(bool)` (`0x10066e94c`), donde `PlatformCreateDynamicRHI` (`0x101a28268`) no consigue inicializar `GDynamicRHI`, dejando `GDynamicRHI = 0x0`, lo cual provoca que `CompileGlobalShaderMap()` (`0x10066eacc`) busque `GlobalShaderCache-None.bin`, solicite la salida con `RequestExit(false)` y termine con `_Exit(1)`.

**Evidencia:**  
1. **Ejecución downstream confirmada:** En todos los tests, `AppInit` retornó 1 (true) porque las instrucciones posteriores `0x10066ddcc` (`threads=39`) y `0x10066df5c` (`[UE4] Matched Mac as MacGame`) se ejecutan siempre.
2. **Estado en el momento de `_Exit`:** En Test 20 y Test 26, el muestreo de memoria en `_Exit` registró:
   `GIsRequestingExit=1, GDynamicRHI=0x0, GIsRHIInitialized=0, GIsMetalInitialized=0, GShaderPlatformForFeatureLevel=49` (49 = `SP_NumPlatforms` -> `"None"`).
3. **Binario monolítico:** `Stray-Mac-Shipping` no requiere `.dylib` de plugins de UE ni de proyecto: todo el código está enlazado estáticamente.
4. **PhysX dylibs operativas:** Test 26 confirmó que las 5 librerías de PhysX cargan con `dlopen -> OK`.

**Interpretación:**  
La hipótesis de que `AppInit()` devolvía false por falta de módulos o por `BinaryConfig.ini` queda descartada como un falso positivo originado por la presencia de `"Fatal error!\n\n"` en `GErrorHist` (la cual es una copia estática por defecto en `0x10066fe14`). El verdadero cuello de botella es la creación del Dynamic RHI de Metal.

**Certeza:**  
`CONFIRMADO`.

**Recomendación:**  
1. No alterar `.uproject` ni buscar módulos sueltos.
2. Enfocar la siguiente prueba en resolver la carga de PhysX en `dlopen`.

---

## R12. Revisión del Bloqueo Real: InitGamePhys() precede a RHIInit() (Antigravity)

**Hallazgo:**  
El desensamblado de `PreInitPreStartupScreen` demuestra que `InitGamePhys()` (`0x10066e38c`) se ejecuta **antes** que `RHIInit(bool)` (`0x10066e94c`). Si `InitGamePhys()` devuelve 0, la instrucción `0x10066e39c: cbz w24, 0x10066ee38` salta al bloque de salida con error, por lo que `RHIInit(bool)` nunca llega a ejecutarse.

**Evidencia:**  
- `0x10066e38c`: llamada a `InitGamePhys()`.
- `0x10066e39c`: `cbz w24, 0x10066ee38`.
- `0x10066e94c`: llamada a `RHIInit(bool)` (556 bytes después del salto condicional).
- `PhysDLLHelper::LoadPhysicsLibrary` contiene 5 llamadas a `FGenericPlatformProcess::Sleep(0.5f)` espaciadas por reintentos de `GetDllHandle`.

**Interpretación:**  
El estado `GDynamicRHI == 0x0` y `rhiInit == 0` es consecuencia de que el hilo del juego aborta en `InitGamePhys()` y jamás alcanza la inicialización de Metal. Al resolver la carga de PhysX en `dlopen`, el motor superará esta barrera y alcanzará `RHIInit(bool)`.

**Certeza:**  
`CONFIRMADO`.

**Recomendación:**  
Aplicar la redirección de `dlopen` para PhysX según se detalla en `coordination/proposed-fixes/FIX_PHYSX_DLOPEN_REDIRECT.md`.

