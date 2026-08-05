# Ustalenia diagnostyczne

## 2026-07-21 — rozpoznanie wstępne (bez uruchamiania gry)

### Środowisko
- Instancja: Prism Launcher, MC 1.20.1, Forge 47.4.13, TFG-Modern **0.13.1** (CurseForge, ManagedPack).
- Java: Microsoft OpenJDK 17.0.15, heap **512 MB – 8192 MB** (`instance.cfg`: MaxMemAlloc=8192), **brak własnych flag JVM**.
- Komputer testowy z crash logu: Intel Core Ultra 7 155H (22 wątki), 32 GB RAM, **iGPU Intel Arc** → VRAM = RAM systemowy!
- Paczka ma już mody perf: Embeddium, Oculus, ModernFix, FerriteCore, Krypton, Radium, Saturn, EntityCulling, SmoothBoot, AllTheLeaks.

### Objawy zgłoszone przez użytkownika
1. Na maszynie 16 GB: przy `-Xmx4G` proces alokuje **>10 GB** → system stronicuje na dysk → FPS spada do 0.
2. Na **każdej** testowanej maszynie: kilka sekund po załadowaniu świata nagły drop FPS do ~0; gra stabilizuje się dopiero po dłuższej chwili (dlatego profilujemy min. 5 minut).

### Twarde liczby z crash logu (`minecraft/hs_err_pid26304.log`, 2026-07-15, sesja 1h50m)
- Heap G1: total 8 GB, **used 6,1 GB** (blisko limitu po ~2h gry).
- Metaspace: 493 MB used (dużo — 255 modów), reserved 1,5 GB.
- **Commit procesu: 17 852 MB, peak 23 186 MB** przy heapie 8 GB → **~10-15 GB pamięci natywnej poza heapem**.
- WorkingSet: 9,8 GB, peak 18,6 GB.
- 108 wątków JVM.
- **Brak `-XX:MaxDirectMemorySize`** → limit direct buffers = Xmx (drugie 8 GB dozwolone poza heapem).
- Załadowana natywna biblioteka `EffekseerNativeForJava.dll` (efekty cząsteczkowe moda TACZ) — alokuje poza JVM.

### Wycieki pamięci na heapie (raport moda AllTheLeaks, latest.log 2026-07-18)
Po sesji z wchodzeniem/wychodzeniem ze świata AllTheLeaks wykrył NIE-zwolnione obiekty:
- **ServerLevel: 30 instancji** (całe wymiary trzymane w pamięci po wyjściu!)
- **LevelChunk: 4309** wyciekniętych chunków
- IntegratedServer: 2, ServerPlayer: 2, LocalPlayer: 2, ClientLevel: 2
- Raport `B: 4486MB / C: 5196MB / Diff: +710MB` — przyrost heapu między pomiarami.
→ Główny podejrzany dla rosnącego RAM w trakcie sesji. Coś trzyma referencje do poziomów
(30 ServerLevel ≈ wielokrotne przeładowania świata × liczba wymiarów). Do namierzenia heap dumpem.

### Crash (przy okazji, niezwiązany z RAM)
- `EXCEPTION_ACCESS_VIOLATION` w `glfw.dll` przy `glfwSetWindowMonitor`, wywołane przez
  `toni.sodiumextras.EmbyConfig.setFullScreenMode` (mod **Embeddium Extras / sodiumextras 1.0.6**)
  podczas przełączania fullscreen (Alt+Enter). Znany typ buga — do obejścia/aktualizacji (zadanie C1).

### Hipotezy dot. pamięci natywnej (~10+ GB poza heapem) — do weryfikacji NMT (zadanie A3)
1. Direct ByteBuffers bez limitu (chunk meshing Embeddium, staging buffers) — brak MaxDirectMemorySize.
2. Sterownik iGPU Intel Arc alokujący "VRAM" w RAM procesu (tekstury, bufory, shadery Oculus).
3. Effekseer (TACZ) — natywne alokacje.
4. 108 wątków × stosy + G1/JIT/metaspace overhead.
5. Fragmentacja domyślnego alokatora Windows.

### Hipotezy dot. dropu FPS po załadowaniu świata (zadanie A4)
1. Burst budowania meshy chunków przez workery Embeddium (direct buffers + CPU).
2. Kompilacja shaderów (Oculus) po wejściu do świata.
3. Pierwszy pełny cykl GC po alokacyjnym burscie ładowania.
4. Na 16 GB: początek stronicowania (commit przekracza fizyczny RAM).

### Dodatkowe obserwacje
- `debug.log` ma 20 MB po jednej sesji — spam logów kosztuje IO/CPU; do przycięcia (zadanie B5).
- Zainstalowano profilery: **spark 1.10.53**, **Observable 4.4.2** (2026-07-21).

---

## 2026-07-21 — pierwsza sesja pomiarowa (zadania A1 + A2 wykonane)

Źródła: spark profiler https://spark.lucko.me/e947jfdt54 (5 min, klient),
spark heapsummary https://spark.lucko.me/3uFB1NLcWO, Observable https://observable.tas.sh/p/4CFr2.
Surowe dane + dekoder protobuf: scratchpad `decode_spark.js` / `spark_analysis.json`
(spark upubliczna surowce na `bytebin.lucko.me/<id>`, Observable na `/v1/get/<id>`).

### Stan systemu podczas profilu (maszyna 32 GB!)
- RAM fizyczny: **26,7 / 32 GB zajęte**; commit/swap systemu: **40 / 58 GB** → nawet 32 GB maszyna stronicuje.
- Heap: 6,36 / 8 GB w trakcie profilu (4,27 GB przy heapsummary).
- Flagi JVM: potwierdzone tylko `-Xms512m -Xmx8192m` — zadanie B1 wciąż niewdrożone.

### Render thread (5 min) — gdzie idzie czas klatki
- **43,5% LWJGL/sterownik OpenGL** — w tym ~11% czekanie na vsync/swap (`JNI.invokeV`, maxFps=60),
  ale realnie: draw calle `nglDrawElements*` ~8%, `glBindFramebuffer` 3,3% (przebiegi shaderów),
  **`glLinkProgram` 1,4% = kompilacja shaderów W TRAKCIE gry → stuttery** (to jest mechanizm dropów!),
  `glTexBuffer` 1,1%, `glUseProgram` 1,0%.
- **Embeddium 9,6%**, z czego `OcclusionCuller.processQueue` 4,7% — koszt rośnie z renderDistance (jest 24!).
- Minecraft 20,3% (budowanie meshy: VertexConsumer 3,0%, BufferBuilder 2,0%; PalettedContainer 2,5%).
- **Oculus 4,9%**. Mody dalej: xaeroworldmap 1,7%, create 1,1%, tfc 0,8%, aaa_particles 0,7%, wakes 0,6%.
- **Aktywny shaderpack: Complementary 3.1.5** (`config/oculus.properties`), renderDistance **24**,
  simulationDistance 12, maxFps 60 — na iGPU Intel Arc to główne obciążenie GPU.

