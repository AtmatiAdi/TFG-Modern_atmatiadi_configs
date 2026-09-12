# Format presetu — kontrakt między Patcherem a repozytorium presetów

**Wersja formatu: 1.**

Ten dokument jest **umową**. Patcher implementuje dokładnie to, co tu opisane, i nic
ponadto; repozytorium presetów nie wolno użyć niczego, czego tu nie ma.

**Ten plik jest jedyny** — leży tutaj, a repozytorium Patchera na niego wskazuje
(`README.md`, `docs/PATCHER.md`), zamiast trzymać kopię, która i tak by się rozjechała.
Zmiana formatu to trzy rzeczy naraz: ten opis, implementacja po stronie Patchera
i podbicie `formatVersion`. Trzecia jest po to, żeby starszy Patcher **odrzucił** manifest,
którego nie umie wykonać, zamiast wykonać go połowicznie.

Zasada nadrzędna: **Patcher nie wie nic o TerraFirmaGreg.** Nie zna nazwy żadnego moda,
żadnego klucza configu, żadnej flagi JVM. Umie tylko: pobrać manifest z wydania, zbudować
z niego plan, sprawdzić stan i wykonać zaznaczone pozycje odwracalnie.

---

## 1. Skąd Patcher bierze manifest

Patcher ma **jedną listę repozytoriów** — `sources.json` w aplikacji plus plik użytkownika
`%LOCALAPPDATA%\TFG-Patcher\sources.json` (§5a). Repozytorium **nie ma rodzaju**: każde jest
sprawdzane pod obie konwencje, więc jeden autor wydaje z jednego repo i mody, i configi.
Dla każdego z nich:

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
  "shaderpack": "TFG_OPTIMISED_Complementary-3.1.5.zip",
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
| `{profile}` | id profilu, wg którego liczony jest **ten** preset (§4) — wybrany, a gdy preset go nie zna: jego własny `default`. Preset bez profili dostaje `standard` |

