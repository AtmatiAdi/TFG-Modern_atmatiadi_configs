# Brief przekazania — stan na 2026-07-23

Instancja: `c:\Users\atmat\AppData\Roaming\PrismLauncher\instances\TerraFirmaGreg-Modern`
(MC 1.20.1, Forge 47.4.13, TFG-Modern 0.13.1, **257 modów**). Repo git w rocie instancji.

---

## GŁÓWNE USTALENIE: pamięć jest rozbita co do modułu

Pytanie „który mod ile zajmuje" zostało **rozstrzygnięte pomiarem**. Rozbicie procesu
(menu główne, ~11,4 GB, ślad ETW `VirtualAlloc` ze stosami):

| moduł | Exc | udział | co to jest |
|---|---|---|---|
| `jvm` | **4,03 GB** | 34,5% | sama JVM: sterta, metaspace, JIT — zgodne z NMT |
| **`nvoglv64`** | **3,34 GB** | 28,6% | **sterownik OpenGL NVIDII (backing WDDM w RAM)** |
| **`effekseernativeforjava`** | **1,03 GB** | 8,8% | **natywna biblioteka moda `aaa_particles`** |
| `?!?` | 781 MB | 6,7% | ramki kodu JIT Javy |
| `vcruntime140` + `ucrtbase` | 1,30 GB | 11,1% | malloc bibliotek natywnych |
| `lwjgl_stb` | 388 MB | 3,3% | dekodowanie tekstur |
| `zip` | 205 MB | 1,8% | rozpakowywanie 257 jarów |
| `win32u` / `nio` | 286 MB | 2,4% | GDI / kanały NIO |
| `jemalloc` | 71 MB | 0,6% | alokator LWJGL |

**Kontrola krzyżowa**: „niewyjaśnione 5,8 GB" z `mem-budget.ps1` rozkłada się na
`nvoglv64` 3,34 + `effekseer` 1,03 + `vcruntime` 0,77 + `ucrtbase` 0,54 + `stb` 0,39
= **6,07 GB**. Dwie niezależne metody dają zgodny wynik.

---

## DLACZEGO PROBLEM ZALEŻY OD MASZYNY (klucz do priorytetów)

| maszyna | GPU | VRAM | objawy |
|---|---|---|---|
| laptop A | RTX 4050 Laptop | **6 GB** | stronicowanie, przycięcia |
| laptop B (16 GB RAM) + stacja TB4 | RTX 4080 SUPER | **16 GB** | dużo RAM, ale **nigdy** stronicowania |
| **laptop docelowy** | **Radeon 780M (iGPU)** | **brak własnej** | cel optymalizacji, brak TB4 |

Windows (WDDM) trzyma w RAM systemowym kopie zasobów GPU, żeby móc je wywłaszczać.
Im mniej VRAM, tym więcej pracy po stronie RAM. To wyjaśnia te 3,34 GB w `nvoglv64`
oraz to, czemu na 4080S problem nie występuje.

**Prognoza dla 780M: będzie najgorzej.** iGPU nie ma własnej pamięci — zasoby graficzne
kosztują RAM podwójnie. Dlatego **redukcja zasobów graficznych jest dla maszyny
docelowej ważniejsza niż cokolwiek po stronie Javy.**

---

## SHADERY: kluczowy kontekst wszystkich pomiarów

**`config/oculus.properties` → `enableShaders=false`.** Wszystkie nasze pomiary
(agent2/3/4, bez-aaa, ślad ETW) robione były **z shaderami WYŁĄCZONYMI**. Zatem
**3,34 GB sterownika to baseline zasobów GPU modów (tekstury+geometria) BEZ shaderów.**
Z shaderami ON będzie WYŻSZY. Użytkownik nie zauważył, że są off — w tych testach
nie grał, tylko menu.