### Oś czasu (okna ~1 min): potwierdzony spike po world-load
| minuta | mspt median | mspt max | CPU proc |
|---|---|---|---|
| 1 | 6,0 | **288,8** | 34% |
| 2 | 4,2 | 74,2 | 17% |
| 3 | 3,9 | 9,7 | 10% |
| 4-6 | 2,9-3,5 | 12-18 | 6-8% |
Pierwsza minuta po wejściu: zacięcia do 289 ms (≈3 FPS) — potem stabilnie. Winowajcy spike'a:
kompilacja shaderów (glLinkProgram), burst budowy chunków, oraz na słabszych maszynach stronicowanie.

### Heap — top konsumenci (heapsummary, 3,9 GB policzone)
| MB | instancje | klasa | interpretacja |
|---|---|---|---|
| 710 | 6,4M | byte[] | dane chunków/tekstury/bufory (rozbić heap dumpem, C2) |
| 468 | 6,2M | Object[] | kolekcje |
| 148 | 1,22M | BlockState | eksplozja stanów GT×TFC (FerriteCore już działa) |
| **145+31** | **3,2M+1,3M** | **oculus…antlr…CommonToken / TerminalNodeImpl** | **Oculus trzyma drzewa parsowania GLSL shaderpacka w RAM — ~200+ MB tylko przez włączone shadery!** |
| 133 | 5,8M | String | — |
| 83 | 1,8M | ItemEmiStack | indeks EMI (miliony wariantów GT) |
| 81 | 1,07M | ItemStack | + 16 MB lambd ItemStack |
| 57 | 1,5M | xaero MapBlock | cache mapy Xaero w RAM (konfigurowalne) |
| ~80 | — | dev.latvian.mods.rhino.* | KubeJS/Rhino (metadane refleksji) |
| 34 | 1,5M | ModelPart$Vertex | modele encji |
| 22 | 0,6M | geckolib Keyframe | animacje |
| 16 | 410k | ZipFileSystem$IndexNode | indeksy 255 otwartych jarów |

### Observable — tick serwera JEST ZDROWY (nie tu leży problem)
Cały koszt: encje ~6,1 ms + bloki ~5,3 ms ≈ 11 ms/tick (limit 50 ms). Największe pozycje:
woda `minecraft:water` 3,8 ms (77 bloków — mechanika płynów), tfc:lake_trout 1,3 ms (43 szt.),
zombie 0,7 ms, berry_bush 0,2 ms (749 szt. — tanie). Wniosek: **depriorytet optymalizacji serwera**;
cała walka toczy się o klienta (render + RAM).

### KOREKTA 2026-07-21 (po uwagach użytkownika)
1. **GPU:** sesja profilowana szła na **RTX 4080 SUPER** (debug.log: `GL info: NVIDIA GeForce RTX 4080 SUPER`),
   NIE na iGPU — wcześniejszy wniosek "iGPU Arc" był błędną dedukcją z modelu CPU (Core Ultra 155H).
   Użytkownik gra na 4080S; stary crash log (17,8/23 GB commit) mógł pochodzić z sesji z przypadkowo
   wyłączonym dGPU — **liczby commitu procesu trzeba zmierzyć na nowo na obecnej konfiguracji** (A3/A5).
   Implikacja: na 4080S render nie jest wysycony (cpu okien 6-34%, cap 60 FPS z vsync — duża część
   43% LWJGL to czekanie na swap). Problem FPS na tym sprzęcie = STUTTERY (kompilacja shaderów,
   burst chunków, ew. stronicowanie), nie surowa moc GPU. Eksperyment C5 (shadery/rd) jest istotny
   głównie dla słabszych testowanych maszyn.
2. **Rozróżnienie trzech poziomów pamięci** (liczby z sesji 1 się spinają, ale to inne zakresy):
   - 26,7/32 GB = RAM **całego systemu** (spark raportuje pamięć maszyny: OS + wszystkie procesy + cache);
   - heap JVM = 4,3-6,4/8 GB; heapsummary liczy TYLKO heap (3,9 GB policzone: 710 MB byte[],
     468 MB Object[], długi ogon 77 tys. klas — Oculus 200 MB i EMI 83 MB to najwięksi
     *jednoznacznie przypisywalni* konsumenci, reszta to współdzielone kolekcje wymagające
     pełnego heap dumpa do atrybucji, zad. C2);
   - commit **procesu** (heap + pamięć natywna) — heapsummary go w ogóle nie widzi; jedyny
     pomiar (17,8/23 GB) jest ze starego crash logu o niepewnej konfiguracji → do zmierzenia
     na żywo: `Get-Process javaw | Select-Object WS,PM` podczas gry + NMT (A3).

## 2026-07-21 — monitoring procesu na żywo (rig z RTX 4080S, 32 GB; zadanie A5 częściowo)

34 min gry, próbka co 20 s → `docs/data/ram-monitor-2026-07-21-2324.csv`. Jednorazowe zrzuty
jcmd: heap committed pełne 8 GB (G1 bierze cały Xmx od razu — stąd F3 pokazuje mniej niż Task
Manager), metaspace 0,5 GB. nvidia-smi w trakcie: 5,3/16 GB VRAM, GPU util 62%.

**Kluczowy wynik: commit procesu jest STAŁY ~24,4 GB przez całą sesję** (min 24 249, max
24 418 MB — płaska linia), WS 9,0-9,6 GB, heap piłokształtny 4,0-7,3 GB ze stabilnym floor
~4,1 GB (GC zdrowe, bez trendu wzrostu w jednym świecie). 240→212 wątków.

Interpretacja:
1. ~15-16 GB pamięci natywnej to **stała rezerwacja robiona do momentu wejścia do świata**,
   nie pełzający wyciek w trakcie grania. Kandydaci: pule direct buffers (skalowane od Xmx,
   brak limitu), zaplecze WDDM sterownika NVIDII dla VRAM, Effekseer, 240 wątków, alokator.
   Rozbicie da dopiero NMT (A3) — flaga jeszcze NIE dodana.
2. Heap floor ~4,1 GB stały → wycieki ServerLevel/LevelChunk z AllTheLeaks aktywują się przy
   PRZEŁADOWANIU świata (test wyjdź-wejdź nie został wykonany w tej sesji — do powtórzenia).
3. Wniosek dla 16 GB maszyn: nawet bez żadnego wycieku commit 24 GB > RAM fizyczny →
   stronicowanie od startu. Redukcja: mniejszy Xmx (5 GB), MaxDirectMemorySize,
   mniejszy renderDistance (mniej meshy = mniejsze pule buforów).

## 2026-07-22 — NMT + eksperyment renderDistance (zadanie A3 WYKONANE)

Sesja na **RTX 4050 Laptop (6 GB VRAM)** — użytkownik gra na 3 platformach:
4080S przez stację dokującą (wczoraj), 4050 laptopowe (dziś), docelowo **iGPU Radeon 780M
z 16 GB RAM** (maszyna problemowa). Nadmiarowy RAM występuje na KAŻDEJ platformie
→ przyczyna leży w konfiguracji paczki, nie w sprzęcie.

