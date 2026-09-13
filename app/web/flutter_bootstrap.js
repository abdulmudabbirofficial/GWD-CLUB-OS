// Custom bootstrap, so the renderer is loaded from this server rather than a CDN.
//
// Flutter's default `canvasKitBaseUrl` points at gstatic.com. That is wrong
// twice over here:
//
//   1. The club's backend runs on a laptop on the college Wi-Fi and has to keep
//      working when the internet does not. An app that will not paint without
//      reaching Google is not a LAN app.
//   2. Fetching executable code from a third-party origin is exactly what the
//      site's Content Security Policy forbids, so the default silently renders
//      a blank page with the script blocked and nothing in the server log.
//
// The CanvasKit files are already produced into build/web/canvaskit/, so this
// only points at what is there.
//
// It has to be done here rather than in an inline `<script>` setting
// `window.flutterConfiguration`: that global was removed, and inline scripts
// are blocked by the CSP anyway. `_flutter.loader.load({config})` is the
// supported path, and this file is served from the app's own origin.
//
// The two placeholders are substituted by `flutter build web`. Leave them.
{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  config: {
    canvasKitBaseUrl: 'canvaskit/',
  },
  serviceWorkerSettings: {
    serviceWorkerVersion: {{flutter_service_worker_version}},
  },
});
