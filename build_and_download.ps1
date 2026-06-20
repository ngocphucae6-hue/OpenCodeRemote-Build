$repo = "ngocphucae6-hue/OpenCodeRemote-Build"
$workflow = ".github/workflows/build-ipa.yml"
$artifact = "OpenCodeRemote-unsigned-IPA"
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
$ipaDest = Join-Path $dest "OpenCodeRemote-unsigned.ipa"

# Download to temp folder then move (avoid extraction conflicts)
$tempDir = Join-Path $dest "temp_$(Get-Random)"
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

gh run download $run.databaseId --repo $repo --name $artifact --dir $tempDir

$ipaTemp = Join-Path $tempDir "OpenCodeRemote-unsigned.ipa"
if (Test-Path $ipaTemp) {
    # Ensure destination doesn't exist before moving
    if (Test-Path $ipaDest) {
        Remove-Item -LiteralPath $ipaDest -Force -ErrorAction SilentlyContinue
    }
    Move-Item -Path $ipaTemp -Destination $ipaDest -Force
    Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
    Write-Host "✅ IPA saved: $ipaDest"
} else {
    Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
    Write-Error "IPA not found in artifact"
    exit 1
}
