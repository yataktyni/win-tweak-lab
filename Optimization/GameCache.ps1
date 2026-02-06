<#
    Win-Tweak-Lab: GPU Cache Manager v1.0.5
    Professional optimization tools for Workstations & Gaming PCs
    
    Repository: https://github.com/yataktyni/Win-Tweak-Lab/GameCache.ps1
    
    Quick Run (Admin):
    irm https://raw.githubusercontent.com/yataktyni/win-tweak-lab/main/Optimization/GameCache.ps1 | iex
#>

# 1. Адмін-права
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs; exit
}

# 2. Локалізація
$OSLang = [System.Globalization.CultureInfo]::CurrentUICulture.Name
$IsUKR = ($OSLang -eq "uk-UA")

$Text = @{
    Header       = "   GPU CACHE MANAGER v1.0.4   "
    OptInstall   = if ($IsUKR) { "1. ВСТАНОВЛЕННЯ (Link)" } else { "1. INSTALL (Link)" }
    OptUninstall  = if ($IsUKR) { "2. ВИДАЛЕННЯ (Restore)" } else { "2. UNINSTALL (Restore)" }
    DrivesInstall = if ($IsUKR) { "Оберіть диск для GameCache (натисніть клавішу):" } else { "Select drive for GameCache (press key):" }
    DrivesUninst  = if ($IsUKR) { "Оберіть диск з лінкованим кешем (натисніть клавішу):" } else { "Select drive with linked cache (press key):" }
    StopSvc       = if ($IsUKR) { "[!] Зупинка графічних процесів та служб..." } else { "[!] Stopping GPU processes and services..." }
    Done          = if ($IsUKR) { "УСПІШНО! Операцію завершено на" } else { "SUCCESS! Operation finished on" }
    ManualHeader  = if ($IsUKR) { "   ПОТРІБНА ВАША ДОПОМОГА   " } else { "   MANUAL ACTION REQUIRED   " }
    ManualSteps   = if ($IsUKR) { 
        "1. Вимкніть Shader Cache в панелі керування GPU.`n2. Перезавантажте ПК.`n3. Запустіть цей скрипт знову.`n4. Увімкніть кеш назад." 
    } else { 
        "1. Disable Shader Cache in GPU settings.`n2. Reboot your PC.`n3. Run this script again.`n4. Re-enable Shader Cache." 
    }
    SupportTitle = if ($IsUKR) { "ПІДТРИМКА ПРОЄКТУ" } else { "SUPPORT THE PROJECT" }
    Finish       = if ($IsUKR) { "Натисніть Enter для виходу" } else { "Press Enter to exit" }
}

# 3. Шляхи Steam
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

# 4. Вибір диска
$Prompt = if ($ModeKey -eq '1') { $Text.DrivesInstall } else { $Text.DrivesUninst }
Write-Host "`n$Prompt" -ForegroundColor Yellow

$Volumes = Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' -and $_.DriveLetter -ne 'C' }
$ValidKeys = @()

foreach ($Vol in $Volumes) {
    $Key = $Vol.DriveLetter.ToString().ToUpper()
    $FreeGB = [math]::Round($Vol.SizeRemaining / 1GB, 1)
    $Label = if ($Vol.FileSystemLabel) { $Vol.FileSystemLabel } else { "Local Disk" }
    Write-Host " [$Key] " -NoNewline -ForegroundColor Cyan
    Write-Host "-> Диск $Label ($FreeGB GB free)"
    $ValidKeys += $Key
}

$DriveKey = ""
while ($ValidKeys -notcontains $DriveKey) {
    $DriveKey = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown").Character.ToString().ToUpper()
}
$TargetRoot = "${DriveKey}:\GameCache"
Write-Host "`nОбрано шлях: $TargetRoot" -ForegroundColor Green

# 5. Матриця шляхів
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
    $Services = @("NVDisplay.ContainerLocalSystem", "AMD External Events Utility")
    foreach ($s in $Services) { 
        $svc = Get-Service $s -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq 'Running') { Stop-Service $s -Force -ErrorAction SilentlyContinue }
    }
    Start-Sleep -Seconds 2
}

if ($ModeKey -eq '1') {
    Stop-GraphicsProcesses
    $LockedFolders = @()
    foreach ($Name in $Folders.GetEnumerator() | Sort-Object Name) {
        $Old = $Name.Value; $New = Join-Path $TargetRoot $Name.Key
        if (!(Test-Path $Old)) { continue }
        if ((Get-Item $Old -ErrorAction SilentlyContinue).Attributes -match "ReparsePoint") { continue }
        if (!(Test-Path $New)) { New-Item -ItemType Directory -Path $New -Force | Out-Null }
        cmd /c "rd /s /q `"$Old`"" 2>$null
        if (!(Test-Path $Old)) {
            New-Item -ItemType Junction -Path $Old -Value $New | Out-Null
            Write-Host "[OK] $($Name.Key)" -ForegroundColor Green
        } else { $LockedFolders += $Name.Key }
    }
    if ($LockedFolders.Count -gt 0) {
        Write-Host "`n" + ("="*50) -ForegroundColor Yellow
        Write-Host $Text.ManualHeader -BackgroundColor Yellow -ForegroundColor Black
        Write-Host $Text.ManualSteps -ForegroundColor White
        Write-Host ("="*50) -ForegroundColor Yellow
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
            Write-Host "[OK] Restored: $($Name.Key)" -ForegroundColor Green
        }
    }
}

Get-Service "NVDisplay.ContainerLocalSystem" -ErrorAction SilentlyContinue | Start-Service -ErrorAction SilentlyContinue
Write-Host "`n=== $($Text.Done) $TargetRoot ===" -ForegroundColor Green

# 6. Блок донату (Donate Block)
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
