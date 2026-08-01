param(
    [string]$BackendUrl = "http://127.0.0.1:8000"
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$mobileDir = Join-Path $repoRoot "mobile_app"

Push-Location $mobileDir
try {
    flutter build web `
        --dart-define=APP_ENV=dev `
        --dart-define=BACKEND_BASE_URL=$BackendUrl

    $buildDir = Join-Path $mobileDir "build\web"
    $indexPath = Join-Path $buildDir "index.html"
    $serviceWorkerPath = Join-Path $buildDir "flutter_service_worker.js"
    $cacheBust = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $devBootstrap = @"
  <script>
    (function () {
      function loadFlutter() {
        var script = document.createElement('script');
        script.src = 'flutter_bootstrap.js?v=$cacheBust';
        script.async = true;
        document.body.appendChild(script);
      }

      if (!('serviceWorker' in navigator)) {
        loadFlutter();
        return;
      }

      Promise.all([
        navigator.serviceWorker.getRegistrations()
          .then(function (registrations) {
            return Promise.all(registrations.map(function (registration) {
              return registration.unregister();
            }));
          }),
        window.caches
          ? caches.keys().then(function (keys) {
              return Promise.all(keys.map(function (key) {
                return caches.delete(key);
              }));
            })
          : Promise.resolve()
      ]).finally(loadFlutter);
    })();
  </script>
"@

    $index = Get-Content -LiteralPath $indexPath -Raw
    $index = $index -replace '<script src="flutter_bootstrap\.js" async></script>', $devBootstrap
    Set-Content -LiteralPath $indexPath -Value $index -Encoding UTF8
    if (Test-Path -LiteralPath $serviceWorkerPath) {
        Remove-Item -LiteralPath $serviceWorkerPath -Force
    }
}
finally {
    Pop-Location
}
