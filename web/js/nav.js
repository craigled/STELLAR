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
})();
