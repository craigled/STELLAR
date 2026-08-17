// Shared top nav + theme toggle. Include on every page with <script src="js/nav.js"></script>.
(function () {
  var TABS = [
    ['index.html',        'Overview'],
    ['architecture.html', 'Architecture'],
    ['core.html',         'VM Core'],
    ['scheduler.html',    'Multitasking'],
    ['opcodes.html',      'Opcodes'],
    ['simulator.html',    'Simulator'],
  ];
  var here = (location.pathname.split('/').pop() || 'index.html').toLowerCase();

  // theme: persist choice; default = system
  var saved = localStorage.getItem('stellar-theme');
  if (saved === 'light' || saved === 'dark') document.documentElement.setAttribute('data-theme', saved);

  var nav = document.createElement('nav');
  nav.className = 'nav';
  var inner = document.createElement('div');
  inner.className = 'nav-inner';
  inner.innerHTML = '<a class="brand" href="index.html">STELLAR<span class="dot">·</span>VM</a>';
  TABS.forEach(function (t) {
    var a = document.createElement('a');
    a.className = 'tab' + (t[0] === here ? ' active' : '');
    a.href = t[0]; a.textContent = t[1];
    inner.appendChild(a);
  });
  var sp = document.createElement('span'); sp.className = 'spacer'; inner.appendChild(sp);
  var btn = document.createElement('button');
  btn.className = 'theme-btn'; btn.type = 'button';
  function label() {
    var t = document.documentElement.getAttribute('data-theme');
    btn.textContent = t === 'dark' ? '☾ dark' : t === 'light' ? '☀ light' : '◐ auto';
  }
  btn.addEventListener('click', function () {
    var cur = document.documentElement.getAttribute('data-theme');
    var next = cur === 'dark' ? 'light' : cur === 'light' ? '' : 'dark';
    if (next) { document.documentElement.setAttribute('data-theme', next); localStorage.setItem('stellar-theme', next); }
    else { document.documentElement.removeAttribute('data-theme'); localStorage.removeItem('stellar-theme'); }
    label();
  });
  label();
  inner.appendChild(btn);
  nav.appendChild(inner);
  document.body.insertBefore(nav, document.body.firstChild);

  // Build stamp in the footer. The pages version their css/js with ?v=N to defeat
  // browser caching; this reads the version off this script's own URL, so what it
  // shows is the build actually loaded — not what the file on disk says. If a page
  // ever misbehaves, this is the first thing to check: a stamp older than the
  // current build means the browser is serving cached assets.
  var me = document.currentScript || (function () {
    var s = document.getElementsByTagName('script');
    return s[s.length - 1];
  })();
  var m = me && me.src && me.src.match(/[?&]v=(\d+)/);
  var foot = document.querySelector('footer.foot');
  if (foot) {
    var tag = document.createElement('span');
    tag.className = 'mono small';
    tag.style.opacity = '.55';
    tag.style.marginLeft = '8px';
    tag.textContent = ' · build ' + (m ? 'v' + m[1] : 'unversioned');
    foot.appendChild(tag);
  }
})();
