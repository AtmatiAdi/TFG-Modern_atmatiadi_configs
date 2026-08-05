# Specyfikacja: co Patcher wprowadza i dlaczego

Ten dokument jest **źródłem prawdy dla listy pozycji** w `../preset.json`.
Każda pozycja manifestu wskazuje tu sekcję (pole `doc`), a każda sekcja mówi, skąd wiadomo,
że warto. Dowody pomiarowe: `ram/FINDINGS.md`, brief: `ram/HANDOFF.md`.

**Dodajesz pozycję do manifestu → dopisz ją tutaj. Najpierw uzasadnienie, potem dane.**
Pozycja bez uzasadnienia to pozycja, której nikt za pół roku nie odważy się ruszyć
ani usunąć.

Problem wyjściowy: proces gry brał **18,4 GB** przy 16 GB fizycznych → stronicowanie →
przycięcia co ~60 s. Cel: zejść poniżej ~15 GB z zapasem, nie tracąc wyglądu gry.

---

## GRUPA: Optymalizacje

### A1. Effekseer — auto-zwalnianie pamięci cząstek (`aaa-particles-gc`)
- **Plik:** `config/aaa_particles-client.toml`, `[gc] enabled` : `false` → **`true`**
- **Po co:** potwierdzone pomiarem **1,03 GB** natywnej pamięci cząstek. Mechanizm oddaje
  ją, gdy wolny RAM spada poniżej ~1,5 GB — zwalnia po jednym efekcie na wywołanie
  i pomija efekty `preload`, więc nie widać tego w grze.

### A2. AllTheLeaks — pilnowanie, że dedup sterty ZOSTAJE wyłączony (`alltheleaks-guard`)
- **Plik:** `config/alltheleaks.json`, `ingredientDedupe` i `resourceLocationDedupe` : **`false`**
- **To pozycja obronna, nie optymalizacja.** Próbowaliśmy `true` — **wywala grę przy
  wejściu do świata**: `ATLUnsupportedOperation: An Ingredient ... was cached and locked`
  → „Couldn't place player in world". `ingredientDedupe` blokuje itemstacki w składnikach,
  a mody (np. SophisticatedBackpacks) je modyfikują. `resourceLocationDedupe` dodatkowo
  wydłużał wejście do świata do 9–20 s. Zysk był marginalny wobec skali problemu.

### A3. FerriteCore — kompaktowe mapy blockstate (`ferritecore-compact`)
- **Plik:** `config/ferritecore-mixin.toml`, `compactFastMap` : `false` → **`true`**
- **Po co:** mniejsza reprezentacja stanów bloków. Koszt: minimalnie wolniejsze odczyty,
  bez ryzyka crasha.
- **NIE włączać `useSmallThreadingDetector`** — sam mod ostrzega o rzadkich crashach.

### A4. ModernFix — leniwe ładowanie modeli i tekstur (`modernfix-dynres`)
- **Plik:** `config/modernfix-mixins.properties`, `mixin.perf.dynamic_resources` : **`true`**
- **Po co:** największa gałka ModernFixa. Zwykle jest już ustawiona; pozycja pilnuje, żeby
  aktualizacja paczki jej nie cofnęła.

### B. Shadery — profil „light" (`shaders-light`)
- **Plik:** `shaderpacks/<pakiet>.zip.txt` (nazwa pliku = nazwa aktywnego pakietu + `.txt`)

| Klucz | Wartość | Uwaga |
|---|---|---|
| `COLORED_LIGHTING` | `128` → **`32`** | woksele kolorowego światła — bufor 4× mniejszy, efekt zachowany |
| `shadowDistance` | `64.0` → **`48.0`** | mniejsza mapa cieni |
| `ANISOTROPIC_FILTER` | `4` → **`0`** | profile ≤HIGH i tak mają `0`; Iris zapisuje tylko wartości inne od domyślnych, więc klucza mogło w pliku nie być — wpisujemy go jawnie |

- **Zasada: shaderów NIE wyłączamy.** Są wizualnie istotne (decyzja użytkownika). Tniemy
  wyłącznie gałki pamięci. `GENERATED_NORMALS`, `COATED_TEXTURES` i
  `BLOCK_REFLECT_QUALITY` **zostają włączone** — świadomie, warte swojego VRAM.
- Rezerwa, gdyby trzeba było przyciąć głębiej: `COLORED_LIGHTING=0` i wyłączenie dwóch
  powyższych (czyli fabryczny profil HIGH).

### C. Ustawienia gry — `options.txt` (`game-options`, `render-distance`)

| Klucz | Wartość | Po co |
|---|---|---|
| `renderDistance` | **wg profilu** (8 / 24) | NAJWIĘKSZA gałka RAM po stronie gry — dane i meshe chunków rosną kwadratowo |
| `simulationDistance` | `12` → **`8`** | mniej tykanych chunków (encje, RAM serwera) |
| `mipmapLevels` | `4` → **`2`** | mniej VRAM na mipmapy; drobne rozmycie tekstur w dali |
| `entityShadows` | `true` → **`false`** | drobny zysk VRAM/GPU |
| `particles` | **`0`** (Minimal) | idzie w parze z A1 |