### NMT: JVM przyznaje się do mniej niż połowy commitu
```
JVM committed (NMT):   9 526 MB
Commit procesu:       21 556 MB
POZA JVM:             12 030 MB   <- biblioteki natywne, niewidoczne dla JVM
```
Rozbicie JVM: heap 8192 (G1 commituje CAŁY Xmx niezależnie od użycia — dlatego F3
pokazuje mniej niż Task Manager), metaspace 404, GC 420, kod JIT 202, symbole 90,
klasy 97, wątki 19 MB (331 wątków).

**HIPOTEZA OBALONA: direct buffers = 33 MB** (kategoria "Other"). Planowana flaga
`-XX:MaxDirectMemorySize` NIC by nie dała — usunięta z zadania B1. Ważne: LWJGL alokuje
przez `MemoryUtil`/malloc, co omija ZARÓWNO heap, JAK I liczniki NMT — stąd niewidzialność.

### Rozbicie regionów pamięci (scripts/mem-regions.ps1, VirtualQueryEx)
PRIVATE 21 505 MB / IMAGE 491 MB / MAPPED 76 MB. Heap = jeden region 8192 MB @0x600000000.
Reszta: setki bloków 64-294 MB w jednym obszarze adresowym (charakterystyka alokatora natywnego).
Załadowany `nvoglv64.dll` (sterownik GL), `EffekseerNativeForJava.dll`.

### Eksperyment renderDistance 24 -> 8 (docs/data/rd-test-2026-07-22-0938.csv)
| faza | commit |
|---|---|
| baseline rd 24 | 21,9 GB |
| moment przebudowy | 22,6 GB (skok) |
| po zmianie na rd 8 | **19,7 GB** |
| 10 min później | 19,7-19,9 GB (stabilnie) |
WS spadł 15,1 -> 14,1 GB. **Zysk: ~2,2 GB.** Potwierdza: natywne bufory siatek chunków
skalują się z renderDistance i nie widzi ich żaden licznik Javy.
ALE: to tylko 2,2 z 12 GB. Po zmianie nadal ~11 GB natywnej bez atrybucji.
Uwaga: pamięć NIE wróciła po ewentualnym powrocie na rd 24 → część alokacji nie jest
oddawana systemowi (retencja alokatora).

### Zweryfikowane dźwignie (gotowe do wdrożenia)
| Dźwignia | Efekt na commit | Podstawa |
|---|---|---|
| renderDistance 24 -> 8 | **-2,2 GB** | zmierzone bezpośrednio |
| Xmx 8 -> 5 GB | **-3 GB** | G1 commituje cały Xmx; heap floor po GC = 4,1 GB |
| MaxDirectMemorySize | 0 | obalone (33 MB) |

### Pozostały trop: ~11 GB
Główny kandydat: **backing systemowy WDDM dla zasobów GPU** (Windows trzyma w RAM kopie
zasobów karty; Complementary generuje ogrom celów renderowania, map cieni i wariantów
shaderów). Spójne z występowaniem problemu na każdej karcie i z prognozą, że na 780M
będzie najgorzej (iGPU bierze pamięć wprost z RAM). Test: shadery OFF (klawisz K) — w toku.
Drugi kandydat: retencja/fragmentacja alokatora natywnego (bloki nieoddawane po spadku rd).

### Eksperyment shadery OFF (docs/data/shader-test-2026-07-22-0957.csv)
| metryka | shadery ON | shadery OFF | zysk |
|---|---|---|---|
| **WorkingSet (realny RAM)** | 14,1 GB | **9,96 GB** | **-4,2 GB** |
| commit | 20,1 GB | 19,0 GB | -1,1 GB |

**To największa pojedyncza dźwignia.** Kluczowe rozróżnienie: shadery zwalniają przede
wszystkim pamięć REZYDENTNĄ (fizyczny RAM), a nie commit. Dla maszyny 16 GB liczy się
głównie WorkingSet — to on decyduje o stronicowaniu i dropach do 0 FPS.
Potwierdza hipotezę WDDM/sterownik: Complementary trzyma w RAM ~4 GB kopii zasobów GPU.

### Zestawienie WorkingSet (rig 4050, ta sama sesja)
| konfiguracja | WS |
|---|---|
| rd 24 + shadery | 15,1 GB |
| rd 8 + shadery | 14,1 GB |
| rd 8 + BEZ shaderów | **9,96 GB** |

### Uwaga metodyczna: commit vs WorkingSet
Commit ~19 GB przy WS ~10 GB → ok. 9 GB jest zacommitowane ale NIEREZYDENTNE
(pagefile, nietknięte strony). Dla wydajności liczy się WS; commit ogranicza tylko,
ile w ogóle da się zaalokować (limit RAM+pagefile). Na 16 GB oba są problemem.

## 2026-07-22 — PRZEŁOM: RAM zjadany jest przy ŁADOWANIU MODÓW, nie w rozgrywce

Sesja z DebugAllocator, shadery OFF (docs/data/debugalloc-session-2026-07-22-1016.csv).
Kontekst od użytkownika: **vanilla + ten sam shaderpack = zero problemów**, gra trzyma się
sterty z argumentów, działa nawet Distant Horizons. Problem jest wyłącznie w tej paczce.

### Krzywa całej sesji
| moment | WorkingSet | commit |
|---|---|---|
| start, ładowanie modów | 3,5 GB -> 11,0 GB (w 45 s!) | 3,7 -> 12,3 GB |
| **MENU GŁÓWNE, żaden świat nie wczytany** | **10,9 GB** | **12,3 GB** |
| menu, 11 minut bezczynności | 10,9 GB (płasko) | 12,3 GB |
| wejście do świata | 13,4 GB | 16,1 GB |
| gra w świecie | 13,5 GB | 16,8 GB |
| **po wyjściu ze świata do menu** | **13,5 GB (BEZ ZMIAN!)** | 15,9 GB |

### Dwa wnioski, które przestawiają cały projekt
1. **~11 GB RAM / 12,3 GB commitu jest zjadane ZANIM powstanie jakikolwiek świat.**
   To ładowanie 255 modów: rejestry, atlasy tekstur, modele, recepty GTCEu/TFC, KubeJS.
   Dlatego zoptymalizowany profil dla 16 GB (niski render distance, Xmx 4 GB, lekkie shadery)
   NIE POMÓGŁ — te ustawienia dotykają tylko ~3 GB przyrostu rozgrywki, a nie bazy 11-12 GB.
   **Na maszynie 16 GB gra jest już w menu głównym na granicy stronicowania.**
2. **Wyjście ze świata nie zwalnia NICZEGO** (WS 13,5 GB przed i po). Potwierdza wyciek
   retencyjny — spójne z raportem AllTheLeaks (30x ServerLevel, 4309x LevelChunk) oraz
   z ostrzeżeniem w logu dokładnie w momencie wyjścia:
   `[Finalizer/WARN] [ModernFix]: One or more BufferBuilders have been leaked` —
   BufferBuilder trzyma bufor NATYWNY, więc to bezpośredni dowód wycieku pamięci natywnej.