**EuphoriaPatcher pada przy KAŻDYM starcie — ROZSTRZYGNIĘTE, NIESZKODLIWE.**
Pakiet `TerraFirmaGreg-Shaders-Complementary-3.1.5.zip` to **samodzielny prekompilowany**
Complementary Reimagined + Euphoria (wbudowane `new_Euphoria_Version.glsl`,
`euphoria_patches.png`) + łatki TFG (`TerraFirmaGreg.glsl`, `block.properties` 2,4 MB
mapujący custom bloki). Mod EuphoriaPatcher próbuje na żywo załatać CZYSTY Complementary
r5.8.1, którego nie ma → loguje błąd i nic nie robi. Shadery u użytkownika zawsze
działały. **Nie podmieniać pakietu** (czysty psuje custom bloki TFG). **Nie usuwać
EuphoriaPatchera** (`iris_shader_folder`, `supplemental_patches` odwołują się doń
w mods.toml). Szczegóły: pamięć `shader-pack-tfg`.

**Light-config zastosowany** (commit ea493a0, plik `...zip.txt`, kopia `.bak-2026-07-23`):
- `COLORED_LIGHTING` 128 → 64 (główny pożeracz RAM/VRAM: woksele kolorowego światła)
- `shadowDistance` 64 → 48
Reszta gałek nietknięta (generated normals, coated textures, odbicia, anizotropia).

**ATRYBUCJA STEROWNIKA PRZEZ ETW = ŚLEPY ZAUŁEK (potwierdzone empirycznie).**
Callers `nvoglv64` nie zawierają go w ogóle — sterownik alokuje 3,34 GB na własnych
wątkach, bez stosu prowadzącego do kodu moda. W widoku zostają gołe wątki
(CompilerThread, G1, ResourceReload) po kilka MB + effekseer 120 MB. Nie ma jak
przypisać RAM sterownika do konkretnego moda tą drogą. Zostaje pomiar różnicowy
(ale shaderów NIE wyłączamy na stałe — tylko config) albo sesja na 780M z realnym
sterownikiem AMD.

## POMIAR W ŚWIECIE, RTX 4050 (real gameplay) — źródło stutterów

Pierwszy pomiar na maszynie, która FAKTYCZNIE się tnie (4050, 6 GB VRAM, ~16 GB RAM),
w świecie, ten sam świat/miejsce, light-config aktywny:

| | shadery OFF (1012) | shadery ON (1004) | różnica |
|---|---|---|---|
| **Total commit** | 15 914 MB | **18 394 MB** | **+2 480 MB (shadery)** |
| POZA JVM | 9 079 | 11 597 | +2 518 |
| JVM (heap) | 6 267 (4 984) | 6 230 (4 960) | ~0 (shadery nie ruszają sterty) |
| Working set | 11 726 | 12 030 | |

**PRZYCZYNA STUTTERÓW ZNALEZIONA**: proces chce 18,4 GB commitu na maszynie z 16 GB RAM
→ **2,4 GB ponad fizyczny RAM** → stronicowanie → przycięcia co ~60 s. Bez shaderów
15,9 GB — i tak na krawędzi. Na 4080S/32GB (dok) problem nie występował: było miejsce.

**Koszt shaderów = 2,48 GB** (różniczka, ten sam świat) — i to JUŻ po light-configu.
Shadery to główny pojedynczy czynnik przepychający grę przez próg 16 GB.

Rozbicie 18,4 GB (wykres w artefakcie): reszta natywna 8 087 (sterownik GPU+libki),
sterta Java 4 960, shadery 2 480, narzut JVM 1 270, Effekseer 1 030, DLL+mapped 567.

### Dodatkowe gałki configów znalezione (do rozważenia, malejący zysk)
- **DistantHorizons `lodChunkRenderDistanceRadius = 256`** → 128. NAJWIĘKSZY nowy zysk
  RAM/GPU (LOD dalekich chunków). Koszt: bliższy horyzont LOD.
- **AllTheLeaks** `ingredientDedupe`, `resourceLocationDedupe` = false → true (dedup sterty).
- **FerriteCore** `compactFastMap` = false → true (mniej sterty).
- ModernFix `dynamic_resources` = true — JUŻ włączone przez autorów (dobrze).

