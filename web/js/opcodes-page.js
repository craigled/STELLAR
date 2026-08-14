// Renders the opcode reference from window.STELLAR_OPCODES / _GROUPS.
(function () {
  var OPS = window.STELLAR_OPCODES || [];
  var GROUPS = window.STELLAR_OPCODE_GROUPS || [];
  var listEl = document.getElementById('list');
  var qEl = document.getElementById('q');
  var countEl = document.getElementById('count');
  var chipsEl = document.getElementById('chips');

  var activeGroup = null; // null = all

  // group chips
  var allChip = chip('all', 'All', null);
  allChip.classList.add('on');
  chipsEl.appendChild(allChip);
  GROUPS.forEach(function (g) { chipsEl.appendChild(chip(g[0], g[1], g[2])); });

  function chip(id, label, range) {
    var b = document.createElement('button');
    b.className = 'chip'; b.dataset.g = id === 'all' ? '' : id;
    b.innerHTML = label + (range ? ' <span class="mono" style="opacity:.6">' + range + '</span>' : '');
    b.addEventListener('click', function () {
      activeGroup = (id === 'all') ? null : id;
      [].forEach.call(chipsEl.children, function (c) { c.classList.remove('on'); });
      b.classList.add('on');
      render();
    });
    return b;
  }

  function hx(op) { return '$' + op.toString(16).toUpperCase().padStart(2, '0'); }
  function esc(s) { return (s || '').replace(/[&<>]/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]; }); }

  function render() {
    var q = (qEl.value || '').trim().toLowerCase();
    var groupName = {};
    GROUPS.forEach(function (g) { groupName[g[0]] = g; });

    var byGroup = {};
    var shown = 0;
    OPS.forEach(function (o) {
      if (activeGroup && o.group !== activeGroup) return;
      if (q) {
        var hay = (hx(o.op) + ' ' + o.name + ' ' + o.operands + ' ' + o.desc).toLowerCase();
        if (hay.indexOf(q) === -1) return;
      }
      (byGroup[o.group] = byGroup[o.group] || []).push(o);
      shown++;
    });

    var html = '';
    GROUPS.forEach(function (g) {
      var rows = byGroup[g[0]];
      if (!rows || !rows.length) return;
      html += '<div class="op-group"><h3>' + esc(g[1]) +
        '<span class="rng">' + esc(g[2]) + '</span></h3>';
      rows.forEach(function (o) {
        var len = o.length < 0 ? 'var' : o.length + 'b';
        html += '<div class="op-row" id="op-' + o.op.toString(16).toUpperCase().padStart(2, '0') + '">' +
          '<div class="oc">' + hx(o.op) + '</div>' +
          '<div class="nm">' + esc(o.name) + ' <span class="muted small" style="font-weight:400">' + len + '</span></div>' +
          '<div class="ops">' + (esc(o.operands) || '—') + '</div>' +
          '<div class="ds">' + esc(o.desc) + '</div>' +
          '</div>';
      });
      html += '</div>';
    });
    listEl.innerHTML = html || '<p class="muted">No opcodes match.</p>';
    countEl.textContent = shown + ' of ' + OPS.length + ' opcodes';

    // if navigated with a #hash, reveal it
    if (location.hash) {
      var t = document.getElementById(location.hash.slice(1));
      if (t) t.scrollIntoView({ block: 'center' });
    }
  }

  qEl.addEventListener('input', render);
  window.addEventListener('hashchange', function () {
    var t = document.getElementById(location.hash.slice(1));
    if (t) t.scrollIntoView({ block: 'center' });
  });
  render();
})();