### NMT w menu głównym (po wyjściu ze świata, shadery OFF)
```
JVM committed:  8 100 MB   (heap committed 6840, used tylko 4453!)
Commit procesu: 15 940 MB
POZA JVM:        7 840 MB
```
Uwaga: G1 rozdął heap do 6,8 GB w trakcie ładowania i **nie oddaje go z powrotem**,
mimo że używane jest 4,4 GB. To bezpośredni argument za obniżeniem Xmx.

### Rewizja priorytetów
Dotychczasowe dźwignie (shadery -4,2 GB, rd -2,2 GB) działają na przyrost rozgrywki i zostają,
ale NIE dotykają bazy 11-12 GB z ładowania. Nowy priorytet:
1. Zmniejszyć bazę: co konkretnie alokuje 11 GB przy starcie (DebugAllocator, atlasy, rejestry).
2. Naprawić retencję przy wyjściu ze świata (BufferBuilder + ServerLevel).
3. Xmx: G1 nie oddaje rozdętego heapu -> ograniczyć od góry.

### Sesja DebugAllocator — NIEUDANA metodycznie (2026-07-22)
LWJGL nie wypisał NIC (zero linii `[LWJGL]`, `stderr_stream.log` pusty), mimo że flagi
na pewno dotarły do JVM (NMT z tych samych argumentów działało — `jcmd` zwracał dane).
Przyczyna: Forge przekierowuje System.err do log4j, a raport DebugAllocatora drukuje się
w haku zamykającym JVM — już PO wyłączeniu log4j. Wynik przepada.
**Wniosek: nie powtarzać tej metody bez rozwiązania problemu przechwytywania wyjścia.**

### Tropy WYKLUCZONE (2026-07-22)
- **Atlasy tekstur**: blocks 4096x4096x4 (~90 MB z mipmapami), reszta drobnica.
  Suma wszystkich atlasów rzędu 200-300 MB. To NIE one.
- **ModernFix `dynamic_resources`**: **JUŻ WŁĄCZONE** przez autorów paczki
  (`config/modernfix-mixins.properties`), podobnie `dynamic_entity_renderers`,
  `deduplicate_location`, `remove_spawn_chunks`, `clear_mixin_classinfo`.
  Największy oszczędzacz ModernFixa jest wykorzystany — łatwej wygranej tu nie ma.
- **Direct buffers** (33 MB, patrz wyżej).
- Rozmiar jarów: 257 jarów = 548 MB na dysku. Sam kod to nie jest te 11 GB.

### Metoda na następną sesję: pomiar W MENU GŁÓWNYM przez jcmd
Kluczowe usprawnienie: `/sparkc heapsummary` wymaga wejścia do świata (miesza dane
świata z danymi ładowania). Zamiast tego **`jcmd` działa z zewnątrz i nie potrzebuje świata**:
```
jcmd <PID> GC.class_histogram      # pelny histogram klas na stercie
jcmd <PID> GC.heap_info            # totals
jcmd <PID> VM.native_memory summary scale=MB
scripts\mem-regions.ps1 -ProcessId <PID>
```
Użytkownik ma tylko uruchomić grę i ZOSTAĆ W MENU. To rozbije bazę 12,3 GB na:
sterta wg klas (-> mody z nazwy) + reszta JVM + pamięć natywna poza JVM.

## 2026-07-22 — POMIAR W MENU GŁÓWNYM (czysta baza po załadowaniu modów)

Gra stojąca w menu, **shadery OFF** (`enableShaders=false`), żaden świat nie wczytany.
Dane: `docs/data/menu-histogram.txt`, `docs/data/menu-nmt.txt`.

### Rozkład 13,1 GB commitu
| składnik | rozmiar | uwagi |
|---|---|---|
| sterta — REALNIE UŻYTA | **1,75 GB** | tyle naprawdę potrzebują mody w menu |
| sterta — PUSTA, zawłaszczona przez G1 | **3,76 GB** | czysta strata |
| metaspace (kod + metadane 257 modów) | 407 MB | |
| kod JIT / GC / klasy / wątki | ~700 MB | |
| **pamięć natywna poza JVM** | **~6,6 GB** | główna zagadka |
| RAZEM commit | 13,1 GB | WS 11,7 GB |

### DOWÓD: G1 zawłaszcza pamięć i nie oddaje
Wymuszony pełny GC (`jcmd GC.run`): sterta użyta spadła 2,68 -> 1,87 GB,
ale **committed pozostało 5,51 GB, a commit procesu nie drgnął** (13,09 -> 13,11 GB).
Przyczyna: udział wolnej sterty = 66%, tuż poniżej domyślnego progu
`MaxHeapFreeRatio=70` — G1 nie widzi powodu do oddania pamięci.
**To ~3,8 GB do odzyskania samymi flagami, bez ruszania modów.**

### Sterta jest ZDROWA — nie ma jednego winowajcy
Histogram w menu (1,75 GB obiektów): byte[] 497 MB, BlockState 155 MB (1,2 mln instancji —
normalne dla GTCEu+TFC), Object[] 106 MB, String 89 MB, FerriteCore 39 MB (działa poprawnie),
ModelPart$Vertex 36 MB, geckolib Keyframe 23 MB, ZipFileSystem$IndexNode 16 MB (257 jarów).
Żaden mod nie wyróżnia się patologicznie. **Problemem NIE jest "jeden żarłoczny mod na stercie".**

### Pozostaje ~6,6 GB natywnej przy shaderach OFF i bez świata
Regiony: po stercie (5,5 GB) największe to 294, 151, 86, 86, 76, 76 MB — rozproszone,
brak pojedynczej wielkiej alokacji. Kandydaci do testu empirycznego (usuwanie grup modów
i pomiar RAM w menu — metryka szybka, ~4 min na test):
1. **AAAParticles + Effekseer** (`EffekseerNativeForJava.dll` — biblioteka natywna,
   alokuje CAŁKOWICIE poza JVM, więc idealnie pasuje do profilu "niewidzialne dla NMT"),
2. rodzina TACZ (55 MB, używa Effekseera),
3. Oculus (nawet z wyłączonymi shaderami wpina się w render),
4. mapy Xaero, 5. Embeddium (bufory chunków — ale potrzebny).

### Odpowiedź na pytanie "czy da się wypiec mody, żeby zajmowały mniej RAM?"
NIE — bo RAM zjada nie kod, tylko struktury danych tworzone w czasie działania.
Cały kod i metadane 257 modów to **407 MB metaspace z 13,1 GB** (3%). Prekompilacja
nic tu nie da. Jedyna realna technika z tej rodziny to **AppCDS** (`-XX:SharedArchiveFile`) —
współdzielone archiwum klas: oszczędza ~100-200 MB metaspace i skraca start, ale przy
skali 13 GB to błąd zaokrąglenia. Właściwe dźwignie to konfiguracja JVM i redukcja
zawartości, nie "wypiekanie".

## 2026-07-23 — ZIDENTYFIKOWANY ALOKATOR: jemalloc z 88 arenami

