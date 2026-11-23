# OPENCODE SOURCE AUDIT — Fuentes externas aplicadas a Stray 1.5#99 en iOS

Fecha: 2026-11-23. Autor: OpenCode. Ámbito: comparar el código público con nuestro shim y nuestros
artefactos recuperados. **No se ha aplicado ningún cambio** (fase de integración aplazada).

Etiquetas: `VERIFICADO` (con archivo:línea o log), `HIPÓTESIS`, `PENDIENTE`, `REFUTADO`.

---

## 0. Qué sabemos ahora que antes no

1. **ICU**: el árbol del PAK es un superconjunto exacto del open order de referencia
   (893 rutas externas ⊆ 3.463 del PAK). El fatal ICU desapareció en la prueba controlada; el
   siguiente bloqueo es el chequeo **case-sensitive**, no ICU. (`EditorOpenOrder.log:413-432`,
   `Engine.ini:1787`, `artifacts/logs/icu_test/launch_retry.log`).
2. **Existe un fix histórico exacto para ese bloqueo**: `ShimURLGetResourceValue` devolvía `NO` para
   `NSURLVolumeSupportsCaseSensitiveNamesKey`. El clon actual **no** lo tiene.
3. **Límite de huesos móvil**: `MaxSkinBones=(Default=65536,PerPlatform=(("Mobile",256)))`
   (`Engine.ini:892`). Es la primera explicación con base para el gato invisible/corrupto en iOS y
   encaja con los parches históricos de skin/bone limit.
