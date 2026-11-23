# BUG → SOURCE MAP — Stray 1.5#99 (ARM64/iOS) sobre `macos-on-ios-public`

Fecha: 2026-11-23. Autor: OpenCode.
Ámbito: unir **cada síntoma observado** con **evidencia literal**, **fuente de código** (propia o externa)
y **experimento A/B de una variable**. No se ha aplicado ningún cambio.

Etiquetas: `VERIFICADO` (log/fichero:línea), `HIPÓTESIS`, `PENDIENTE`, `REFUTADO`, `RESUELTO`.

Regla de oro: un bug solo pasa a `RESUELTO` con evidencia de **render + input + audio** verificados
en el mismo run. Ningún bug de esta lista lo está todavía.

---

## 0. Tabla resumen

| ID | Síntoma | Estado | Fuente principal | Experimento |
|---|---|---|---|---|
| BUG-001 | `ICU data directory was not discovered` | **RESUELTO** (fatal eliminado) | `SHIMPathRedirects` + árbol `icudt64l` | ICU-A (hecho) |
| BUG-002 | `does not support running from case-sensitive file systems` → signal 6 | **ACTIVO — bloqueo actual** | `ShimURLGetResourceValue` histórico | **A** |
| BUG-003 | Gato no visible | ABIERTO | `CatPawn.h:114`, `BP_CatPawn.hpp:83`, `Engine.ini:892` | **B/C/D** |
| BUG-004 | Pantalla negra / sin render | ABIERTO (parcial: Run 11 renderizó) | `AHKPlayerCameraManager`, `CameraThirdPerson` | A → B |
| BUG-005 | Wireframe blanco + líneas rojas (Run 11) | ABIERTO | `HKPlayerController.h:74-80`, `BP_CatPawn.hpp:15-17`, `AppKit_RuntimeHooks.m:242-247` | **G → E** |
| BUG-006 | Input táctil/mando no verificado | PARCIAL | `AppKit.m:836-838`, `main.lua:18-25` | F |
| BUG-007 | Audio nunca verificado | PENDIENTE | `AudioManager.h`, `HKGameUserSettings` | posterior |
| BUG-008 | Referencias destruidas tras recarga | RIESGO | `main.lua:54-57` | diseño |
| BUG-009 | `mutex lock failed` / MainThread | ABIERTO | `NSAlert` → abort; `GameThreadCall(bWait)` | A (observar) |
| BUG-010 | Spoof GPU incompleto (Apple1..3 no suprimidas) | **VERIFICADO + G** | `AppKit_RuntimeHooks.m:242-247` vs `recovered_edits_all.txt` | **G** |
| BUG-011 | “60 FPS” / “gato visible” históricos | **REFUTADO** | capturas reales | — |
| BUG-012 | `profile has not been explicitly trusted` | **TRANSIENTE** | reinstalación | — |

---

## BUG-001 — ICU data directory was not discovered

**Estado: `RESUELTO` como fatal. No implica jugabilidad.**

### Síntoma literal

Run 10 (`artifacts/logs/launch10_console.log`):

```
ICU data directory was not discovered
```

Run ICU-A (`artifacts/logs/icu_test/launch_retry.log`):

```
grep -c "ICU data directory was not discovered" → 0
```

### Evidencia

- `VERIFICADO`: el árbol extraído del PAK tiene **3.463 ficheros / 22.072.253 B**.
- `VERIFICADO`: el open order externo (`DOMEHero/EditorOpenOrder.log` + `CookerOpenOrder.log`) tiene
  **893 rutas únicas** `icudt64l/*`; **0 faltan** en nuestro PAK (el PAK tiene 2.570 extra).
- `VERIFICADO`: `Engine.ini:1787` `DirectoryIndexKeepFiles=*/Content/Internationalization/*`.
- `VERIFICADO`: en el run ICU-A siguen apareciendo faltantes **solo** de:
  ```
  SHIM missing file (open): ../../../Engine/Content/Internationalization/icudt64l/lang/en_US_POSIX.res
  SHIM missing file (open): ../../../Engine/Content/Internationalization/icudt64l/lang/en_US.res
  SHIM missing file (open): ../../../Engine/Content/Internationalization/icudt64l/region/en_US_POSIX.res
  SHIM missing file (open): ../../../Engine/Content/Internationalization/icudt64l/region/en_US.res
  ```
  Ni el PAK ni el open order de referencia contienen `lang/en_US.res` ni `region/en_US.res`.
  ICU cae a `en.res`. **No es un fallo del redirect.**
