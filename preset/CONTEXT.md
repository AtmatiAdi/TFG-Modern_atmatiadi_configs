# Kontekst repozytorium presetów — czytaj to najpierw

Dokument dla każdej nowej sesji (człowieka albo modelu) pracującej tutaj. Mówi, czym to
jest, skąd się wzięło i czego **nie** wolno zmieniać bez pomiaru.

---

## Trzy repozytoria, trzy role

| Repo | Co w nim jest | Kiedy tu pracujesz |
|---|---|---|
| **to repo** (presety) | `preset.json`, uzasadnienia pomiarowe, shaderpack, narzędzia systemowe | zmiana optymalizacji, nowy profil, nowe narzędzie |
| **repo z grą** (`TerraFirmaGreg-Modern_Optimisation`) | żywa instancja Prisma, źródła naszych modów (`mapatlas/`), surowe dane pomiarowe | tworzenie modów, zmiana mechaniki, nowe pomiary |
| **repo Patchera** (`TFG-Modern_Patcher`) | silnik: plan, wykonanie, cofanie. **Zero wiedzy o TFG** | zmiany w samym narzędziu |

Podział powstał 2026-08-05 (historia: `MIGRATION/` w repo Patchera). Powód: każda zmiana
`renderDistance` wymagała wcześniej przebudowy `.exe` i rozesłania binarki. Teraz preset
i narzędzie mają własne tempo.

---

## Jak to działa w dwóch zdaniach

Patcher pyta GitHuba o najnowsze wydanie tego repozytorium zawierające `preset-*.json`,
pobiera **sam manifest** (11 KB) i buduje z niego plan — każdą zmianę osobno, ze stanem
„zrobione / do zmiany / brak celu". Ciężkie załączniki (shaderpack, narzędzia) ściąga
dopiero, gdy użytkownik zaznaczy pozycję, która ich potrzebuje.

Wykonywane jest **tylko** to, co użytkownik zaznaczy, i wszystko jest odwracalne: kopie
plików lądują w `.tfg-patcher/backup-<data>/` w katalogu instancji.

---

## Dlaczego te konkretne optymalizacje — skrót śledztwa RAM

Pełny zapis: `docs/ram/FINDINGS.md` (chronologiczny) i `docs/ram/HANDOFF.md` (brief).
Tu tylko to, bez czego nie wolno ruszać `preset.json`:

**Problem wyjściowy.** Proces gry brał **18,4 GB** przy 16 GB fizycznych → stronicowanie
→ przycięcia co ~60 s. Heap `-Xmx` to była mniejszość tego rachunku.

**Ustalenie, które przestawiło projekt** (2026-07-22): RAM jest zjadany **przy ładowaniu
modów**, nie w rozgrywce. Pomiar w menu głównym, po załadowaniu 255 modów i bez wczytanego
świata, dał **13,1 GB commitu**. Czyli: mierz w menu głównym, nie w świecie — inaczej
mierzysz szum.

**Dowód na G1.** Garbage collector trzymał **3,8 GB pustej sterty** i nie oddawał jej
systemowi. Flagi `MinHeapFreeRatio=10 / MaxHeapFreeRatio=30 / G1PeriodicGCInterval=15000`
zbiły commit z **13,1 do 10,1 GB** — to najtańsze 3 GB w całym projekcie i dlatego
`prism-jvm` jest pozycją, której nie wolno „uprościć".

**Effekseer (`aaa_particles`).** Potwierdzone **1,03 GB** pamięci natywnej. Config `[gc]
enabled=true` oddaje ją pod presją RAM.

**renderDistance.** Największa gałka po stronie gry — dane i meshe chunków rosną
kwadratowo. Stąd 8 jako standard i 24 dopiero z `Xmx 8192` (większy zasięg bez wyższego
sufitu sterty tylko zagoniłby GC).

**Czego NIE robić** (sprawdzone, kosztowało nas sesje):
- **Nie włączać `ingredientDedupe` w AllTheLeaks** — wywala grę przy wejściu do świata
  (`ATLUnsupportedOperation`). Pozycja `alltheleaks-guard` istnieje po to, żeby pilnować
  wartości `false`, a nie żeby ją zmieniać.
