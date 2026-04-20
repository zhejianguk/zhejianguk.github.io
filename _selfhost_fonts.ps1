Add-Type -AssemblyName System.Net.Http
$ErrorActionPreference = 'Stop'

$cssUrl = 'https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@500;600&family=Source+Serif+Pro:ital,wght@0,400;0,600;0,700;1,400&display=swap'

# Modern browsers get WOFF2; pretend to be a recent Chrome so Google returns WOFF2.
$ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36'
$web = [System.Net.WebClient]::new()
$web.Headers.Add('User-Agent', $ua)
$css = $web.DownloadString($cssUrl)

# Parse @font-face blocks. We only want the /* latin */ blocks (not cyrillic,
# greek, vietnamese, latin-ext, etc.) since the site is English-only. This is
# the minimal set a browser would actually download anyway.
$pattern = "(?s)/\* latin \*/\s*(@font-face\s*\{[^}]+\})"
$blocks = [regex]::Matches($css, $pattern)

if ($blocks.Count -eq 0) { throw "No /* latin */ blocks found in Google Fonts CSS." }

Write-Host "Found $($blocks.Count) latin @font-face blocks."

if (-not (Test-Path fonts)) { New-Item -ItemType Directory fonts | Out-Null }

$localCss = New-Object System.Text.StringBuilder
[void]$localCss.AppendLine("/* Self-hosted Google Fonts (latin subset only) — fetched once at build")
[void]$localCss.AppendLine("   time so first-visit cold loads pay zero third-party DNS/TLS cost. */")

$downloaded = @{}

foreach ($m in $blocks) {
    $block = $m.Groups[1].Value

    # Extract font-family, weight, style
    $fam    = ([regex]::Match($block, "font-family:\s*'([^']+)'")).Groups[1].Value
    $style  = ([regex]::Match($block, "font-style:\s*([^;]+);")).Groups[1].Value.Trim()
    $weight = ([regex]::Match($block, "font-weight:\s*([^;]+);")).Groups[1].Value.Trim()
    $url    = ([regex]::Match($block, "url\(([^)]+)\)")).Groups[1].Value.Trim()

    # Build a friendly local filename, e.g. Inter-400.woff2, SourceSerifPro-400i.woff2
    $famClean = $fam -replace '\s', ''
    $suffix   = if ($style -eq 'italic') { "${weight}i" } else { "$weight" }
    $localName = "$famClean-$suffix.woff2"
    $localPath = "fonts/$localName"

    if (-not $downloaded.ContainsKey($localPath)) {
        Write-Host ("  downloading {0,-32} <- {1}" -f $localName, $url)
        $bytes = $web.DownloadData($url)
        [System.IO.File]::WriteAllBytes((Join-Path (Get-Location) $localPath), $bytes)
        $downloaded[$localPath] = $bytes.Length
    }

    # Rewrite URL to local path, preserve unicode-range and everything else
    $newBlock = [regex]::Replace($block, "url\([^)]+\)", "url('fonts/$localName')")
    [void]$localCss.AppendLine($newBlock.Trim())
    [void]$localCss.AppendLine()
}

[System.IO.File]::WriteAllText((Join-Path (Get-Location) 'fonts.css'), $localCss.ToString())

$totalKB = ($downloaded.Values | Measure-Object -Sum).Sum / 1KB
Write-Host ""
Write-Host ("Saved {0} font files, {1:N1} KB total, to fonts/" -f $downloaded.Count, $totalKB)
Write-Host "Wrote fonts.css ($(((Get-Item fonts.css).Length)/1KB) KB) alongside stylesheet.css"
