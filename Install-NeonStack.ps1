[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string]$FolderPainterPath,
    [Parameter(Mandatory = $true)][ValidateRange(1, 15)][int]$Slot
)
$ErrorActionPreference = 'Stop'
$appRoot = (Resolve-Path -LiteralPath $FolderPainterPath).Path
$iconsRoot = Join-Path $appRoot 'Icons'
$slotId = '{0:00}' -f $Slot
$packName = 'Pack_' + $slotId
$targetPack = Join-Path $iconsRoot $packName
$iniPath = Join-Path $iconsRoot 'FolderPainter.ini'
$sourcePack = Join-Path $PSScriptRoot 'Pack_NeonStack'
if (!(Test-Path -LiteralPath (Join-Path $appRoot 'FolderPainter_x64.exe')) -and !(Test-Path -LiteralPath (Join-Path $appRoot 'FolderPainter.exe'))) { throw 'Select the FolderPainter application folder.' }
if (!(Test-Path -LiteralPath $targetPack -PathType Container)) { throw "$packName does not exist. Select an existing menu slot." }
if (!(Test-Path -LiteralPath $iniPath -PathType Leaf)) { throw 'FolderPainter.ini was not found.' }
if ((Get-Item -LiteralPath $targetPack).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'The selected pack is a linked folder. Use a regular pack folder.' }
foreach ($number in 0..14) {
    $icon = Join-Path $sourcePack ('{0:00}.ico' -f $number)
    if (!(Test-Path -LiteralPath $icon -PathType Leaf)) { throw "Incomplete Neon Stack package: $icon" }
}

$iniBytes = [IO.File]::ReadAllBytes($iniPath)
$skip = 0
$encoding = [Text.Encoding]::Default
if ($iniBytes.Length -ge 2 -and $iniBytes[0] -eq 255 -and $iniBytes[1] -eq 254) { $encoding = [Text.Encoding]::Unicode; $skip = 2 }
elseif ($iniBytes.Length -ge 2 -and $iniBytes[0] -eq 254 -and $iniBytes[1] -eq 255) { $encoding = [Text.Encoding]::BigEndianUnicode; $skip = 2 }
elseif ($iniBytes.Length -ge 3 -and $iniBytes[0] -eq 239 -and $iniBytes[1] -eq 187 -and $iniBytes[2] -eq 191) { $encoding = New-Object Text.UTF8Encoding($true); $skip = 3 }
$iniText = $encoding.GetString($iniBytes, $skip, $iniBytes.Length - $skip)
$packMatch = [regex]::Match($iniText, '(?m)^IconPack=([^\r\n]*)')
$knownSlots = @($packMatch.Groups[1].Value.Split('/') | Where-Object { $_.Length -ge 2 } | ForEach-Object { $_.Substring($_.Length - 2) })
if ($knownSlots -notcontains $slotId) { throw "$packName is not in the current menu configuration. Choose a slot already shown in FolderPainter." }
$labels = @('Projects','Frontend','Backend','APIs','Database','Cloud','Containers','Git','Testing','Security','Design','Docs','Deploy','Archive')
$menuValue = $slotId + '="Neon Stack \n ' + ($labels -join ' \n ') + '"'
$languagePattern = '(?ms)(^\[Language_[^\r\n]+\]\r?\n)(.*?)(?=^\[|\z)'
$sections = [regex]::Matches($iniText, $languagePattern)
if ($sections.Count -eq 0) { throw 'No supported FolderPainter language sections were found.' }
$newText = [regex]::Replace($iniText, $languagePattern, [Text.RegularExpressions.MatchEvaluator]{
    param($section)
    $body = $section.Groups[2].Value
    $linePattern = '(?m)^' + $slotId + '=[^\r\n]*'
    if ([regex]::IsMatch($body, $linePattern)) {
        $body = [regex]::Replace($body, $linePattern, [Text.RegularExpressions.MatchEvaluator]{ param($line) $menuValue })
    } else {
        $body = $menuValue + "`r`n" + $body
    }
    $section.Groups[1].Value + $body
})

Write-Host 'Close FolderPainter before continuing.'
Write-Host "Selected replacement: $targetPack"
Write-Host 'Folders that still reference icons in this slot will show the new icons.'
Write-Host 'Existing menus must be reinstalled using the FolderPainter Install button.'
if (!$PSCmdlet.ShouldProcess($targetPack, 'Back up the current pack and settings, then install Neon Stack')) { return }

$backupRoot = Join-Path $appRoot 'NeonStack-Backups'
$backup = Join-Path $backupRoot ((Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + $packName + '-' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $backup -Force | Out-Null
Copy-Item -LiteralPath $targetPack -Destination (Join-Path $backup $packName) -Recurse
Copy-Item -LiteralPath $iniPath -Destination (Join-Path $backup 'FolderPainter.ini')
@{ ApplicationPath=$appRoot; Pack=$packName; Created=(Get-Date -Format o) } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $backup 'backup.json') -Encoding UTF8
try {
    foreach ($number in 0..14) {
        $filename = '{0:00}.ico' -f $number
        Copy-Item -LiteralPath (Join-Path $sourcePack $filename) -Destination (Join-Path $targetPack $filename) -Force
    }
    if ([Convert]::ToBase64String($iniBytes) -cne [Convert]::ToBase64String([IO.File]::ReadAllBytes($iniPath))) { throw 'Settings changed during installation. Close FolderPainter and retry.' }
    $newBytes = $encoding.GetBytes($newText)
    if ($skip -gt 0) { $newBytes = [byte[]]($encoding.GetPreamble() + $newBytes) }
    [IO.File]::WriteAllBytes($iniPath, $newBytes)
} catch {
    $failure = $_
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $backup $packName) -File) {
        Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $targetPack $file.Name) -Force
    }
    if ($failure.Exception.Message -notlike 'Settings changed during installation*') {
        Copy-Item -LiteralPath (Join-Path $backup 'FolderPainter.ini') -Destination $iniPath -Force
    }
    throw $failure
}
Write-Host "Installed Neon Stack in $packName. Backup: $backup" -ForegroundColor Cyan
Write-Host 'Open FolderPainter, select Neon Stack, then click Install to refresh its context menu.'
