# Auditoría independiente de fuentes externas — Stray iOS Port
**Fecha de auditoría:** 2026-11-23  
**Auditor:** Antigravity (solo lectura; ningún fichero del proyecto modificado)  
**Contexto:** Stray 1.5 build 99, UE 4.27, binario macOS arm64 ejecutado en iPhone vía `macos-on-ios-public`. ICU desbloqueado. Nuevo bloqueo activo: `Unreal Engine does not support running from case-sensitive file systems`.

---

## Convenciones

| Etiqueta | Significado |
|---|---|
| **VERIFICADO** | Evidencia directa con `archivo:línea` |
| **HIPÓTESIS** | Inferencia razonable desde las fuentes; requiere prueba en dispositivo |
| **PENDIENTE** | Ninguna fuente disponible permite concluir |

---

## Pregunta 1 — Cámara / orden de inicialización (`AHKPlayerCameraManager`, `PCOwner`, `ViewTarget`)

### Evidencia en `main.lua`

**VERIFICADO**  
El comentario de cabecera del bloque "Fix 2" ([main.lua:141-144](file:///Volumes/Disco%20Juan/Projects/Stray%20iOS/PortWorkspace/Stray-iOS-From-Scratch/work/external/repos/Stray-Local-Co-op-Mod/Mods/StrayCoop/Scripts/main.lua#L141-L144)) dice textualmente:

> `AHKPlayerCameraManager::BeginPlay` pushes a view target, and `APlayerCameraManager::SetViewTarget` then reads `PCOwner->Pawn`. **P1's camera manager is spawned before the world begins play, so its `BeginPlay` waits until `InitializeFor()` has set `PCOwner`**. P2's is spawned mid-game, so `BeginPlay` runs inside `SpawnActor` while `PCOwner` is still null (crash: read 0x258 = `Controller.Pawn`).

La solución aplicada ([main.lua:156-160](file:///Volumes/Disco%20Juan/Projects/Stray%20iOS/PortWorkspace/Stray-iOS-From-Scratch/work/external/repos/Stray-Local-Co-op-Mod/Mods/StrayCoop/Scripts/main.lua#L156-L160)):

```lua
pcall(NotifyOnNewObject, "/Game/Technical/BP_HKPlayerCameraManager.BP_HKPlayerCameraManager_C", function(cam)
    if spawningP2 and p2Controller and p2Controller:IsValid() then
        cam.PCOwner = p2Controller
    end
end)
```

**VERIFICADO**  
`AHKPlayerCameraManager` hereda de `APlayerCameraManager` y expone `PushCamera`/`PopCamera`; **no tiene `BeginPlay` propio** declarado en el header ([HKPlayerCameraManager.h:45-82](file:///Volumes/Disco%20Juan/Projects/Stray%20iOS/PortWorkspace/Stray-iOS-From-Scratch/work/external/repos/HK_Project/Source/Hk_project/Public/HKPlayerCameraManager.h#L45-L82)), lo que confirma que el `BeginPlay` que llama a `SetViewTarget`→`CheckViewTarget`→`PCOwner->Pawn` es el de la clase base `APlayerCameraManager` del engine.

**VERIFICADO**  
`isCinematicView(p1)` detecta el `ViewTarget` activo vía `p1:GetViewTarget()` ([main.lua:279-287](file:///Volumes/Disco%20Juan/Projects/Stray%20iOS/PortWorkspace/Stray-iOS-From-Scratch/work/external/repos/Stray-Local-Co-op-Mod/Mods/StrayCoop/Scripts/main.lua#L279-L287)); considera "cinemático" si la clase del `ViewTarget` contiene `"Cine"`, es `"CameraActor"` o P1 no tiene un `CatPawn`.

### Aplicabilidad a iOS

**HIPÓTESIS**  
El crash `PCOwner` nulo que el mod resuelve ocurre al añadir un **segundo jugador local** mediante `UGameplayStatics::CreatePlayer`, operación específica de co-op en Windows. En nuestro port iOS ejecutamos **un solo jugador**; el `AHKPlayerCameraManager` del jugador 1 se instancia en la ruta normal (antes de `BeginPlay`) y `PCOwner` se establece en `InitializeFor()` antes de que `BeginPlay` se ejecute. El crash descrito no aplica a nuestra configuración de un solo jugador.

Lo que **sí aplica** al port es la cámara cinemática (`CineCameraActor`, `BP_SplineCameraCine_*`): el mecanismo `PushCamera`/`PopCamera` de `AHKPlayerCameraManager` y el delegate `CameraChanged` ([HKPlayerCameraManager.h:23-26](file:///Volumes/Disco%20Juan/Projects/Stray%20iOS/PortWorkspace/Stray-iOS-From-Scratch/work/external/repos/HK_Project/Source/Hk_project/Public/HKPlayerCameraManager.h#L23-L26)) actúan igual en un solo jugador. Si hay errores de hilo en nuestra configuración durante una transición de cámara, el origen será distinto (ver Pregunta 5), no la ausencia de `PCOwner`.

---

## Pregunta 2 — Gato invisible (`m_visual`, colisores, `GetSkeletalMesh`, LOD, skin, huesos)

### Mapa de componentes verificados

**VERIFICADO — `CatPawn.h`**

| Símbolo | Tipo | Línea | Notas |
|---|---|---|---|
| `m_visual` | `USkeletalMeshComponent*` (protegida) | [CatPawn.h:114](file:///Volumes/Disco%20Juan/Projects/Stray%20iOS/PortWorkspace/Stray-iOS-From-Scratch/work/external/repos/HK_Project/Source/Hk_project/Public/CatPawn.h#L114) | Componente principal de malla del gato |
| `m_largeInteractionCollider` | `USphereComponent*` (protegida) | [CatPawn.h:120](file:///Volumes/Disco%20Juan/Projects/Stray%20iOS/PortWorkspace/Stray-iOS-From-Scratch/work/external/repos/HK_Project/Source/Hk_project/Public/CatPawn.h#L120) | Esfera de interacción amplia |
| `m_capsule` | `UCapsuleComponent*` | [CatPawn.h:117](file:///Volumes/Disco%20Juan/Projects/Stray%20iOS/PortWorkspace/Stray-iOS-From-Scratch/work/external/repos/HK_Project/Source/Hk_project/Public/CatPawn.h#L117) | Cápsula de colisión principal |
| `GetSkeletalMesh()` | `USkeletalMeshComponent*` (const) | [CatPawn.h:1364](file:///Volumes/Disco%20Juan/Projects/Stray%20iOS/PortWorkspace/Stray-iOS-From-Scratch/work/external/repos/HK_Project/Source/Hk_project/Public/CatPawn.h#L1364) | Accessor público que devuelve `m_visual` |

> [!NOTE]
> La versión auditada de `HK_Project` corresponde a **1.3#214**, no a 1.5#99. Los nombres de los campos son estables entre versiones menores pero los offsets de memoria en memoria ARM64 son completamente distintos.

**VERIFICADO — `main.lua` y colisores**  
`patchCatColliders` ([main.lua:106-138](file:///Volumes/Disco%20Juan/Projects/Stray%20iOS/PortWorkspace/Stray-iOS-From-Scratch/work/external/repos/Stray-Local-Co-op-Mod/Mods/StrayCoop/Scripts/main.lua#L106-L138)) muestra que el motivo de un gato invisible puede ser que el co-op no parchee la respuesta al canal `ECC_Pawn` del colisionador de interacción. El método de ocultamiento durante cinemáticas es `SetActorHiddenInGame(on)` ([main.lua:303](file:///Volumes/Disco%20Juan/Projects/Stray%20iOS/PortWorkspace/Stray-iOS-From-Scratch/work/external/repos/Stray-Local-Co-op-Mod/Mods/StrayCoop/Scripts/main.lua#L303)), que se llama **sólo sobre P2** cuando comienza una cinemática.

**VERIFICADO — Límite de huesos en Mobile**  
[Engine.ini:892](file:///Volumes/Disco%20Juan/Projects/Stray%20iOS/PortWorkspace/Stray-iOS-From-Scratch/work/external/reference_files/DOMEHero/Engine.ini#L892):
```ini
MaxSkinBones=(Default=65536,PerPlatform=(("Mobile", 256)))
```
Con `PerPlatform Mobile = 256`, si UE4 detecta la plataforma como `Mobile` (lo cual ocurre cuando `MTLGPUFamilyApple1` no es suprimido por el shim), el renderer reduce el límite de huesos de skinning a 256. El esqueleto del gato tiene más de 256 huesos en sus LODs de alta calidad, lo que provocaría que la malla no se renderice (gato invisible) o se renderice con skin corrupta.

**HIPÓTESIS**  
Si el shim `ShimSupportsFamily` que suprime `MTLGPUFamilyApple1-9` **no está activo**, UE4 entra en la ruta de iOS, aplica el límite de 256 huesos y el gato puede volverse invisible o mostrar pose en T. Esta hipótesis es consistente con los edits recuperados en `recovered_edits_all.txt` que modifican `ShimSupportsFamily` para suprimir exactamente esas familias GPU.

**HIPÓTESIS**  
El LOD de Zurg (`EZurgLOD`) existe en el sistema de enemigos ([ZurgPawnLeader.h:119](file:///Volumes/Disco%20Juan/Projects/Stray%20iOS/PortWorkspace/Stray-iOS-From-Scratch/work/external/repos/HK_Project/Source/Hk_project/Public/ZurgPawnLeader.h#L119), [ZurgManager.h:58](file:///Volumes/Disco%20Juan/Projects/Stray%20iOS/PortWorkspace/Stray-iOS-From-Scratch/work/external/repos/HK_Project/Source/Hk_project/Public/ZurgManager.h#L58)), pero no existe un sistema LOD equivalente documentado para el `CatPawn` en las headers disponibles.

---

## Pregunta 3 — Geometría roja/blanca de Run 11 (debug walkable vs. artefacto de shim)

### Evidencia en `HKPlayerController.h`

**VERIFICADO**  
`AHKPlayerController` declara ([HKPlayerController.h:74-80](file:///Volumes/Disco%20Juan/Projects/Stray%20iOS/PortWorkspace/Stray-iOS-From-Scratch/work/external/repos/HK_Project/Source/Hk_project/Public/HKPlayerController.h#L74-L80)):
```cpp
TArray<FWalkableDebuggedPrimitive> m_walkableDebuggedPrimitives;
UMaterialInterface* m_walkableDebugMaterial;
UMaterialInterface* m_movementObstacleDebugMaterial;
```
Con el método público ([HKPlayerController.h:106](file:///Volumes/Disco%20Juan/Projects/Stray%20iOS/PortWorkspace/Stray-iOS-From-Scratch/work/external/repos/HK_Project/Source/Hk_project/Public/HKPlayerController.h#L106)):
```cpp
void SetWalkableDebugModeEnabled(bool _enabled);
```

**VERIFICADO — `FWalkableDebuggedPrimitive`**  
([WalkableDebuggedPrimitive.h:8-15](file:///Volumes/Disco%20Juan/Projects/Stray%20iOS/PortWorkspace/Stray-iOS-From-Scratch/work/external/repos/HK_Project/Source/Hk_project/Public/WalkableDebuggedPrimitive.h#L8-L15)):
```cpp
USTRUCT(BlueprintType)
struct FWalkableDebuggedPrimitive {
    TArray<UMaterialInterface*> Materials;
};
```
La estructura almacena los materiales originales de las primitivas antes de que el modo debug los reemplace con `m_walkableDebugMaterial` (presumiblemente rojo) y `m_movementObstacleDebugMaterial` (presumiblemente blanco/naranja).

### Evaluación de la hipótesis

**HIPÓTESIS (plausible, no confirmada sin logs de Run 11)**  
La geometría roja/blanca observada en Run 11 es consistente con `SetWalkableDebugModeEnabled(true)` activo. Dos fuentes de activación posibles en un binario Shipping:

1. Una llamada Blueprint a `SetWalkableDebugModeEnabled` disparada por error durante la inicialización (p.ej. una secuencia de BP que se ejecuta en modo debug y no fue excluida del cocinado).
2. Un valor de propiedad serializado en el `AHKPlayerController` del nivel que tiene `m_walkableDebugMaterial` asignado.

**CONTRA-HIPÓTESIS: artefacto del shim**  
Si la geometría afectada es **universal** (todos los meshes de la escena, no solo primitivas del camino del gato) o si su color varía por frame (flickering), es más probable que sea un artefacto de formato de textura incorrecto — por ejemplo, BC7 renderizado en tabla ASTC por `MTLGPUFamilyApple1` sin suprimir, que el shim `ShimSupportsFamily` resuelve según el edit recuperado.

**Distinción clave:** si el debug walkable está activo, **sólo las primitivas geométricas del navmesh/walkable** deberían aparecer con el material de debug; el resto de la escena quedaría normal. Si toda la escena aparece roja/blanca, el origen es el shim/textura.

---

## Pregunta 4 — Transiciones / recargas (`ai.lua`, `RestartPlayer`, `SetForceDisableSplitscreen`, cámaras cinemáticas)

### Referencias destruidas tras nivel

**VERIFICADO**  
`ai.lua:7` advierte explícitamente:
> "Enemies are looked up fresh every call (never cached): Stray destroys them on level loads and reloads."

Y `ai.lua:51-53`:
> "Only the swarm leaders' cached cat is retargeted. `AZurgManager.m_catPawn` is deliberately left on Player 1: it's the game-wide 'player cat' that other systems (chase cameras, pursuit state) read, and pointing it at Player 2 crashed the game in the camera code after the first Zurk chase."

**VERIFICADO — Campos confirmados en headers**  
- `ZurgManager.m_catPawn` ([ZurgManager.h:83](file:///Volumes/Disco%20Juan/Projects/Stray%20iOS/PortWorkspace/Stray-iOS-From-Scratch/work/external/repos/HK_Project/Source/Hk_project/Public/ZurgManager.h#L83)): `ACatPawn*`  
- `ZurgPawnLeader.m_cachedPlayerCatPawn` ([ZurgPawnLeader.h:101](file:///Volumes/Disco%20Juan/Projects/Stray%20iOS/PortWorkspace/Stray-iOS-From-Scratch/work/external/repos/HK_Project/Source/Hk_project/Public/ZurgPawnLeader.h#L101)): `ACatPawn*`

### `RestartPlayer`

**VERIFICADO**  
`main.lua:258`:
```lua
gm:RestartPlayer(p2)
if isCat(p2.Pawn) then bringP2ToP1(p1.Pawn, p2.Pawn) end
```
`RestartPlayer` es un método de `AGameModeBase`; tras un nivel reload de Stray, P2 pierde su `Pawn` y el mod llama `RestartPlayer` después de `RESPAWN_DELAY = 3` segundos.

### `SetForceDisableSplitscreen`

**VERIFICADO**  
`main.lua:301`:
```lua
UEHelpers.GetGameplayStatics():SetForceDisableSplitscreen(p1, on)
```
Se llama al inicio y fin de cada cinemática. **En un port de un solo jugador (iOS) esta llamada no existe y no es necesaria**; sin embargo el patrón de ocultar el `Pawn` secundario con `SetActorHiddenInGame` durante cinemáticas sí puede inspirar una solución si en iOS el gato aparece visible durante FMV.

### Cámaras cinemáticas

**VERIFICADO**  
`isCinematicView` ([main.lua:278-287](file:///Volumes/Disco%20Juan/Projects/Stray%20iOS/PortWorkspace/Stray-iOS-From-Scratch/work/external/repos/Stray-Local-Co-op-Mod/Mods/StrayCoop/Scripts/main.lua#L278-L287)) detecta:
- `cls:find("Cine") ~= nil` → actores `CineCameraActor`, `BP_SplineCameraCine_*`
- `cls == "CameraActor"`
- P1 sin `CatPawn` (nivel de menú, loading)

`AHKPlayerCameraManager` usa `PushCamera`/`PopCamera` con `EViewTargetBlendFunction` y `EInputTransitionMode` ([HKPlayerCameraManager.h:53-59](file:///Volumes/Disco%20Juan/Projects/Stray%20iOS/PortWorkspace/Stray-iOS-From-Scratch/work/external/repos/HK_Project/Source/Hk_project/Public/HKPlayerCameraManager.h#L53-L59)); el delegate `CameraChanged` se dispara en cada transición.

**HIPÓTESIS**  
Las transiciones de cámara que requieren `CheckViewTarget` podrían ser problemáticas si hay una ventana en la que `PCOwner` es temporalmente nulo en el shim. En un solo jugador este escenario solo ocurriría si el controlador se destruye y recrea (por ejemplo, `RestartPlayer` en nuestra hipotética solución de respawn en iOS), no durante operación normal.

---

## Pregunta 5 — Hilo principal: `ExecuteInGameThread`, `LoopAsync`, `NotifyOnNewObject`

### Patrones observados

**VERIFICADO — `LoopAsync` + `ExecuteInGameThread`**  
El mod usa dos timers independientes:

```lua
-- Timer 1: cutscene check, 250 ms
LoopAsync(250, function()
    if coopEnabled and not cutsceneBusy then
        cutsceneBusy = true
        ExecuteInGameThread(function() ... cutsceneBusy = false end)
    end
    return false
end)

-- Timer 2: main tick, 1000 ms
LoopAsync(LOOP_MS, function()
    if coopEnabled and not busy then
        busy = true
        ExecuteInGameThread(function() ... busy = false end)
    end
    return false
end)
```
([main.lua:349-372](file:///Volumes/Disco%20Juan/Projects/Stray%20iOS/PortWorkspace/Stray-iOS-From-Scratch/work/external/repos/Stray-Local-Co-op-Mod/Mods/StrayCoop/Scripts/main.lua#L349-L372))

El flag `busy`/`cutsceneBusy` evita reentrancia. **Todo acceso a objetos UE se hace dentro de `ExecuteInGameThread`**.

**VERIFICADO — `NotifyOnNewObject` llamado desde hilo Lua**  
`installHooks` ([main.lua:150-168](file:///Volumes/Disco%20Juan/Projects/Stray%20iOS/PortWorkspace/Stray-iOS-From-Scratch/work/external/repos/Stray-Local-Co-op-Mod/Mods/StrayCoop/Scripts/main.lua#L150-L168)) llama `NotifyOnNewObject` y `RegisterHook` en el hilo Lua, no dentro de `ExecuteInGameThread`. La callback sí puede ejecutarse desde el game thread cuando UE crea el objeto.

**VERIFICADO — `menu.lua` LoopAsync para UI**  
`menu.lua:164` y `menu.lua:197` tienen dos `LoopAsync` propios (100 ms y 1000 ms), ambos con `ExecuteInGameThread` para toda manipulación de widgets.

### Riesgo en nuestro shim

**HIPÓTESIS**  
En `macos-on-ios-public`, el shim convierte el modelo de threading de macOS a iOS. Si `LoopAsync` crea un hilo Objective-C o POSIX que no tiene un `NSRunLoop`, y la callback de `NotifyOnNewObject` se despacha en ese hilo en lugar del game thread, podemos ver el `mutex lock failed` + signal 6 que ya se observó. **Este es un riesgo real** porque UE4SS está diseñado para Windows donde `LoopAsync` delega en el scheduler de Win32; en nuestro shim el scheduler es distinto.

**HIPÓTESIS**  
El error `mutex lock failed` puede también surgir si `ExecuteInGameThread` en UE4SS encola trabajo en `FRunnableThread` de UE4, y el hilo principal del proceso en iOS (manejado por el shim) no hace `tick` de esa cola. Sin embargo, **UE4SS no está disponible en iOS** (ver Pregunta 6), por lo que este riesgo es teórico para nuestra arquitectura actual.

---

## Pregunta 6 — `tracer.lua`: portabilidad a iOS

### Qué hace `tracer.lua`

**VERIFICADO**  
`tracer.lua` ([tracer.lua:1-74](file:///Volumes/Disco%20Juan/Projects/Stray%20iOS/PortWorkspace/Stray-iOS-From-Scratch/work/external/repos/Stray-Local-Co-op-Mod/Mods/StrayCoop/Scripts/tracer.lua)):
1. Recorre la cadena de herencia de clases via `class:ForEachFunction` y `class:GetSuperStruct()`.
2. Llama `RegisterHook` en cada función Blueprint no-Tick (~650 hooks).
3. Usa `NotifyOnNewObject` para loggear spawns de `Actor`, `ActorComponent`, `UserWidget`.
4. Traza `ClientRestart`, `ClientSetHUD`, `ClientSetViewTarget` del engine.

Está diseñado para correr mientras `spawningP2 = true` y se activa con `tracer.active = true`.

### Portabilidad a iOS

**NO PORTABLE** — por múltiples razones:

| Razón | Detalle |
|---|---|
| **UE4SS es Windows-only** | El README de RE-UE4SS ([RE-UE4SS/README.md:69](file:///Volumes/Disco%20Juan/Projects/Stray%20iOS/PortWorkspace/Stray-iOS-From-Scratch/work/external/repos/RE-UE4SS/README.md#L69)) dice explícitamente: "Windows is required for native builds. Native Linux builds are not currently supported." No existe build macOS ni iOS. |
| **APIs de UE4SS ausentes** | `RegisterHook`, `NotifyOnNewObject`, `FindAllOf`, `FindFirstOf`, `LoopAsync`, `ExecuteInGameThread` son APIs de UE4SS que no están disponibles fuera de su runtime. |
| **Hook sobre bytecode BP** | `RegisterHook` intercepta el bytecode Kismet en memoria. En iOS (ARM64, Shipping), el bytecode está en el PAK cifrado y no hay mecanismo de intercepción disponible sin UE4SS. |
| **Instalación en Win64 Binaries** | StrayAP README confirma: instalar en `Hk_project/Binaries/Win64/` — ruta inexistente en nuestro binario macOS arm64. |

**Lo que tracer.lua SÍ aporta como técnica de referencia:**  
El patrón de `hookClassChain` — recorrer la jerarquía de clases via reflexión UHT/UE y hookear funciones — puede implementarse en un shim de macOS mediante `method_swizzling` de Objective-C, pero requeriría identificar las funciones por símbolo (disponibles en nuestro binario no-stripped) en lugar de por `GetFullName()` de UE4SS.

---

## Pregunta 7 — Herramientas de análisis de PAK/uassets en macOS

### UAssetAPI / UAssetGUI

**VERIFICADO — Plataforma**  
Target framework: `net10.0` ([UAssetAPI.csproj](file:///Volumes/Disco%20Juan/Projects/Stray%20iOS/PortWorkspace/Stray-iOS-From-Scratch/work/external/repos/UAssetAPI/UAssetAPI/UAssetAPI.csproj)). .NET 10 corre en macOS arm64 vía `dotnet` CLI. **Portable a macOS.**

**VERIFICADO — Capacidades PAK**  
`UAssetAPI/Pak/RePak.cs` expone `pak_reader_get`, `pak_reader_files`, `pak_reader_mount_point` via P/Invoke a una librería nativa Rust (`RePak`). Puede leer contenido de PAK versión UE4 y extraer archivos individuales. Puede leer y escribir `.uasset` de UE4.13 a 5.7.

**VERIFICADO — Licencia**  
MIT ([README.md:38-39](file:///Volumes/Disco%20Juan/Projects/Stray%20iOS/PortWorkspace/Stray-iOS-From-Scratch/work/external/repos/UAssetAPI/README.md#L38-L39)). Permite uso en proyecto.

| Capacidad | ¿Funciona en macOS? |
|---|---|
| Leer `.uasset` UE4 (cooked, Stray) | **SÍ** — net10 + AnyCPU |
| Leer PAK / extraer entradas | **SÍ** (via RePak, necesita build arm64 de la lib nativa) |
| Escribir / parchear `.uasset` | **SÍ** |
| Volcado JSON de propiedades BP | **SÍ** |
| Leer bytecode Kismet raw | **SÍ** |
| GUI (UAssetGUI) | **NO** — WinForms, requiere Windows |

> [!CAUTION]
> La librería nativa `RePak` (Rust) incluida en el paquete NuGet puede ser un binario Windows. Para macOS arm64 se necesita compilar `repak` desde fuentes. La funcionalidad de `.uasset` puro (sin PAK) no depende de RePak y sí funciona directamente.

### UEAssetToolkitGenerator / CookedAssetSerializer

**VERIFICADO — Capacidades**  
`CookedAssetSerializer` serializa assets cocinados de Stray a JSON para reimportarlos en el editor UE4. Requiere acceso a los assets desempaquetados (ya extraídos del PAK). `AssetDumper` requiere correr el juego en Shipping con un plugin instalado — no aplicable a nuestro binario sin fuente.

**VERIFICADO — Plataforma**  
Proyecto .NET (C#), pero el `AssetDumper` de `UEAssetToolkit` requiere integración en el binario de juego. El serializador sí puede correr en macOS para procesar assets ya extraídos.

**VERIFICADO — Licencia**  
No explícita en README de `UEAssetToolkit`. `UEAssetToolkitGenerator/NOTICE.md` cita MIT para UAssetAPI y Json.NET.

| Herramienta | Útil para iOS port | Notas |
|---|---|---|
| **UAssetAPI** | ✅ Sí | Leer/escribir uassets Stray en macOS |
| **UAssetGUI** | ❌ No | Solo Windows |
| **CookedAssetSerializer** | ⚠️ Parcial | Serializa assets ya extraídos; sirve para inspección |
| **AssetDumper plugin** | ❌ No | Necesita compilar en el binario de juego |
| **CUE4Parse** | **PENDIENTE** | No está en los repos auditados; es una alternativa .NET que sí soporta extracción de PAK de UE4 |
| **RE-UE4SS** | ❌ No portable | Windows-only |

### Lo que NO es portable

- **RE-UE4SS**: runtime de Windows, no existe en macOS/iOS.
- **UAssetGUI**: WinForms.
- **AssetDumper (plugin en juego)**: requiere rebuild del binario.
- **Offsets de `CXXAllAssets1.3-214`**: generados por UE4SS en Win64; inválidos para arm64 y para versión 1.5#99.

---

## Pregunta 8 — ICU: `EditorOpenOrder.log` y `DirectoryIndexKeepFiles`

### `EditorOpenOrder.log` — 893 rutas ICU

**VERIFICADO**  
El log tiene 2382 líneas ([EditorOpenOrder.log](file:///Volumes/Disco%20Juan/Projects/Stray%20iOS/PortWorkspace/Stray-iOS-From-Scratch/work/external/reference_files/DOMEHero/EditorOpenOrder.log)), de las cuales **893** contienen rutas `icudt64l`:

```
"../../../Engine/Content/Internationalization/icudt64l/cnvalias.icu" 413
"../../../Engine/Content/Internationalization/icudt64l/res_index.res" 414
"../../../Engine/Content/Internationalization/icudt64l/plurals.res" 415
"../../../Engine/Content/Internationalization/icudt64l/lang/zh_CN.res" 416
...
"../../../Engine/Content/Internationalization/icudt64l/en.res" 437
"../../../Engine/Content/Internationalization/icudt64l/root.res" 438
"../../../Engine/Content/Internationalization/icudt64l/supplementalData.res" 439
```
([EditorOpenOrder.log:413-439](file:///Volumes/Disco%20Juan/Projects/Stray%20iOS/PortWorkspace/Stray-iOS-From-Scratch/work/external/reference_files/DOMEHero/EditorOpenOrder.log#L413-L439))

**Qué aporta:** Este log registra el orden en que el **editor** de UE4 abre archivos; **no es el orden de acceso en runtime de juego**. Sin embargo, es la mejor referencia disponible del árbol completo de `icudt64l` que el engine de UE4.27 necesita, confirmando que:
1. Los archivos se abren secuencialmente desde el tope (`cnvalias.icu` → `res_index.res` → `plurals.res`).
2. Los locales mínimos para un juego con soporte zh/en son los archivos de las líneas 413–439 más la línea 647-649 (locale zh_CN separado).
3. El árbol completo de 3.463 ficheros que el port ya desplegó cubre todos los locales, incluido el subconjunto mínimo.

**VERIFICADO**  
`CookerOpenOrder.log` tiene **0 referencias ICU**: el cooker no abre archivos ICU porque los empaqueta como blobs binarios en el PAK, no como ficheros individuales. Esto confirma que la ruta de acceso ICU en runtime **no pasa por el PAK** sino por el sistema de ficheros directamente.

### `DirectoryIndexKeepFiles`

**VERIFICADO — `Engine.ini:1787`**  
([Engine.ini:1787](file:///Volumes/Disco%20Juan/Projects/Stray%20iOS/PortWorkspace/Stray-iOS-From-Scratch/work/external/reference_files/DOMEHero/Engine.ini#L1787)):
```ini
DirectoryIndexKeepFiles=*/Content/Internationalization/*
```
Esta directiva le indica al sistema de paquetización que el índice del directorio `Content/Internationalization/` debe preservarse explícitamente, incluso si los archivos individuales dentro de él están marcados como no-críticos por otras reglas. Combinado con `ExtensionsToNotUsePluginCompression=icu` ([Engine.ini:1782](file:///Volumes/Disco%20Juan/Projects/Stray%20iOS/PortWorkspace/Stray-iOS-From-Scratch/work/external/reference_files/DOMEHero/Engine.ini#L1782)), esto garantiza que los `.icu` y `.res` no sean comprimidos por el plugin de compresión (evita descompresión en runtime).

**HIPÓTESIS**  
La directiva `Internationalization=Documents/stray/StrayICU` que resolvió el bloqueo ICU en la prueba del 2026-11-23 redirige la búsqueda de ICU al sistema de ficheros del app container de iOS, que sí tiene el árbol `icudt64l` desplegado. El engine usa la ruta como prefijo en `FPaths::EngineContentDir()` + `Internationalization/icudt64l`; cuando el directorio no existe en la sandbox de iOS pero sí en `Documents/stray/StrayICU`, la redirección es necesaria y suficiente.

---

## Resumen ejecutivo por bloqueo activo

### Bloqueo actual: `Unreal Engine does not support running from case-sensitive file systems`

**VERIFICADO — Shim histórico**  
El hook `ShimURLGetResourceValue` ([fulltext/e5026e30/step_01057.txt:136-142](file:///Volumes/Disco%20Juan/Projects/Stray%20iOS/PortWorkspace/Stray-iOS-From-Scratch/work/antigravity/fulltext/e5026e30-f1f5-4d12-83cb-05324d72547d/step_01057.txt#L136-L142)) fue desarrollado en la sesión `e5026e30`:

```objc
static BOOL ShimURLGetResourceValue(NSURL *self, SEL _cmd, id *value, NSURLResourceKey key, NSError **error) {
    if ([key isEqualToString:NSURLVolumeSupportsCaseSensitiveNamesKey] && self.isFileURL) {
        *value = @NO;
        return YES;
    }
    return ((BOOL (*)(id, SEL, id *, NSURLResourceKey, NSError **))gURLGetResourceValue)(self, _cmd, value, key, error);
}
```

**VERIFICADO — Estado actual del clon público**  
`grep` en `upstream/macos-on-ios-public/shim/overrides/AppKit_RuntimeHooks.m` encuentra **sólo** `ShimURLForResource` (intercepta `URLForResource:withExtension:`). **No hay** `ShimURLGetResourceValue` ni `NSURLVolumeSupportsCaseSensitiveNamesKey` en el clon actual. El método swizzled en `AppKit_RuntimeHooks.m:95` es distinto.

**Acción necesaria (a implementar en el shim, NO en este documento):**  
Añadir `ShimURLGetResourceValue` que devuelva `@NO` para `NSURLVolumeSupportsCaseSensitiveNamesKey` e instalar el swizzle en la función de setup de `AppKit_RuntimeHooks.m`.

---

## Inventario de evidencias por fuente

| Fuente | Versión auditada | Licencia | Uso principal |
|---|---|---|---|
| `Stray-Local-Co-op-Mod` | commit 9d1d696 | No declarada (código de mod) | Evidencia de comportamiento de motor UE4 en Stray |
| `HK_Project` | cc92879 | "as-is", sin licencia OSS | Headers UHT — mapa de clases (1.3#214) |
| `Hk_CXX-and-UHT` | 0a7ee57 | "as-is", stubs C++/UHT | Solo como mapa de offsets Win64/1.3#214 — NO aplicar a arm64/1.5#99 |
| `UAssetAPI` | HEAD | MIT | Lectura/escritura de uassets en macOS |
| `UEAssetToolkit` | HEAD | No declarada explícitamente | Referencia; AssetDumper no portable |
| `UEAssetToolkitGenerator` | HEAD | MIT (via NOTICE.md) | Serialización de assets cocinados |
| `RE-UE4SS` | HEAD | — | Windows-only; no portable |
| `DOMEHero/Engine.ini` | — | — | Referencia de configuración (otro juego UE4) |
| `DOMEHero/EditorOpenOrder.log` | — | — | Mapa de árbol ICU |
| `gist-d6c6522a` | — | — | Ejemplo mínimo de mod UE4SS |
| `StrayAP` | HEAD | — | Referencia de arquitectura de mod UE4SS |
| `StrayModdingWiki` | HEAD | — | Referencia de ModLoader (Windows/Steam) |
| `work/antigravity/fulltext/e5026e30/step_01057.txt` | — | — | VERIFICADO: `ShimURLGetResourceValue` desarrollado en sesión previa |
| `work/antigravity/recovered_edits_all.txt` | — | — | VERIFICADO: `ShimSupportsFamily` para suprimir GPU Apple families |

---

## Pendientes sin resolución por falta de fuentes

1. **Comportamiento exacto de `SetWalkableDebugModeEnabled` en Shipping**: el `.cpp` correspondiente no está en los repos auditados (solo el stub vacío en `HK_Project/Private/HKPlayerController.cpp`). No es posible confirmar si el modo debug queda activo en Shipping builds o si existe un guard `#if !UE_BUILD_SHIPPING`.
2. **CUE4Parse**: no clonado; sería la alternativa multiplataforma más robusta para extracción de PAK.
3. **Comportamiento de `LoopAsync` en el shim**: requiere prueba en dispositivo para verificar si los callbacks se ejecutan en el hilo correcto bajo iOS.
4. **Logs de Run 11**: sin los logs del run 11 no es posible distinguir el debug walkable de un artefacto de textura.

---

*Documento generado 2026-11-23 por auditoría de solo lectura. Ningún fichero del proyecto fue modificado.*
