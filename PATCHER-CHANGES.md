# Co zmienia się w Patcherze

Ten dokument zostaje **w repozytorium Patchera** — opisuje robotę po tej stronie granicy.
Kontrakt, którego trzeba się trzymać: `preset/docs/PRESET-FORMAT.md` (przy migracji jego
kopia trafia do `docs/` tego repozytorium — obie muszą się zgadzać co do znaku).
Zawartość nowego repozytorium: `preset/`.

Cel: **Patcher przestaje wiedzieć cokolwiek o TerraFirmaGreg.** Zostaje silnikiem, który
pobiera manifesty z wydań, buduje z nich plan i wykonuje go odwracalnie.

---

## 1. Co znika z tego repozytorium

| Plik | Los | Dokąd |
|---|---|---|
| `src/engine/patches.js` | **usunąć** (212 linii) | całość jako dane → `preset.json` |
| `src/engine/assets.js` | **usunąć** | shaderpack idzie z wydania presetu, nie z `.exe` |
| `assets/shaderpacks/*` | **usunąć** (2,2 MB) | załączniki wydania presetu |
| `sources.json` | **usunąć** | zastąpione przez `modSources` — preset wymienia **repozytoria**, nie mody |
| `docs/OPTIMIZATIONS-SPEC.md` | **przenieść** | repo presetów — uzasadnia configi, nie narzędzie |
| `docs/ram/FINDINGS.md`, `docs/ram/HANDOFF.md` | **przenieść** | tamże — to dowody pod configi |
| `docs/RELEASES.md` | **przepisać** | część o wydawaniu → `preset/docs/RELEASING.md`; zostaje krótki opis rejestru źródeł |

`runner.PROFILES` przestaje być stałą w kodzie — profile przychodzą z presetu.
`JVM_ARGS` i `XAERO_TOKENS` znikają razem z `patches.js`.

Po tej operacji `.exe` nie zawiera **żadnej** wartości konfiguracyjnej ani żadnego pliku
paczki. Zmiana optymalizacji przestaje wymagać przebudowy binarki.

---

## 2. Co dochodzi

### `src/engine/registry.js` — skąd brać presety *(nowy)*

Dwie warstwy, jak ustalono:

```jsonc
// registry.json obok exe (wbudowane domyślne)
{
  "presets": [
    { "repo": "AtmatiAdi/TerraFirmaGreg-Modern_Presets", "asset": "preset-*.json" }
  ]
}
```

```jsonc
// %LOCALAPPDATA%\TFG-Patcher\registry.json (użytkownika)
{
  "presets": [ { "repo": "kolega/jego-presety", "asset": "preset-*.json" } ],
  "disabled": [ "AtmatiAdi/TerraFirmaGreg-Modern_Presets" ]
}
```

Wynik = wbudowane + użytkownika, minus `disabled`. UI dostaje sekcję **Źródła**: lista
repozytoriów, „dodaj", „wyłącz", stan ostatniego pobrania. Plik użytkownika jest jedynym,
który Patcher zapisuje — wbudowanego nie rusza.

### `src/engine/preset.js` — manifest z wydania *(nowy)*