4. **Bandera de ocultación propia del gato**: `BP_CatPawn_C` tiene `bool HiddenInGameplay`
   (`BP_CatPawn.hpp:83`, 1.3#214). No es un artefacto del shim.
5. **Candidatos reales para la geometría roja/blanca de Run 11**: debug de superficies caminables
   (`m_walkableDebugMaterial`, `m_walkableDebuggedPrimitives`, `FWalkableDebuggedPrimitive::Materials`),
   componentes `DrawMovement1/2/3` del gato, y colores de LOD (blanco/rojo/verde/azul).
6. **Cámara**: el crash de `PCOwner` nulo al crear un segundo jugador está documentado y resuelto por
   el mod cooperativo; es específico de multijugador local en Windows, **no** debe asumirse como
   nuestra causa de pantalla negra.
7. **Teleport**: `SetActorLocation` no basta; `CatMovementComponent` devuelve al gato. Hay que usar
   `K2_TeleportTo`.
8. **Recargas**: el nivel se recarga al morir el gato; las referencias a pawns/controllers quedan
   invalidadas. El patrón correcto es releer del `GameInstance`, no cachear.
9. **Herramientas**: UE4SS es Windows-only; UAssetAPI (.NET) sí puede inspeccionar nuestros `.uasset`
   en macOS; UEAssetToolkit exige editor UE en Windows y es GPL-3.0.

---

## 1. Método

- Repos clonados con `--depth 1` (y sparse checkout en `HK_Project` y `UAssetAPI`), aislados en
  `work/external/repos/`. Manifiesto y hashes en `REPOSITORY_MANIFEST.md`.
- Lectura directa de Lua, headers UHT, configs y logs. Los `.cpp` de HK_Project se clasificaron como
  **stubs** (cuerpos vacíos), no como lógica de BlueTwelve: p. ej. `HKPlayerController.cpp:8-97`
  devuelve `false`/`NULL`/`0.0f` en todo.
- Contraste con: `Documentation/STRAY_HANDOFF.md`, `Documentation/TEST_RESULTS.md`,
  `work/antigravity/recovered_appkit/` (13 ficheros) y `work/antigravity/recovered_edits_all.txt`.
- No se ejecutó código de terceros ni se instaló nada.

---

## 2. Mapa de clases documentado (1.3#214; nombres útiles, offsets no)

| Clase | Evidencia | Papel | Notas |
|---|---|---|---|
| `ACatPawn` (`BP_CatPawn_C`) | `HK_Project/Source/Hk_project/Public/CatPawn.h:114-120,139,1364,1677` | pawn del gato; mesh visual, collider grande, cámara | `m_visual` es `USkeletalMeshComponent`; `GetSkeletalMesh()` |
| `AHKPlayerController` | `HKPlayerController.h:50,53,74,77,80,106` | guarda `m_catPawn` y `m_cameraManager`; debug de superficies | offset Win64 citado por el mod: 0x608/0x610 |
| `AHKPlayerCameraManager` | `HKPlayerCameraManager.h:1-84` | pila de cámaras, fade, input | `PushCamera`/`PopCamera`, `CameraChanged` |
| `ACameraThirdPerson` | `CameraThirdPerson.h:32-35,59-62,173,191` | brazo, cámara, colisión, presets | muchos cursores de respuesta |
| `UCatMovementComponent` | `CatMovementComponent.h:1-48` | movimiento del gato; snap-back | `_CapsuleTouched` |
| `UCatAnimInstance` | `CatAnimInstance.h:15-64` | animación; bancos y notifies | `SetupAnimationBanks` |
| `AAudioManager` | `AudioManager.h:1-15` | manager de audio | clase mínima en 1.3 |
| `AHKGameInstance` | `HKGameInstance.h:53-56,104,107` | save instance, streaming de zona, audio persistente | vive toda la sesión |
| `BP_DummyCatPawn_C` | `CXXAllAssets1.3-214/BP_DummyCatPawn.hpp:5-20` | gato dummy para streaming/cinematics | hereda de `BP_CatPawn_C` |
| `BP_HKPlayerCameraManager` / `BP_HKPlayerController` | `main.lua:153-158` | clases reales usadas por el mod | confirman los nombres |
| `AZurgPawnLeader` / `AZurgManager` / `ASentinel` | `ai.lua:51-112` | IA | campos cacheados y API de lock-on |

**Trampa de versión**: los headers de `HK_Project` y `Hk_CXX-and-UHT` son el **mismo dump 1.3#214**
(difieren 72 líneas, casi todas includes/`Export` vs `Instanced`). Stray actual es **1.5#99**.
No usar offsets (`0x37B8`, `0x5480`, `0x608`, `0x610`, `0x258`) en ARM64.

---

## 3. Cámara y orden de inicialización

Evidencia del mod (`main.lua:141-160` y README §“How it works” punto 3):

- `AHKPlayerCameraManager::BeginPlay` empuja un view target.
- `APlayerCameraManager::SetViewTarget` → `ViewTarget.CheckViewTarget(PCOwner)` lee `PCOwner->Pawn`.
- El camera manager de P1 se crea antes de que empiece el mundo, así que su `BeginPlay` espera a que
  `InitializeFor()` fije `PCOwner`.
- El de P2 se crea a mitad de partida; `BeginPlay` corre dentro de `SpawnActor` con `PCOwner == null`
  y el juego lee `0x258` (`AController::Pawn`) → crash.
- Fix del mod: hook `NotifyOnNewObject` sobre `BP_HKPlayerCameraManager_C` y asignar
  `cam.PCOwner = p2Controller` antes de `BeginPlay` (`main.lua:156-160`).

**Aplicabilidad a nuestro port**: `HIPÓTESIS` baja/media. Nuestro caso es **un solo jugador**; no
creamos un segundo controller. Solo sería relevante si el shim construye el camera manager antes de
`InitializeFor` o si el auto-continue fuerza un estado de menú/cinematics. **No** es la primera causa a
investigar para la pantalla negra. `PENDIENTE` confirmar el orden real en iOS con instrumentación.

Cámaras cinematográficas: el mod detecta `CineCameraActor`, `CameraActor` y `BP_SplineCameraCine_*`
(`main.lua:278-287`), desactiva split y oculta P2 (`main.lua:299-310`). Esto demuestra que:
- el juego **sí** tiene un mecanismo estándar de ocultación (`SetActorHiddenInGame`);
- los estados de cámara/transición son un punto real donde el gato “desaparece” de forma legítima.

---

## 4. Gato invisible: evidencia convergente

### 4.1 Límite de huesos en móvil (la pista más fuerte)

`Engine.ini:892` (config cocinada de referencia, UE4.27):

```
MaxSkinBones=(Default=65536,PerPlatform=(("Mobile", 256)))
```

- En móvil el skinning se limita a **256 huesos**; en escritorio, 65.536.
- El gato de Stray usa `m_visual` (`USkeletalMeshComponent`, `CatPawn.h:114`) y `GetSkeletalMesh()`
  (`CatPawn.h:1364`).
- Los parches históricos incluyen precisamente:
  - `USkinnedMeshComponent::CreateSceneProxy` **bone limit** → NOP en `0x2fd68c0`;
  - `CreateSceneProxy` **bHideSkin** → NOP en `0x2fd67f0`;
  - `CreateRenderState_Concurrent` → NOP en `0x2fd6e44`.
  (`work/antigravity/recovered_files/B_178_iterate_stray.sh:16-21`).
- **HIPÓTESIS fuerte**: si el mesh del gato supera 256 huesos, el skinning móvil puede descartar
  secciones o el proxy entero. Los parches históricos apuntan exactamente a ese código.
- **PENDIENTE**: contar huesos del skeletal mesh real de 1.5#99 e inspeccionar el asset; no asumir que
  el límite de 1.3 es el de 1.5.

### 4.2 Bandera del propio Blueprint

`BP_CatPawn.hpp:83`: `bool HiddenInGameplay; // 0x3A34 (size: 0x1)`.

- Es una propiedad del Blueprint del gato, no del shim.
- **HIPÓTESIS**: si el estado de gameplay queda en “oculto” (menú/cinemática/transición), el gato no
  se dibuja aunque el render funcione. El auto-continue histórico pulsa menú y gameplay a ciegas; un
  estado mal secuenciado puede dejarla activa.
- **PENDIENTE**: leer el valor por defecto y los escritores de `HiddenInGameplay` en el asset 1.5.

### 4.3 Componentes de render del gato

`BP_CatPawn.hpp` (1.3#214):

| Línea | Componente | Relevancia |
|---|---|---|
| 21 | `UGFurComponent* GFur` | pelo (plugin GFur). Si el shader/plugin falla en iOS, el pelo puede no renderizar; el mesh base debería seguir. |
| 20 | `USceneCaptureComponent2D* SceneCaptureComponent2D` | captura 2D; puede alterar lo que ve la cámara. |
| 15-17 | `UDrawMovementComponent* DrawMovement1/2/3` | dibujo de movimiento/probes; posible origen de líneas de debug. |
| 12 | `UWidgetComponent* Widget` | HUD/indicador sobre el gato. |
| 27-30 | `USpringArmComponent`, `UPointLightComponent` x4 | cámara/iluminación adjunta. |

- El mod cooperativo **oculta** a P2 con `SetActorHiddenInGame(on)` (`main.lua:302-303`), lo que
  confirma que la API estándar funciona; no explica por sí solo la invisibilidad.
- **HIPÓTESIS**: GFur o el SceneCapture pueden fallar silenciosamente en Metal/iOS; el mesh base
  seguiría visible, así que por sí solos no explican un gato totalmente ausente.
- **PENDIENTE**: comparar el asset 1.5 (¿sigue teniendo GFur/SceneCapture?) y probar sin GFur.

### 4.4 Lo que NO explica la invisibilidad

- Los parches de visibilidad forzada (`IsVisible`, `ShouldComponentAddToScene`) **añaden** geometría,
  no la quitan. Es más probable que revelen debug que oculten al gato.
- El shim de touch/gamepad no toca el render del pawn.

---

## 5. Geometría roja/blanca de Run 11: tres candidatos verificables

La captura `671dc9b1_step00536` muestra: escena 3D texturizada, overlay táctil, HUD `19.51 FPS`,
**líneas rojas largas** y **wireframe blanco masivo** sobre rejas/rampas, y una pirámide texturizada con
un ojo. No se identifica al gato.

Candidatos, en orden de probabilidad:

1. **Debug de superficies caminables** (`HIPÓTESIS fuerte`)
   - `AHKPlayerController::m_walkableDebuggedPrimitives` (`HKPlayerController.h:74`),
     `m_walkableDebugMaterial` (`:77`), `m_movementObstacleDebugMaterial` (`:80`) y
     `SetWalkableDebugModeEnabled(bool)` (`:106`).
   - `FWalkableDebuggedPrimitive` contiene `TArray<UMaterialInterface*> Materials`
     (`WalkableDebuggedPrimitive.h`).
   - Es geometría de colisión/suelo dibujada con materiales de debug: encaja con “massive” y con el
     patrón rojo/blanco.
2. **`DrawMovementComponent` del gato** (`HIPÓTESIS`)
   - `BP_CatPawn.hpp:15-17` declara `DrawMovement1/2/3` (plugin JoyLibrary). Podría dibujar splines,
     trayectorias y probes alrededor del gato; las líneas rojas largas que cruzan la pantalla encajan.
   - El código del plugin **no está** en los repos clonados; `PENDIENTE` localizarlo o inspeccionar
     el asset.
3. **Colores de LOD / material de huesos** (`HIPÓTESIS débil`)
   - `Engine.ini:160-167` define `LODColorationColors` blanco/rojo/verde/azul y
     `Engine.ini:106` `BoneWeightMaterialName=/Engine/EngineDebugMaterials/BoneWeightMaterial`.
   - Producen color plano, no necesariamente wireframe; explican la paleta, no las líneas.

**Explicación histórica**: los parches de visibilidad forzada (`0x2fb20c0`, `0x2faf8e4`, `0x2f8c68c`)
hacen visible lo que el juego oculta; si entre esos componentes están los debug de walkable/draw
movement, aparece exactamente este wireframe. **No** atribuirlo al shim sin un A/B.

---

## 6. Transiciones, recargas y referencias destruidas

- `main.lua:54-57`: **nunca** cachear controllers, pawns ni widgets; el nivel se recarga al morir el
  gato y tocar un objeto destruido rompe UE4SS. Solo se conserva el `GameInstance`.
- `main.lua:234-264`: si P2 no tiene gato, `RestartPlayer` tras 3 s; luego teleport a P1.
- `main.lua:289-346`: tras una cinemática, espera a que P1 esté quieto (3 ticks de 250 ms), reagrupa
  y reintenta hasta 15 s.
- `ai.lua:7,51-53`: enemigos releídos en cada llamada; **no** se cambia `AZurgManager::m_catPawn`
  porque “other systems such as chase cameras read it” y apuntarlo a P2 crasheaba la cámara.
- `ai.lua:80-112`: Sentinels con `GetLockedTargetActor`, `SetLockOnTarget`, `IsActorInVision`.

**Aplicabilidad**: conceptual/media. No tenemos segundo jugador, pero el principio “releer del
GameInstance tras recarga” sí aplica a cualquier auto-continue/teleport del shim. El crash de
`m_catPawn` del manager es una advertencia contra cambiar estado global del juego desde el shim.

---

## 7. Input y gamepad

- Semántica de `ControllerId` y `bOffsetPlayerGamepadIds` (`main.lua:18-25,81-97`):
  Unreal entrega el gamepad *N* al local player cuyo `ControllerId` es *N*, o *N+1* con el flag;
  teclado/ratón siempre llegan como ID 0.
- `SetPlayerControllerID` intercambia IDs si otro local player ya tiene el solicitado, por eso el
  orden de las dos llamadas no importa (`main.lua:87-97`).
- Nuestro shim ya tiene polling de `GCController` (`shim/overrides/AppKit.m:836-838`) y un gamepad
  virtual histórico recuperado; la lógica de IDs del mod es una referencia útil si el juego ignora
  el mando virtual.
- `UDebugInputComponent` (`DebugInputComponent.h`) expone todos los botones/ejes como delegados:
  mapa útil para saber qué nombres espera el juego.

**PENDIENTE**: verificar si el `ShimVirtualGamepad` histórico publica el `ControllerId` correcto y si
Stray 1.5 lee `bOffsetPlayerGamepadIds` en el arranque automático.

---

## 8. Colisiones

- `main.lua:99-138`: los colliders de interacción del gato deben ignorar el canal `Pawn`
  (`ECC_Pawn=2`, `ECR_Ignore=0`), porque `CatPawn::_OnLargeInteractionColliderBeginOverlap`
  (`CatPawn.h:1677`) asume que nunca ve otro pawn de jugador.
- El mod busca componentes por nombre que contenga “Interaction” y llama
  `SetCollisionResponseToChannel(ECC_Pawn, ECR_Ignore)`.
- **Aplicabilidad iOS**: nula para un solo gato; útil solo si el shim duplica pawns o si un pawn
  fantasma del menú queda en el mundo.

---

## 9. Audio

- `AudioManager.h` es mínimo en 1.3 (`m_maxAudioHolderTicksPerFrame`), no permite concluir nada sobre
  el pipeline de audio.
- `StrayAP` y el gist no aportan nada de audio.
- `GameUserSettings`/`HKGameUserSettings` exponen `MasterVolume`, `MusicVolume`, `EffectsVolume`
  (`HK_Project/Config/DefaultGameUserSettings.ini`).
- **PENDIENTE**: no hay ninguna verificación de audio en iOS. UAssetAPI puede listar assets de audio
  (`CueBank`, `VoiceBank`, `BP_AudioManager`), pero eso no demuestra reproducción.

---

## 10. Hilos y MainThread

Evidencia recuperada (AppKit histórico):

- Comentario en el código: “synchronously on the Main Thread, AND then calls
  `GameThreadCall(block, @[NSDefaultRunLoopMode], bWait=true)`”
  (`work/antigravity/fulltext/e5026e30-*/all.txt`).
- `ShimYieldToGame`, `ShimContextSwitch(&gGameContext, &gUIKitContext)` y
  `ShimPrepareAutonomousLaunchEnvironment` (`work/antigravity/recovered_appkit/00289_*.m`).

Evidencia externa:

- `tracer.lua` y `main.lua` usan `ExecuteInGameThread`/`LoopAsync` para no tocar objetos UE desde
  otros hilos (`main.lua:349-372`, `tracer.lua:17-31`). Es una **analogía**, no una prueba: UE4SS y
  nuestro shim tienen modelos distintos.
- **HIPÓTESIS**: los errores históricos de MainThread provienen de llamar a APIs de UE/AppKit desde
  el hilo equivocado o de bloquear el runloop con `bWait=true` durante transiciones. La corrección
  sería instrumentar `ShimContextSwitch`/`GameThreadCall` y no cambiar el diseño a ciegas.
- **PENDIENTE**: no tenemos un stack de un MainThread error actual; el `mutex lock failed` del run ICU
  es posterior al `NSAlert` de case-sensitivity, no un error de hilo de UE.

---

## 11. ICU y case-sensitivity (nuestro estado real)

### 11.1 ICU: superado, no “jugable”

`artifacts/logs/icu_test/launch_retry.log`:

```
grep -c "ICU data directory was not discovered"  → 0   (launch10 → 1)
SHIM NSAlert runModal: Unreal Engine does not support running from case-sensitive file systems.
libc++abi: terminating ... mutex lock failed: Invalid argument
SHIM FAULT signal 6
Spinning after fatal error
```

- `VERIFICADO`: la redirección `Internationalization=Documents/stray/StrayICU` + árbol `icudt64l`
  elimina el fatal ICU. El motor sigue inicializando hasta el chequeo de case-sensitivity.
- Avisos `lang/en_US.res`, `region/en_US.res`: normales; ni el open order de referencia ni el PAK los
  tienen; ICU cae a `en.res`.
- `Engine.ini:1787` `DirectoryIndexKeepFiles=*/Content/Internationalization/*` explica por qué el
  árbol está en el PAK; el loader de ICU usa el filesystem, no el VFS del PAK (`HIPÓTESIS fuerte`).

### 11.2 Case-sensitivity: fix histórico localizado

Código recuperado (`work/antigravity/fulltext/eaa6cb79-*/step_00003.txt:53-69`):

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

- `VERIFICADO`: el shim actual **no** contiene `NSURLVolumeSupportsCaseSensitiveNamesKey`
  (`grep` = 0).
- `VERIFICADO`: el shim actual solo tiene `FixCase` para rutas libc (`libSystem.m:120-166`), que no
  cubre la consulta NSURL que hace UE.
- **HIPÓTESIS fuerte**: reinstalar ese hook (o equivalente) desbloquea el chequeo y permite seguir
  la inicialización. Es el siguiente experimento A/B de una variable.

---

## 12. Herramientas: qué sirve y qué no

| Necesidad | Herramienta | Veredicto |
|---|---|---|
| Ver defaults de `BP_CatPawn` (`HiddenInGameplay`, GFur, materiales) | **UAssetAPI** (.NET) sobre `.uasset` extraído del PAK | **Viable en macOS**; requiere `repak` para extraer y posible `.usmap` |
| Ver bytecode/estructura de Blueprints | UAssetAPI (Kismet) | Viable, con limitaciones de versión |
| Ejecutar hooks en el juego | UE4SS | **No** en iOS; solo Windows |
| Regenerar assets en editor | UEAssetToolkit + Generator | **No** en macOS/iOS; requiere UE 4.27 en Windows; GPL-3.0 |
| Dump de clases | UHT dump ya disponible (1.3#214) | Útil como mapa, no como offsets de 1.5 |
| Inspeccionar PAK | `repak` (ya usado) | **Verificado**: 3.463 ficheros ICU |

**Advertencia**: UAssetAPI no acepta contribuciones generadas por IA; nosotros solo lo usaríamos como
consumidor local, sin contribuir.

---

## 13. Comparación: shim actual vs AppKit recuperado vs fuentes externas

| Capacidad | Shim actual | AppKit histórico recuperado | Fuente externa | Comentario |
|---|---|---|---|---|
| Redirect de rutas | `libSystem.m:15-30` (`SHIMPathRedirects`) | logs de `SHIM redirect` | — | Funciona; ICU lo probó |
| Case-insensitive libc | `FixCase` (`libSystem.m:120-166`) | — | — | No cubre NSURL |
| Case-insensitive NSURL | **Ausente** | `ShimURLGetResourceValue` | — | Siguiente bloqueo |
| Touch overlay | **Ausente** | `ShimTouchOverlayView` (`00436_*.m`) | — | Solo UI, no render |
| Gamepad virtual | **Ausente** (`ShimVirtual*` = 0) | polling `GCController` (`01351_*.m`) | ControllerId del mod | Reintegrar con cuidado |
| Auto-continue | **Ausente** | `scheduleAutoContinueIfRequested` (`671dc9b1_step637`) | — | Peligroso sin ver estado |
| `GSavedCommandLine` | **Ausente** | `ShimSyncUnrealGSavedCommandLine` (`00287_*.m`) | — | Evita crash en transiciones |
| `FMemory::Realloc` | **Ausente** | `ShimUnrealMalloc` (`00287_*.m`) | — | Evita panic de allocator |
| Sanear `GameUserSettings` | **Ausente** | `ShimSanitizeGameUserSettingsIni` (`00285_*.m`) | `Engine.ini`/`GameUserSettings.ini` | Resolución/quality |
| Spoof GPU | Básico `MTLGPUFamilyMac2` (`AppKit_RuntimeHooks.m:242-246`) | Apple1..3 → NO, Mac1/2 → YES | — | Falta la supresión Apple |
| Debug walkable | No aplica | — | `m_walkableDebugMaterial` | Candidato a wireframe |
| Límite de huesos | No aplica | parches skin/bone | `MaxSkinBones` Mobile=256 | Candidato a gato invisible |

---

## 14. Cola de experimentos A/B (una variable; no ejecutados aún)

| # | Variable | Cambio mínimo | Éxito medible | Riesgo |
|---|---|---|---|---|
| A | Case-sensitivity | añadir `ShimURLGetResourceValue` (hook NSURL) y re-firmar | desaparece el `NSAlert` de case-sensitive; aparecen `Looking for binary`/`Device Type` | bajo; solo hook |
| B | Si A pasa: estado del gato | inspeccionar `HiddenInGameplay` y huesos del mesh 1.5 con UAssetAPI | gato visible en captura | nulo (solo lectura) |
| C | Skin móvil | probar override de `MaxSkinBones`/skin cache en config | gato deja de estar corrupto/invisible | medio; puede afectar rendimiento |
| D | GFur | desactivar `GFur` en el asset o config | gato visible sin pelo | bajo |
| E | Debug geometry | comparar build sin parches de visibilidad (actual) vs histórico parcheado | identificar origen del wireframe | alto: no tocar parches aún |
| F | Auto-continue | pulsos de menú/gameplay con verificación de estado | llega a gameplay sin atascarse | medio |

**No** se aplica ninguno en esta fase. El orden recomendado es A → (medir) → B/C/D.

---

## 15. Técnicas no portables / trampas

1. UE4SS (`dwmapi.dll`, `RegisterHook`, `NotifyOnNewObject`, `LoopAsync`, live viewer): **Windows**.
   No se puede inyectar en iOS. Solo ideas.
2. Offsets Win64: `0x608`/`0x610` (HKPlayerController), `0x258` (`AController::Pawn`): **no** ARM64.
3. Offsets de assets 1.3#214 (`0x37B8`, `0x5480`): **no** 1.5#99.
4. `.cpp` de HK_Project: **stubs**; no son lógica de BlueTwelve.
5. CXX headers: el propio autor advierte que “no son memory accurate”.
6. `SetActorLocation` para teleportar al gato: **no** funciona; usar `K2_TeleportTo`.
7. Cambiar `AZurgManager::m_catPawn`: crashea cámaras; solo tocar líderes.
8. `UEAssetToolkit`: GPL-3.0 y editor Windows; no mezclar.
9. La distribución Nexus de StrayCoop v1.4 tiene restricciones de IA; no reutilizar su código.

---

## 16. Preguntas abiertas

1. ¿Qué API exacta usa UE4.27 para el chequeo case-sensitive y por qué no pasa por `FixCase`?
   (`PENDIENTE`; el hook NSURL histórico es la respuesta más probable).
2. ¿El `mutex lock failed` es consecuencia del `NSAlert` o un fallo independiente del shim?
3. ¿Stray 1.5#99 conserva `HiddenInGameplay`, `GFur`, `SceneCaptureComponent2D` y
   `DrawMovement1/2/3`? (`PENDIENTE`: inspeccionar el asset real).
4. ¿Cuántos huesos tiene el skeletal mesh del gato en 1.5? ¿Supera 256?
5. ¿El wireframe de Run 11 viene de walkable debug, DrawMovement o parches de visibilidad?
6. ¿El audio funciona en iOS? Nunca se ha verificado.
7. ¿El auto-continue histórico deja el juego en un estado de menú/cinemática que explica pantallas
   negras y ausencia del gato?

---

## 17. Conclusión operativa

- **ICU ya no es el bloqueo**. El bloqueo actual es el chequeo case-sensitive, y existe un fix
  histórico concreto y localizado.
- Las fuentes externas no aportan código de shim reutilizable, pero sí un **mapa de clases** y
  **patrones de estado** (cámara, ocultación, teleport, recarga, input) que reducen la ingeniería
  inversa.
- La invisibilidad del gato tiene ahora dos hipótesis con base: **límite de huesos móvil (256)** y
  **`HiddenInGameplay`**; los parches históricos de skin refuerzan la primera.
- El wireframe de Run 11 tiene candidatos concretos en el propio juego (walkable debug, DrawMovement),
  además de los parches de visibilidad.
- No se declara nada jugable. No se han aplicado cambios.

---

## 18. Consolidación: validación cruzada de `ANTIGRAVITY_SOURCE_ANALYSIS.md`

Antigravity terminó con `EXIT=0` y escribió **401 líneas** en
`Documentation/ExternalResearch/ANTIGRAVITY_SOURCE_ANALYSIS.md` (28.886 B). Se acepta como
**segunda opinión**, no como fuente de verdad. Estas son las comprobaciones hechas contra disco.

### 18.1 Afirmaciones suyas confirmadas

| Afirmación | Comprobación | Veredicto |
|---|---|---|
| `EditorOpenOrder.log` = 2.382 líneas, 893 con `icudt64l` | `wc -l` = 2382; `grep -c` = 893 | **VERIFICADO** |
| `CookerOpenOrder.log` = 0 referencias ICU | `grep -c` = 0 | **VERIFICADO** |
| `ExtensionsToNotUsePluginCompression=icu` en `Engine.ini:1782` | `sed -n '1778,1792p'` | **VERIFICADO** |
| `DirectoryIndexKeepFiles=*/Content/Internationalization/*` en `Engine.ini:1787` | ídem | **VERIFICADO** |
| UAssetAPI target `net10.0` | `UAssetAPI.csproj:4` | **VERIFICADO** |
| `UAssetAPI/Pak/RePak.cs` existe (P/Invoke a Rust) | `ls` | **VERIFICADO** |
| `ShimSupportsFamily` histórico suprime familias Apple | `recovered_edits_all.txt` (6 ocurrencias) | **VERIFICADO** |
| El clon actual solo reclama `MTLGPUFamilyMac2` | `AppKit_RuntimeHooks.m:244-247` | **VERIFICADO** |
| `AppKit_RuntimeHooks.m:95` solo swizzlea `URLForResource:` | `sed -n` | **VERIFICADO** |
| RE-UE4SS exige Windows | `RE-UE4SS/README.md:69` | **VERIFICADO** |

### 18.2 Correcciones obligatorias (no aceptar tal cual)

1. **Licencias mal declaradas.**
   - `UEAssetToolkit/LICENSE` = **GPL-3.0** (Antigravity: “no declarada explícitamente”). Fichero presente.
   - `UEAssetToolkitGenerator/LICENSE` = **Apache-2.0** (Antigravity: “MIT vía NOTICE.md”). Fichero presente.
   - `HK_Project`: GitHub detecta **GPL-3.0**, aunque el checkout sparse no incluya `LICENSE`.
     Mantener la restricción de solo lectura hasta verificar.
2. **Confusión `MTLGPUFamilyApple1` ↔ `MaxSkinBones` “Mobile”.** Antigravity afirma que si no se
   suprime `MTLGPUFamilyApple1`, UE4 “entra en la ruta iOS” y aplica el límite de 256 huesos.
   Esto **no está demostrado** y mezcla dos rutas distintas:
   - `ShimSupportsFamily` afecta a `ToSRGBFormat` (**formatos de textura BC → ASTC**), según el
     comentario histórico recuperado (`recovered_edits_all.txt`). No se ha demostrado que cambie
     `MaxSkinBones`.
   - `MaxSkinBones` usa `PerPlatform=(("Mobile", 256))`, que depende de la plataforma de
     **cocción/runtime** (`IniPlatformName`), no de `supportsFamily:`. Nuestro PAK es
     `pakchunk0-MacNoEditor.pak` (Mac), por lo que el valor “Mobile” podría **no aplicarse**.
   - **Veredicto**: `PENDIENTE`. Medir `IniPlatformName`/plataforma efectiva antes de atribuir el
     gato invisible al límite de huesos.
3. **`GetSkeletalMesh()` no devuelve `m_visual` en el dump.** El `.cpp` es un stub:
   `CatPawn.cpp:646-648` → `return NULL;`. El header declara el accessor, pero **no** prueba el
   retorno. Es `HIPÓTESIS`, no `VERIFICADO`.
4. **Ruta del fichero**: es `shim/overrides/AppKit_RuntimeHooks.m`, no `shim/AppKit_RuntimeHooks.m`.
5. **“No tiene `BeginPlay` propio”**: cierto en el header C++ (`HKPlayerCameraManager.h`), pero el
   `BeginPlay` que empuja el view target puede estar en `BP_HKPlayerCameraManager_C`. No convertir
   esa inferencia en hecho.

### 18.3 Hallazgo nuevo confirmado (prioritario)

El clon actual (`AppKit_RuntimeHooks.m:242-247`) solo hace:

```objc
if (family == MTLGPUFamilyMac2) return YES;
```

Los edits históricos demuestran que **también** hay que devolver `NO` para
`MTLGPUFamilyApple1..Apple3` (versión final del 2026-11-06):

```objc
if (family == MTLGPUFamilyApple1 || family == MTLGPUFamilyApple2 || family == MTLGPUFamilyApple3) {
    return NO;
}
if (family == MTLGPUFamilyMac1 || family == MTLGPUFamilyMac2) {
    return YES;
}
```

Motivo documentado en el propio edit: en `ToSRGBFormat` (`0x10123071c`), si el device responde `YES`
a `MTLGPUFamilyApple1`, UE4 asume build iOS y mapea texturas por la tabla **ASTC**, corrompiendo
texturas de escritorio **BC1..BC7** (“dropping them to linear / unrendered”). Con `NO` para
Apple1..3, toma la rama Mac1 (`0x101230790`).

- `VERIFICADO`: el clon actual **no** suprime Apple1..3.
- `HIPÓTESIS fuerte`: esto explica superficies blancas/lineales o “unrendered” en Run 11.
- **No** explica por sí solo el wireframe (eso apunta a debug walkable/DrawMovement), ni el gato
  invisible, ni la pantalla negra.
- Es un cambio **solo de shim**, de bajo riesgo, y debe ser el **experimento G** después de A.

### 18.4 Resultado de la consolidación

- Antigravity aporta valor en: cámaras (PCOwner solo afecta a P2), transiciones, no-portabilidad de
  UE4SS, capacidades de UAssetAPI, y la confirmación del árbol ICU.
- Sus dos errores materiales son las **licencias** y la **conflación GPU/bones**; ambos quedan
  corregidos aquí y en `BUG_TO_SOURCE_MAP.md`.
- **Decisión**: el siguiente experimento sigue siendo **A (case-sensitivity)**. Después, **G
  (suprimir Apple1..3)**, que es más barato y más probable que cualquier parche de visibilidad.
- No se integra nada todavía. No se declara jugable.