- `HIPÓTESIS fuerte`: el loader de ICU usa el filesystem real, no el VFS del PAK; por eso el PAK por sí
  solo no basta y hay que extraer a `Documents/stray/StrayICU`.
- `VERIFICADO`: el `stat` de `../../../.../Content/Internationalization` **no** aparece como missing;
  solo el primer candidato GUID (`../../../0EE11112-.../Content/Internationalization`) falla. Eso es
  coherente con que el redirect sí resolvió la ruta de `Engine/Content/...` al árbol copiado.
- Nota: `grep "SHIM redirect"` = 0 en `launch_retry.log`. El shim **no** imprime una línea por redirect;
  la ausencia de log no prueba nada.

### Fuente

- Propia: `upstream/macos-on-ios-public/shim/overrides/libSystem.m:15-35,104-121` (`SHIMPathRedirects`,
  `RedirectOnly`, `FixCase`).
- Config: `work/out_icu/Stray.app/Info.plist` → `SHIMPathRedirects["Internationalization"] =
  "Documents/stray/StrayICU"`.

### Criterio de aceptación

Ya cumplido: desaparece el fatal ICU y el motor avanza al siguiente chequeo.

---

## BUG-002 — Case-sensitive file system abort (bloqueo actual)

**Estado: `ACTIVO`. Es el siguiente bloqueo real.**

### Síntoma literal (`artifacts/logs/icu_test/launch_retry.log:44-49`)

```
SHIM NSAlert runModal: Unreal Engine does not support running from case-sensitive file systems. |
Please install the application on a drive formatted as case-insensitive.
libc++abi: terminating due to uncaught exception of type std::__1::system_error: mutex lock failed: Invalid argument
SHIM FAULT signal 6 address 0x258cfc1fc
SHIM FAULT pc 0x258cfc1fc = libsystem_kernel.dylib+0xb1fc (__pthread_kill)
[UE4] Spinning after fatal error..
```

### Causa localizada

`VERIFICADO` — el shim histórico resolvía exactamente este chequeo
(`work/antigravity/fulltext/eaa6cb79-3600-4d81-9e51-9bd35ce10c56/step_00003.txt:53-69`):

```objc
static IMP gURLGetResourceValue;
static BOOL ShimURLGetResourceValue(NSURL *self, SEL _cmd, id __autoreleasing *value,
                                    NSURLResourceKey key, NSError *__autoreleasing *error) {
    if ([key isEqualToString:NSURLVolumeSupportsCaseSensitiveNamesKey] && self.isFileURL) {
        if (value) *value = @NO;
        if (error) *error = nil;
        static int logged;
        if (logged++ < 3) NSLog(@"SHIM: file URL %@ reported as case-insensitive", self.path);
        return YES;
    }
    return ((BOOL (*)(id, SEL, id __autoreleasing *, NSURLResourceKey,
                      NSError *__autoreleasing *))gURLGetResourceValue)(self, _cmd, value, key, error);
}
```

`VERIFICADO` — el clon actual **no** contiene `NSURLVolumeSupportsCaseSensitiveNamesKey`
(`grep -rn` = 0 en `upstream/macos-on-ios-public/shim`).

`VERIFICADO` — el shim actual solo normaliza rutas libc con `FixCase`
(`libSystem.m:122`), que **no cubre** la consulta NSURL que hace UE4.27.

### Hipótesis

- `HIPÓTESIS fuerte`: UE4.27 pregunta `NSURLVolumeSupportsCaseSensitiveNamesKey` sobre el volumen de
  la app; el APFS del iPhone responde “sí” y el motor aborta. Devolver `NO` para file URLs desbloquea.
- `PENDIENTE`: confirmar que el chequeo pasa por `-[NSURL getResourceValue:forKey:error:]` y no por
  `statfs`/`getattrlist` directo. Si fuera `statfs`, `FixCase` tampoco ayudaría y haría falta otro hook.