**Patcher dotyka dokładnie tych pięciu kluczy i niczego więcej.** Reszta `options.txt` to
sprawy osobiste gracza — `fullscreen`, `guiScale`, głośności, keybindy. Nie ruszamy ich.

### D. Argumenty JVM w Prismie (`prism-jvm`)
- **Plik:** `instance.cfg`, sekcja `[General]`: `OverrideJavaArgs`, `OverrideMemory`,
  `MinMemAlloc`, `MaxMemAlloc`, `JvmArgs`

```
-XX:+UseG1GC -XX:MaxGCPauseMillis=50 -XX:G1HeapRegionSize=8M
-XX:MinHeapFreeRatio=10 -XX:MaxHeapFreeRatio=30
-XX:G1PeriodicGCInterval=15000 -XX:G1PeriodicGCSystemLoadThreshold=0
-XX:+UseStringDeduplication -XX:NativeMemoryTracking=summary
-Xms512m -Xmx<profil>
```

- **Najtańsze 3 GB w całym projekcie.** Zmierzone: commit **13,1 → 10,1 GB**. Dowód:
  G1 trzymał **3,8 GB pustej sterty** i nie oddawał jej systemowi; trzy flagi
  (`MinHeapFreeRatio`, `MaxHeapFreeRatio`, `G1PeriodicGCInterval`) zmuszają go do oddania.
- **NIE dodawać `-XX:+AlwaysPreTouch`** — zarezerwowałoby całą stertę z góry, czyli
  dokładnie odwrotnie do celu.
- `NativeMemoryTracking=summary` zostaje: pozwala powtórzyć pomiar przez `jcmd`.

### E. Profile maszyn

| Profil | `renderDistance` | `MaxMemAlloc` | Dla kogo |
|---|---|---|---|
| `standard` | **8** | 6144 | domyślny; obie nasze maszyny (RTX 4050 16 GB, Radeon 780M iGPU 16 GB) |
| `high` | 24 | **8192** | maszyna z zapasem RAM — żadna z naszych |
| `server` | — | 6144 | serwer dedykowany: tylko pozycje serwerowe |

Większy `renderDistance` idzie **w parze** z wyższym `Xmx`: więcej danych chunków bez
podniesienia sufitu sterty tylko zagoniłoby GC. Poza tą jedną gałką **wszystkie maszyny
mają być identyczne** — to była świadoma decyzja, żeby przestać debugować różnice.

---

## GRUPA: Mody i zasoby

### Shaderpack (`shaderpack`)
- Wgranie `<pakiet>.zip` + `.zip.txt` (załączniki wydania presetu, `installAsset`),
  następnie `config/oculus.properties`: `shaderPack=<pakiet>`, `enableShaders=true`.
- **Pakietu NIE MA w bazowej paczce z CurseForge** — został dołożony ręcznie, dlatego
  jedzie z presetem. Nazwa siedzi w `vars.shaderpack` i jest podstawiana jako
  `{shaderpack}`; podmiana wersji = nowy plik w `assets/shaderpacks/` + jedna zmiana
  tej zmiennej.
- **Nie podmieniać pakietu** — TFG-Complementary jest samodzielny i zgodny z custom
  blokami TFG (`block.properties`, 2,4 MB). Czysty Complementary psuje custom bloki.
- **Nie usuwać EuphoriaPatchera** z instancji — jego błąd „SHADER NOT FOUND" jest
  nieszkodliwy (Euphoria jest już wbudowana w pakiet), ale inne mody deklarują od niego
  zależność.
- Pliki wgrywane są **tylko gdy ich nie ma** — nie nadpisujemy cudzych ustawień shaderów.

### Mody z wydań (`mod-*`)
- Operacja `installRelease` w `preset.json`, po jednej pozycji na mod: repozytorium
  + maska załącznika. Instrukcja wydawania: `RELEASING.md`, opis pól: `PRESET-FORMAT.md`.