### Kolejny możliwy krok: profil "TFG-Light"
Zamiast pisać shader od zera (niewykonalne — `block.properties` 2,4 MB mapuje custom
bloki TFG), przygotować agresywny profil ustawień istniejącego pakietu (kolorowe
światło off, cienie/odbicia niżej), przełączany podmianą pliku `...zip.txt`.

## Co jest OBALONE — nie wracać do tego

| trop | werdykt | dowód |
|---|---|---|
| **jemalloc / 88 aren** | **OBALONY** | regiony alokatora 681,7 MB na 676,5 MB żywych = narzut **5,1 MB (0,75%)**. `JE_MALLOC_CONF` nie ma czego odzyskiwać |
| **Direct buffers** | obalony | 33 MB. `MaxDirectMemorySize` bezużyteczne |
| **Atlasy tekstur** | obalony | suma 200–300 MB |
| **ModernFix `dynamic_resources`** | już włączone przez autorów paczki | |
| **„Wypiekanie" modów** | bezcelowe | cały kod 257 modów to 407 MB metaspace |
| **TACZ używa Effekseera** | **NIEPRAWDA** | skan constant pool: `tacz`, `tacz-tweaks`, `particle_core` mają **zero** odwołań. Effekseer jest wyłącznie w `aaa_particles` |
| **LWJGL DebugAllocator** | nie działa tutaj | raport drukuje się po wyłączeniu log4j |
| **Księgowanie GL bajtkodem** | **niemożliwe** | `glBindTexture`, `glBindBuffer`, `nglTexImage2D`, `nglBufferData` w LWJGL są metodami **natywnymi** — nie ma tam bajtkodu |

---

## Pułapki środowiska — kosztowały nas po jednej sesji każda

1. **Forge ładuje LWJGL własnym class loaderem** (`cpw.mods.cl.ModuleClassLoader`,
   moduł JPMS `org.lwjgl.jemalloc`). Klasa podstawiona z class patha agenta
   implementuje interfejs z *innej kopii* LWJGL → cichy `ClassCastException`.
   → Wstrzykiwany kod może wołać **tylko sygnatury na typach prostych**,
   a liczniki muszą siedzieć w class loaderze **bootstrap**.
   → Potrzebny `Instrumentation.redefineModule`, inaczej `IllegalAccessError`.

2. **Nie wnosić na classpath gry bibliotek, których Forge używa sam.**
   Prism uruchamia Forge z **ASM 9.8 na zwykłym classpathie** (bez `-p`).
   Wtopienie ASM 9.9.1 do jara agenta wywalało grę przy starcie, bez crash-reportu
   i bez jednej linii w `latest.log`. → ASM tylko przy budowaniu.

3. **Logować do własnego pliku, nie na stderr.** Forge przekierowuje stderr do log4j.

4. **Pole argumentów JVM w Prism wkleja się w CAŁOŚCI**, nie dopisuje.
   Raz skasowało to wszystkie flagi G1 i `NativeMemoryTracking`.

5. **ETW: nie przycinać zdarzeń jądra.** `Process,Thread,ImageLoad,VirtualAlloc`
   daje małe pliki, ale odcina chodzenie po stosie — cała pamięć ląduje jako `Exc`
   na gołym węźle wątku. Używać `Default,VirtualAlloc`.

6. **ETW: ślad włączyć PRZED startem gry.** Szukana pamięć powstaje w pierwszych ~45 s.
   Skrypt teraz sam przerywa, gdy `javaw` już działa.

7. **Zrzut agenta przy zamykaniu nadpisywał migawkę** ze stanu ustalonego
   (676 → 307 MB). Teraz idzie do osobnych plików `*-final.csv`.

---

## Narzędzia (wszystkie własne, w repo)

| narzędzie | co robi |
|---|---|
| `scripts/mem-budget.ps1` | **pełny budżet procesu**, suma WS spina się do −0,1 MB. `-AgentAddr` zderza adresy z regionami |
| `scripts/build-mod-index.ps1` | mapa pakiet→mod z 257 jarów (5179 jednoznacznych prefiksów) |
| `scripts/heap-by-mod.ps1` | atrybucja histogramu sterty do modów |
| `scripts/trace-virtualalloc.ps1` | ślad ETW `VirtualAlloc` (PerfView). `-Analyze` otwiera gotowy ślad |
| `tools/ramattr/` | agent: księguje alokacje natywne LWJGL per mod (`build.ps1`) |
| `scripts/session-monitor.ps1` | rejestrator sesji (RAM/GPU/stronicowanie) |

