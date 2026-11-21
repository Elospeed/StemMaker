/* Danke-Seite nach dem Download (danke.html und de/danke.html).
   Startet den gewählten Download sofort und zählt ihn bei GoatCounter.
   Alle Download-Knöpfe der Projektseite laufen über diese Seite
   (danke.html?f=setup|zip|appimage). Bei jedem Release VERSION anpassen,
   sobald Setup und ZIP am Release hängen; VERSION_APPIMAGE erst, wenn auch
   das AppImage (wird von Hand hochgeladen) dort liegt. */
(function () {
  var VERSION = '2.4';
  var VERSION_APPIMAGE = '2.4';
  function Url(art) {
    var v = art === 'appimage' ? VERSION_APPIMAGE : VERSION;
    var name = { setup: 'StemMaker-' + v + '-Setup.exe', zip: 'StemMaker-' + v + '.zip',
      appimage: 'StemMaker-' + v + '-x86_64.AppImage' }[art];
    return { name: name, url: 'https://github.com/Elospeed/StemMaker/releases/download/v' + v + '/' + name };
  }
  function Gueltig(a) { return a === 'setup' || a === 'zip' || a === 'appimage'; }

  /* Gewählte Datei: aus ?f= (dann Download starten), sonst aus dem
     Verlauf (Zurück-Knopf) oder aus #f (Sprachwechsel), dann ohne Download */
  var m = /[?&]f=([a-z]+)/.exec(location.search);
  var art = m && Gueltig(m[1]) ? m[1] : '';
  var starten = !!art;
  if (!art && history.state && Gueltig(history.state.f)) art = history.state.f;
  if (!art && Gueltig(location.hash.slice(1))) art = location.hash.slice(1);

  /* GoatCounter: nur der echte Download zählt, mit Dateiart
     (z. B. /StemMaker/danke.html?f=setup); Zurück oder Neuladen zählt nicht. */
  window.goatcounter = {
    path: function (p) { return starten ? p.split('?')[0] + '?f=' + art : null; }
  };

  document.documentElement.className += ' ' + (art || 'setup');

  document.addEventListener('DOMContentLoaded', function () {
    var i, el = document.querySelectorAll('[data-datei]');
    for (i = 0; i < el.length; i++) el[i].href = Url(el[i].getAttribute('data-datei')).url;
    el = document.querySelectorAll('[data-dateiname]');
    for (i = 0; i < el.length; i++) el[i].textContent = Url(art || 'setup').name;
    var sprache = document.querySelector('a.lang');
    if (sprache && art) sprache.href = sprache.getAttribute('href').split('#')[0] + '#' + art;
    if (!art) return;
    document.getElementById('nochmal').href = Url(art).url;
    if (!starten) return;
    var titel = document.querySelector('h1[data-laeuft]');
    if (titel) titel.textContent = titel.getAttribute('data-laeuft');
    if (history.replaceState) history.replaceState({ f: art }, '', location.pathname);
  });

  /* Download erst nach "load" starten, damit GoatCounter (async) schon
     gezählt hat; spätestens nach 1,5 s, falls count.js blockiert ist. */
  if (!starten) return;
  var los = false;
  function Start() {
    if (los) return;
    los = true;
    location.href = Url(art).url;
  }
  window.addEventListener('load', function () { setTimeout(Start, 100); });
  setTimeout(Start, 1500);
})();