- Nasz mod **`mapatlas`** (item „Atlas map") zastępuje Xaero: dane trzyma serwerowo
  (per UUID atlasu), ekran otwiera na żądanie, nie cache'uje terenu w tle. Teren wyostrza
  1:1 tylko w obszarze zarezerwowanym przez dodane do niego mapy.

### G. Wyłączenie Xaero (`xaero-off`) — **klient i serwer**
- Rename `.jar` → `.jar.disabled` dla: `xaerominimap`, `xaeroworldmap`, `ftbxaerocompat`.
- **Po co:** Xaero trzyma w RAM kafle mini/worldmapy i renderuje minimapę co klatkę.
  Zastąpione mapatlasem.
- **Skan zależności jest OBOWIĄZKOWY.** Przeskanowano constant pool 258 modów pod
  `xaero/(common|map|hud|minimap)` — żaden inny mod nie zależy od Xaero poza
  `ftbxaerocompat` (też wyłączany).
- **NA SERWERZE TEŻ.** Xaero nie ustawia `displayTest` w `mods.toml`, więc Forge stosuje
  domyślne `MATCH_VERSION` i wpisuje te mody na listę wymaganych od klienta: **serwer
  z Xaero odrzuci klienta bez Xaero** („Your client is missing the following mods").

---

## GRUPA: Programy wspierające

### H. RAM Keeper — cykliczne zwalnianie pamięci w tle gry (`ram-keeper`)

- **Pliki:** `.tfg-patcher/tools/ram-keeper/` (rozpakowany załącznik wydania) +
  `instance.cfg` `[General]`: `OverrideCommands=true`,
  `PreLaunchCommand="<tools>\ram-keeper\ram-keeper.cmd"`
- **Strona:** klient, **tylko instancje Prisma** (mechanizm wpina się przez `instance.cfg`).

Co 60 sekund, dopóki proces gry żyje:

| Krok | Wywołanie | Uwaga |
|---|---|---|
| working sety pozostałych procesów | `EmptyWorkingSet` (psapi) | strony idą na listę standby, skąd system odzyskuje je natychmiast |
| lista standby | `NtSetSystemInformation(SystemMemoryListInformation, MemoryPurgeStandbyList)` | **to wymaga administratora** — chodzi na `SeProfileSingleProcessPrivilege` |
| proces gry | `EmptyWorkingSet` **tylko** gdy wolny RAM < 1536 MB | trim gry to soft-faulty; robimy go, gdy i tak groziłoby stronicowanie |

- **Po co:** śledztwo RAM (`ram/HANDOFF.md`) pokazało, że 28,6% pamięci procesu to
  `nvoglv64` — kopie zasobów GPU, które WDDM trzyma w RAM systemowym. Tego nie da się
  wyciąć configiem; można natomiast pilnować, żeby **reszta systemu** nie trzymała
  niepotrzebnie stron, gdy gra dochodzi do sufitu.
- **Dlaczego nie RAMMap.** Narzędzie Sysinternals robi dokładnie to samo przez te same
  API. Własny skrypt (8 KB) znaczy: nic do pobierania, nic do licencjonowania, nic, co
  mogłoby zniknąć z serwera producenta.
- **W profilu `high` pozycja jest domyślnie ODZNACZONA** (`"selected": { "high": false }`).
  High to maszyna z zapasem RAM — nie ma czego odzyskiwać, a okno UAC przy każdym starcie
  gry byłoby płaceniem za nic. Pozycja zostaje widoczna i można ją zaznaczyć ręcznie.
- **NIE ustawiać `-TrimGameAlways`** bez powodu. Agresywny trim procesu gry co minutę to
  mikroprzycięcia w zamian za pamięć, której nikt w tej chwili nie potrzebuje.
- **To dokładka, nie zamiennik.** Trim nie zmniejsza zapotrzebowania gry na pamięć —
  przesuwa strony tak, żeby system miał co oddać, zamiast sięgać po plik stronicowania.
  Właściwe oszczędności robią sekcje A–D.

#### Stan pomiaru — DO UZUPEŁNIENIA

Zmierzone (2026-08-05, maszyna testowa, **bez uprawnień administratora**, poza grą):
182 przetrimowane procesy, wolny RAM **16 116 → 18 220 MB (+2,1 GB)** w pierwszym cyklu.
Czyszczenie listy standby odmówiło z `0xC0000061` (`STATUS_PRIVILEGE_NOT_HELD`) — czyli
zmierzony zysk pochodzi **wyłącznie** z samych working setów, bez drugiego mechanizmu.

Kolejne cykle (co 4 s, ten sam bieg): **+499, +93, +59, +63 MB**. Raz oddanego working
setu nie da się oddać drugi raz — pętla zbiera to, co system zajmuje **narastająco**,
i tak trzeba czytać jej wartość.

**Czego brakuje:** pomiaru w grze. Commit procesu i wolny RAM przed włączeniem i po
~30 minutach gry, na maszynie docelowej (Radeon 780M, 16 GB). Dopóki tych liczb nie ma,
ta pozycja stoi na innej podstawie niż sekcje A–D i trzeba to mówić wprost.

---

Zanim wejdzie tu cokolwiek nowego: musi mieć pomiar albo jasne uzasadnienie, tak jak
każda pozycja wyżej.

---

## Czego NIE robić (zamknięte tematy)

- **Nie wyłączać shaderów na stałe** — tylko config (sekcja B).
- **Nie podmieniać pakietu shaderów**, nie usuwać EuphoriaPatchera.
- **Nie włączać dedupu w AllTheLeaks** (A2) — wywala grę.
- **Nie dodawać `AlwaysPreTouch`** (D).
- **Nie wyłączać moda bez skanu constant pool** — `mods.toml` nie wystarcza. Precedens:
  wyłączenie `aaa_particles` wywaliło grę przez `sandworm_mod`, który odwoływał się do
  niego bez wpisu w `mods.toml`.
- **DistantHorizons nie jest zainstalowany** — `config/DistantHorizons.toml` w paczce jest
  martwy i nic nie oszczędza. Nie wracać do tego pomysłu.
