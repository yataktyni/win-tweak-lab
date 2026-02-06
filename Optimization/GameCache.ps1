# [Win-Tweak-Lab: GPU CACHE MANAGER v1.2.2]
# Quick Run: powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $s=irm 'https://raw.githubusercontent.com/yataktyni/win-tweak-lab/main/Optimization/GameCache.ps1'; iex ([System.Text.Encoding]::UTF8.GetString([System.Text.Encoding]::Default.GetBytes($s)))"

# 0. Глобальні параметри
$AppInfo = "Win-Tweak-Lab: GPU CACHE MANAGER v1.2.2"
if ($MyInvocation.MyCommand.Path) {
    try {
        $FirstLine = Get-Content $MyInvocation.MyCommand.Path -TotalCount 1 -Encoding UTF8 -ErrorAction SilentlyContinue
        if ($FirstLine -match '\[(.*)\]') { $AppInfo = $Matches[1] }
    } catch {}
}
$FullTitle = "       $AppInfo        "

# 1. Налаштування кодування та розумна перевірка адмін-прав
try {
    # Спроба налаштувати консоль (ігноруємо помилку, якщо handle invalid)
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

# Ці змінні працюють навіть без вікна консолі (ISE, VS Code тощо)
$OutputEncoding = [System.Text.Encoding]::UTF8
$InputEncoding = [System.Text.Encoding]::UTF8
$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'

if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $CurrentScript = $MyInvocation.MyCommand.Path
    $Utf8Fix = "[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; `$OutputEncoding = [System.Text.Encoding]::UTF8;"
    
    if (!$CurrentScript) {
        $Command = "$Utf8Fix irm https://raw.githubusercontent.com/yataktyni/win-tweak-lab/main/Optimization/GameCache.ps1 | iex"
    } else {
        $Command = "$Utf8Fix & '$CurrentScript'"
    }
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command $Command" -Verb RunAs
    exit
}

# 2. Вибір локалізації
Clear-Host
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host $FullTitle -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host " Select Language / Оберіть мову:" -ForegroundColor Yellow
Write-Host " [1] English"
Write-Host " [2] Українська"
Write-Host " [Enter] Auto (System Default)" -ForegroundColor Gray

$LangChar = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown").Character
if ($LangChar -eq '1') { $IsUKR = $false }
elseif ($LangChar -eq '2') { $IsUKR = $true }
else { $IsUKR = ([System.Globalization.CultureInfo]::CurrentUICulture.Name -eq "uk-UA") }

$Text = @{
    OptInstall     = if ($IsUKR) { "1. ВСТАНОВЛЕННЯ (Link)" } else { "1. INSTALL (Link)" }
    OptUninstall   = if ($IsUKR) { "2. ВИДАЛЕННЯ (Restore)" } else { "2. UNINSTALL (Restore)" }
    DrivesPrompt   = if ($IsUKR) { "Оберіть номер диска для GameCache:" } else { "Select drive number for GameCache:" }
    DriveLabel     = if ($IsUKR) { "Диск" } else { "Drive" }
    FreeSpace      = if ($IsUKR) { "вільно" } else { "free" }
    SelectedDrive  = if ($IsUKR) { "Обрано диск" } else { "Selected drive" }
    Path           = if ($IsUKR) { "шлях" } else { "path" }
    StopSvc        = if ($IsUKR) { "[!] Зупинка графічних процесів та служб..." } else { "[!] Stopping GPU processes..." }
    StatusLinked   = if ($IsUKR) { "Статус лінкування:" } else { "Linking Status:" }
    StatusRestored = if ($IsUKR) { "Відновлено:" } else { "Restored:" }
    AlreadyLinked  = if ($IsUKR) { "(Вже залінковано)" } else { "(Already Linked)" }
    Done           = if ($IsUKR) { "УСПІШНО! Операцію за за цією адресою завершено:" } else { "SUCCESS! Operation finished at:" }
    SupportTitle   = if ($IsUKR) { "ПІДТРИМКА ПРОЄКТУ" } else { "SUPPORT THE PROJECT" }
    Finish         = if ($IsUKR) { "Натисніть Enter для виходу" } else { "Press Enter to exit" }
    LocalDisk      = if ($IsUKR) { "Локальний диск" } else { "Local Disk" }
}

