# Format presetu — kontrakt między Patcherem a repozytorium presetów

**Wersja formatu: 1.**

Ten dokument jest **umową**. Patcher implementuje dokładnie to, co tu opisane, i nic
ponadto; repozytorium presetów nie wolno użyć niczego, czego tu nie ma. Kopia tego pliku
leży w obu repozytoriach — zmiana formatu to zmiana **obu** kopii naraz i podbicie
`formatVersion`.

Zasada nadrzędna: **Patcher nie wie nic o TerraFirmaGreg.** Nie zna nazwy żadnego moda,
żadnego klucza configu, żadnej flagi JVM. Umie tylko: pobrać manifest z wydania, zbudować
z niego plan, sprawdzić stan i wykonać zaznaczone pozycje odwracalnie.

---

## 1. Skąd Patcher bierze manifest

Patcher ma listę **repozytoriów presetów** (wbudowane domyślne + dodane przez użytkownika,
patrz `PATCHER-CHANGES.md` §2). Dla każdego z nich:

1. pyta GitHuba o najnowsze wydanie zawierające załącznik `preset-*.json`,
2. pobiera **tylko ten plik** (kilkanaście KB) i waliduje,
3. buduje plan; ciężkie załączniki (shaderpack, narzędzia) ściąga **dopiero**, gdy
   użytkownik zaznaczy pozycję, która ich potrzebuje.

Manifest i jego załączniki muszą leżeć w **tym samym wydaniu** — `installAsset` szuka
załącznika obok manifestu, po masce.

---

## 2. Szkielet manifestu

```json
{
  "formatVersion": 1,
  "id": "tfg-modern",
  "name": "TerraFirmaGreg-Modern - stan optymalizacyjny",
  "version": "3.0.0",
  "minPatcher": "3.1.0",
  "docs": "https://github.com/.../OPTIMIZATIONS-SPEC.md",
  "pack": { "minecraft": "1.20.1", "loader": "forge", "loaderVersion": "47.4.13" },
  "vars":     { ... },
  "profiles": [ ... ],
  "groups":   [ ... ],
  "items":    [ ... ]
}
```

| Pole | Wymagane | Znaczenie |
|---|---|---|
| `formatVersion` | tak | musi być `1`; wyższą wartość Patcher odrzuca z czytelnym komunikatem |
| `id` | tak | identyfikator presetu; klucz w cache |
| `name` | tak | nagłówek w oknie Patchera |
| `version` | tak | wersja presetu, pokazywana użytkownikowi; zwykle = tag wydania |
| `minPatcher` | nie | najniższa wersja Patchera, która to obsłuży; niższa → ostrzeżenie i pominięcie |
| `docs` | nie | link „dlaczego" pokazywany przy nagłówku |
| `pack` | nie | do ostrzeżeń walidacyjnych (MC/loader instancji ≠ preset) |

**Klucz `_` w dowolnym obiekcie to komentarz.** Wartość: napis albo tablica napisów.
Patcher go ignoruje. JSON nie ma komentarzy, a te pliki mają być czytane przez ludzi.

---

## 3. `vars` — zmienne presetu

Wartości: napis, liczba albo **tablica napisów** (składana spacjami — po to, żeby długie
listy flag dały się czytać i recenzować w diffie po jednej na linię).

```json
"vars": {
  "shaderpack": "TerraFirmaGreg-Shaders-Complementary-3.1.5.zip",
  "jvmArgs": ["-XX:+UseG1GC", "-XX:MaxGCPauseMillis=50"]
}
```

Podstawienie `{nazwa}` działa **w każdym napisie** w `items`: w ścieżkach, wartościach,
tytułach, maskach załączników. Kolejność rozstrzygania nazwy:

1. `vars` profilu (przesłaniają presetowe),
2. `vars` presetu,
3. zmienne wbudowane Patchera (niżej).

Nieznana nazwa w klamrach = **błąd walidacji**, nie puste podstawienie. Literalna klamra:
`{{`.

### Zmienne wbudowane (dostarcza Patcher)

| Zmienna | Wartość |
|---|---|
| `{instanceDir}` | katalog instancji (ten z `instance.cfg`) |
| `{gameDir}` | katalog gry (`minecraft/` w Prismie, sam katalog przy serwerze) |
| `{toolsDir}` | `{instanceDir}\.tfg-patcher\tools` — tam lądują narzędzia |
| `{profile}` | id wybranego profilu |

