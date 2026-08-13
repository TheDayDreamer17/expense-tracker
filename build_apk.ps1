# ==============================================================================
# FLUTTER APK BUILD & VERSIONING SCRIPT (Windows PowerShell)
# ==============================================================================
#
# INSTRUCTIONS ON HOW TO USE:
#
# 1. Change the values of $VERSION_NAME and $VERSION_CODE below for new updates.
# 2. Run this script in PowerShell from the root project directory:
#    .\build_apk.ps1
# 3. The built APK will be generated and copied to:
#    .\builds\expense_tracker_v<VERSION_NAME>.apk
#
# ------------------------------------------------------------------------------
# HOW FLUTTER VERSIONING WORKS:
#
# - VERSION NAME ($VERSION_NAME):
#   This is the user-facing version string (e.g., "1.0.0", "1.0.1", "1.1.0").
#   Usually follows Semantic Versioning (Major.Minor.Patch).
#
# - VERSION CODE ($VERSION_CODE):
#   This is an internal integer (e.g., 1, 2, 3, 4) used by Android / Google Play.
#   CRITICAL: For every new update you publish to users or Google Play, this
#   number MUST be strictly greater than the previous release's version code.
# ==============================================================================

# Change these values for new releases:
$VERSION_NAME = "1.0.0"
$VERSION_CODE = 1

# --- Script Execution ---
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "Building Expense Tracker Release APK" -ForegroundColor Cyan
Write-Host "Version Name: $VERSION_NAME" -ForegroundColor Yellow
Write-Host "Version Code: $VERSION_CODE" -ForegroundColor Yellow
Write-Host "==============================================" -ForegroundColor Cyan

# Navigate to finance_app directory
cd finance_app

# Run Flutter Release Build
Write-Host "Running Flutter build..." -ForegroundColor Gray
flutter build apk --release --build-name=$VERSION_NAME --build-number=$VERSION_CODE

if ($LASTEXITCODE -eq 0) {
    Write-Host "`nBuild successful!" -ForegroundColor Green
    
    # Create builds output directory at workspace root
    cd ..
    if (!(Test-Path -Path "builds")) {
        New-Item -ItemType Directory -Path "builds" | Out-Null
    }

    # Copy built APK to root builds folder for convenience
    $SourceApk = "finance_app\build\app\outputs\flutter-apk\app-release.apk"
    $DestApk = "builds\expense_tracker_v$VERSION_NAME.apk"
    
    Copy-Item -Path $SourceApk -Destination $DestApk -Force
    
    Write-Host "`n==============================================" -ForegroundColor Green
    Write-Host "APK copied to convenient location:" -ForegroundColor Green
    Write-Host ">> $DestApk" -ForegroundColor Yellow
    Write-Host "==============================================" -ForegroundColor Green
} else {
    Write-Error "Flutter build failed."
    cd ..
}
