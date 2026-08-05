# Shaderpack

Ten katalog jest **pusty celowo**. Pakiet waży 2,2 MB i leży już w repozytorium Patchera —
nie ma powodu, żeby ta sama binarka trafiła drugi raz do historii gita.

Przy zakładaniu tego repozytorium skopiuj go tutaj:

```powershell
Copy-Item C:\Projects\TFG-Modern_Patcher\assets\shaderpacks\* .
```

Mają się pojawić dwa pliki:

```
TerraFirmaGreg-Shaders-Complementary-3.1.5.zip       2,2 MB   <- pakiet
TerraFirmaGreg-Shaders-Complementary-3.1.5.zip.txt   600 B    <- ustawienia (profil "light")
```

Dopóki ich nie ma, `build/pack.ps1` **przerwie** z komunikatem:

```
BLAD   items (shaderpack): brak zalacznika pasujacego do
       "TerraFirmaGreg-Shaders-Complementary-3.1.5.zip" w ...\dist
```

To jest zamierzone — lepiej nie wydać nic, niż wydać preset obiecujący plik, którego
w wydaniu nie będzie.

---

## Uwagi

- **Nazwa pakietu siedzi w `preset.json` w `vars.shaderpack`** i jest podstawiana wszędzie
  (`{shaderpack}`). Podmiana pakietu na nowszą wersję = nowy plik tutaj + jedna zmiana
  w tej zmiennej.
- **Nie podmieniać pakietu na czysty Complementary.** TFG-Complementary jest samodzielny
  i zgodny z custom blokami TFG (`block.properties`, 2,4 MB); czysty Complementary psuje
  custom bloki.
- **Plik `.zip.txt` już niesie wartości profilu „light"** (`COLORED_LIGHTING=32`,
  `shadowDistance=48.0`, `ANISOTROPIC_FILTER=0`). Pozycja `shaders-light` w manifeście jest
  strażnikiem dla instancji, w których pakiet siedzi po swojemu — nie dubluje tej roboty.
- Oba pliki wgrywane są **tylko gdy ich nie ma** (`onlyIfMissing`) — nie nadpisujemy
  cudzych ustawień shaderów.
