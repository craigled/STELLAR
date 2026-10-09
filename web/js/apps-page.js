// Apps page: a card per showcase app with its real screen (web/apps/apps.json, built by
// web/build/gen_apps.py from the simulator). A card opens the app in the Simulator:
// simulator.html#app=FILE loads it, runs it and enlarges the terminal.
(function () {
  'use strict';
  var grid = document.getElementById('grid'), chips = document.getElementById('chips');
  var ORDER = ['Games', 'Graphics', 'Text', 'Math', 'Multitasking', 'Morse', 'Clock'];

  function esc(s) { return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); }

  // The screen as HTML: 24 rows of 80 columns, reverse-video spans marked.
  function screen(app) {
    var rev = {}, out = [];
    app.rev.forEach(function (r) { rev[r[0]] = r.slice(1); });
    for (var r = 0; r < 24; r++) {
      var line = (app.rows[r] || '');
      var spans = rev[r];
      if (spans) {
        line = line.padEnd(80);
        var html = '', at = 0;
        spans.forEach(function (sp) {
          html += esc(line.slice(at, sp[0])) + '<span class="rv">' + esc(line.slice(sp[0], sp[1])) + '</span>';
          at = sp[1];
        });
        out.push(html + esc(line.slice(at).replace(/\s+$/, '')));
      } else out.push(esc(line) || ' ');          // ' ': an empty last row still takes its height
    }
    return out.join('\n');
  }

  function card(app) {
    var a = document.createElement('a');
    a.className = 'app-card';
    a.href = app.href || ('simulator.html#app=' + encodeURIComponent(app.file));
    a.dataset.group = app.group;
    a.setAttribute('aria-label', app.name + (app.href ? ' - run it on the Multitasking page' : ' - run it in the Simulator'));
    a.innerHTML =
      '<div class="app-shot"><pre class="app-scr" aria-hidden="true">' + screen(app) + '</pre>' +
      '<span class="app-play">&#9654; Run it</span></div>' +
      '<div class="app-txt"><div class="app-h"><h3>' + esc(app.name) + '</h3>' +
      '<span class="app-grp">' + esc(app.group) + '</span></div>' +
      '<p>' + esc(app.desc) + '</p></div>';
    return a;
  }

  function filter(g) {
    Array.prototype.forEach.call(grid.children, function (c) {
      c.hidden = g !== 'All' && c.dataset.group !== g;
    });
    Array.prototype.forEach.call(chips.children, function (b) {
      b.setAttribute('aria-selected', b.textContent.indexOf(g) === 0 ? 'true' : 'false');
    });
    try { history.replaceState(null, '', g === 'All' ? location.pathname : '#' + g.toLowerCase()); } catch (e) {}
  }

  fetch('apps/apps.json?v=118')
    .then(function (r) { return r.json(); })
    .then(function (apps) {
      apps.sort(function (x, y) { return ORDER.indexOf(x.group) - ORDER.indexOf(y.group); });
      apps.forEach(function (a) { grid.appendChild(card(a)); });
      var counts = { All: apps.length };
      apps.forEach(function (a) { counts[a.group] = (counts[a.group] || 0) + 1; });
      ['All'].concat(ORDER.filter(function (g) { return counts[g]; })).forEach(function (g) {
        var b = document.createElement('button');
        b.type = 'button'; b.setAttribute('role', 'tab');
        b.textContent = g + ' ' + counts[g];
        b.addEventListener('click', function () { filter(g); });
        chips.appendChild(b);
      });
      var want = decodeURIComponent(location.hash.slice(1));
      var g = ORDER.filter(function (x) { return x.toLowerCase() === want.toLowerCase(); })[0];
      filter(g || 'All');
    })
    .catch(function (e) { grid.textContent = 'Could not load the app list: ' + e; });
})();
