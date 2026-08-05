# MIGRACJA: wydzielenie presetów z Patchera

**Stan: przygotowane, nie wykonane.** Patcher działa dalej po staremu — nic tu jeszcze
nie jest podłączone.

---

## O co chodzi

Dziś Patcher **jest** stanem optymalizacyjnym: lista zmian siedzi w `src/engine/patches.js`,
profile w `runner.js`, shaderpack w `assets/`. Zmiana jednej wartości `renderDistance`
wymaga przebudowy `.exe` i rozesłania go ludziom.

Po migracji:

```
                    ┌─────────────────────────────────────────┐
   repo PRESETÓW    │  preset.json + shaderpack + narzedzia    │  <- tu sie optymalizuje
   (nowe)           │  wydanie GitHuba: preset-3.0.0          │
                    └────────────────┬────────────────────────┘
                                     │
   repo MODÓW       ┌────────────────┴───────┐
   (istnieje)       │  jary jako zalaczniki  │  <- tu sie pisze mody
                    └────────────────┬───────┘
                                     │  pobiera, nie zna zawartosci
                    ┌────────────────▼────────────────────────┐
   repo PATCHERA    │  silnik: plan, wykonanie, cofanie       │  <- tu sie rozwija narzedzie
   (to)             │  zero wiedzy o TerraFirmaGreg           │
                    └─────────────────────────────────────────┘
```

Trzy niezależne tempa pracy. Nowy `renderDistance` = wydanie presetu, bez dotykania
`.exe`. Nowy mod = wydanie w repo moda. Poprawka w oknie = nowy `.exe`, bez ruszania
optymalizacji.

---

## Co tu leży

| Ścieżka | Co to |
|---|---|
| **`preset/docs/PRESET-FORMAT.md`** | **umowa między repozytoriami.** Format `preset.json` v1: pola, ścieżki, słownik operacji. Po migracji kopia trafia też do `docs/` Patchera — zmiana formatu to zmiana obu naraz |
| **`PATCHER-CHANGES.md`** | robota po stronie Patchera: co usunąć, co dopisać, w jakiej kolejności, gdzie leży granica zaufania. **Zostaje w tym repozytorium** |
| `preset/` | **zawartość nowego repozytorium** — kopiujesz to w całości, jest kompletna |
| `preset/preset.json` | cały dzisiejszy stan Patchera wyrażony jako dane: 12 pozycji, 27 operacji, 3 profile. Przechodzi walidację |
| `preset/tools/ram-keeper/` | narzędzie zwalniające RAM — **napisane i sprawdzone**, patrz niżej |
| **`reference/discover.js`** | **działający prototyp wykrywania modów po tagach wydań** — sprawdzony na żywym repozytorium; docelowo `engine/discover.js` w Patcherze |
| `preset/build/validate.js` | walidator manifestu (zero zależności); tę samą listę sprawdzeń Patcher powtarza po pobraniu |
| `preset/build/pack.ps1` | złożenie załączników wydania + `gh release create`. Sprawdzone od końca do końca |
| `preset/docs/` | dokumenty **przenoszone** z Patchera: `OPTIMIZATIONS-SPEC.md`, `ram/FINDINGS.md`, `ram/HANDOFF.md` |
| `preset/CONTEXT.md` | brief dla nowej sesji pracującej w repo presetów |

---

## Jak to przenieść

```powershell
# 1. Nowe repozytorium (nazwa robocza - jesli inna, popraw ja w registry.json Patchera)
gh repo create AtmatiAdi/TerraFirmaGreg-Modern_Presets --public --clone
cd TerraFirmaGreg-Modern_Presets

# 2. Zawartosc (komplet - manifest, doki, narzedzia, build)
Copy-Item -Recurse C:\Projects\TFG-Modern_Patcher\MIGRATION\preset\* .

# 3. Shaderpack - jedyna rzecz, ktorej NIE ma w MIGRATION (2,2 MB binarki nie musi
#    trafic drugi raz do historii gita tego repo)
Copy-Item C:\Projects\TFG-Modern_Patcher\assets\shaderpacks\* .\assets\shaderpacks\

# 4. Sprawdzenie i pierwsze wydanie
node build/validate.js
pwsh -File build/pack.ps1            # zbuduj dist/ i zwaliduj to, co pojdzie
pwsh -File build/pack.ps1 -Release   # wystaw preset-3.0.0

git add . ; git commit -m "Preset 3.0.0: stan wydzielony z Patchera" ; git push
```

Dopiero **potem** ruszaj Patchera — według `PATCHER-CHANGES.md`. Do tego czasu preset
sobie leży w wydaniu i nikomu nie przeszkadza, a Patcher działa po staremu.

Usunięcie plików z Patchera (`patches.js`, `assets/`, `sources.json`, przeniesione doki)
to **ostatni** krok, nie pierwszy — dopóki `compile.js` nie daje identycznego planu,
`patches.js` jest jedynym punktem odniesienia.