### Jak powtórzyć pomiar ETW (najważniejsza procedura)
1. **Zamknij grę.** PowerShell **jako administrator**:
   `pwsh -File scripts\trace-virtualalloc.ps1`
2. Skrypt czeka → **dopiero teraz uruchom grę** → menu główne → Enter.
3. `pwsh -File scripts\trace-virtualalloc.ps1 -Analyze`
4. W PerfView: `Net Virtual Alloc Stacks` → proces `javaw` →
   **`FoldPats`: `ntoskrnl;*.sys;ntdll;kernelbase;kernel32`** → `ByName`, sort po `Exc`.

Bez tego `FoldPats` widok jest bezużyteczny — na górze lądują ramki jądra.

---

## Pamięć natywna LWJGL per mod (agent, menu główne, 676,5 MB)

| mod | żywe MB | uwagi |
|---|---|---|
| yet_another_config_lib_v3 | 304,00 | 8 alokacji po 38 MB — **niewyjaśnione, do sprawdzenia** |
| oculus | 192,00 | `SegmentedBufferBuilder` |
| (minecraft-vanilla) | 116,98 | głównie `MemoryTracker` 52 MB |
| lodestone | 60,00 | `RenderHandler` 48 MB + `ScreenParticleHandler` 12 MB |

Osobno: **`alekiships` zaalokował 3,9 GB narastająco, trzymając 0 B** — bardzo wysoka
rotacja alokacji natywnych. Kandydat na przyczynę mikroprzycięć, nie na zjadacza RAM.

## Sterta (histogram po wymuszonym GC: 1821 MB żywych)
92,7% sterty to typy JDK/vanilli *trzymane* przez mody — histogram tego nie rozstrzygnie,
potrzebny pełny heap dump z retained size. Przypisane wprost: ferritecore 38,9 MB,
geckolib 31,6 MB, tacz 13,6 MB, modernfix 8,2 MB, gtceu 6,2 MB, embeddium 6,0 MB.
To i tak drugorzędne — cała sterta to 1,8 GB z ~11 GB procesu.

---

## EFFEKSEER POTWIERDZONY: 1,03 GB (test zakończony)

Pomiar bez `aaa_particles` + `sandworm_mod` (`budget-bez-aaa-2026-07-23-2009.csv`,
maszyna 4080S) potwierdził koszt **dwiema niezależnymi metodami**:

| | z aaa (agent4) | bez aaa | różnica |
|---|---|---|---|
| **POZA JVM** (cel śledztwa) | 6477 MB | **5461 MB** | **−1016 MB** |
| JVM heap | 2632 MB | 3808 MB | +1176 MB (szum GC) |
| Total | 10 518 | 10 586 | +68 MB (zaślepiony) |

- **Binarnie**: w działającym procesie `effekseernativeforjava.dll` = **0 modułów** (na 141).
- **Ilościowo**: POZA JVM −1016 MB = ETW 1,03 GB, co do MB.

**NAUCZKA: total commit to zły miernik** — sterta JVM pływa z rytmem GC (tu urosła
+1176 MB i zamaskowała ubytek). Patrzeć na **POZA JVM**, albo `jcmd <pid> GC.run`
przed pomiarem. Ostrzeżenie o 4080S słuszne, ale to sterta zaślepiła, nie sterownik.

### Config aaa_particles — WŁĄCZONY [gc]=true (commit 15f8960)
`config/aaa_particles-client.toml` → `[gc] enabled = true` (było false). Jedyna gałka
moda (klasa `AAAClientConfig`, brak limitu cząstek/budżetu). Plik dodany do śledzenia
w `.gitignore`.

