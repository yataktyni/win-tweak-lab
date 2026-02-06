<#
    Win-Tweak-Lab: GPU Cache Manager v1.1.5
    Quick Run: [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; iex (irm https://raw.githubusercontent.com/yataktyni/win-tweak-lab/main/Optimization/GameCache.ps1)
#>

# 1. Налаштування кодування та розумна перевірка адмін-прав
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$OutputEncoding = [System.Text.Encoding]::UTF8

if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $CurrentScript = $MyInvocation.MyCommand.Path
    $Utf8Fix = "[Console]::OutputEncoding = [System.Text.Encoding]::UTF8;"
    if (!$CurrentScript) {
        $Command = "$Utf8Fix irm https://raw.githubusercontent.com/yataktyni/win-tweak-lab/main/Optimization/GameCache.ps1 | iex"
    } else {
        $Command = "$Utf8Fix & '$CurrentScript'"
    }
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command $Command" -Verb RunAs
    exit
}

# 2. Локалізація
$OSLang = [System.Globalization.CultureInfo]::CurrentUICulture.Name
$IsUKR = ($OSLang -eq "uk-UA")

$Text = @{
    Header       = "   GPU CACHE MANAGER v1.1.5   "
    OptInstall   = if ($IsUKR) { "1. ВСТАНОВЛЕННЯ (Link)" } else { "1. INSTALL (Link)" }
    OptUninstall  = if ($IsUKR) { "2. ВИДАЛЕННЯ (Restore)" } else { "2. UNINSTALL (Restore)" }
    DrivesPrompt  = if ($IsUKR) { "Оберіть номер диска для GameCache:" } else { "Select drive number for GameCache:" }
    StopSvc       = if ($IsUKR) { "[!] Зупинка графічних процесів та служб..." } else { "[!] Stopping GPU processes..." }
    Done          = if ($IsUKR) { "УСПІШНО! Операцію завершено на" } else { "SUCCESS! Operation finished on" }
    SupportTitle  = if ($IsUKR) { "ПІДТРИМКА ПРОЄКТУ" } else { "SUPPORT THE PROJECT" }
    Finish        = if ($IsUKR) { "Натисніть Enter для виходу" } else { "Press Enter to exit" }
}

# 3. Пошук Steam
$SteamPath = (Get-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam" -Name "InstallPath" -ErrorAction SilentlyContinue).InstallPath
if (!$SteamPath) { $SteamPath = (Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -Name "SteamPath" -ErrorAction SilentlyContinue).SteamPath }
$SteamShaderPath = if ($SteamPath) { "$SteamPath\steamapps\shadercache" } else { "C:\Program Files (x86)\Steam\steamapps\shadercache" }

Clear-Host
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host $Text.Header -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host $Text.OptInstall
Write-Host $Text.OptUninstall

$ModeKey = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown").Character
if ($ModeKey -ne '1' -and $ModeKey -ne '2') { exit }

# 4. Вибір диска за порядковим номером
Write-Host "`n$($Text.DrivesPrompt)" -ForegroundColor Yellow
$Volumes = Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' -and $_.DriveLetter -ne 'C' }
$DriveOptions = @{}
$i = 1

foreach ($Vol in $Volumes) {
    $FreeGB = [math]::Round($Vol.SizeRemaining / 1GB, 1)
    $Label = if ($Vol.FileSystemLabel) { $Vol.FileSystemLabel } else { "Local Disk" }
    Write-Host " [$i] " -NoNewline -ForegroundColor Cyan
    Write-Host "-> Диск $($Vol.DriveLetter): $Label ($FreeGB GB free)"
    $DriveOptions["$i"] = $Vol.DriveLetter
    $i++
}

$Choice = ""
while (!$DriveOptions.ContainsKey($Choice)) {
    $Choice = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown").Character.ToString()
}
$DriveKey = $DriveOptions[$Choice]
$TargetRoot = "${DriveKey}:\GameCache"
Write-Host "`nОбрано диск $DriveKey (шлях: $TargetRoot)" -ForegroundColor Green

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
        
        # Якщо вже залінковано - просто додаємо в звіт і йдемо далі
        if ((Get-Item $Old -ErrorAction SilentlyContinue).Attributes -match "ReparsePoint") {
            $ProcessedFolders += "$($Name.Key) (Already Linked)"
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
$StatusText = if ($ModeKey -eq '1') { if ($IsUKR) {"Статус лінкування:"} else {"Linking Status:"} } else { if ($IsUKR) {"Відновлено:"} else {"Restored:"} }
Write-Host "$StatusText" -ForegroundColor Cyan
foreach ($Folder in $ProcessedFolders) { 
    $Color = if ($Folder -match "Already") { "Yellow" } else { "Green" }
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
