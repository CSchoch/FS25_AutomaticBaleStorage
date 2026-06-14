param(
    [string]$Src,
    [string]$Dst
)

$excludeExt = @('.bat', '.png', '.pdn', '.ps1', '.zip')
$srcLen     = $Src.Length

Add-Type -Assembly 'System.IO.Compression.FileSystem'
$zip = [System.IO.Compression.ZipFile]::Open($Dst, 'Create')

Get-ChildItem $Src -Recurse -File | ForEach-Object {
    if ($excludeExt -contains $_.Extension.ToLower()) { return }
    $rel = $_.FullName.Substring($srcLen + 1).Replace('\', '/')
    if ($rel -like '.git/*' -or $rel -eq '.git') { return }
    if ($rel -eq 'CLAUDE.md') { return }
    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $_.FullName, $rel) | Out-Null
}

$zip.Dispose()
Write-Host "Done."