Separatory ścieżek są **natywne dla systemu** — w `{toolsDir}` na Windowsie backslashe.

---

## 4. `profiles`

```json
{ "id": "standard", "label": "Standard", "description": "...",
  "default": true, "vars": { "renderDistance": 8, "xmx": 6144 } }
```

| Pole | Znaczenie |
|---|---|
| `id`, `label`, `description` | identyfikator i to, co widać w oknie |
| `default` | profil zaznaczony na starcie; dokładnie jeden w manifeście |
| `side` | `client` \| `server` \| `both` (domyślnie `both`) — profil serwerowy Patcher wybiera sam, gdy wykryje serwer |
| `vars` | wartości przesłaniające `vars` presetu |

Profile są **danymi presetu**, nie kodem Patchera. Dodanie profilu „laptop 8 GB" to wpis
w manifeście i nowe wydanie.

### Kto jest właścicielem profili

Podział jest taki: **Patcher zna pojęcie profilu, preset zna wartości.**

Po stronie Patchera (kod, ten sam dla każdego presetu):
- selektor profilu w oknie i `--profile` w CLI,
- **automatyczne przełączenie na profil serwerowy**, gdy wykryje serwer,
- ręczne nadpisanie pojedynczych gałek (`renderDistance`, `MaxMemAlloc`) po wybraniu profilu,
- pamiętanie wyboru użytkownika.

Po stronie presetu (dane): jakie profile istnieją, jak się nazywają i jakie mają wartości.
Preset 3.0.0 deklaruje trzy — `standard`, `high`, `server` — czyli dokładnie to, co
Patcher 3.0.0 miał zaszyte w `runner.PROFILES`. Dla użytkownika nic się nie zmienia:
te same trzy przyciski, te same wartości.

**Gdy źródeł jest kilka**, a każde deklaruje profile: Patcher pokazuje **sumę po `id`**,
pierwsze źródło wygrywa etykietę i opis. Preset, który nie zna wybranego `id`, liczy
swoje pozycje z własnego profilu `default` — dzięki temu cudzy preset nie znika z planu
tylko dlatego, że nie słyszał o naszym „high". Stąd zalecenie: **trzymać się wspólnych
`id`** (`standard` / `high` / `server`), a różnicować wartości, nie nazwy.

---

## 5. `groups`

```json
{ "id": "optimizations", "label": "Optymalizacje", "description": "..." }
```

Kolejność tablicy = kolejność sekcji w oknie i w `--list`. Grupa bez pozycji się nie
pokazuje. Pozycja wskazująca nieistniejącą grupę = błąd walidacji.

---

## 5a. `modSources` — repozytoria z modami (nie: lista modów)

**Preset nie wylicza modów.** Wylicza **repozytoria**; mody Patcher znajduje sam.

```json
"modSources": [
  {
    "repo": "AtmatiAdi/TFG-Modern_atmatiadi",
    "label": "Mody AtmatiAdi",
    "group": "mods",
    "side": "both",
    "prerelease": false,
    "only": null,
    "except": ["testmod"],
    "mods": {
      "mapatlas": { "name": "Map Atlas", "why": "...", "doc": "...", "side": "both" }
    }
  }
]
```

Powód jest ten sam, dla którego robimy całą migrację: **lista modów w manifeście znaczy,
że nowy mod wymaga nowego wydania presetu.** Repozytorium jako źródło znaczy, że autor
moda wydaje jar i to wszystko — mod pojawia się w planie u wszystkich, jako osobna
pozycja do zaznaczenia.

### Konwencja tagów — jedyne, na co trzeba się umówić

```
<mod>-<x.y.z>            mapatlas-0.4.0   ferrite-tweaks-1.2   map-atlas-v1.2.3
```

Patcher przegląda wydania repozytorium, rozkłada tagi, **grupuje po nazwie moda i bierze
najwyższą wersję każdego**. Jedno wydanie = jeden mod w jednej wersji; nie trzeba dopinać
jarów pozostałych modów ani rozbijać modów na osobne repozytoria.

