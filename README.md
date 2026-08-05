# TerraFirmaGreg-Modern — presety

Stan optymalizacyjny naszej paczki: **configi, profile maszyn, flagi JVM, shaderpack
i programy wspierające**. Wszystko jako dane w `preset.json`, wydawane jako release
GitHuba i pobierane przez [TFG Patcher](https://github.com/AtmatiAdi/TFG-Modern_Patcher).

Patcher jest tylko silnikiem — **nie zna żadnej z tych wartości**. Zmiana optymalizacji
kończy się tutaj: `preset.json` → `pack.ps1 -Release`. Nikt nie przebudowuje `.exe`,
nikt nie rozsyła nowej binarki.

---

## Co tu leży

| Ścieżka | Co to |
|---|---|
| **`preset.json`** | **manifest** — źródło prawdy dla tego, co Patcher proponuje zrobić |
| `docs/OPTIMIZATIONS-SPEC.md` | **dlaczego** każda pozycja istnieje; pomiar albo uzasadnienie przy każdej |
| `docs/PRESET-FORMAT.md` | umowa z Patcherem: format manifestu, słownik operacji |
| `docs/RELEASING.md` | jak wydać preset i jak sprawdzić, że odbiorca go zobaczy |
| `docs/ram/FINDINGS.md` | pełny zapis śledztwa RAM (chronologiczny) |
| `docs/ram/HANDOFF.md` | brief: stan śledztwa, co obalone |
| `tools/ram-keeper/` | narzędzie zwalniające RAM w czasie gry |
| `assets/shaderpacks/` | shaderpack i jego ustawienia (załączniki wydania) |
| `build/validate.js` | walidacja manifestu — **uruchamiaj przed każdym wydaniem** |
| `build/pack.ps1` | złożenie załączników + `gh release create` |
| `CONTEXT.md` | **zacznij tutaj**, jeśli siadasz do tego pierwszy raz |

---

## Praca

```powershell
node build/validate.js               # sprawdzenie manifestu
pwsh -File build/pack.ps1            # zlozenie dist/ (bez wydawania)
pwsh -File build/pack.ps1 -Release   # wydanie na GitHuba
```

Zmiana wartości optymalizacji:

1. **Najpierw** dopisz uzasadnienie do `docs/OPTIMIZATIONS-SPEC.md` — pomiar albo jasny
   powód. Pozycja bez uzasadnienia to pozycja, której nikt za pół roku nie odważy się
   ruszyć ani usunąć.
2. Zmień `preset.json` (pole `doc` pozycji ma wskazywać tę sekcję).
3. Podbij `version` w manifeście.
4. `pwsh -File build/pack.ps1 -Release`.

Patcher zobaczy nowe wydanie przy najbliższym **Sprawdź źródła**.

---

## Co tu NIE trafia

- **Kod modów.** Mody żyją we własnych repozytoriach i wydają się własnym tempem; manifest
  odwołuje się do nich przez `installRelease` (repozytorium + maska załącznika). Tu wchodzi
  najwyżej mod, który nie ma sensownego innego domu.
- **Kod Patchera.** Osobne repozytorium, osobne tempo.
- **Ustawienia osobiste gracza** — `fullscreen`, `guiScale`, głośności, keybindy. Patcher
  dotyka dokładnie tych kluczy `options.txt`, które wymienia sekcja C spec-u, i niczego
  więcej. To jest granica, nie przeoczenie.
