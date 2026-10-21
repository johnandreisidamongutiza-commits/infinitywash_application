// Public HTTPS page for rendering the Turnstile challenge in native WebViews.
// Deploy with JWT verification disabled because this page is loaded directly
// by the app's WebView before the user is authenticated.
const SITE_KEY = "0x4AAAAAAFfDP6su1SdD_bk-"

const HTML = `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>InfinityWash security check</title>
  <style>
    html, body { margin: 0; padding: 0; background: transparent; }
    body { min-height: 68px; display: flex; justify-content: center; align-items: center; }
  </style>
  <script>
    let widgetId;
    let errorRetries = 0;
    function turnstileReady() {
      widgetId = turnstile.render('#turnstile', {
        sitekey: '${SITE_KEY}',
        action: 'password_reset',
        callback: function(token) { Turnstile.postMessage(token); },
        'expired-callback': function() { Turnstile.postMessage(''); },
        'error-callback': function() {
          Turnstile.postMessage('');
          if (errorRetries++ < 2) {
            setTimeout(function() { turnstile.reset(widgetId); }, 1500);
          }
        }
      });
    }
  </script>
  <script src="https://challenges.cloudflare.com/turnstile/v0/api.js?onload=turnstileReady" defer></script>
</head>
<body>
  <div id="turnstile"></div>
</body>
</html>`

Deno.serve((req) => {
  if (req.method !== "GET") {
    return new Response("Method not allowed", { status: 405 })
  }
  return new Response(HTML, {
    status: 200,
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
    },
  })
})