Separatory ścieżek są **natywne dla systemu** — w `{toolsDir}` na Windowsie backslashe.
Do `instance.cfg` (styl `ini`) wpisujesz je **dosłownie**, bez podwajania — Patcher sam
koduje wartość po QSettingsowemu (`\` → `\\`, cudzysłowy gdy trzeba), bo Prism czyta ten
plik przez `QSettings::IniFormat`, gdzie goły backslash otwiera sekwencję ucieczki.

---

## 4. `profiles` — pole opcjonalne

**Preset nie musi deklarować profili.** Preset dokładający same pliki — configi jednego
moda, KubeJS, resourcepack — nie ma czego profilować, a profile i tak są wspólne dla
całego planu: narzuca je ten preset, który je przynosi.

```json
{ "id": "standard", "label": "Standard", "description": "...",
  "default": true, "vars": { "renderDistance": 8, "xmx": 6144 } }
```

| Pole | Znaczenie |
|---|---|
| `id`, `label`, `description` | identyfikator i to, co widać w oknie |
| `default` | profil zaznaczony na starcie; dokładnie jeden — ale wymagany dopiero wtedy, gdy manifest deklaruje jakikolwiek profil |
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

### Preset bez profili

Nic nie znika i nic nie trzeba deklarować „na wszelki wypadek":

- pozycje liczą się z samych `vars` presetu — profil nie ma czego przesłonić,
- w selektorze profili taki preset nie ma głosu; użytkownik wybiera spośród profili
  przyniesionych przez **inne** presety, a ten dokłada swoje pozycje do każdego,
- `selected` (§6) wolno mu mimo to wskazywać **cudze** `id` profilu (np. `"server": false`) —
  nazwy profili są sprawdzane tylko wtedy, gdy manifest sam jakieś deklaruje.

Gdy profili nie przyniesie **żadne** źródło, okno pokazuje jeden profil wbudowany,
`standard`, **bez wartości optymalizacyjnych** — istnieje po to, żeby selektor miał co
pokazać, zanim cokolwiek zostanie pobrane. `renderDistance` i `MaxMemAlloc` są wtedy puste,
bo nie ma ich skąd wziąć; Patcher ich **nie zmyśla**.

---

## 5. `groups`

```json
{ "id": "optimizations", "label": "Optymalizacje", "description": "..." }
```

Kolejność tablicy = kolejność sekcji w oknie i w `--list`. Grupa bez pozycji się nie
pokazuje. Pozycja wskazująca nieistniejącą grupę = błąd walidacji.

---

## 5a. Mody — ich tu nie ma i nie ma być

**Preset nie wymienia modów.** Nie ma na nie miejsca w tym formacie i to jest celowe:
lista modów w manifeście znaczyłaby, że każdy nowy mod wymaga nowego wydania presetu.

Repozytoria z modami wymienia **rejestr Patchera** — `sources.json` w aplikacji, plus
`%LOCALAPPDATA%\TFG-Patcher\sources.json` użytkownika. Jedna lista, bez rodzajów:

```json
{ "repos": [ { "repo": "AtmatiAdi/TFG-Modern_atmatiadi_mods" } ] }
```

To samo repozytorium może wydawać mody **i** preset — Patcher sprawdza każde pod obie
konwencje. Starsze klucze `"mods"` i `"configs"` są nadal czytane (leżą w plikach
użytkownika i w starszych wydaniach), ale wpadają do tej samej listy: **rodzaj
repozytorium przestał cokolwiek znaczyć**.

Patcher przegląda wydania takiego repozytorium i **znajduje mody sam**: rozkłada tagi
wg konwencji `<mod>-<x.y.z>` (np. `mapatlas-0.4.0`), grupuje po nazwie moda i bierze
najwyższą wersję każdego. Autor moda wydaje jar i to wszystko — mod pojawia się w planie
jako osobna pozycja do zaznaczenia.

Preset odpowiada wyłącznie za **configi, profile, shaderpack i narzędzia**. Jedyny
wyjątek to `installRelease` (§8) — przypięcie konkretnego pliku z cudzego wydania, gdy
jakiś zasób musi iść razem z configiem.

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
| `undo` | nie | lista operacji opisująca stan **wyłączony** pozycji; szczegóły niżej |

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
inaczej niewidoczna) — ale **tylko w manifeście, który sam deklaruje profile**. Preset bez
profili (§4) wolno odwołać się do cudzych `id`, bo nie ma jak ich znać z wyprzedzeniem;
nazwa, której nikt nie przyniósł, po prostu nie zadziała.

To wpływa **wyłącznie na początkowy stan pola wyboru**. Pozycja nadal jest widoczna
w planie ze swoim stanem, użytkownik nadal może ją zaznaczyć ręcznie, i nadal nic się nie
dzieje bez kliknięcia. `selected` **nie jest** sposobem na ukrywanie pozycji.

### `undo` — stan wyłączony; profile mają się wzajemnie wycofywać

Samo `selected: false` znaczy tylko „nie zakładaj". To za mało, gdy profile są sobie
przeciwne: ktoś zastosował Standard (RAM Keeper założony), przełącza na High — i RAM
Keeper **zostaje**, bo High go jedynie nie zaznacza. Plan nie może być przyrostowy.

`undo` to lista operacji (ten sam słownik co `changes`, §8) opisująca, jak wygląda
instancja **bez** tej pozycji. Patcher liczy dla pozycji oba stany i pokazuje ten, który
użytkownik wybrał — pole wyboru ma trzy położenia: **✓ zastosuj** (`changes`),
**✕ wycofaj** (`undo`), **puste = nie ruszaj**.

```json
"selected": { "high": false },
"undo": [
  { "op": "setKey", "file": "@instance/instance.cfg", "style": "ini", "section": "General",
    "key": "PreLaunchCommand", "value": "", "addIfMissing": false },
  { "op": "setKey", "file": "@instance/instance.cfg", "style": "ini", "section": "General",
    "key": "OverrideCommands", "value": "false", "addIfMissing": false },
  { "op": "removePath", "target": "@tools/ram-keeper" }
]
```

Tryb domyślny pozycji w profilu:

| `selected` w profilu | `undo` | tryb startowy |
|---|---|---|
| `true` (domyślnie) | — | **✓ zastosuj**, gdy jest coś do zrobienia |
| `false` | jest | **✕ wycofaj**, gdy jest coś do wycofania |
| `false` | brak | **puste** — nie ruszaj (zachowanie sprzed `undo`) |

Preset bez `undo` działa jak dotąd, a Patcher starszy niż 3.2 ignoruje nieznane pole —
cudze manifesty niczego nie muszą zmieniać. `addIfMissing: false` w `undo` jest ważne:
wycofanie nie ma **dopisywać** kluczy, których pozycja nigdy nie założyła.

Wycofanie idzie przez dziennik tak samo, jak zastosowanie (usunięte pliki lądują w kopii
zapasowej), więc „Cofnij ostatnie" odwraca również je.

**Kolejność pozycji w `items` = kolejność wykonania.** Pozycja, która tworzy plik, musi
stać przed pozycją, która ten plik edytuje. (Patcher i tak sprawdza stan każdej operacji
ponownie tuż przed wykonaniem, ale to zabezpieczenie, nie zastępstwo kolejności.)

### Stany pozycji

`ok` (zrobione) · `todo` (do zmiany) · `missing` (brak celu — np. nie ma pliku configu) ·
`error` · `skipped` (nie ta strona). Pozycja z `undo` ma te stany **osobno dla każdej
strony**: patrząc od strony „wycofaj", `ok` znaczy „wycofane", `todo` — „do wycofania".
Preset **nie** wpływa na to, co Patcher zaznacza poza wyborem trybu startowego: do
wykonania idzie wyłącznie `todo` wybranej strony.

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

**Do repozytoriów, które nie trzymają konwencji tagów.** Repozytorium trzymające konwencję
dopisuje się do `repos` w `sources.json` (§5a) — wtedy nowy mod nie wymaga wydania presetu.

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

### `enableMods` — odwrotność `disableMods` (`.jar.disabled` → `.jar`)

```json
{ "op": "enableMods", "prefixes": ["xaerominimap", "xaeroworldmap"] }
```

Bez skanu — włączenie moda niczego nie pozbawia klas. Typowe miejsce: `undo` pozycji
z `disableMods`.

### `removePath` — usunięcie pliku albo katalogu

```json
{ "op": "removePath", "target": "@tools/ram-keeper" }
```

Odwrotność `installAsset`. Każdy usuwany plik trafia do kopii zapasowej z wpisem
w dzienniku, więc „Cofnij ostatnie" odtwarza całość. Katalog główny instancji, gry
i narzędzi nie są dozwolonym celem (błąd walidacji, a przy wykonaniu — odmowa).

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
grup, znane `op` i `style`, wszystkie `{zmienne}` rozwiązywalne, ścieżki bez wyjścia poza
instancję, `disableMods` z niepustym `scan.tokens`. Profile — **gdy manifest je deklaruje**:
unikalne `id`, poprawny `side`, dokładnie jeden `default` i sprawdzone nazwy w `selected`.
Manifest bez profili przechodzi walidację; brak grup to nadal błąd.

---

## 11. Zgodność wstecz

- Patcher **starszy** niż `minPatcher` presetu: pokazuje komunikat „zaktualizuj Patcher"
  i **nie** buduje planu z tego presetu. Pozostałe presety działają normalnie.
- Patcher **nowszy**: obsługuje `formatVersion` 1 tak długo, jak długo istnieje ta sekcja.
  Format 2 nie usunie formatu 1 — dodanie obsługi nowego nie może zabrać starego, bo
  ludzie mają w cache stare manifesty i grają offline.
- Zmiana znaczenia istniejącego `op` bez podbicia `formatVersion` jest **zabroniona**.
- `undo`, `removePath` i `enableMods` przyszły z Patcherem **3.2.0** bez podbicia formatu:
  starszy Patcher nie zna pola `undo` i go pomija (pozycja jest wtedy tylko odznaczona,
  jak dawniej), a `changes` bez nowych operacji czyta jak zawsze. Dopiero preset, który
  używa `removePath`/`enableMods` **w `changes`**, musi podnieść `minPatcher` do `3.2.0`.