- **Nie wyłączać shaderów** — decyzja użytkownika, są wizualnie istotne. Wolno tylko
  przycinać ich gałki pamięci (`shaders-light`).
- **Nie dodawać `-XX:+AlwaysPreTouch`** — zarezerwowałoby całą stertę z góry.
- **`mods.toml` NIE wystarcza** do wykrycia zależności między modami. Dlatego `disableMods`
  ma **obowiązkowy** `scan.tokens`: Patcher skanuje constant pool pozostałych jarów.
  Precedens: `sandworm_mod` odwoływał się do `aaa_particles` bez wpisu w `mods.toml`
  i wyłączenie wywaliło grę.
- **Tokeny skanu mają być wąskie.** `xaero/` łapało `xaero/pac/`, czyli Open Parties and
  Claims — inny mod tego samego autora. Stąd `xaero/common/`, `xaero/map/`, `xaero/hud/`,
  `xaero/minimap/`.

---

## Zasady tego repozytorium

- **Pozycja bez uzasadnienia w `OPTIMIZATIONS-SPEC.md` nie wchodzi do `preset.json`.**
  Najpierw dokument, potem manifest. Pole `doc` każdej pozycji wskazuje sekcję.
- **Walidacja przed wydaniem, zawsze.** `pack.ps1` sam ją odpala i nie wyda niczego, co
  nie przeszło. Uszkodzony manifest u odbiorcy blokuje mu cały Patcher.
- **`id` pozycji jest wieczne.** Ludzie mają je w dziennikach cofania i w `--only`.
  Zmiana `id` to nowa pozycja, nie przemianowana stara.
- **Repozytoria z wydaniami muszą być PUBLICZNE.** Na prywatne GitHub odpowiada `404`,
  nie `403` — anonimowy Patcher odbiorcy po prostu ich nie zobaczy, choć Ty widzisz je
  w przeglądarce.
- Commity **po polsku**, krótko. Dokumentacja normalną polszczyzną; `preset.json`
  i skrypty **bez polskich znaków diakrytycznych** (konsola Windows).
- **Nie ustawiamy `fullscreen` ani `guiScale`** — to ustawienia osobiste gracza, nie
  optymalizacje.

---

## Pułapki (każda kosztowała sesję)

- **Xaero trzeba wyłączyć TAKŻE na serwerze.** Nie ustawia `displayTest` w `mods.toml`,
  więc Forge wymusza zgodność listy modów: serwer z Xaero **odrzuca** klienta bez Xaero
  („Your client is missing the following mods"). Dlatego `xaero-off` ma `side: both`.
- **Kolejność pozycji w `items` = kolejność wykonania.** Pozycja tworząca plik musi stać
  przed pozycją, która ten plik edytuje.
- **`shaders-light` stoi PRZED `shaderpack` i to jest w porządku** — wgrywany plik
  ustawień już niesie wartości profilu „light", a pozycja `shaders-light` jest strażnikiem
  dla instancji, w których pakiet siedzi po swojemu.
- **`onlyIfMissing` przy shaderpacku jest celowe.** Nie nadpisujemy cudzych ustawień
  shaderów.
- **Narzędzia działają tylko w instancjach Prisma** (wpinają się przez `instance.cfg`).
  W katalogu gry bez Prisma pozycja pokaże „brak celu" — to poprawne zachowanie.
- **Prism czeka na `PreLaunchCommand`** przed startem gry. Skrypt startowy narzędzia musi
  odpalić właściwy proces w tle i natychmiast wrócić, z przekierowaniem strumieni na `nul`
  (Prism czyta wyjście komendy — otwarty potok trzymałby go w miejscu).

---

## Stan i co dalej

- Preset **3.0.0** = jeden do jednego to, co Patcher 3.0.0 miał zaszyte w kodzie:
  12 pozycji, 27 operacji, 3 profile.
- **`ram-keeper` czeka na pomiar.** Działanie potwierdzone (+2,1 GB w cyklu, bez admina,
  na maszynie testowej), ale **nie ma pomiaru w grze** — sekcja H spec-u mówi o tym wprost.
  Pierwsza sesja z grą: commit przed/po, do `docs/ram/FINDINGS.md`.
- Model „wielu współpracowników, każdy z własnym repo" obsługuje `installRelease`; na
  razie wpisany jest jeden mod (`mapatlas`).