Rozpoznanie bez uruchamiania gry + własny agent uruchomiony na teście syntetycznym.

### Alokatorem pamięci natywnej LWJGL jest jemalloc (potwierdzone)
Odczyt wprost z biblioteki przez `je_mallctl`:
```
opt.narenas=88   arenas.narenas=89
opt.dirty_decay_ms=10000   opt.muzzy_decay_ms=0
opt.retain=false   opt.tcache=true
```
88 aren = 4 × 22 logiczne CPU. Gra ma 240–331 wątków, więc realnie używane są wszystkie,
a każda arena trzyma własny zapas stron i własny cache ekstentów.

**To wyjaśnia naraz wszystkie dotychczasowe ślepe zaułki:**
- jemalloc bierze pamięć przez `VirtualAlloc`, więc **nie widzi go ani NMT, ani `!heap`** —
  stąd „niewidzialność" 6,6 GB dla każdego licznika;
- pasuje do obserwacji „setki bloków 64–294 MB w jednym obszarze adresowym";
- pasuje do „pamięć NIE wróciła po zmianie renderDistance 24→8" (cache aren).

### Pokrętło istnieje i działa
Zmienna środowiskowa nazywa się **`JE_MALLOC_CONF`** (nie `MALLOC_CONF` — LWJGL buduje
jemalloc z prefiksem `je_`). Zweryfikowane: `JE_MALLOC_CONF=narenas:4,dirty_decay_ms:0`
zmieniło odczyt na `opt.narenas=4, opt.dirty_decay_ms=0`.

### Ograniczenie: brak statystyk jemalloca
`stats.allocated` / `stats.retained` zwracają `rc=2` — LWJGL buduje jemalloc bez
`--enable-stats`. Narzut alokatora liczymy więc jako różnicę: commit procesu
minus suma żywych bajtów z agenta.

### Zbudowane narzędzia (szczegóły w docs/RAM-ATTRIBUTION-PLAN.md)
- `scripts/build-mod-index.ps1` → mapa pakiet→mod: 64 592 klasy, 841 jednoznacznych
  prefiksów, 54 kolizyjne.
- `scripts/mem-budget.ps1` → pełny budżet procesu; kolumna WorkingSet spina się
  do **−0,1 MB** względem `Get-Process` (każdy rezydentny bajt policzony).
- `tools/ramattr/` → agent atrybucji natywnej per mod. Na teście syntetycznym pokazał
  dokładnie `tacz 48,00 MB` i `fpsreducer 32,00 MB` przy zadanych 64−16 i 32 MB.

## 2026-07-23 — pierwsza sesja z agentem: budżet procesu i rozkład regionów

Sesja nieudana pomiarowo dla agenta (patrz niżej), ale budżet procesu i histogram
sterty dały twarde liczby. **Uwaga: ten przebieg szedł BEZ flag G1 i bez NMT** —
wklejenie argumentu `-javaagent` w Prism zastąpiło całe pole zamiast je uzupełnić.
Dlatego liczby nie są porównywalne z bazą 10,1 GB.

### Budżet procesu (mem-budget.ps1, menu główne)
| składnik | commit | WS |
|---|---|---|
| IMAGE (161 modułów DLL/EXE) | 488 MB | 79 MB |
| MAPPED (pliki) | 76 MB | 22 MB |
| PRIVATE | 12 098 MB | 11 724 MB |
| **RAZEM PROCES** | **12 662 MB** | **11 825 MB** |

Największe pozycje IMAGE to sterowniki graficzne: `nvgpucomp64.dll` 94 MB,
`nvwgf2umx.dll` 86 MB, `igc64.dll` 80 MB, `nvoglv64.dll` 47 MB.

### Rozkład regionów PRIVATE — sygnatura alokatora arenowego
137 regionów >= 16 MB, razem 10 689 MB:
- **sterta JVM: jeden region 4816 MB** @0x680000000,
- **pozostałe 136 regionów: 5872 MB**, w tym **85 sztuk po ~32 MB**, 27 po ~64 MB,
  6 po ~80 MB, oraz pojedyncze 288/160/96 MB.

Wszystkie w pełni rezydentne (WS == commit). Rozkład „dziesiątki niezależnych bloków
32–64 MB" to dokładnie to, czego należy się spodziewać po **88 arenach jemalloca** —
i nie ma tu żadnej pojedynczej wielkiej alokacji, którą dałoby się wskazać palcem.

### Sterta: histogram po wymuszonym GC
`GC.heap_info` przed histogramem: total 5021 MB, **used 4266 MB**. Ale `GC.class_histogram`
wymusza pełny GC i naliczył **1821 MB żywych obiektów**. Potwierdza wcześniejsze
ustalenie: realnie żywej sterty jest ~1,8 GB, reszta to śmieci i luz G1.

Atrybucja histogramu do modów (`scripts/heap-by-mod.ps1`):
| kategoria | MB | udział |
|---|---|---|
| tablice typów prostych (`byte[]`, `int[]`...) | 680 | 37,3% |
| typy współdzielone JDK | 453 | 24,9% |
| minecraft-vanilla | 318 | 17,5% |
| nieprzypisane | 236 | 13,0% |
| **konkretne mody razem** | **133** | **7,3%** |

Najwięksi z przypisanych: ferritecore 38,9 MB, geckolib 31,6 MB, tacz 13,6 MB,
modernfix 8,2 MB, gtceu 6,2 MB, embeddium 6,0 MB.

**Wniosek metodyczny**: 92,7% sterty siedzi w typach, które formalnie należą do JDK
lub vanilli, a *trzymane* są przez mody. Histogram tego nie rozstrzygnie — potrzebny
pełny heap dump z retained size. To jednak i tak drugorzędne, bo cała sterta to
1,8 GB z 12,7 GB procesu.

### Agent: pierwsza wersja nie zadziałała, przyczyna ustalona
`alokator NIEAKTYWNY`, zero danych. Forge ładuje LWJGL własnym class loaderem, więc
podstawiona klasa implementowała interfejs z *innej kopii* LWJGL → cichy
`ClassCastException` wewnątrz LWJGL → powrót do domyślnego alokatora.
Ślad w logu: `UnsatisfiedLinkError: lwjgl.dll already loaded in another classloader`.

Naprawione: agent **wstrzykuje bajtkod** do `JEmallocAllocator`, woła wyłącznie metody
o sygnaturach na typach prostych, a liczniki mieszkają w class loaderze **bootstrap**
(jedynym wspólnym dla wszystkich). Szczegóły i wnioski na przyszłość:
`docs/RAM-ATTRIBUTION-PLAN.md`.

### Druga próba: ASM w jarze agenta wywalał grę przy starcie
JVM kończył pracę w tej samej sekundzie, w której startował — bez crash-reportu,
bez jednej linii w `latest.log`. Przyczyna: **Prism uruchamia Forge z ASM 9.8 na zwykłym
classpathie** (w logu launchera nie ma `-p` ani `--module-path`). Wtopiona do agenta
kopia ASM 9.9.1 dawała dwie wersje `org.objectweb.asm` w jednym class loaderze
i ModLauncher przewracał się przy budowaniu warstwy modułów.