`release.findRelease(repo, 'preset-*.json')` → pobranie **samego manifestu** → parsowanie →
**walidacja** → cache w `%LOCALAPPDATA%\TFG-Patcher\cache\<repo>\<tag>\`. Offline: ostatni
poprawny manifest z cache, tak jak dziś działa `catalog.loadCached()`.

Walidacja to port `preset/build/validate.js` — ta sama lista sprawdzeń. **Preset, który jej
nie przechodzi, jest odrzucany w całości**, z komunikatem i wskazaniem repozytorium; reszta
źródeł działa normalnie (ta sama zasada, co przy błędzie pojedynczego moda dzisiaj).

### `src/engine/discover.js` — mody znajdowane, nie wyliczane *(nowy)*

**Gotowy prototyp: `MIGRATION/reference/discover.js`** — działa, sprawdzony na żywym
`AtmatiAdi/TerraFirmaGreg-Modern_Optimisation` (anonimowo, bez tokenu). Do silnika trafia
praktycznie bez zmian; brakuje mu tylko pobierania plików (to już robi `release.js`).

Zamiast listy modów Patcher dostaje **repozytorium**: pobiera `releases?per_page=100`
(strony do 5), rozkłada tagi `<mod>-<x.y.z>`, grupuje po nazwie moda i bierze najwyższą
wersję. Jedno zapytanie na repozytorium — taniej niż dzisiejsze `findRelease` na mod.

Rzeczy, które muszą zostać zrobione dokładnie tak, jak w prototypie:

- **Wersje porównywane liczbowo, odcinkami.** Porównanie napisów daje `"0.10.0" < "0.9.0"`
  i **cicho instaluje starszy jar** — najgorszy możliwy rodzaj błędu, bo wygląda jak
  działanie. Sprawdzone: `0.10.0`>`0.9.0`, `10.0.0`>`2.0.0`, `0.4`==`0.4.0`.
- **`(.+?)-v?(\d+(?:\.\d+)*)$`** — nazwa moda to wszystko przed ostatnim `-<wersja>`,
  więc `map-atlas-1.2.3` daje `map-atlas`, a nie `map`.
- **Tag bez wersji i wydanie bez `.jar` — pomijane z wpisem w logu.** Tak odpadają tagi
  w rodzaju `TFG-1.20.1` czy `v1.0`.
- **`replaceGlob` wyprowadzany z nazwy moda** (`<mod>-*.jar`) — nikt go nie wpisuje, więc
  nie da się zapomnieć i zostawić dwóch kopii moda w `mods/`.
- **`id` pozycji = `mod-<nazwa moda>`, bez wersji** — stabilne między aktualizacjami,
  inaczej `--only` i dzienniki cofania przestają działać po każdym wydaniu moda.
- **Błąd źródła jest lokalny** — repo, które nie odpowiedziało, zostaje przy tym, co jest
  w cache; reszta planu działa. Tak jak dziś.

### `src/engine/paths.js` — rozwiązywanie i pilnowanie ścieżek *(nowy)*

`resolve(inst, 'config/foo.toml')`, `@instance/…`, `@tools/…` → ścieżka bezwzględna.
**Wynik musi leżeć wewnątrz katalogu instancji** — sprawdzane po `path.resolve`, nie na
napisie. Manifest przychodzi z sieci; to jest granica zaufania i nie wolno jej przenieść
do `changes.js`, gdzie łatwo ją przeoczyć.

### `src/engine/compile.js` — manifest → pozycje planu *(nowy, zastępuje `patches.js`)*

```js
compile(presets, opts) -> [{ id, group, side, title, doc, why, changes: [...] }]
```

Podstawia zmienne (`vars` presetu + `vars` profilu + wbudowane), rozwiązuje ścieżki
i buduje **te same obiekty operacji, co dziś** — `setKey`, `setJson`, `installFile`,
`disableMods` z `changes.js` zostają bez zmian w środku. To jest cała sztuczka tej
migracji: zmienia się **źródło** listy, nie mechanika jej wykonywania.

Pozycje z wielu presetów sklejane są w kolejności źródeł; `id` kolidujące między presetami
dostaje przedrostek `<presetId>:`.

Dwie rzeczy, które `compile()` musi przekazać dalej, a których dziś nie ma:

- **`selected`** — domyślne zaznaczenie pozycji, także per profil (`{ "high": false }`).
  Dziś UI robi `state.checked = wszystkie todo`; ma robić `wszystkie todo, dla których
  preset nie powiedział „nie" w tym profilu`. To samo w CLI przy wyborze `ids`.
  Pierwszy użytkownik tego pola: `ram-keeper` (odznaczony w `high`).
- **Profile** — `runner.PROFILES` przestaje być stałą. Patcher zachowuje **selektor,
  automatyczne przełączenie na serwer i ręczne nadpisanie gałek**; preset dostarcza
  listę i wartości. Przy kilku źródłach: suma po `id`, pierwsze źródło wygrywa etykietę,
  preset nieznający wybranego `id` liczy się ze swojego `default`
  (`preset/docs/PRESET-FORMAT.md` §4).

---

