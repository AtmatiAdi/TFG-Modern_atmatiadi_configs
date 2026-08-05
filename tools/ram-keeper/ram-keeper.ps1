<#
.SYNOPSIS
  TFG RAM Keeper - cyklicznie zmusza Windowsa do oddania pamieci w czasie gry.

.DESCRIPTION
  Co IntervalSeconds sekund, dopoki proces gry zyje:
    1. EmptyWorkingSet na kazdym dostepnym procesie POZA gra - strony trafiaja na
       liste standby, skad system moze je natychmiast odzyskac,
    2. czyszczenie listy standby (NtSetSystemInformation / MemoryPurgeStandbyList),
    3. proces gry ruszany DOPIERO gdy wolny RAM spadnie ponizej ThresholdMB - trim
       working setu gry powoduje soft-faulty, wiec robimy to tylko wtedy, gdy i tak
       grozi stronicowanie (albo gdy podano -TrimGameAlways).

  Skrypt wymaga uprawnien administratora (czyszczenie listy standby chodzi na
  SeProfileSingleProcessPrivilege) i podnosi je sam - przy starcie pokaze sie UAC.

  Uruchamiany jest przez ram-keeper.cmd z PreLaunchCommand Prisma, wiec startuje
  ZANIM gra ruszy: najpierw czeka na pojawienie sie procesu, potem pracuje, a gdy
  gra znika - konczy sie sam.

.EXAMPLE
  .\ram-keeper.ps1 -GameDir "C:\...\instances\TFG\minecraft"
.EXAMPLE
  .\ram-keeper.ps1 -Once -NoWaitForGame        # jeden cykl, do sprawdzenia dzialania
#>

[CmdletBinding()]
param(
  # Katalog gry - sluzy do rozpoznania WLASCIWEGO procesu javy, gdy chodzi ich kilka.
  [string] $GameDir = $env:INST_MC_DIR,

  [int]    $IntervalSeconds = 60,

  # Ponizej tylu MB wolnego RAM trimujemy takze sam proces gry.
  [int]    $ThresholdMB = 1536,

  # Ile czekac na pojawienie sie procesu gry (PreLaunchCommand idzie przed startem).
  [int]    $WaitSeconds = 300,

  [string[]] $GameProcess = @('javaw', 'java'),

  [switch] $TrimGameAlways,
  [switch] $NoStandbyPurge,
  [switch] $NoWaitForGame,
  [switch] $Once,
  [switch] $NoElevate,

  [string] $LogPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

# --------------------------------------------------------------------------- log

if (-not $LogPath) {
  $base = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'TFG-Patcher' } else { $PSScriptRoot }
  $LogPath = Join-Path $base 'ram-keeper.log'
}

function Write-Log {
  param([string] $Message)
  $line = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
  Write-Verbose $line
  try {
    $dir = Split-Path -Parent $LogPath
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
      New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    # Prosta rotacja: log ma nie rosnac w nieskonczonosc na cudzej maszynie.
    if ((Test-Path -LiteralPath $LogPath) -and (Get-Item -LiteralPath $LogPath).Length -gt 1MB) {
      Move-Item -LiteralPath $LogPath -Destination ($LogPath + '.old') -Force
    }
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
  } catch {
    # Log jest wygoda, nie warunkiem dzialania.
  }
}

# ------------------------------------------------------------------- podniesienie