Naprawione: ASM używany **wyłącznie przy budowaniu** — generuje gotowe załatane `.class`,
a agent w czasie działania tylko podmienia bajty, osłonięty sumą kontrolną SHA-256
oryginału. Agent schudł ze 133 KB do 9 KB.

**Reguła na przyszłość: nie wnosić na classpath gry żadnej biblioteki, której Forge
używa sam** (ASM, Guava, Gson). Wszystko idzie albo do bootstrapu, albo jest
generowane przy budowaniu.

## 2026-07-23 — AGENT ZADZIAŁAŁ: LWJGL to tylko 10% pamięci natywnej

Pierwszy udany pomiar z instrumentacją. Menu główne, pełne flagi G1 + NMT.

### Pełny budżet procesu (mem-budget.ps1, `budget-agent2-2026-07-23-1239.csv`)
| składnik | commit |
|---|---|
| JVM razem wg NMT | 3755 MB |
| — z tego sterta | 2816 MB |
| — metaspace | 330 MB |
| — GC 196, kod JIT 102, symbole 79, klasy 80, StringDedup 53, NMT 52 | ~560 MB |
| IMAGE (moduły DLL/EXE) | 491 MB |
| MAPPED (pliki) | 96 MB |
| **poza JVM** | **6927 MB** |
| **RAZEM PROCES** | **11 269 MB** (WS 9396 MB) |

Sterta zacommitowana 2816 MB (poprzedni przebieg bez flag: 4816 MB) — **flagi G1
ponownie potwierdzone**, G1 oddaje pamięć.

### Wynik agenta: 676 MB
123 047 żywych alokacji, **676,5 MB**, przy 196 411 wywołaniach z wstrzykniętego kodu
i **tylko 1 sierocym zwolnieniu** — księgowość alloc/free domyka się praktycznie idealnie.

**To jest kluczowe ustalenie: cały `MemoryUtil` LWJGL to 676 MB z 6927 MB pamięci
poza JVM, czyli ~10%.** Pozostałe ~6,2 GB nie przechodzi przez alokator LWJGL.

Kandydaci na te 6,2 GB, w kolejności prawdopodobieństwa:
1. **Sterownik GPU** — pamięć alokowana przez `nvoglv64.dll`/`nvwgf2umx.dll` przy
   tworzeniu zasobów GL (tekstury, bufory, shadery). Nie widzi jej żaden licznik Javy.
2. **Natywne DLL modów** (Effekseer) — alokują całkowicie samodzielnie.
3. **Biblioteki dostające wskaźniki na funkcje alokatora** (stb) — nasz udokumentowany
   martwy punkt.
4. Narzut samego jemalloca (areny) — mierzalny dopiero po zderzeniu adresów, patrz niżej.

### LWJGL JEST w nazwanym module JPMS — kod na to był potrzebny
```
dodano modulowi org.lwjgl.jemalloc prawo czytania unnamed module
podmieniono org/lwjgl/system/jemalloc/JEmallocAllocator na wersje zalatana
  (loader: cpw.mods.cl.ModuleClassLoader, modul: org.lwjgl.jemalloc)
```
Bez `Instrumentation.redefineModule` wstrzyknięta `INVOKESTATIC` rzuciłaby
`IllegalAccessError`. Warto zapamiętać przy każdej przyszłej instrumentacji tej paczki.

### Błąd atrybucji wykryty i naprawiony
Pierwszy zrzut przypisał **676 MB z 676 MB do `(minecraft-vanilla)`**. Przyczyna:
mody wołają kod Minecrafta, więc sama alokacja dzieje się w klasie vanilli, a szukanie
właściciela kończyło się na pierwszej nie-JDK klasie.

Poprawka: szukamy **najbliższej alokacji klasy należącej do MODA**, a vanilla jest
tylko odpowiedzią zapasową, gdy w całym stosie nie ma żadnego moda. Dodatkowo agent
zapisuje teraz **miejsce alokacji** (`ramattr-sites.csv`) — odpowiada nie tylko
„który mod", ale i „którym kodem".

### Nowy pomiar: zderzenie adresów z mapą regionów
Agent zrzuca rozkład adresów żywych alokacji (`ramattr-addr.csv`), a `mem-budget.ps1`
z przełącznikiem `-AgentAddr` sprawdza, które regiony prywatne procesu w ogóle
zawierają alokacje LWJGL. To rozdziela trzy rzeczy, których wcześniej nie dało się
rozróżnić: pamięć realnie używaną, **narzut alokatora** (regiony alokatora minus żywe
bajty) oraz **regiony niemające z alokatorem nic wspólnego** (sterownik, natywne DLL).

## 2026-07-23 — sesja 3: PIERWSZA TABELA PER MOD (pamięć natywna LWJGL)

Stan ustalony w menu głównym, 676,5 MB żywej pamięci natywnej, stabilne przez
ponad 800 s (timeline: identyczne 676,5 MB / 123 047 alokacji w kolejnych próbkach).

| mod | żywe MB | alokacji | uwagi |
|---|---|---|---|
| yet_another_config_lib_v3 | **304,00** | **8** | 8 alokacji po 38 MB — do wyjaśnienia |
| oculus | **192,00** | 70 | `SegmentedBufferBuilder` (batched entity rendering) |
| (minecraft-vanilla) | 116,98 | 122 680 | głównie `MemoryTracker` 52 MB |
| lodestone | 60,00 | 98 | `RenderHandler$LodestoneRenderLayer` 48 MB + `ScreenParticleHandler` 12 MB |
| fancymenu | 2,50 | 378 | `MarkdownTextFragment` |
| xaeroworldmap / xaerominimap | 0,01 | 17 | `CustomVertexConsumers` |
| **RAZEM** | **676,5** | 123 047 | |

**Osobno warte uwagi — przepływ, nie retencja**: `alekiships` zaalokował
**3,9 GB narastająco w 12 103 alokacjach**, ale trzyma 0 B. To nie wyciek, tylko
bardzo wysoka rotacja alokacji natywnych — kandydat na przyczynę mikroprzycięć,
nie na zjadacza RAM.

### Trzy błędy metodyczne wykryte i naprawione w tej sesji

1. **Zrzut przy zamykaniu nadpisywał migawkę ze stanu ustalonego.** Po zamknięciu gry
   bufory są zwolnione i zostaje 307 MB zamiast 676 MB — czyli dane bezużyteczne.
   Naprawa: zrzut końcowy idzie do osobnych plików `*-final.csv`.

2. **Kubełkowanie adresów po 1 MB dawało ujemny narzut alokatora** (−207 MB).
   Regiony zaczynają się na granicy 64 KB, więc początek kubełka potrafił wypaść
   PRZED początkiem regionu i bajty lądowały w złym regionie albo nigdzie.
   Naprawa: agent zrzuca dokładne adresy każdej żywej alokacji.

3. Raport zderzenia nie odejmował JVM, przez to „regiony bez alokacji agenta"
   zawierały stertę. Teraz rozdziela: LWJGL / JVM wg NMT / **niewyjaśnione**.