## 3. Co się zmienia w plikach, które zostają

| Plik | Zmiana |
|---|---|
| `engine/changes.js` | `installFile` dostaje `unpack: 'zip'` (rozpakowanie przez istniejący `zip.js`, każdy plik przez `journal.recordAdd`, żeby `--revert` je usunął) oraz źródło „załącznik wydania presetu" obok dzisiejszych `assetResource`/`fileResource` |
| `engine/catalog.js` | przestaje czytać `sources.json`; źródłem modów są `modSources` z manifestów (wykrywanie po tagach, patrz niżej) + `installRelease` dla repo bez konwencji |
| `engine/runner.js` | `PROFILES` z presetu; `defaults()` bierze profil `default: true` |
| `cli.js` | `--list` iteruje po presetach; nowe `--sources` (lista źródeł), `--preset <id>` (tylko jeden) |
| `ui/app.js`, `main.js`, `preload.js` | sekcja **Źródła**, „Sprawdź źródła" zamiast „Sprawdź mody", nagłówek presetu z jego wersją |
| `package.json`, `build.ps1` | `.exe` przestaje pakować `assets/`; wersja **3.0.0 → 3.1.0** (= `minPatcher` pierwszego presetu) |

---

## 4. Zaufanie do źródeł — przeczytaj przed dodaniem cudzego repo

Dodanie repozytorium presetów to **wpuszczenie go do swojej instancji**. Konkretnie:

- pozycja z grupy `tools` może ustawić `PreLaunchCommand` w `instance.cfg`, czyli
  **doprowadzić do uruchomienia kodu** przy starcie gry,
- `installAsset` / `installRelease` wgrywają pliki do `mods/` — czyli kod, który gra ładuje.

To nie jest dziura do załatania, tylko istota narzędzia: Patcher zawsze wgrywał mody
z cudzych wydań. Ale skoro źródła stają się edytowalne, trzeba to postawić jasno:

1. **Nic nie dzieje się bez zaznaczenia i kliknięcia** — zasada zostaje bez zmian.
2. Pozycja z grupy `tools` pokazuje w planie **pełną komendę**, która trafi do
   `instance.cfg`, i **osobne ostrzeżenie** o uprawnieniach administratora.
3. Dodanie repozytorium w UI pokazuje jednorazowy komunikat: *„Preset może wgrywać mody
   i uruchamiać programy razem z grą. Dodawaj tylko repozytoria, którym ufasz."*
4. Ścieżki są ograniczone do katalogu instancji (`paths.js`) — preset nie sięgnie do
   `system32` ani do katalogu domowego, nawet gdyby chciał.
5. Słownik operacji jest **zamknięty**. Manifest nie może dodać nowej operacji; nie ma
   w formacie niczego, co wykonywałoby polecenie wprost. `PreLaunchCommand` jest wyjątkiem
   wynikającym z tego, co robi Prism — i dlatego jest z osobna pokazywany użytkownikowi.

---

## 5. Kolejność robót

1. `paths.js` + `preset.js` + `registry.js` — dają się przetestować bez ruszania reszty
   (`node -e` na manifeście z `MIGRATION/preset/preset.json`).
2. `compile.js` obok `patches.js`. Kryterium poprawności: **`--list` z presetu ma dać ten
   sam wynik, co `--list` z `patches.js`** — to jest test tej migracji, złóż go najpierw.
3. Przełączenie `runner.plan()` na `compile()`, usunięcie `patches.js`, `assets.js`,
   `sources.json`, `assets/`.
4. `unpack: 'zip'` w `changes.js` + pozycja `ram-keeper` na atrapie instancji: plan →
   apply → ponowny plan (wszystko „ZROBIONE") → revert (stan wraca, `instance.cfg` czysty,
   `.tfg-patcher/tools/` puste).
5. UI: sekcja Źródła.
6. Podbicie wersji, build, sprawdzenie u odbiorcy **bez internetu** (cache musi wystarczyć).

Kroki 1–3 nie zmieniają niczego dla użytkownika — plan ma wyglądać identycznie. Jeśli
wygląda inaczej, to nie jest „drobna różnica", tylko błąd w `compile.js`.
