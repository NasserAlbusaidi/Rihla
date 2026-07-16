(function () {
  // Generic "Get the app" links default to Google Play; on Apple devices
  // point them at the App Store instead. Explicitly labelled store buttons
  // keep their store. Runs before campaign.js so rewritten links are no
  // longer play.google.com and skip Play-referrer decoration.
  var ua = navigator.userAgent;
  var isApple =
    /iPhone|iPad|iPod/.test(ua) ||
    (ua.indexOf('Macintosh') !== -1 && navigator.maxTouchPoints > 1);
  if (!isApple) return;

  document.querySelectorAll('a[data-store-auto]').forEach(function (link) {
    link.href = 'https://apps.apple.com/app/id6788822382';
  });
})();