- `HIPÓTESIS`: `mutex lock failed` es **consecuencia** del `NSAlert`/abort (se dispara al intentar
  mostrar UI o registrar el fatal), no un bug independiente. Se resolverá o cambiará al pasar BUG-002.

### Experimento A (una variable)

1. Reintroducir **solo** `ShimURLGetResourceValue` en `libSystem.m` (o `AppKit.m`), con `swizzle` de
   `-[NSURL getResourceValue:forKey:error:]` en `+load`.
2. Recompilar shim, re-firmar, instalar sobre el build ICU-A **sin** tocar el árbol ICU ni la config.
3. Lanzar 60 s y capturar log.

**Éxito medible**: desaparece la línea `NSAlert runModal: Unreal Engine does not support running from
case-sensitive file systems` y aparecen logs de inicialización posteriores (p. ej. `Device Type`,
`Looking for binary`, carga de mapa). **Fracaso**: el mismo `NSAlert` o un nuevo fatal distinto.

**Riesgo**: bajo (un hook de una API de solo lectura). **No** mezclar con parches de visibilidad.

---

## BUG-003 — Gato no visible

**Estado: `ABIERTO`. Dos hipótesis con base; ninguna verificada.**

### Síntoma

- Run 10/11: no se identifica al gato en las capturas recuperadas
  (`work/antigravity/recovered_images/671dc9b1_step00536_*.jpg`, `..._544_*.jpg`).
- `REFUTADO`: el informe de Antigravity que afirmaba “Run 12 gato visible (1483 px, bbox a pantalla
  completa)”. No hay captura original de Run 12; el análisis de píxeles no era fiable.

### Hipótesis 3.1 — Límite de huesos móvil (prioridad alta)

- `VERIFICADO`: `work/external/reference_files/DOMEHero/Engine.ini:892`
  ```
  MaxSkinBones=(Default=65536,PerPlatform=(("Mobile", 256)))
  ```
  En móvil, 256 huesos; en escritorio, 65.536.
- `VERIFICADO`: el gato usa `USkeletalMeshComponent* m_visual` (`CatPawn.h:114`) y
  `GetSkeletalMesh()` (`CatPawn.h:1364`).
- `VERIFICADO`: los parches históricos atacan justo ese código
  (`work/antigravity/recovered_files/B_178_iterate_stray.sh:16-21`): NOP en
  `USkinnedMeshComponent::CreateSceneProxy` (bone limit, `0x2fd68c0`), `bHideSkin` (`0x2fd67f0`) y
  `CreateRenderState_Concurrent` (`0x2fd6e44`).
- `HIPÓTESIS fuerte`: si el mesh de 1.5#99 supera 256 huesos, el skinning móvil descarta secciones o
  el proxy completo.
- **Matiz obligatorio (corrección del informe de Antigravity)**: `PerPlatform=(("Mobile", 256))`
  depende de la plataforma de cocción/runtime (`IniPlatformName`), **no** de `supportsFamily:`.
  Nuestro PAK es `pakchunk0-MacNoEditor.pak` (Mac); el valor “Mobile” podría **no aplicarse**.
  `MTLGPUFamilyApple1` afecta a formatos de textura BC→ASTC (`ToSRGBFormat`), no al límite de huesos.
- `PENDIENTE`: medir la plataforma efectiva (`IniPlatformName`) y contar huesos del asset real; no
  asumir el límite de 1.3 para 1.5.

### Hipótesis 3.2 — `HiddenInGameplay`

