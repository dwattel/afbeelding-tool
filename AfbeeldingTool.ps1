# Afbeelding & Media Tool (PowerShell - Uitgebreid & 100% veilig voor speciale tekens)
$ErrorActionPreference = "Continue"
Add-Type -AssemblyName PresentationCore

$WorkDir = Get-Location
$OutRoot = Join-Path $WorkDir "uitvoer"
$LogFile = Join-Path $WorkDir "foutenlog.txt"

while ($true) {
    Clear-Host
    Write-Host "Huidige werkmap: $WorkDir" -ForegroundColor Yellow
    Write-Host "Uitvoer komt in: $OutRoot\[mapstructuur]" -ForegroundColor Yellow
    Write-Host "Foutenlog:       $LogFile`n" -ForegroundColor Yellow

    Write-Host "Wat doet dit script in ALLE submappen:"
    Write-Host " 1. Verwijdert .txt, .url en .bat bestanden"
    Write-Host " 2. Schoont bestandsnamen op (%5B/%5D weg, %2F -> -, %20 -> spatie, %28/%29 -> haakjes)"
    Write-Host " 3. JPG <= 2560x1440: Direct verplaatsen (100% originele kwaliteit)"
    Write-Host " 4. JPG >  2560x1440: Trimmen + schalen naar max 2560x1440 in uitvoer\..."
    Write-Host " 5. Overige afbeeldingen (png, webp, heic, avif, bmp, tif, psd, gif, jpeg, etc.): -> JPG"
    Write-Host " 6. Video's (mp4, mov, avi, mkv, wmv, webm, m4v, flv, mpg, ts, 3gp, etc.): Direct verplaatsen"
    Write-Host " 7. Verwijdert alleen LEGE bronmappen (mappen met fouten blijven staan)`n"

    Write-Host "Druk op een willekeurige toets om te starten, of druk op [ESC] om te stoppen..." -ForegroundColor Cyan
    $key = [Console]::ReadKey($true).Key
    if ($key -eq 'Escape') { exit }

    Clear-Host
    $ErrorCount = 0
    if (Test-Path -LiteralPath $LogFile) { Remove-Item -LiteralPath $LogFile -Force }

    function Write-ErrLog([string]$Message) {
        $script:ErrorCount++
        Write-Host $Message -ForegroundColor Red
        Add-Content -LiteralPath $LogFile -Value $Message
    }

    Write-Host "Verwerking gestart... (Alleen foutmeldingen verschijnen hier en in foutenlog.txt)`n"

    # Haal vooraf alle submappen op (exclusief \uitvoer)
    $SubFolders = Get-ChildItem -LiteralPath $WorkDir -Directory -Recurse | Where-Object {
        $_.FullName -notlike "$OutRoot*"
    }

    if ($SubFolders.Count -eq 0) {
        Write-ErrLog "[FOUT] Geen submappen gevonden om te verwerken!"
        Read-Host "Druk op Enter om terug te keren"
        continue
    }

    $ImageExts = @('.jpeg', '.png', '.webp', '.tif', '.tiff', '.psd', '.bmp', '.gif', '.heic', '.heif', '.avif', '.ico', '.svg', '.tga')
    $VideoExts = @('.mp4', '.mov', '.avi', '.mkv', '.wmv', '.webm', '.m4v', '.flv', '.3gp', '.mpg', '.mpeg', '.ts', '.vob', '.ogv')
    $JunkExts  = @('.txt', '.url', '.bat')

    foreach ($Folder in $SubFolders) {
        if (-not (Test-Path -LiteralPath $Folder.FullName)) { continue }

        $RelPath   = $Folder.FullName.Substring($WorkDir.Path.Length)
        $TargetDir = Join-Path $OutRoot $RelPath

        # 1. Ongewenste bestanden verwijderen
        $Files = Get-ChildItem -LiteralPath $Folder.FullName -File
        foreach ($File in $Files) {
            if ($JunkExts -contains $File.Extension.ToLower()) {
                try {
                    $File.IsReadOnly = $false
                    Remove-Item -LiteralPath $File.FullName -Force
                } catch {
                    Write-ErrLog "[FOUT] Kon ongewenst bestand niet verwijderen: $RelPath\$($File.Name)"
                }
            }
        }

        # 2. Bestandsnamen opschonen (%5B/%5D weg, %2F -> -, %20 -> spatie, %28/%29 -> haakjes, %26 -> &, %2C -> ,)
        $Files = Get-ChildItem -LiteralPath $Folder.FullName -File
        foreach ($File in $Files) {
            if ($File.Name -match '%5B|%5D|%2F|%20|%28|%29|%26|%2C') {
                $CleanName = $File.Name `
                    -ireplace '%5B|%5D', '' `
                    -ireplace '%2F', '-' `
                    -ireplace '%20', ' ' `
                    -ireplace '%28', '(' `
                    -ireplace '%29', ')' `
                    -ireplace '%26', '&' `
                    -ireplace '%2C', ','

                if ($CleanName -ne $File.Name) {
                    try {
                        $File.IsReadOnly = $false
                        $Base = [IO.Path]::GetFileNameWithoutExtension($CleanName)
                        $Ext  = [IO.Path]::GetExtension($CleanName)
                        $DestName = $CleanName
                        $Counter = 1
                        while (Test-Path -LiteralPath (Join-Path $Folder.FullName $DestName)) {
                            $DestName = "{0}_{1}{2}" -f $Base, $Counter, $Ext
                            $Counter++
                        }
                        Rename-Item -LiteralPath $File.FullName -NewName $DestName
                    } catch {
                        Write-ErrLog "[FOUT] Hernoemen mislukt: $RelPath\$($File.Name)"
                    }
                }
            }
        }

        # 3. Media verwerken
        $Files = Get-ChildItem -LiteralPath $Folder.FullName -File
        foreach ($File in $Files) {
            $Ext = $File.Extension.ToLower()
            $File.IsReadOnly = $false

            # A. Bestaande JPG-bestanden (afmetingen direct via Windows .NET uitlezen)
            if ($Ext -eq '.jpg') {
                try {
                    if (-not (Test-Path -LiteralPath $TargetDir)) {
                        New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
                    }

                    $W = 0
                    $H = 0
                    $Stream = [System.IO.File]::OpenRead($File.FullName)
                    try {
                        $Decoder = [System.Windows.Media.Imaging.BitmapDecoder]::Create(
                            $Stream,
                            [System.Windows.Media.Imaging.BitmapCreateOptions]::DelayCreation,
                            [System.Windows.Media.Imaging.BitmapCacheOption]::None
                        )
                        $W = $Decoder.Frames[0].PixelWidth
                        $H = $Decoder.Frames[0].PixelHeight
                    } finally {
                        $Stream.Close()
                        $Stream.Dispose()
                    }

                    if ($W -le 0 -or $H -le 0) {
                        Write-ErrLog "[FOUT] Kan afmetingen niet lezen (beschadigd/ongeldig): $RelPath\$($File.Name)"
                        continue
                    }

                    if ($W -le 2560 -and $H -le 1440) {
                        $DestFile = Join-Path $TargetDir $File.Name
                        Move-Item -LiteralPath $File.FullName -Destination $DestFile -Force
                    } else {
                        $DestFile = Join-Path $TargetDir ($File.BaseName + ".jpg")
                        & magick "$($File.FullName)" -background white -alpha remove -fuzz 25% -trim +repage -resize "2560x1440>" "$DestFile" 2>$null
                        if ($LASTEXITCODE -eq 0) {
                            Remove-Item -LiteralPath $File.FullName -Force
                        } else {
                            Write-ErrLog "[FOUT] Schalen mislukt (origineel behouden): $RelPath\$($File.Name)"
                        }
                    }
                } catch {
                    Write-ErrLog "[FOUT] Fout bij verwerken JPG: $RelPath\$($File.Name) - $($_.Exception.Message)"
                }
            }
            # B. Overige afbeeldingsformaten
            elseif ($ImageExts -contains $Ext) {
                try {
                    if (-not (Test-Path -LiteralPath $TargetDir)) {
                        New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
                    }
                    $DestFile = Join-Path $TargetDir ($File.BaseName + ".jpg")
                    & magick "$($File.FullName)" -background white -alpha remove -fuzz 25% -trim +repage -resize "2560x1440>" "$DestFile" 2>$null
                    if ($LASTEXITCODE -eq 0) {
                        Remove-Item -LiteralPath $File.FullName -Force
                    } else {
                        Write-ErrLog "[FOUT] Converteren mislukt (origineel behouden): $RelPath\$($File.Name)"
                    }
                } catch {
                    Write-ErrLog "[FOUT] Fout bij converteren: $RelPath\$($File.Name) - $($_.Exception.Message)"
                }
            }
            # C. Videobestanden
            elseif ($VideoExts -contains $Ext) {
                try {
                    if (-not (Test-Path -LiteralPath $TargetDir)) {
                        New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
                    }
                    $DestFile = Join-Path $TargetDir $File.Name
                    Move-Item -LiteralPath $File.FullName -Destination $DestFile -Force
                } catch {
                    Write-ErrLog "[FOUT] Video verplaatsen mislukt: $RelPath\$($File.Name)"
                }
            }
        }
    }

    # 4. Alleen volledig lege bronmappen opruimen (van diep naar ondiep)
    $AllDirsDesc = Get-ChildItem -LiteralPath $WorkDir -Directory -Recurse | Where-Object {
        $_.FullName -notlike "$OutRoot*"
    } | Sort-Object { $_.FullName.Length } -Descending

    foreach ($Dir in $AllDirsDesc) {
        if (Test-Path -LiteralPath $Dir.FullName) {
            $Remaining = Get-ChildItem -LiteralPath $Dir.FullName -Force
            if ($Remaining.Count -eq 0) {
                Remove-Item -LiteralPath $Dir.FullName -Force
            } else {
                Write-ErrLog "[NIET LEEG / OVERGESLAGEN] Map bevat nog niet-verwerkte bestanden: $($Dir.FullName)"
            }
        }
    }

    Write-Host ""
    if ($ErrorCount -eq 0) {
        Write-Host "[KLAAR] Alles is 100% foutloos verwerkt en opgeruimd naar: $OutRoot" -ForegroundColor Green
    } else {
        Write-Host "[KLAAR MET $ErrorCount FOUTMELDING(EN)]" -ForegroundColor Red
        Write-Host "De betreffende bestanden en mappen zijn BEHOUDEN in de bronmap."
        Write-Host "Bekijk het overzicht hierboven of open: $LogFile"
    }

    Write-Host "`nDruk op een willekeurige toets om terug te keren naar het menu, of op [ESC] om te stoppen..." -ForegroundColor Cyan
    $key = [Console]::ReadKey($true).Key
    if ($key -eq 'Escape') { exit }
}