| Zasada | Szczegół |
|---|---|
| wersja | segmenty liczbowe, porównywane **liczbowo**: `0.10.0` > `0.9.0`, `10.0.0` > `2.0.0`; `v` z przodu wolno |
| nazwa moda | wszystko przed ostatnim `-<wersja>`; myślniki w nazwie są w porządku (`map-atlas-1.2.3` → `map-atlas`) |
| tag bez wersji | pomijany z wpisem w logu — `v1.0`, `mapatlas`, `mapatlas-0.4.0-beta` nie wejdą |
| załączniki | brane są `.jar` zaczynające się od nazwy moda; gdy takich nie ma — wszystkie `.jar` z wydania |
| wydanie bez `.jar` | pomijane (tak odpadają tagi w rodzaju `TFG-1.20.1`) |
| drafty | zawsze pomijane |
| prereleasy | pomijane, chyba że źródło ma `"prerelease": true` — to jest kanał testowy |
| usuwanie starszych | wyprowadzane z nazwy moda (`<mod>-*.jar`), nikt tego nie wpisuje i nie da się zapomnieć |

### Pola źródła

| Pole | Wymagane | Znaczenie |
|---|---|---|
| `repo` | tak | `wlasciciel/repozytorium`; **musi być publiczne** |
| `label` | nie | nazwa źródła pokazywana przy pozycjach |
| `group` | nie | grupa dla znalezionych modów (domyślnie `mods`) |
| `side` | nie | domyślna strona dla modów z tego repo (domyślnie `both`) |
| `prerelease` | nie | czy brać prereleasy (domyślnie `false`) |
| `only` | nie | biała lista nazw modów; `null` = wszystkie |
| `except` | nie | czarna lista nazw modów |
| `mods` | nie | **opcjonalne** opisy: `name`, `why`, `doc`, `side` per mod |

`mods` służy wyłącznie temu, żeby pozycja ładnie wyglądała. Mod, którego tam nie ma,
działa normalnie: nazwa z tagu, opis z pierwszej linii notatek wydania.

Pozycja planu dostaje `id` = `mod-<nazwa moda>` — **stabilne między wersjami**, więc
dziennik cofania i `--only` działają po aktualizacji moda. Znalezione mody trafiają do
swojej grupy **po** pozycjach wypisanych w `items`, w kolejności alfabetycznej.

### Kiedy mimo to użyć `installRelease`

Gdy repozytorium **nie trzyma naszej konwencji** — cudzy mod na GitHubie, wydawany tagami
`release-2024-11` albo `v3`. Wtedy wskazujesz repo i maskę załącznika ręcznie (§8).
Dla własnych repozytoriów to niepotrzebne i szkodliwe: wraca problem, od którego uciekamy.

---

## 6. `items` — pozycje planu

```json
{
  "id": "aaa-particles-gc",
  "group": "optimizations",
  "side": "client",
  "title": "Effekseer: auto-zwalnianie pamieci czastek pod presja RAM",
  "doc": "OPTIMIZATIONS-SPEC.md sekcja A1",
  "why": "Zwalnia do ~1 GB natywnej pamieci czastek, gdy wolny RAM spada ponizej ~1,5 GB.",
  "changes": [ { "op": "...", ... } ]
}
```

| Pole | Wymagane | Znaczenie |
|---|---|---|
| `id` | tak | unikalny; **nie zmieniaj go po wydaniu** — użytkownik ma go w dzienniku i w `--only` |
| `group` | tak | musi istnieć w `groups` |
| `side` | tak | `client` \| `server` \| `both`; niepasująca strona → stan „pominięte" |
| `title` | tak | jedna linia w planie |
| `doc` | tak | sekcja w `OPTIMIZATIONS-SPEC.md` albo link — **pozycja bez uzasadnienia nie wchodzi** |
| `why` | tak | jedno–dwa zdania widoczne w planie |
| `changes` | tak | lista operacji, kolejność ma znaczenie |
| `selected` | nie | czy pozycja ma być **zaznaczona domyślnie**; szczegóły niżej |

### `selected` — domyślne zaznaczenie, także per profil

Domyślnie Patcher zaznacza wszystko, co jest w stanie `todo`. `selected` pozwala presetowi
powiedzieć, że dana pozycja ma być **widoczna, ale niezaznaczona** — bo jest opcjonalna
albo ma sens tylko na części maszyn.

```json
"selected": false                 // nigdy nie zaznaczaj z automatu
"selected": { "high": false }     // odznaczona w profilu "high", w reszcie normalnie
"selected": { "*": false, "standard": true }   // "*" ustawia resztę profili
```

Wartość: `true`/`false` albo obiekt `id profilu → bool` z opcjonalnym kluczem `"*"` dla
pozostałych. Brak wpisu i brak `"*"` = zachowanie domyślne (zaznacz, gdy `todo`).
Nieznany id profilu w obiekcie = **błąd walidacji** (literówka w nazwie profilu byłaby
inaczej niewidoczna).