---

## Decyzje, które są już podjęte

Zapadły w sesji 2026-08-05 — jeśli któraś ma się zmienić, zmienia się też `PRESET-FORMAT.md`.

| Decyzja | Wybór | Dlaczego |
|---|---|---|
| Skąd Patcher zna źródła | **wbudowany `registry.json` + edycja w UI** | `.exe` zna „dom", ale nie jest do niego przywiązany; własna lista w `%LOCALAPPDATA%` |
| Skąd biorą się mody | **preset wymienia REPOZYTORIA, nie mody** — Patcher znajduje je po tagach `<mod>-<x.y.z>` | lista modów w manifeście znaczyłaby, że nowy mod wymaga nowego wydania presetu; to ta sama pułapka, z której wychodzimy (dawny `sources.json`) |
| Postać wydania presetu | **manifest + osobne załączniki** | manifest (11 KB) pobierany zawsze, shaderpack (2,2 MB) i narzędzia dopiero gdy zaznaczone |
| Start narzędzia RAM | **`PreLaunchCommand` Prisma** | zero zadań w systemie; kosztem okienka UAC przy każdym starcie gry |
| Zakres trimowania | **reszta systemu zawsze, gra pod presją** | trim gry to soft-faulty; robimy go, gdy wolny RAM < 1536 MB, czyli gdy i tak groziłoby stronicowanie |

---

## Narzędzie RAM — stan faktyczny

Twojego pierwotnego skryptu nie było gdzie szukać, więc jest napisany od nowa.
**Nie używa RAMMapa** (Sysinternals) ani żadnego zewnętrznego pliku — woła te same API
systemowe, z których RAMMap korzysta:

- `EmptyWorkingSet` (psapi) na procesach,
- `NtSetSystemInformation(SystemMemoryListInformation, MemoryPurgeStandbyList)` na liście
  standby — to jest ten fragment, który wymaga administratora.

Dzięki temu nie ma czego pobierać ani licencjonować, a narzędzie waży 8 KB.

### Co zostało sprawdzone (2026-08-05, maszyna testowa, bez admina)

| Co | Wynik |
|---|---|
| trim working setów | 182 procesy, wolny RAM 16 116 → 18 220 MB (**+2,1 GB**) w pierwszym cyklu |
| kolejne cykle | +499, +93, +59, +63 MB — raz oddanego working setu nie da się oddać drugi raz; pętla zbiera to, co narasta |
| lista standby bez admina | odmowa `0xC0000061` (`STATUS_PRIVILEGE_NOT_HELD`) — dokładnie dlatego skrypt prosi o uprawnienia |
| **`.cmd` (to, co uruchamia Prism)** | **wraca po 58 ms**, potomek żyje dalej z poprawnie przekazanym katalogiem gry — Prism nie zostanie zablokowany |
| **pełny cykl życia** | wykrycie właściwego procesu **po wierszu poleceń** (marker katalogu), cykle co zadany interwał, **zakończenie 2 s po zniknięciu gry** |
| mutex, log, rotacja, obsługa braku uprawnień | działa |

### Czego NIE dało się sprawdzić

1. **Udanego** czyszczenia listy standby — wymaga podniesionej sesji (UAC).
2. Wpięcia przez `PreLaunchCommand` na **żywej instancji Prisma**.

Zostało do zrobienia ręcznie, przy pierwszym uruchomieniu gry:

```powershell
cd MIGRATION\preset\tools\ram-keeper
.\ram-keeper.ps1 -Once -NoWaitForGame          # zgodzic sie na UAC
Get-Content "$env:LOCALAPPDATA\TFG-Patcher\ram-keeper.log" -Tail 3
```

W logu ma być `standby wyczyszczone`. Jeśli jest `NIEwyczyszczone (NTSTATUS 0xC0000061)` —
skrypt nie dostał uprawnień.

Szczegóły, parametry i ograniczenia: `preset/tools/ram-keeper/README.md`.

---

## Czego jeszcze nie ma

- **Sekcja H w `OPTIMIZATIONS-SPEC.md`** opisuje RAM Keepera, ale **bez pomiaru w grze**.
  Zasada tego dokumentu jest twarda: pozycja bez pomiaru nie ma tam czego szukać. Przy
  pierwszej sesji z grą trzeba zapisać commit przed/po — inaczej ta pozycja za pół roku
  będzie nie do obrony, jak każda inna bez liczb.
- **Nikt jeszcze nie sprawdził `PreLaunchCommand` na żywej instancji Prisma.** Mechanika
  `.cmd` jest przemyślana pod to, że Prism czeka na komendę i czyta jej wyjście (`start /b`
  + przekierowanie na `nul`), ale to trzeba zobaczyć w działaniu.
- **Patcher nie umie jeszcze nic z tego przeczytać.** Cała robota w `PATCHER-CHANGES.md`.