**Dokładny mechanizm** (zdekompilowany `EffectRegistry.isSystemAtLowFreeMem` + `gc`):
- **Próg**: zwalnia, gdy `wolny fizyczny RAM systemu ≤ 0,25 × Xmx`.
  Przy Xmx6144 → **≤ 1536 MB wolnego RAM**. (`getFreeMemorySize()` to WOLNY RAM,
  nie standby/cache — na Windows bywa niski, ale przy 16 GB i menu zwykle 2–4 GB.)
- **Akcja**: `gc()` przy każdym wywołaniu zwalnia **tylko JEDEN efekt** (`limit(1)`),
  pomijając efekty `preload`; wyzwalane okresowo ze zdarzenia poziomu klienta.
- **Skutek**: reaktywne, stopniowe przycinanie pod realną presją. NIE odda całego
  1 GB naraz i NIE ruszy efektów preload.

**Konsekwencje testowe:**
1. Na 4080S/16GB w menu **nie odpali się** (za dużo wolnego RAM) — pomiar pokaże brak
   zmiany, to NIE porażka. Nie mierzyć tam „−1 GB", bo myli.
2. Realna walidacja należy do sesji na **780M** (obserwować pamięć Effekseera i wolny
   RAM pod obciążeniem), albo do testu z wymuszoną presją pamięci.
3. Pełny gwarantowany −1 GB daje tylko wycięcie `aaa_particles`+`sandworm_mod`.
   Gałka `[gc]=true` to tania polisa, nie gwarancja.

**Stan modów: OBA WŁĄCZONE** (paczka grywalna).

### PUŁAPKA: `mods.toml` NIE wystarcza do wykrycia zależności
Pierwsza próba (samo wyłączenie `aaa_particles`) **wywaliła grę przy ładowaniu**:
`sandworm_mod` woła wprost `mod.chloeprime.aaaparticles.client.loader.EffekAssetLoader`
w `onClientSetup` — **twarda zależność w bajtkodzie, nie zadeklarowana w `mods.toml`**.
`NoClassDefFoundError` → crash całego `completeModLoading`
(`crash-2026-07-23_19.58.51-fml.txt`).

Zanim wyłączysz mod, skanuj **constant pool zależnych** (`unzip -p jar | grep -a`
formy `pkg/klasa` ORAZ `pkg.klasa`), nie tylko `mods.toml`. Odwołania do
`aaaparticles` mają:
- `sandworm_mod` — **twarde** (`EffekAssetLoader` w `onClientSetup`) → crash bez aaa.
- `TerraFirmaGreg-Core` (`TFGMixinPlugin`) — mixiny kompatybilności
  (`MixinGameRenderer`, `MixinItemInHandRenderer`); plugin mixinów zwykle pomija je,
  gdy cel nie istnieje — **warunkowe, prawdopodobnie bezpieczne**, ale zweryfikować
  przy pierwszym starcie bez aaa_particles.

Oczekiwany wynik pomiaru: **−1,03 GB** commitu względem `budget-agent4` (10 518 MB).
Uwaga: bez aaa_particles `effekseernativeforjava.dll` w ogóle się nie ładuje.

## Następne kroki
1. **Zmierzyć bez `aaa_particles`** → `mem-budget.ps1 -Tag bez-aaa -Csv`. Potwierdzi
   lub obali 1,03 GB Effekseera.
2. **Rozbić 3,34 GB sterownika**: w PerfView zaznaczyć `nvoglv64` → prawym → `Callers`.
   Pokaże, które wywołania GL tworzą zasoby, a stamtąd blisko do konkretnych modów.
3. **Wyjaśnić 304 MB przypisane do `yet_another_config_lib_v3`** (8 alokacji po 38 MB).
4. Sesja na maszynie docelowej **Radeon 780M** — tam składnik sterownika będzie największy.

## Otwarte, niezrobione
- Retencja przy wyjściu ze świata: nie zwalnia się nic; AllTheLeaks raportuje
  15–30× ServerLevel i setki LevelChunk; ModernFix loguje wyciek BufferBuilder.
- Weryfikacja, czy Xmx 6144 nie zwiększył mikroprzycięć w dłuższej grze.