To wpływa **wyłącznie na początkowy stan pola wyboru**. Pozycja nadal jest widoczna
w planie ze swoim stanem, użytkownik nadal może ją zaznaczyć ręcznie, i nadal nic się nie
dzieje bez kliknięcia. `selected` **nie jest** sposobem na ukrywanie pozycji.

**Kolejność pozycji w `items` = kolejność wykonania.** Pozycja, która tworzy plik, musi
stać przed pozycją, która ten plik edytuje. (Patcher i tak sprawdza stan każdej operacji
ponownie tuż przed wykonaniem, ale to zabezpieczenie, nie zastępstwo kolejności.)

### Stany pozycji

`ok` (zrobione) · `todo` (do zmiany) · `missing` (brak celu — np. nie ma pliku configu) ·
`error` · `skipped` (nie ta strona). Preset **nie** wpływa na to, co Patcher zaznacza:
zaznaczane jest wyłącznie `todo`.

---

## 7. Ścieżki

Ścieżka w `file` / `target` jest **względna wobec katalogu gry** (`{gameDir}`), z dwoma
przedrostkami wyjątkowymi:

| Zapis | Rozwija się do |
|---|---|
| `config/foo.toml` | `{gameDir}/config/foo.toml` |
| `options.txt` | `{gameDir}/options.txt` |
| `mods/` | `{gameDir}/mods/` |
| `@instance/instance.cfg` | `{instanceDir}/instance.cfg` |
| `@tools/ram-keeper` | `{toolsDir}/ram-keeper` |

Zawsze ukośnik `/` — Patcher tłumaczy go na separator systemu. **Wyjście poza katalog
instancji (`..`, ścieżka bezwzględna, litera dysku) jest błędem walidacji** i jest
odrzucane także w czasie wykonania. Manifest przychodzi z sieci; to jest granica zaufania.

---

## 8. Słownik operacji (`changes[].op`)

To **jedyne** operacje, jakie Patcher potrafi. Nowej nie da się „dopisać w manifeście" —
wymaga zmiany w Patcherze, podbicia `formatVersion` i tego dokumentu.

### `setKey` — jeden klucz w pliku klucz-wartość

```json
{ "op": "setKey", "file": "config/ferritecore-mixin.toml", "style": "toml",
  "section": null, "key": "compactFastMap", "value": "true", "addIfMissing": true }
```

| Pole | Znaczenie |
|---|---|
| `style` | `toml` \| `properties` \| `options` \| `ini` — sposób zapisu (separator, sekcje, wcięcie) |
| `section` | nazwa sekcji `[...]`; tylko dla `toml` i `ini`, inaczej pomiń |
| `value` | zawsze **napis** (także dla liczb i `true`/`false`) — porównanie idzie po tekście |
| `addIfMissing` | domyślnie `true`; `false` = brak klucza to „brak celu", nie „dopisz" |

Zmiana jest **chirurgiczna**: komentarze, kolejność linii, wcięcia i znaki końca linii
zostają nietknięte. Cudzysłowy są zdejmowane przy porównaniu (Prism trzyma `JvmArgs`
w cudzysłowach), więc `"{jvmArgs}"` w manifeście jest poprawne i porówna się sensownie.

### `setJson` — jedna wartość skalarna w pliku JSON

```json
{ "op": "setJson", "file": "config/alltheleaks.json", "key": "ingredientDedupe", "value": "false" }
```

Podmiana **bez reformatowania pliku** — tylko wartość skalarna (`true`/`false`/liczba/
napis) przy podanym kluczu. Brak klucza = „brak celu"; ta operacja niczego nie dopisuje.
Klucze zagnieżdżone nie są obsługiwane.

### `installAsset` — plik z załączników TEGO wydania

```json
{ "op": "installAsset", "asset": "{shaderpack}", "target": "shaderpacks/{shaderpack}",
  "onlyIfMissing": true, "replaceGlob": null, "unpack": null }
```

| Pole | Znaczenie |
|---|---|
| `asset` | maska nazwy załącznika wydania (`*` = dowolny fragment) |
| `target` | plik docelowy, a przy `unpack` — katalog docelowy |
| `onlyIfMissing` | `true` = nie nadpisuj, gdy plik już jest (cudze ustawienia zostają) |
| `replaceGlob` | które **starsze** pliki w katalogu docelowym usunąć (z kopią zapasową) |
| `unpack` | `"zip"` = rozpakuj archiwum do `target` zamiast kopiować plik |