### Budżet tej sesji
| składnik | commit |
|---|---|
| JVM wg NMT | 3566 MB |
| IMAGE + MAPPED | 564 MB |
| poza JVM | 6583 MB |
| **RAZEM** | **10 713 MB** (WS 8865 MB) |

## 2026-07-23 — sesja 4: JEMALLOC OBALONY, 5,8 GB nadal niewyjaśnione

Zderzenie dokładnych adresów żywych alokacji z mapą regionów procesu
(`mem-budget.ps1 -AgentAddr`, `budget-agent4-2026-07-23-1343.csv`).

| składnik | commit |
|---|---|
| **regiony zawierające alokacje LWJGL** | **681,7 MB** |
| — z tego żywe wg agenta | 676,5 MB |
| — **narzut jemalloca** | **5,1 MB** |
| JVM wg NMT | 3555,2 MB |
| **NIEWYJAŚNIONE** | **5795,4 MB** |
| IMAGE + MAPPED | 486 MB |
| **RAZEM PROCES** | **10 518 MB** (WS 8751 MB) |

### Hipoteza 88 aren jemalloca — OBALONA
Alokator trzyma pamięć **wyjątkowo ciasno**: 681,7 MB regionów na 676,5 MB żywych
danych, czyli narzut **5,1 MB (0,75%)**. Mimo 88 aren i `dirty_decay_ms=10000`.
Strojenie `JE_MALLOC_CONF` nie ma sensu — nie ma tam czego odzyskiwać.
Wariant `stdalloc` i `jemalloc-tuned` z planu są **bezprzedmiotowe**.

### Charakterystyka niewyjaśnionych 5,8 GB
Regiony >= 16 MB, poza stertą (2328 MB @0x680000000):
- **71 regionów po dokładnie 32 MB**, 16 po 64 MB, 4 po 68 MB, 3 po 76 MB, 7 po 40 MB,
- skupione w jednym obszarze adresowym (0x1A6…–0x1A8…),
- część **zacommitowana, ale nigdy nietknięta** (WS = 0 przy 76 MB commitu).

Taka regularność (dokładnie 32/64 MB) to sygnatura **puli o stałym rozmiarze kawałka**.
Nie jest to jemalloc (ten ma tylko 681 MB), nie jest to JVM (NMT to pokrywa).

### Ślepy zaułek: księgowanie zasobów GPU bajtkodem NIE JEST MOŻLIWE
Zbudowane i **odłożone**. Punkty wejścia OpenGL w LWJGL 3.3.1 są **metodami natywnymi**:
```
public static native void glBindTexture(int, int);
public static native void glBindBuffer(int, int);
public static native void nglTexImage2D(int,int,int,int,int,int,int,int,long);
public static native void nglBufferData(int,long,long,int);
```
Metoda natywna nie ma bajtkodu, więc nie ma gdzie wstrzyknąć licznika. Bez przechwycenia
`glBindTexture`/`glBindBuffer` nie da się powiązać `glTexImage2D` z identyfikatorem
tekstury, a bez tego księgowanie kasowania zasobów jest niemożliwe i licznik by dryfował.

Zabezpieczenie: `Patcher` **przerywa budowę**, gdy metoda docelowa okaże się natywna —
żeby nigdy nie wydać agenta, który udaje, że mierzy. Dodano też weryfikację
wygenerowanego bajtkodu (`CheckClassAdapter.verify`), bo łatek na GL nie da się
sprawdzić lokalnie bez kontekstu graficznego.

Kod `GlTracker` zostaje w repo — będzie potrzebny, jeśli znajdziemy inny sposób
przechwycenia (np. mixin do `GlStateManager` Blaze3D, choć to nie pokryje modów
wołających LWJGL bezpośrednio).

### Następny krok: ETW VirtualAlloc ze stosami wywołań
Skoro to nie JVM, nie LWJGL i nie jemalloc — trzeba zapytać system operacyjny,
**kto woła `VirtualAlloc`**. Windows ma do tego ETW (`wpr.exe` jest wbudowany),
a stosy wywołań wskażą DLL: sterownik GPU, Effekseer, czy coś jeszcze innego.
To jedyna metoda, która da odpowiedź bez zgadywania.

## 2026-07-23 — ETW: pamięć bierze WĄTEK RENDERUJĄCY

Ślad ETW `VirtualAlloc` (PerfView 3.2.5), pełny start gry aż do menu.
Suma zdarzeń **12,14 GB** — zgadza się z commitem procesu, więc dane są kompletne.

| wątek | VirtualAlloc (net) | udział |
|---|---|---|
| **Render thread** | **6,25 GB** | 51,5% |
| **VM Thread** (JVM) | **3,57 GB** | 29,4% |
| C2 CompilerThread0 | 94 MB | 0,8% |
| Worker-ResourceReload (×20) | ~70 MB każdy | — |
| reszta (GC, modloading, pool) | pojedyncze MB | — |

- **VM Thread 3,57 GB** to JVM rozszerzająca stertę — zgodne z NMT (~3,5 GB).
- **Render thread 6,25 GB** pokrywa się z naszymi niewyjaśnionymi ~5,8 GB.

**Pamięć jest więc alokowana przez wątek renderujący.** To zawęża pole do stosu
graficznego, ale NIE jest jeszcze dowodem na sterownik — brakuje nazwy modułu.

### Błąd metodyczny: przycięcie zdarzeń jądra zabiło stosy
Pierwsze zbieranie użyło `/KernelEvents:Process,Thread,ImageLoad,VirtualAlloc`
(żeby zmniejszyć plik). Skutek: **całe 6,25 GB wylądowało jako `Exc` na gołym węźle
wątku**, bez ani jednej ramki modułu. Pod `Render thread` rozwinęło się tylko 8,8 MB,
i to samego szumu (`condrv.sys`, `ntoskrnl`).

To nie jest urwanie stosu na kodzie JIT — wtedy widzielibyśmy ramki natywne
POWYŻEJ urwania (`ntdll` → `kernelbase` → sterownik). Nie ma ich wcale, więc
stosy w ogóle nie zostały zapisane.

Poprawka: `/KernelEvents:Default,VirtualAlloc` (Default włącza infrastrukturę
chodzenia po stosie), bez `/StackCompression`, większe bufory. Cena: znacznie
większy plik śladu.

### Drugi błąd: kolejność uruchamiania
Ślad trzeba włączyć **przed** startem gry — szukana pamięć powstaje w pierwszych
~45 s przy ładowaniu modów. Skrypt teraz przerywa, gdy `javaw` już działa.

### Do zweryfikowania przy interpretacji
Czy PerfView liczy w tym widoku wyłącznie **commit**, czy również **rezerwacje**
przestrzeni adresowej. Jeśli to drugie, część z 6,25 GB może być pustą przestrzenią
bez kosztu w RAM. Zderzyć z niezależnym pomiarem commitu z `mem-budget.ps1`.

## 2026-07-23 — ROZWIĄZANE: pełna atrybucja pamięci natywnej per moduł

