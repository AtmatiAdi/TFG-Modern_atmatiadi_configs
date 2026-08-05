@echo off
rem ---------------------------------------------------------------------------
rem  TFG RAM Keeper - punkt wejscia dla PreLaunchCommand Prisma.
rem
rem  Prism URUCHAMIA TE KOMENDE I CZEKA na jej zakonczenie, zanim wystartuje gre.
rem  Dlatego ten plik nie robi nic poza odpaleniem wlasciwego skryptu w tle i musi
rem  wrocic natychmiast. Gdyby czekal, gra nie ruszylaby az do konca sesji grania.
rem
rem  Przekierowanie na nul jest istotne: potomek dziedziczy uchwyty strumieni,
rem  a Prism czyta wyjscie komendy - otwarty potok trzymalby go w miejscu mimo
rem  zakonczenia cmd.
rem
rem  Podnoszeniem uprawnien (UAC) zajmuje sie juz ram-keeper.ps1.
rem ---------------------------------------------------------------------------
setlocal

set "KEEPER=%~dp0ram-keeper.ps1"

rem Katalog gry: zmienna od Prisma, argument z wiersza polecen, w ostatecznosci CWD.
if "%INST_MC_DIR%"=="" set "INST_MC_DIR=%~1"
if "%INST_MC_DIR%"=="" set "INST_MC_DIR=%CD%"

start "" /b powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden ^
  -File "%KEEPER%" -GameDir "%INST_MC_DIR%" >nul 2>&1

exit /b 0