function Test-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($id)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
  if ($NoElevate) {
    Write-Log 'Brak uprawnien administratora, a podnoszenie wylaczone (-NoElevate) - koncze.'
    exit 1
  }
  # Sciezki podajemy w cudzyslowach, bo Start-Process skleja ArgumentList spacjami
  # i sam niczego nie cytuje - katalog ze spacja rozjechalby argumenty.
  $q = { param($s) '"{0}"' -f $s }
  $childArgs = @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
    '-File', (& $q $PSCommandPath),
    '-IntervalSeconds', $IntervalSeconds,
    '-ThresholdMB', $ThresholdMB,
    '-WaitSeconds', $WaitSeconds,
    '-LogPath', (& $q $LogPath)
  )
  if ($GameDir)        { $childArgs += @('-GameDir', (& $q $GameDir)) }
  if ($TrimGameAlways) { $childArgs += '-TrimGameAlways' }
  if ($NoStandbyPurge) { $childArgs += '-NoStandbyPurge' }
  if ($NoWaitForGame)  { $childArgs += '-NoWaitForGame' }
  if ($Once)           { $childArgs += '-Once' }

  Write-Log 'Podnoszenie uprawnien (UAC)...'
  try {
    Start-Process -FilePath (Get-Process -Id $PID).Path -Verb RunAs `
                  -WindowStyle Hidden -ArgumentList $childArgs | Out-Null
  } catch {
    # 1223 = uzytkownik odmowil w oknie UAC. To jego decyzja, nie awaria.
    Write-Log ('Nie podniesiono uprawnien: ' + $_.Exception.Message)
    exit 1
  }
  exit 0
}

# ------------------------------------------------------------------- API systemu

if (-not ('TfgRam' -as [type])) {
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class TfgRam
{
    [StructLayout(LayoutKind.Sequential)]
    private struct MEMORYSTATUSEX
    {
        public uint dwLength;
        public uint dwMemoryLoad;
        public ulong ullTotalPhys;
        public ulong ullAvailPhys;
        public ulong ullTotalPageFile;
        public ulong ullAvailPageFile;
        public ulong ullTotalVirtual;
        public ulong ullAvailVirtual;
        public ulong ullAvailExtendedVirtual;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct LUID { public uint LowPart; public int HighPart; }

    [StructLayout(LayoutKind.Sequential)]
    private struct TOKEN_PRIVILEGES
    {
        public int PrivilegeCount;
        public LUID Luid;
        public int Attributes;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX buffer);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr OpenProcess(int access, bool inherit, int pid);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr handle);
    [DllImport("kernel32.dll")]
    private static extern IntPtr GetCurrentProcess();
    [DllImport("psapi.dll", SetLastError = true)]
    private static extern bool EmptyWorkingSet(IntPtr handle);
    [DllImport("ntdll.dll")]
    private static extern int NtSetSystemInformation(int infoClass, IntPtr info, int length);
    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool OpenProcessToken(IntPtr process, int access, out IntPtr token);
    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool LookupPrivilegeValue(string system, string name, out LUID luid);
    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool AdjustTokenPrivileges(IntPtr token, bool disableAll,
        ref TOKEN_PRIVILEGES newState, int length, IntPtr previous, IntPtr returned);

    private const int PROCESS_QUERY_INFORMATION = 0x0400;
    private const int PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;
    private const int PROCESS_SET_QUOTA = 0x0100;

    private const int TOKEN_ADJUST_PRIVILEGES = 0x0020;
    private const int TOKEN_QUERY = 0x0008;
    private const int SE_PRIVILEGE_ENABLED = 0x0002;

    // SYSTEM_INFORMATION_CLASS.SystemMemoryListInformation
    private const int SystemMemoryListInformation = 80;
    private const int MemoryPurgeStandbyList = 4;
    private const int MemoryPurgeLowPriorityStandbyList = 5;

    /// <summary>Wolna pamiec fizyczna w MB.</summary>
    public static ulong AvailableMB()
    {
        MEMORYSTATUSEX s = new MEMORYSTATUSEX();
        s.dwLength = (uint)Marshal.SizeOf(typeof(MEMORYSTATUSEX));
        if (!GlobalMemoryStatusEx(ref s)) return 0;
        return s.ullAvailPhys / (1024 * 1024);
    }

    /// <summary>Calkowita pamiec fizyczna w MB.</summary>
    public static ulong TotalMB()
    {
        MEMORYSTATUSEX s = new MEMORYSTATUSEX();
        s.dwLength = (uint)Marshal.SizeOf(typeof(MEMORYSTATUSEX));
        if (!GlobalMemoryStatusEx(ref s)) return 0;
        return s.ullTotalPhys / (1024 * 1024);
    }

    /// <summary>
    /// Oddaje working set procesu. Strony ida na liste standby - system moze je
    /// odzyskac natychmiast, a proces sciagnie z powrotem tylko te, ktorych faktycznie
    /// uzywa (soft fault, bez ruchu na dysku, dopoki strona jest na liscie).
    /// </summary>
    public static bool Trim(int pid)
    {
        IntPtr h = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_SET_QUOTA, false, pid);
        if (h == IntPtr.Zero)
        {
            // Procesy chronione i te z innego poziomu integralnosci - probujemy wezszym prawem.
            h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_SET_QUOTA, false, pid);
        }
        if (h == IntPtr.Zero) return false;
        bool done = EmptyWorkingSet(h);
        CloseHandle(h);
        return done;
    }

    /// <summary>Wlacza przywilej biezacego procesu (potrzebne do listy standby).</summary>
    public static bool EnablePrivilege(string name)
    {
        IntPtr token;
        if (!OpenProcessToken(GetCurrentProcess(), TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, out token))
            return false;
        try
        {
            LUID luid;
            if (!LookupPrivilegeValue(null, name, out luid)) return false;
            TOKEN_PRIVILEGES tp = new TOKEN_PRIVILEGES();
            tp.PrivilegeCount = 1;
            tp.Luid = luid;
            tp.Attributes = SE_PRIVILEGE_ENABLED;
            if (!AdjustTokenPrivileges(token, false, ref tp, Marshal.SizeOf(tp), IntPtr.Zero, IntPtr.Zero))
                return false;
            // AdjustTokenPrivileges zwraca sukces takze przy CZESCIOWYM powodzeniu.
            return Marshal.GetLastWin32Error() == 0;
        }
        finally
        {
            CloseHandle(token);
        }
    }

    /// <summary>Czysci liste standby. 0 = OK (NTSTATUS).</summary>
    public static int PurgeStandbyList(bool lowPriorityOnly)
    {
        int command = lowPriorityOnly ? MemoryPurgeLowPriorityStandbyList : MemoryPurgeStandbyList;
        IntPtr buffer = Marshal.AllocHGlobal(sizeof(int));
        try
        {
            Marshal.WriteInt32(buffer, command);
            return NtSetSystemInformation(SystemMemoryListInformation, buffer, sizeof(int));
        }
        finally
        {
            Marshal.FreeHGlobal(buffer);
        }
    }
}
'@
}

# ------------------------------------------------------------- jedna instancja

$created = $false
$mutex = New-Object System.Threading.Mutex($true, 'Global\TFG-RamKeeper', [ref] $created)
if (-not $created) {
  Write-Log 'RAM Keeper juz dziala - ten proces sie konczy.'
  exit 0
}

# ------------------------------------------------------------------ szukanie gry

function Find-GameProcess {
  $filter = ($GameProcess | ForEach-Object { "Name='$_.exe'" }) -join ' OR '
  $procs = @(Get-CimInstance Win32_Process -Filter $filter -ErrorAction SilentlyContinue)
  if (-not $procs) { return $null }

  # Wlasciwa instancja: ta, ktorej wiersz polecen wskazuje na nasz katalog gry.
  if ($GameDir) {
    $needle = $GameDir.TrimEnd('\', '/')
    $hit = $procs | Where-Object { $_.CommandLine -and $_.CommandLine -like ('*' + $needle + '*') } |
           Select-Object -First 1
    if ($hit) { return $hit }
  }
  # Bez trafienia: najgrubszy proces javy to prawie na pewno gra.
  return $procs | Sort-Object -Property WorkingSetSize -Descending | Select-Object -First 1
}

function Test-Alive {
  param([int] $ProcessId)
  return [bool] (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)
}

# ----------------------------------------------------------------------- cykl

function Invoke-Cycle {
  param([int] $GamePid)

  $before = [TfgRam]::AvailableMB()
  $trimGame = $TrimGameAlways.IsPresent -or ($before -lt $ThresholdMB)

  $trimmed = 0
  foreach ($p in (Get-Process -ErrorAction SilentlyContinue)) {
    if ($p.Id -le 4)   { continue }   # Idle i System - nie maja working setu do oddania
    if ($p.Id -eq $PID) { continue }
    if ($p.Id -eq $GamePid -and -not $trimGame) { continue }
    if ([TfgRam]::Trim($p.Id)) { $trimmed++ }
  }

  $purge = ''
  if (-not $NoStandbyPurge) {
    $status = [TfgRam]::PurgeStandbyList($false)
    $purge = if ($status -eq 0) { ', standby wyczyszczone' }
             else { ', standby NIEwyczyszczone (NTSTATUS 0x{0:X8})' -f $status }
  }

  $after = [TfgRam]::AvailableMB()
  Write-Log ('cykl: procesow {0}{1}{2}, wolne {3} -> {4} MB (+{5})' -f `
    $trimmed,
    $(if ($trimGame) { ' [z gra]' } else { '' }),
    $purge,
    $before, $after, ($after - $before))
}