Ślad ETW `VirtualAlloc` ze stosami, zdarzenia jądra zwinięte
(`FoldPats: ntoskrnl;*.sys;ntdll;kernelbase;kernel32`), grupowanie po modułach.
**To jest odpowiedź na pytanie postawione na starcie projektu.**

| moduł | Exc | udział | co to jest |
|---|---|---|---|
| `jvm` | **4,03 GB** | 34,5% | sama JVM: sterta, metaspace, kod JIT — zgodne z NMT |
| **`nvoglv64`** | **3,34 GB** | 28,6% | **sterownik OpenGL NVIDII** |
| **`effekseernativeforjava`** | **1,03 GB** | 8,8% | **natywna biblioteka efektów cząsteczkowych** |
| `?!?` (nierozpoznany) | 781 MB | 6,7% | najpewniej ramki kodu JIT Javy |
| `vcruntime140` | 765 MB | 6,5% | malloc bibliotek natywnych |
| `ucrtbase` | 535 MB | 4,6% | jw. |
| `lwjgl_stb` | 388 MB | 3,3% | dekodowanie obrazów (wczytywanie tekstur) |
| `zip` | 205 MB | 1,8% | rozpakowywanie 257 jarów |
| `win32u` / `nio` | 144 / 142 MB | 2,4% | GDI / kanały NIO |
| `jemalloc` | 71 MB | 0,6% | potwierdza wcześniejsze ustalenie: alokator jest niewinny |
| `opengl32` | 2 MB (Inc 142 MB) | — | cienka warstwa nad sterownikiem |

Suma ok. **11,4 GB** — zgadza się z commitem procesu.

### Zgodność z niezależnym pomiarem
Nasze „niewyjaśnione 5,8 GB" z `mem-budget.ps1` rozkłada się na:
`nvoglv64` 3,34 + `effekseer` 1,03 + `vcruntime140` 0,77 + `ucrtbase` 0,54 + `lwjgl_stb` 0,39
= **6,07 GB**. Dwie zupełnie różne metody dają zgodny wynik.

### Dwa konkretne winowajcy

**1. Sterownik NVIDII — 3,34 GB.** Potwierdza hipotezę WDDM: sterownik trzyma w RAM
systemowym kopie zasobów GPU. Nie jest to „wina moda" wprost, ale skutek liczby
i rozmiaru zasobów graficznych, które paczka każe mu utworzyć. Spójne ze zmierzonym
wcześniej zyskiem −4,2 GB WS po wyłączeniu shaderów.

**2. Effekseer — 1,03 GB w 85 alokacjach.** To jest ten trop z pierwotnego briefu,
teraz z liczbą. Alokuje całkowicie poza JVM, więc była niewidoczna dla NMT,
heap dumpów i dla naszego agenta. Kolumna „When" pokazuje, że pamięć powstaje
w jednym oknie czasowym — przy ładowaniu zasobów, nie w trakcie gry.

**KOREKTA wcześniejszego zapisu**: w briefie i w notatkach z 2026-07-22 stało,
że Effekseera używa „rodzina TACZ". **To nieprawda.** Przeskanowaliśmy constant pool
wszystkich klas: `tacz`, `tacz-tweaks` i `particle_core` mają **zero** odwołań do
Effekseera czy AAAParticles. Biblioteka siedzi wyłącznie w `aaa_particles`
(`Effekseer/swig/*` w jarze) i tylko ten mod jej używa. Żaden inny mod nie deklaruje
też od niego zależności w `mods.toml` — wyłączenie jest bezpieczne.

## 2026-07-23 — DLACZEGO PROBLEM ZALEŻY OD MASZYNY (wyjaśnienie od użytkownika)

Kontekst, który spina wszystkie dotychczasowe obserwacje:

| maszyna | GPU | VRAM | objawy |
|---|---|---|---|
| laptop A | RTX 4050 Laptop | **6 GB** | stronicowanie, przycięcia |
| laptop B (16 GB RAM) + stacja TB4 | RTX 4080 SUPER | **16 GB** | dużo RAM zajęte, ale **nigdy** stronicowania |
| **laptop docelowy** | **Radeon 780M (iGPU)** | **brak własnej** | najgorszy przypadek, brak TB4 |

**To wyjaśnia 3,34 GB w `nvoglv64`.** Windows (WDDM) trzyma w RAM systemowym kopie
zasobów GPU, żeby móc je wywłaszczać i wracać. Im mniej VRAM, tym więcej pracy
po stronie RAM. Przy 16 GB VRAM zasoby mieszczą się na karcie i sterownik nie musi
utrzymywać tylu kopii — stąd brak stronicowania na 4080S mimo dużego zużycia RAM.
Przy 6 GB VRAM zaczyna się przelewanie.

**Prognoza dla maszyny docelowej (780M)**: iGPU nie ma własnej pamięci — VRAM
jest wykrojony z RAM systemowego. Zasoby graficzne będą kosztować RAM **dwa razy**
(kopia robocza + backing sterownika) albo trafią w całości do RAM. Ten składnik
będzie tam najgorszy ze wszystkich testowanych konfiguracji, a nie najlepszy.

Wniosek dla priorytetów: redukcja zasobów graficznych (shadery, renderDistance,
rozdzielczość tekstur, liczba wariantów shaderów) jest dla maszyny docelowej
**ważniejsza** niż cokolwiek po stronie Javy.

### Uwaga metodyczna: `lwjgl_stb` to nasz udokumentowany martwy punkt
388 MB przez STB. Agent `ramattr` tego NIE widział, bo STB dostaje surowe wskaźniki
na funkcje alokatora (`getMalloc()`), omijając księgowanie. Przewidzieliśmy ten martwy
punkt przy projektowaniu agenta i ETW go domknął.

### Jak to zmierzyć ponownie
1. `pwsh -File scripts\trace-virtualalloc.ps1` (jako administrator, PRZED startem gry)
2. `pwsh -File scripts\trace-virtualalloc.ps1 -Analyze`
3. W PerfView: `Net Virtual Alloc Stacks` → proces `javaw` →
   **`FoldPats`: `ntoskrnl;*.sys;ntdll;kernelbase;kernel32`** → zakładka `ByName`, sort po `Exc`.

Bez tego `FoldPats` widok jest bezużyteczny — na górze lądują ramki jądra,
przez które przechodzi każda alokacja.

### Wnioski akcyjne po sesji 1
1. **Grafika:** renderDistance 24 → 12 i test bez shaderów da największy skok FPS na iGPU (zad. B3/C5).
2. **RAM heap:** Oculus+shaderpack ≈ 200+ MB samych AST; EMI 100 MB; Xaero 60+ MB; BlockState 148 MB.
3. **RAM natywny:** wciąż nierozbity — zadanie A3 (NMT) pozostaje kluczowe.
4. **Stutter po world-load:** kompilacja shaderów w trakcie gry + burst meshingu — patrz C4/C5.
5. Zadania A1, A2 wykonane; A4 zbędne (oś czasu okien wystarczyła).
