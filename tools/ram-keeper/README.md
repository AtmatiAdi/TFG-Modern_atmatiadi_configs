# RAM Keeper

Wymusza na Windowsie oddawanie pamięci w czasie gry. Uruchamiany automatycznie przez
Prisma (`PreLaunchCommand`), kończy się razem z grą.

## Co dokładnie robi

Co 60 sekund, dopóki proces gry żyje:

1. **`EmptyWorkingSet` na każdym dostępnym procesie poza grą.** Strony trafiają na listę
   standby — system może je odzyskać natychmiast, a proces ściąga z powrotem tylko to,
   czego naprawdę używa (soft fault, bez ruchu na dysku, dopóki strona jest na liście).
2. **Czyszczenie listy standby** — `NtSetSystemInformation(SystemMemoryListInformation,
   MemoryPurgeStandbyList)`. To jest ten fragment, który wymaga administratora: chodzi na
   `SeProfileSingleProcessPrivilege`. Bez niego wywołanie zwraca `0xC0000061`
   (`STATUS_PRIVILEGE_NOT_HELD`) i skrypt mówi o tym w logu.
3. **Proces gry rusza tylko pod presją** — gdy wolny RAM spadnie poniżej `-ThresholdMB`
   (domyślnie 1536). Trim working setu gry powoduje soft-faulty, więc robimy to wtedy,
   gdy i tak groziłoby stronicowanie. `-TrimGameAlways` wyłącza ten warunek.

Zmierzone na maszynie testowej **bez uprawnień administratora**: 182 przetrimowane procesy,
+2,1 GB wolnego RAM-u w pierwszym cyklu. Z administratorem dochodzi lista standby i te
procesy, które bez uprawnień odmawiają otwarcia.

**Kolejne cykle dają dużo mniej** — w teście co 4 s: +499 MB, potem +93, +59, +63 MB.
To jest spodziewane: raz oddanego working setu nie da się oddać drugi raz. Sens tej pętli
polega na zbieraniu tego, co system **narastająco** zajmuje w czasie gry, a nie na
powtarzaniu pierwszego zysku.

## Skąd admin

Pyta o niego `ram-keeper.ps1` — sam się podnosi przez UAC. Przy układzie
z `PreLaunchCommand` okienko UAC pojawia się **przy każdym starcie gry**. Odmowa nie psuje
niczego: skrypt zapisuje to w logu i kończy się, gra startuje normalnie.

## Pliki

| Plik | Rola |
|---|---|
| `ram-keeper.cmd` | punkt wejścia dla Prisma; **musi wrócić natychmiast** — Prism czeka na zakończenie `PreLaunchCommand`, zanim wystartuje grę |
| `ram-keeper.ps1` | całość: podniesienie uprawnień, wykrycie gry, pętla |

`.cmd` odpala `.ps1` przez `start /b` z przekierowaniem na `nul`. Przekierowanie jest
istotne — potomek dziedziczy uchwyty strumieni, a Prism czyta wyjście komendy, więc
otwarty potok trzymałby go w miejscu mimo zakończenia `cmd`.

## Log

`%LOCALAPPDATA%\TFG-Patcher\ram-keeper.log` (rotacja przy 1 MB). Jedna linia na cykl:

```
2026-08-05 16:38:20  start: interwal 60 s, prog 1536 MB, RAM 32116 MB, katalog gry: ...
2026-08-05 16:38:22  gra wykryta: PID 24188 (javaw.exe)
2026-08-05 16:39:22  cykl: procesow 179, standby wyczyszczone, wolne 4210 -> 6350 MB (+2140)
2026-08-05 16:52:41  gra zakonczona - RAM Keeper konczy prace.
```

## Parametry

| Parametr | Domyślnie | Do czego |
|---|---|---|
| `-GameDir` | `$env:INST_MC_DIR` | rozpoznanie **właściwego** procesu javy po wierszu poleceń, gdy chodzi ich kilka |
| `-IntervalSeconds` | 60 | odstęp między cyklami |
| `-ThresholdMB` | 1536 | poniżej tylu MB wolnego RAM-u trimowana jest też gra |
| `-WaitSeconds` | 300 | ile czekać na start gry (skrypt rusza **przed** nią) |
| `-GameProcess` | `javaw, java` | nazwy procesów uznawanych za grę |
| `-TrimGameAlways` | — | trimuj grę w każdym cyklu, nie tylko pod presją |
| `-NoStandbyPurge` | — | sam trim, bez ruszania listy standby |
| `-Once` | — | jeden cykl i koniec (do sprawdzenia działania) |
| `-NoWaitForGame` | — | nie czekaj na grę, pracuj od razu |
| `-NoElevate` | — | nie podnoś uprawnień; brak admina = koniec z komunikatem |

## Sprawdzenie ręczne

```powershell
# jeden cykl, bez czekania na gre - pokaze UAC, potem wpis w logu
.\ram-keeper.ps1 -Once -NoWaitForGame
Get-Content "$env:LOCALAPPDATA\TFG-Patcher\ram-keeper.log" -Tail 5

# pelny cykl zycia: odpal to, potem uruchom gre
.\ram-keeper.cmd "C:\...\instances\TerraFirmaGreg-Modern\minecraft"
```

W logu ma się pojawić `standby wyczyszczone`. Jeśli widnieje `NIEwyczyszczone
(NTSTATUS 0xC0000061)` — skrypt chodzi bez uprawnień administratora.

## Ograniczenia, o których trzeba wiedzieć

- **Tylko Windows.** Na serwerach linuksowych ta pozycja nie ma odpowiednika i się nie
  pokazuje (`side: client`).
- **Tylko instancje Prisma** — mechanizm wpina się przez `instance.cfg`. W katalogu gry
  bez Prisma pozycja pokaże „brak celu".
- **To nie jest zysk z niczego.** Trim nie zmniejsza zapotrzebowania gry na pamięć;
  przesuwa strony tak, żeby system miał co oddać, zamiast sięgać po plik stronicowania.
  Właściwe oszczędności robią flagi JVM i configi (`OPTIMIZATIONS-SPEC.md` sekcje A–D) —
  to jest dokładka, nie zamiennik.
- **Nie łączyć z `-TrimGameAlways` „na wszelki wypadek".** Agresywny trim procesu gry
  co minutę to mikroprzycięcia w zamian za pamięć, której nikt nie potrzebuje.
