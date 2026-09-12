# Jak wydawać, żeby Patcher to zobaczył

Patcher nie zna żadnej wartości „na sztywno". Pyta GitHuba o najnowsze wydanie
zawierające załącznik pasujący do maski, pobiera go i buduje z niego plan. Dotyczy to
zarówno **presetu** (ten plik = `preset-*.json`), jak i **modów** (jary z cudzych repo).

---

## 1. Wydanie presetu

```powershell
# 1. Zmien preset.json (i NAJPIERW docs/OPTIMIZATIONS-SPEC.md), podbij "version"
# 2. Zloz i sprawdz - pack.ps1 waliduje TO, CO POJDZIE do wydania, i przerywa przy bledzie
pwsh -File build/pack.ps1

# 3. Wydaj
pwsh -File build/pack.ps1 -Release
```

Powstaje wydanie z tagiem `preset-<wersja>` i załącznikami:

```
preset-3.0.0.json                                     11 KB   <- Patcher pobiera zawsze
ram-keeper-3.0.0.zip                                   8 KB   <- gdy zaznaczysz narzedzie
TFG_OPTIMISED_Complementary-3.1.5.zip      2190 KB   <- gdy zaznaczysz shadery
TFG_OPTIMISED_Complementary-3.1.5.zip.txt     1 KB
```

**Manifest i jego załączniki muszą być w tym samym wydaniu** — `installAsset` szuka
załącznika obok manifestu, po masce.

### Czego pilnować

- **Podbij `version`.** Bez tego odbiorca nie odróżni wydań, a cache Patchera będzie
  trzymał starą zawartość pod tym samym tagiem.
- **Nie zmieniaj `id` istniejącej pozycji.** Ludzie mają je w dziennikach cofania.
- **Drafty i prereleasy są pomijane** — draft to wygodny sposób, żeby przygotować wydanie,
  zanim trafi do ludzi.
- **`minPatcher` podbijaj tylko wtedy, gdy preset naprawdę potrzebuje nowego Patchera.**
  Zbyt wysoka wartość odcina ludziom preset komunikatem „zaktualizuj Patcher".

### Dogranie pliku do istniejącego wydania

```powershell
gh release upload preset-3.0.0 dist\ram-keeper-3.0.0.zip --clobber
```

---

## 2. Wydanie moda (repozytorium z modami)

Mody nie leżą w tym repozytorium i **nie są tu wymieniane** — ta sekcja jest tu tylko po
to, żeby konwencja tagów była zapisana w jednym miejscu razem z resztą umowy.

Repozytorium z modami wymienia rejestr Patchera — `sources.json` w aplikacji plus plik
użytkownika `%LOCALAPPDATA%\TFG-Patcher\sources.json`. Patcher przegląda jego wydania
i znajduje mody sam:

```json
{ "repos": [ { "repo": "AtmatiAdi/TFG-Modern_atmatiadi_mods" } ] }
```

**Jedna lista, repozytorium nie ma rodzaju**: każde jest sprawdzane pod obie konwencje, więc
to samo repo może wydawać i mody, i preset. (Starsze klucze `"mods"` / `"configs"` są nadal
czytane, ale wpadają do tej samej listy.)

**Wydanie nowego moda nie wymaga niczego poza wydaniem.** Żadnej zmiany w tym
repozytorium, żadnego nowego presetu, żadnego nowego `.exe` — mod pojawi się w planie
u wszystkich jako osobna pozycja do zaznaczenia.

### Umowa: tag wydania

```
<mod>-<x.y.z>          mapatlas-0.4.0        map-atlas-v1.2.3        ferrite-tweaks-1.2
```

To jedyne, na co trzeba uważać. Patcher grupuje wydania po nazwie moda i bierze
**najwyższą wersję** każdego — porównywaną liczbowo, więc `0.10.0` jest nowsze niż
`0.9.0`. Tag bez wersji na końcu (`v1.0`, `mapatlas`, `mapatlas-0.4.0-beta`) zostanie
pominięty z wpisem w logu; wydanie bez załącznika `.jar` też.

Starsze wersje w `mods/` kasują się same — maska `<mod>-*.jar` bierze się z nazwy moda,
więc nie da się jej zapomnieć.

```powershell
# 1. zbuduj jar (JDK 17 z Prisma)
cd <repo-gry>\mapatlas
./gradlew build

# 2. wystaw wydanie; tag = wersja moda z gradle.properties
cd <repo-gry>
gh release create mapatlas-0.4.0 `
  mapatlas\build\libs\mapatlas-0.4.0.jar `
  --title "Map Atlas 0.4.0" `
  --notes "Co sie zmienilo."
