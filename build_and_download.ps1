$repo = "ngocphucae6-hue/OpenCodeRemote-Build"
$workflow = ".github/workflows/build-ipa.yml"
$artifact = "OpenCodeRemote-signed-IPA"
$dest = "C:\Users\Admin\Desktop\OpenCodeRemote-Build\OpenCodeRemote-Build\Downloads"

New-Item -ItemType Directory -Force -Path $dest | Out-Null
Set-Location "C:\Users\Admin\Desktop\OpenCodeRemote-Build\OpenCodeRemote-Build"

# Auto-commit & push if changes exist
$status = git status --porcelain
if ($status) {
    Write-Host "Auto-committing changes..."
    git add -A
    git commit -m "build: automated IPA build $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
    git push origin main
} else {
    Write-Host "No local changes. Ensuring latest remote..."
    git push origin main
}

# Wait for workflow to appear
Write-Host "Waiting for workflow run..."
Start-Sleep -Seconds 20

$run = $null
$attempts = 0
while ($attempts -lt 30 -and (-not $run -or $run.status -in @('in_progress','queued'))) {
    try {
        $run = gh run list --repo $repo --workflow $workflow --limit 1 --json databaseId,status,conclusion,headSha | ConvertFrom-Json | Select-Object -First 1
        if ($run) { Write-Host "$(Get-Date -f HH:mm:ss) Run $($run.databaseId): $($run.status)" }
    } catch { }
    Start-Sleep -Seconds 10
    $attempts++
}

if (-not $run) { Write-Error "No run found"; exit 1 }

# Wait for completion
while ($run.status -ne "completed") {
    Start-Sleep -Seconds 15
    try {
        $run = gh run view $run.databaseId --json status,conclusion --repo $repo | ConvertFrom-Json
        Write-Host "$(Get-Date -f HH:mm:ss) Status: $($run.status)"
    } catch { }
}

if ($run.conclusion -ne "success") {
    Write-Error "Build failed: $($run.conclusion)"
    exit 1
}

Write-Host "Build succeeded. Downloading IPA..."
$ipaSrc = Join-Path $dest "OpenCodeRemote.ipa"
Remove-Item -LiteralPath $ipaSrc -Force -ErrorAction SilentlyContinue

gh run download $run.databaseId --repo $repo --name $artifact --dir $dest

if (Test-Path $ipaSrc) {
    $ipaDst = Join-Path $dest "OpenCodeRemote-signed.ipa"
    Rename-Item -Path $ipaSrc -NewName $ipaDst -Force
    Write-Host "✅ IPA saved: $ipaDst"
} else {
    Write-Error "Download failed - artifact not found"
    exit 1
}
