# Build script for GMWF Management App (Subfolder /new/)
Write-Host "Building GMWF App for Web Subdirectory (/new/)..." -ForegroundColor Cyan
flutter build web --release --base-href "/new/"
if ($LASTEXITCODE -eq 0) {
    Copy-Item web/.htaccess build/web/.htaccess -Force
    Write-Host "Build complete! Upload contents of build/web/ to Hostinger public_html/new/" -ForegroundColor Green
} else {
    Write-Host "Build failed with exit code $LASTEXITCODE" -ForegroundColor Red
}
