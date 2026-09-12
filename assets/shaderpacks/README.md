# Shaderpack

Tu leży pakiet shaderów, który jedzie z wydaniem presetu. Dwa pliki:

```
TFG_OPTIMISED_Complementary-3.1.5.zip       2,2 MB   <- pakiet
TFG_OPTIMISED_Complementary-3.1.5.zip.txt   600 B    <- ustawienia (profil "light")
```

Dopóki ich nie ma, `build/pack.ps1` **przerwie** z komunikatem:

```
BLAD   items (shaderpack): brak zalacznika pasujacego do
       "TFG_OPTIMISED_Complementary-3.1.5.zip" w ...\dist
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
- **Nazwa zaczyna się od `TFG_OPTIMISED_`**, żeby w liście shaderów w grze było od razu
  widać, że to nasz, przycięty pakiet, a nie czysty Complementary. Poprzednia nazwa
  (`TerraFirmaGreg-Shaders-Complementary-3.1.5.zip`) jest przez pozycję `shaderpack`
  usuwana z instancji (`removePath`), żeby nie zostały dwie kopie tego samego pakietu.