```

- **Jedno wydanie = jeden mod w jednej wersji.** Nie trzeba dopinać jarów pozostałych
  modów do każdego wydania ani rozbijać modów na osobne repozytoria:

  ```
  wydanie mapatlas-0.4.0  ->  mapatlas-0.4.0.jar
  wydanie innymod-1.2     ->  innymod-1.2.jar      <- to jest "latest" w repo
  wydanie mapatlas-0.5.0  ->  mapatlas-0.5.0.jar
  ```

  Patcher zobaczy dwa mody: `mapatlas 0.5.0` i `innymod 1.2`.
- **Jar musi być załącznikiem**, nie plikiem w repo — archiwa źródeł, które GitHub dokleja
  sam, Patcherowi nie wystarczą.
- **Pierwsza linia notatek wydania** trafia do planu jako opis moda. Warto ją napisać.
- **Wersje robocze wydawaj jako _prerelease_** — są pomijane, chyba że źródło ma
  `"prerelease": true`.

### Dołożenie moda współpracownika

Jego repozytorium dopisujesz **raz** do `repos` w `sources.json` — od tego momentu wszystkie
jego mody, także te wydane później, pojawiają się same. Jeśli nie trzyma konwencji tagów,
zostaje `installRelease` z maską (`PRESET-FORMAT.md` §8), ale wtedy każdy jego nowy mod znów
wymaga wydania presetu — więc lepiej się umówić na tagi.

Sam sobie każdy dopisze repozytorium bez czekania na nowy `.exe`: plik użytkownika
`%LOCALAPPDATA%\TFG-Patcher\sources.json` dokłada się do wbudowanego.

---

## 3. Repozytorium z wydaniami musi być PUBLICZNE

To najważniejsza pułapka całego mechanizmu: **na repo prywatne GitHub odpowiada `404`,
nie `403`** — celowo, żeby nie zdradzić, że coś takiego istnieje. Patcher u odbiorcy
chodzi anonimowo, więc dla niego prywatne repo z wydaniami po prostu nie istnieje, choć
Ty widzisz je w przeglądarce bez problemu.

Rozsądny układ, gdy repo z grą ma zostać prywatne:

| Repo | Widoczność | Co w nim |
|---|---|---|
| repo z grą | prywatne | instancja, źródła modów, surowe pomiary |
| **repo presetów (to)** | **publiczne** | manifest, shaderpack, narzędzia |
| repo z wydaniami modów | **publiczne** | tylko wydania (jary jako załączniki) — może być zupełnie puste |
| repo Patchera | publiczne albo prywatne | zależy, czy `.exe` rozdajesz z GitHuba |

Publiczne repo na wydania może nie mieć **żadnego kodu** — wystarczy, że istnieje.

Sprawdzenie w 5 sekund, czy wydanie jest widoczne dla Patchera — otwórz w przeglądarce
**wylogowany** (okno prywatne):
`https://github.com/<wlasciciel>/<repo>/releases/latest`

### Zmiana nazwy repozytorium

Jest bezpieczna: GitHub przekierowuje stare adresy, także w API, a klient Patchera podąża
za przekierowaniami. Wydania u ludzi, którzy mają starą nazwę w cache, nie przestaną
działać z dnia na dzień.

Mimo to **popraw nazwę w `sources.json`** — przekierowanie znika, gdy ktoś założy nowe
repozytorium o starej nazwie, a poza tym wpis ma mówić prawdę. Uwaga: od 3.1.0 lista
repozytoriów **nie leży już w manifeście**, tylko po stronie Patchera, więc poprawka
w liście wbudowanej to jedna linia **w repozytorium Patchera** i nowy `.exe`. Kto nie chce
czekać, dopisuje repo u siebie — plik użytkownika dokłada się do wbudowanego.

Nazwa z użytkownikiem w środku (`TFG-Modern_atmatiadi`) jest **sensowną konwencją** przy
wielu współpracownikach: od razu widać, czyje mody są w którym repozytorium, a `sources.json`
i tak wymienia je z pełną nazwą `wlasciciel/repo`.

---

## 4. Limity i token

Anonimowo GitHub daje 60 zapytań na godzinę na adres IP i nie wpuszcza do repo prywatnych.
Token rozwiązuje jedno i drugie:

```powershell
$env:TFG_GITHUB_TOKEN = "ghp_..."     # tylko na te sesje
```

albo na stałe — `%LOCALAPPDATA%\TFG-Patcher\token.txt`. Token jest **opcjonalny**: bez
niego wszystko publiczne działa normalnie. Nie licz na token u odbiorców — token daje
dostęp do całego konta, więc nie rozdaje się go znajomym.

---

## 5. Gdzie lądują pobrane pliki

`%LOCALAPPDATA%\TFG-Patcher\cache\<wlasciciel>__<repo>\<tag>\<plik>`

- pobranie zdarza się **raz na wersję** — plik o zgodnym rozmiarze nie jest ściągany ponownie,
- Patcher pamięta ostatni poprawny manifest, więc pokazuje sensowny plan także **bez
  internetu**,
- gdy GitHub nie odpowiada, źródło zostaje przy wersji z cache i mówi o tym w logu;
  reszta planu działa normalnie,
- kasowanie tego katalogu jest bezpieczne — najwyżej wszystko pobierze się jeszcze raz.

---

## 6. Test bez wydawania czegokolwiek

```powershell
# sam manifest, bez sieci i bez wydania
node build/validate.js preset.json

# pelna sciezka na podstawionym zrodle
$env:TFG_CACHE_DIR = "C:\tmp\cache"
node <patcher>\src\cli.js --list
node <patcher>\src\cli.js -i <atrapa-instancji>
node <patcher>\src\cli.js -i <atrapa-instancji> --apply
node <patcher>\src\cli.js -i <atrapa-instancji> --revert
```

Atrapa instancji: katalog z `instance.cfg`, `mmc-pack.json`, `minecraft/mods` (kilka
pustych plików o właściwych nazwach), `minecraft/config`, `minecraft/options.txt`.
Pełny cykl to plan → apply → **ponowny plan (wszystko „ZROBIONE")** → revert (stan wraca).
Ten drugi plan jest testem idempotencji i wyłapuje więcej błędów niż sam apply.