# 3. Пошук Steam
$SteamPath = (Get-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam" -Name "InstallPath" -ErrorAction SilentlyContinue).InstallPath
if (!$SteamPath) { $SteamPath = (Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -Name "SteamPath" -ErrorAction SilentlyContinue).SteamPath }
$SteamShaderPath = if ($SteamPath) { "$SteamPath\steamapps\shadercache" } else { "C:\Program Files (x86)\Steam\steamapps\shadercache" }

Clear-Host
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host $FullTitle -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host $Text.OptInstall
Write-Host $Text.OptUninstall

$ModeKey = ""
while ($ModeKey -ne '1' -and $ModeKey -ne '2') {
    $ModeKey = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown").Character
}

# 4. Вибір диска
Write-Host "`n$($Text.DrivesPrompt)" -ForegroundColor Yellow
$Volumes = Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' -and $_.DriveLetter -ne 'C' }
$DriveOptions = @{}
$i = 1

foreach ($Vol in $Volumes) {
    $FreeGB = [math]::Round($Vol.SizeRemaining / 1GB, 1)
    $Label = if ($Vol.FileSystemLabel) { $Vol.FileSystemLabel } else { $Text.LocalDisk }
    Write-Host " [$i] " -NoNewline -ForegroundColor Cyan
    Write-Host "-> $($Text.DriveLabel) $($Vol.DriveLetter): $Label ($FreeGB GB $($Text.FreeSpace))"
    $DriveOptions["$i"] = $Vol.DriveLetter
    $i++
}

$Choice = ""
while (!$DriveOptions.ContainsKey($Choice)) {
    $Choice = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown").Character.ToString()
}
$DriveKey = $DriveOptions[$Choice]
$TargetRoot = "${DriveKey}:\GameCache"
Write-Host "`n$($Text.SelectedDrive) $DriveKey ($($Text.Path): $TargetRoot)" -ForegroundColor Green

# 5. Матриця папок
$Folders = @{
    "NVIDIA_DXCache"      = "$env:LOCALAPPDATA\NVIDIA\DXCache"
    "NVIDIA_GLCache"      = "$env:LOCALAPPDATA\NVIDIA\GLCache"
    "NVIDIA_D3D12Cache"   = "$env:LOCALAPPDATA\NVIDIA\D3D12Cache"
    "NVIDIA_Optix"        = "$env:LOCALAPPDATA\NVIDIA\OptixCache"
    "NVIDIA_D3DSCache"    = "$env:LOCALAPPDATA\D3DSCache"
    "NVTopps_Config"      = "$env:ProgramData\NVIDIA Corporation\NVTopps"
    "AMD_GLCache"         = "$env:LOCALAPPDATA\AMD\GLCache"
    "AMD_D3DSCache"       = "$env:LOCALAPPDATA\AMD\D3DSCache"
    "AMD_ComputeCache"    = "$env:LOCALAPPDATA\AMD\ComputeCache"
    "AMD_VkCache"         = "$env:LOCALAPPDATA\AMD\VkCache"
    "Intel_GPUCache"      = "$env:LOCALAPPDATA\Intel\Graphics\GPUCache"
    "Intel_ShaderCache"   = "$env:LOCALAPPDATA\Intel\Graphics\ShaderCache"
    "Intel_D3D12Cache"    = "$env:LOCALAPPDATA\Intel\Graphics\D3D12Cache"
    "Steam_Shaders"       = "$SteamShaderPath"
}

function Stop-GraphicsProcesses {
    Write-Host "`n$($Text.StopSvc)" -ForegroundColor Yellow
    $Procs = @("nvcontainer", "nvdisplay.container", "RadeonSoftware", "cclengine", "amdow")
    foreach ($p in $Procs) { taskkill /F /IM "$p.exe" /T 2>$null }
    Start-Sleep -Seconds 2
}

$ProcessedFolders = @()

if ($ModeKey -eq '1') {
    Stop-GraphicsProcesses
    foreach ($Name in $Folders.GetEnumerator() | Sort-Object Name) {
        $Old = $Name.Value; $New = Join-Path $TargetRoot $Name.Key
        if (!(Test-Path $Old)) { continue }
        
        if ((Get-Item $Old -ErrorAction SilentlyContinue).Attributes -match "ReparsePoint") {
            $ProcessedFolders += "$($Name.Key) $($Text.AlreadyLinked)"
            continue
        }
        
        if (!(Test-Path $New)) { New-Item -ItemType Directory -Path $New -Force | Out-Null }
        cmd /c "rd /s /q `"$Old`"" 2>$null
        
        if (!(Test-Path $Old)) {
            New-Item -ItemType Junction -Path $Old -Value $New | Out-Null
            $ProcessedFolders += $Name.Key
        }
    }
} else {
    Stop-GraphicsProcesses
    foreach ($Name in $Folders.GetEnumerator()) {
        $Old = $Name.Value
        if ((Test-Path $Old) -and (Get-Item $Old -ErrorAction SilentlyContinue).Attributes -match "ReparsePoint") {
            $Source = Join-Path $TargetRoot $Name.Key
            cmd /c "rd `"$Old`"" 2>$null
            New-Item -ItemType Directory -Path $Old -Force | Out-Null
            if (Test-Path $Source) { 
                robocopy "$Source" "$Old" /E /MOVE /B /R:2 /W:2 /NJH /NJS /NDL /NC /NS /XJD 
            }
            $ProcessedFolders += $Name.Key
        }
    }
}

# 6. Фінал
Write-Host "`n------------------------------------------" -ForegroundColor Gray
$StatusText = if ($ModeKey -eq '1') { $Text.StatusLinked } else { $Text.StatusRestored }
Write-Host "$StatusText" -ForegroundColor Cyan
foreach ($Folder in $ProcessedFolders) { 
    $Color = if ($Folder -match "\(|\)") { "Yellow" } else { "Green" }
    Write-Host " [OK] " -NoNewline -ForegroundColor $Color
    Write-Host $Folder 
}
Write-Host "------------------------------------------" -ForegroundColor Gray

Write-Host "`n=== $($Text.Done) $TargetRoot ===" -ForegroundColor Green

# Блок донату
Write-Host "`n   ( (  " -ForegroundColor Cyan
Write-Host "    ) ) " -ForegroundColor Cyan
Write-Host "  ........" -ForegroundColor White
Write-Host "  |      |]  $($Text.SupportTitle)" -ForegroundColor White
Write-Host "  \      /   Donatello: https://donatello.to/yataktyni" -ForegroundColor Yellow
Write-Host "   '----'    Ko-fi:     https://ko-fi.com/yataktyni/tip" -ForegroundColor Yellow
Write-Host "             USDT TRC20: TP63PYsRk3H9JypuHhqmfpwyCqBYyLBxQL" -ForegroundColor White
Write-Host "------------------------------------------------------------" -ForegroundColor Gray

Write-Host "$($Text.Finish)" -ForegroundColor Gray
Read-Host