# ------------------------------------------------------------------------ praca

try {
  Write-Log ('start: interwal {0} s, prog {1} MB, RAM {2} MB, katalog gry: {3}' -f `
    $IntervalSeconds, $ThresholdMB, [TfgRam]::TotalMB(), $(if ($GameDir) { $GameDir } else { '(nie podano)' }))

  if (-not [TfgRam]::EnablePrivilege('SeProfileSingleProcessPrivilege')) {
    Write-Log 'UWAGA: brak SeProfileSingleProcessPrivilege - lista standby nie bedzie czyszczona.'
  }
  [void] [TfgRam]::EnablePrivilege('SeDebugPrivilege')   # dostep do procesow innych sesji

  $game = $null
  if (-not $NoWaitForGame) {
    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    while (-not $game -and (Get-Date) -lt $deadline) {
      $game = Find-GameProcess
      if (-not $game) { Start-Sleep -Seconds 2 }
    }
    if (-not $game) {
      Write-Log ('Gra nie wystartowala w ciagu {0} s - koncze.' -f $WaitSeconds)
      exit 0
    }
    Write-Log ('gra wykryta: PID {0} ({1})' -f $game.ProcessId, $game.Name)
  }

  $gamePid = if ($game) { [int] $game.ProcessId } else { -1 }

  do {
    Invoke-Cycle -GamePid $gamePid
    if ($Once) { break }

    # Spimy w kawalkach, zeby zauwazyc koniec gry szybciej niz po pelnym interwale.
    for ($slept = 0; $slept -lt $IntervalSeconds; $slept += 2) {
      Start-Sleep -Seconds 2
      if ($gamePid -gt 0 -and -not (Test-Alive -ProcessId $gamePid)) { break }
    }
  } while ($gamePid -lt 0 -or (Test-Alive -ProcessId $gamePid))

  Write-Log $(if ($gamePid -gt 0) { 'gra zakonczona - RAM Keeper konczy prace.' }
              else { 'koniec pracy (tryb bez sledzenia procesu gry).' })
} catch {
  Write-Log ('BLAD: ' + $_.Exception.Message)
  exit 2
} finally {
  if ($mutex) {
    try { $mutex.ReleaseMutex() } catch { }
    $mutex.Dispose()
  }
}