Pobranie jest **leniwe**: dopóki pozycja nie jest zaznaczona, załącznik się nie ściąga.
Załącznik nieściągnięty → pozycja widoczna ze stanem „brak celu" i informacją, czego brak.

### `installRelease` — **przypięty** plik z wydania innego repozytorium

```json
{ "op": "installRelease", "repo": "ktos/inny-mod", "asset": "innymod-*.jar",
  "target": "mods/", "replaceGlob": "innymod-*.jar" }
```

**Do repozytoriów, które nie trzymają konwencji tagów.** Dla własnych używa się
`modSources` (§5a) — wtedy nowy mod nie wymaga wydania presetu.

Patcher szuka **najnowszego wydania zawierającego załącznik pasujący do maski** — nie po
prostu `releases/latest`. Nazwa pliku docelowego = nazwa załącznika, gdy `target` kończy
się `/`.

**Repo musi być publiczne.** Na prywatne GitHub odpowiada `404`, nie `403` — odbiorca
z anonimowym Patcherem po prostu go nie zobaczy.

### `disableMods` — wyłączenie modów przez `.jar` → `.jar.disabled`

```json
{ "op": "disableMods", "prefixes": ["xaerominimap", "xaeroworldmap"],
  "scan": { "tokens": ["xaero/common/", "xaero/map/"] } }
```

`scan` jest **obowiązkowy** i nie jest formalnością: przed wyłączeniem Patcher przegląda
**constant pool** wszystkich pozostałych jarów, bo `mods.toml` nie wystarcza (precedens:
`sandworm_mod` → `aaa_particles`, brak wpisu w `mods.toml`, wyłączenie wywaliło grę).

Trafienia dzielą się na **miękkie** (klasa w pakiecie `compat/`, `integration/`, `mixin/`,
`plugin/` — ładowana tylko przy obecnym modzie; wynik: informacja w logu) i **twarde**
(przerywają wykonanie, chyba że `--force`). Dlatego tokeny mają być **wąskie**: `xaero/`
łapało `xaero/pac/`, czyli Open Parties and Claims — inny mod tego samego autora.

---

## 9. Narzędzia (grupa `tools`)

Narzędzie to nie jest osobny rodzaj pozycji — to zwykła pozycja złożona z dwóch rzeczy:

1. `installAsset` z `unpack: "zip"` do `@tools/<nazwa>`,
2. `setKey` na `@instance/instance.cfg`: `OverrideCommands=true` +
   `PreLaunchCommand="{toolsDir}\<nazwa>\<skrypt>.cmd"`.

Prism uruchamia `PreLaunchCommand` **i czeka na jego zakończenie**, zanim wystartuje grę.
Skrypt startowy narzędzia musi więc odpalić właściwy proces w tle i **natychmiast wrócić** —
inaczej gra nie wystartuje, dopóki narzędzie nie skończy pracy.

Wynika z tego, że narzędzia działają **tylko w instancjach Prisma**. W katalogu gry bez
Prisma nie ma `instance.cfg` i pozycja pokaże „brak celu" — to poprawne zachowanie, nie
błąd. Cofnięcie (`--revert`) usuwa wgrane pliki i przywraca `instance.cfg`.

---

## 10. Walidacja

`build/validate.js` w repozytorium presetów sprawdza manifest przed wydaniem; Patcher
sprawdza go **ponownie po pobraniu** i odrzuca całość, gdy coś się nie zgadza — lepiej
pokazać „preset uszkodzony", niż wykonać połowę.

Sprawdzane jest: `formatVersion`, komplet pól wymaganych, unikalność `id`, istnienie
grup i profili, znane `op` i `style`, wszystkie `{zmienne}` rozwiązywalne, ścieżki bez
wyjścia poza instancję, `disableMods` z niepustym `scan.tokens`, dokładnie jeden profil
`default`.

---

## 11. Zgodność wstecz

- Patcher **starszy** niż `minPatcher` presetu: pokazuje komunikat „zaktualizuj Patcher"
  i **nie** buduje planu z tego presetu. Pozostałe presety działają normalnie.
- Patcher **nowszy**: obsługuje `formatVersion` 1 tak długo, jak długo istnieje ta sekcja.
  Format 2 nie usunie formatu 1 — dodanie obsługi nowego nie może zabrać starego, bo
  ludzie mają w cache stare manifesty i grają offline.
- Zmiana znaczenia istniejącego `op` bez podbicia `formatVersion` jest **zabroniona**.