- `VERIFICADO`: `BP_CatPawn.hpp:83` declara `bool HiddenInGameplay; // 0x3A34 (size: 0x1)` (1.3#214).
- `HIPÓTESIS`: un estado de menú/cinemática/transición deja el flag activo; el render funciona pero el
  gato no se dibuja.
- `VERIFICADO`: el juego **sí** usa ocultación estándar: `main.lua:299-303` llama
  `p2.Pawn:SetActorHiddenInGame(on)` en cinemáticas.
- `PENDIENTE`: leer el valor por defecto y los escritores de `HiddenInGameplay` en el asset 1.5.

### Hipótesis 3.3 — Componentes de render (menor)

`VERIFICADO` en `BP_CatPawn.hpp` (1.3#214): `UGFurComponent* GFur` (`:21`),
`USceneCaptureComponent2D* SceneCaptureComponent2D` (`:20`), `UDrawMovementComponent* DrawMovement1/2/3`
(`:15-17`), `UWidgetComponent* Widget` (`:12`), `USpringArmComponent` + 4 `UPointLightComponent`
(`:27-30`). Si GFur o SceneCapture fallan en Metal, el mesh base debería seguir visible; por sí solos
no explican un gato totalmente ausente.

### Lo que NO explica la invisibilidad

`REFUTADO` como causa: los parches históricos de visibilidad forzada (`IsVisible`,
`ShouldComponentAddToScene`) **añaden** geometría; es más probable que revelen debug que oculten al gato.

### Experimentos

- **B** (solo lectura): UAssetAPI sobre el `.uasset` del gato 1.5 → `HiddenInGameplay`, huesos, GFur.
- **C**: override de `MaxSkinBones`/skin cache para móvil.
- **D**: desactivar GFur/SceneCapture en config o asset.

**Éxito medible**: el gato aparece en captura con render 3D estable. **No** vale un análisis de
píxeles sin imagen original.

---

## BUG-004 — Pantalla negra / sin render

**Estado: `ABIERTO`; parcialmente acotado.**

### Evidencia

- `VERIFICADO`: Run 11 sí renderizó escena 3D texturizada con HUD `19.51 FPS`
  (`671dc9b1_step00536_*.jpg`), así que el pipeline Metal **puede** dibujar en iOS.
- `VERIFICADO`: Run 10 muestra escena vacía a `19.81 FPS`; no prueba render de gameplay.
- `PENDIENTE`: no hay captura del run ICU-A (abortó antes de render).

### Fuentes relevantes

- `AHKPlayerCameraManager` (`HKPlayerCameraManager.h`): `PushCamera`/`PopCamera`, `CameraChanged`.
- `ACameraThirdPerson` (`CameraThirdPerson.h:32-35,59-62`): `m_armRoot`, `m_camera`,
  `m_collisionsAvoidanceEnabled`, `m_collisionAvoidanceRadius`.
- `AHKPlayerController` (`HKPlayerController.h:50,53`): `m_cameraManager`, `m_catPawn`.
- `main.lua:141-160`: el camera manager lee `PCOwner->Pawn` en `BeginPlay`; si `PCOwner` es nulo,
  crash (`0x258`). `VERIFICADO` como problema de **segundo jugador en Windows**.

### Hipótesis

- `HIPÓTESIS media`: auto-continue/menú deja la vista en una cámara de menú o cinemática sin mundo.
- `HIPÓTESIS baja`: el orden `PCOwner`/`InitializeFor` se rompe en iOS (no creamos P2).
- `HIPÓTESIS baja`: fallo de presentación Metal/CAMetalLayer, no de escena.

### Criterio

Distinguir “no hay escena” de “hay escena pero cámara negra” con captura + logs de `ViewTarget` y
`CameraChanged`. No tocar cámara antes de resolver BUG-002.

---

## BUG-005 — Wireframe blanco + líneas rojas (Run 11)

**Estado: `ABIERTO`. Candidatos concretos; ninguno confirmado.**

### Evidencia visual

`671dc9b1_step00536_*.jpg`: escena texturizada, overlay táctil, HUD `19.51 FPS`, **líneas rojas largas**
y **wireframe blanco masivo** sobre rejas/rampas; pirámide texturizada con un ojo. No se identifica al gato.

### Candidatos (orden de probabilidad)

0. **Familias GPU Apple no suprimidas — `VERIFICADO` como delta, `HIPÓTESIS` como causa**
   - `VERIFICADO`: el clon actual solo hace `if (family == MTLGPUFamilyMac2) return YES;`
     (`AppKit_RuntimeHooks.m:244-247`). **No** devuelve `NO` para `MTLGPUFamilyApple1..3`.
   - `VERIFICADO`: los edits históricos (`recovered_edits_all.txt`) sí las suprimen, con este motivo
     textual: en `ToSRGBFormat` (`0x10123071c`), si el device responde `YES` a
     `MTLGPUFamilyApple1`, UE4 asume build iOS y mapea texturas por la tabla **ASTC**, corrompiendo
     **BC1..BC7** (“dropping them to linear / unrendered”); con `NO` toma la rama Mac1
     (`0x101230790`).
   - `HIPÓTESIS fuerte`: explica superficies blancas/lineales o “unrendered” (y quizá el aspecto
     lavado de Run 11), pero **no** las líneas rojas ni el wireframe geométrico.
   - **Distinción**: si el problema es universal por material/textura, es esta ruta; si solo afecta a
     primitivas de suelo/navmesh, es el debug walkable (candidato 1).
   - **Experimento G** (solo shim, bajo riesgo), antes que E.
1. **Debug de superficies caminables — `HIPÓTESIS fuerte`**
   - `HKPlayerController.h:74` `TArray<FWalkableDebuggedPrimitive> m_walkableDebuggedPrimitives;`
   - `:77` `UMaterialInterface* m_walkableDebugMaterial;`
   - `:80` `UMaterialInterface* m_movementObstacleDebugMaterial;`
   - `:106` `void SetWalkableDebugModeEnabled(bool _enabled);`
   - `WalkableDebuggedPrimitive.h`: `TArray<UMaterialInterface*> Materials`.
   - Encaja con “massive” y con el patrón rojo/blanco de colisión/suelo.
2. **`DrawMovementComponent` del gato — `HIPÓTESIS`**
   - `BP_CatPawn.hpp:15-17` `DrawMovement1/2/3` (plugin JoyLibrary). Podría dibujar splines/probes;
     las líneas rojas largas encajan. `PENDIENTE`: el plugin no está en los repos clonados.
3. **Colores de LOD / material de huesos — `HIPÓTESIS débil`**
   - `Engine.ini:160-167` `LODColorationColors` blanco/rojo/verde/azul;
     `Engine.ini:106` `BoneWeightMaterialName=.../BoneWeightMaterial`. Dan color plano, no wireframe.

### Explicación histórica probable

`HIPÓTESIS`: los parches de visibilidad forzada (`0x2fb20c0`, `0x2faf8e4`, `0x2f8c68c`) hacen visible
lo que el juego oculta; si entre esos componentes están walkable debug o DrawMovement, aparece este
wireframe. **No** atribuirlo al shim sin A/B.

### Experimento E

Comparar build **actual sin parches de visibilidad** vs build histórico parcheado, mismo mapa y misma
posición. La diferencia aísla el origen. **Alto riesgo**: no ejecutar hasta cerrar BUG-002 y sin tocar
geometría del juego.

---

## BUG-006 — Input táctil / mando

**Estado: `PARCIAL`. Nunca verificado end-to-end.**

### Evidencia

- `VERIFICADO`: el shim actual tiene polling de `GCController`
  (`upstream/macos-on-ios-public/shim/overrides/AppKit.m:836-838`).
- `VERIFICADO`: `ShimVirtualGamepad`, `ShimTouchOverlayView`, `SHIM_AUTO_CONTINUE` **no existen** en el
  clon actual (`grep` = 0).
- `VERIFICADO` (histórico): existen fragmentos recuperados
  `work/antigravity/recovered_appkit/00436_AppKit.m_2225-2300_ShimTouchOverlayView.m` y
  `01351_AppKit.m_1850-1900_GameControllerPolling.m`.
- `VERIFICADO` (externo): semántica de `ControllerId`/`bOffsetPlayerGamepadIds` en `main.lua:18-25,81-97`;
  Unreal entrega el gamepad *N* al local player con `ControllerId` *N* (o *N+1* con el flag);
  teclado/ratón siempre ID 0.
- `VERIFICADO` (externo): `UDebugInputComponent` (`DebugInputComponent.h`) expone botones/ejes como
  delegados — mapa de nombres de input que espera el juego.

### Hipótesis

- `HIPÓTESIS`: el gamepad virtual histórico no publica el `ControllerId` correcto o Stray 1.5 no lee
  `bOffsetPlayerGamepadIds` en arranque automático.
- `HIPÓTESIS`: el overlay táctil actual no traduce a ejes UE (solo a toques UIKit).

### Criterio

Un run con render + movimiento del gato medible (posición cambia) + cámara responde. Sin eso, no hay
input verificado.

---

## BUG-007 — Audio

**Estado: `PENDIENTE` absoluto.**

- `VERIFICADO`: `AudioManager.h` es mínimo en 1.3 (`m_maxAudioHolderTicksPerFrame`); no concluye nada.
- `VERIFICADO`: `HKGameUserSettings` expone `MasterVolume`, `MusicVolume`, `EffectsVolume`, `bUseVSync`,
  `FrameRateLimit` (`HK_Project/Config/DefaultGameUserSettings.ini`).
- `VERIFICADO`: `Engine.ini:819-825` `[Audio] UseAudioThread=true`, `EnableAudioMixer=false`,
  `UnfocusedVolumeMultiplier=0.0`.
- `PENDIENTE`: no existe ninguna verificación de audio en iOS. No declarar audio “funcional”.

**Criterio**: audio audible/capturado con el juego en gameplay, no solo inicialización de submix.

---

## BUG-008 — Referencias destruidas tras recarga de nivel

**Estado: `RIESGO` de diseño (no bug observado aún).**

- `VERIFICADO` (externo, `main.lua:54-57`): Stray recarga el nivel al morir el gato; conservar
  controllers/pawns/widgets entre llamadas rompe UE4SS. Solo el `GameInstance` vive toda la sesión.
- `VERIFICADO` (externo, `main.lua:232-264`): si P2 no tiene gato, `RestartPlayer` tras 3 s y teleport.
- `VERIFICADO` (externo, `main.lua:289-346`): tras cinemática, espera a que P1 esté quieto
  (3 ticks × 250 ms) y reagrupa hasta 15 s.
- `HIPÓTESIS`: cualquier auto-continue/teleport del shim debe releer del `GameInstance`, nunca cachear.

**Acción**: revisar el código del shim que guarde punteros a actores entre frames.

---

## BUG-009 — `mutex lock failed` / MainThread

**Estado: `ABIERTO`; probablemente secundario a BUG-002.**

- `VERIFICADO`: el `mutex lock failed: Invalid argument` aparece **inmediatamente después** del
  `NSAlert` de case-sensitivity (`launch_retry.log:44-45`), en el hilo principal.
- `HIPÓTESIS fuerte`: es el mecanismo de aborto de UE tras el fatal (o el `NSAlert` bloqueando el
  runloop), no un bug de sincronización independiente.
- `VERIFICADO` (histórico): el shim usa `ShimContextSwitch(&gGameContext, &gUIKitContext)` y
  `GameThreadCall(block, modes, bWait=true)`
  (`work/antigravity/recovered_appkit/00289_*.m`, `work/antigravity/fulltext/e5026e30-*/all.txt`).
- `HIPÓTESIS`: bloquear el runloop con `bWait=true` durante transiciones puede producir errores de
  MainThread. `PENDIENTE`: no hay stack de un MainThread error actual.
- `REFUTADO` como causa del run ICU-A: el mutex falla **después** del alert, no antes.

**Acción**: no tocar hilos hasta repetir el experimento A; observar si el mutex desaparece al pasar
el chequeo.

---

## BUG-010 — Spoof GPU incompleto (Apple1..3 no suprimidas)

**Estado: delta `VERIFICADO`; efecto `HIPÓTESIS`.**

- `VERIFICADO`: el shim actual solo reclama Mac2 y deja que el device real responda al resto
  (`shim/overrides/AppKit_RuntimeHooks.m:242-247`):
  ```objc
  if (family == MTLGPUFamilyMac2) return YES;
  return ((BOOL (*)(id, SEL, MTLGPUFamily))gSupportsFamily)(self, _cmd, family);
  ```
- `VERIFICADO` (histórico, `recovered_edits_all.txt`): la versión final devolvía `NO` para
  `MTLGPUFamilyApple1..Apple3` y `YES` para `Mac1`/`Mac2`.
- `VERIFICADO` (motivo documentado): `ToSRGBFormat` (`0x10123071c`) asume build iOS/ASTC si
  `Apple1` responde `YES`, corrompiendo texturas de escritorio **BC1..BC7**; con `NO` toma la rama
  Mac1 (`0x101230790`).
- `HIPÓTESIS fuerte`: causa superficies blancas/lineales o sin textura. **No** explica por sí solo
  el gato invisible, la pantalla negra ni el wireframe.
- **Experimento G**: añadir la supresión Apple1..3 (y Mac1) al build actual, sin tocar nada más.

> Corrección: el informe de Antigravity vinculaba esto al límite de huesos “Mobile”. Es una
> conflación; ver matiz en BUG-003.

---

## BUG-011 — Afirmaciones históricas refutadas

| Afirmación | Veredicto | Evidencia |
|---|---|---|
| Run 10 “60 FPS” | **REFUTADO** | captura: `19.81 FPS`, escena vacía |
| Run 11 “60 FPS” | **REFUTADO** | captura: `19.51 FPS`, wireframe |
| Run 12 “gato visible 1483 px, bbox pantalla completa” | **REFUTADO** | no existe captura original; solo ASCII oscuro `e5026e30` step 2223 |
| Run 10 “~1 FPS” | **REFUTADO** | captura dice 19.81 |
| “ICU resuelto ⇒ jugable” | **REFUTADO** | run ICU-A aborta en case-sensitivity; sin render/input/audio |

Conservar estas correcciones en el handoff: evitan repetir conclusiones falsas.

---

## BUG-012 — Rechazo de instalación “profile has not been explicitly trusted”

**Estado: `TRANSIENTE`.**

- `VERIFICADO`: el primer lanzamiento tras reinstalar puede fallar con
  `invalid code signature ... profile has not been explicitly trusted`.
- `VERIFICADO`: reintentar con **el mismo build** lanza correctamente.
- Perfil `iOS Team Provisioning Profile: com.ju4nm8.strayios` válido hasta **2026-11-30**, incluye
  UDID `<TARGET_DEVICE_UDID>`.
- **No** tratarlo como bug de código ni como fallo de firma.

---

## 1. Cruce con la cola de experimentos del audit

| Exp. | Bug | Cambio mínimo | Éxito medible |
|---|---|---|---|
| **A** | BUG-002 (+009) | hook `ShimURLGetResourceValue` | desaparece el `NSAlert`; avanza init |
| **B** | BUG-003/004 | UAssetAPI solo lectura sobre asset 1.5 | valores de `HiddenInGameplay`, huesos, GFur |
| **C** | BUG-003 | override `MaxSkinBones` móvil | gato visible |
| **D** | BUG-003 | desactivar GFur/SceneCapture | gato visible sin pelo |
| **G** | BUG-005/010 | suprimir `MTLGPUFamilyApple1..3` + reclamar `Mac1` en `ShimSupportsFamily` | desaparecen superficies blancas/lineales; captura más coherente |
| **E** | BUG-005 | comparar build actual vs parcheado | origen del wireframe |
| **F** | BUG-006 | overlay/gamepad con `ControllerId` correcto | movimiento medible |

Orden: **A → medir → G → B → C/D → F → E**. A y G son cambios de shim de bajo riesgo; B es solo
lectura; E es el único de alto riesgo y va al final. Nada de E antes de cerrar A y G.

---

## 2. Fuentes y su fiabilidad

| Fuente | Uso válido | Uso inválido |
|---|---|---|
| `HK_Project/Source/.../*.h` | nombres de clase, propiedades, relaciones | offsets, lógica (los `.cpp` son stubs) |
| `Hk_CXX-and-UHT/Ver1.3#214/**` | mapa de clases/assets 1.3 | offsets Win64 o 1.3 aplicados a 1.5/ARM64 |
| `StrayCoop/*.lua` | patrones de estado (cámara, ocultar, teleport, recarga) | código reutilizable (sin licencia) en iOS |
| `DOMEHero/*.ini`, `*OpenOrder.log` | defaults de UE4.27, layout ICU, `MaxSkinBones` | valores exactos de 1.5#99 |
| `work/antigravity/recovered_*` | evidencia de lo que funcionó históricamente | afirmaciones sin captura/log |

---

## 3. Estado de verificación global

- Render: **NO verificado** en el build actual (Run 11 sí renderizó en un build histórico).
- Input: **NO verificado** end-to-end.
- Audio: **NO verificado** en ningún run.
- Por tanto: **el juego no es jugable**. Cualquier afirmación contraria es `REFUTADO`.
