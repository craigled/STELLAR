// Copyright (C) 2026 Craig Ledbetter
// SPDX-License-Identifier: GPL-3.0-or-later
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

  // The worked examples (js/opcode-examples.js, built by build/gen_opcode_examples.js): each
  // ran on the firmware. An opcode's list opens under its row; the tables are only made
  // when it opens, as there are hundreds of them.
  var EX = window.STELLAR_OP_EXAMPLES || [], byOp = {}, open = {}, whole = [];
  EX.forEach(function (e) {
    if (!e.ops.length) whole.push(e);
    e.ops.forEach(function (o) { (byOp[o] = byOp[o] || []).push(e); });
  });
  function exampleHtml(e) {
    var h = '<article class="ex"><h4>' + esc(e.title);
    if (e.fix) h += ' <span class="ex-tag ex-fixed">Corrected</span>';
    else if (e.src === 'new') h += ' <span class="ex-tag ex-new">New</span>';
    h += '</h4>';
    if (e.note) h += '<p class="ex-note">' + esc(e.note) + '</p>';
    h += '<div class="ex-scroll"><table class="ex-t"><thead><tr><th>Text you enter</th><th>Assembly</th><th>Explanation</th></tr></thead><tbody>';
    e.lines.forEach(function (l) {
      h += '<tr><td class="ex-d">D ' + l.a + ' ' + l.b + '</td><td class="ex-m">' + esc(l.m) + '</td><td>' + esc(l.c) + '</td></tr>';
    });
    h += '</tbody></table></div>';
    var r = e.result.slice();
    if (e.loop) r.push('Runs until you stop it');
    if (r.length) h += '<p class="ex-res"><b>On the firmware:</b> ' + r.map(esc).join(' · ') + '</p>';
    if (e.fix) h += '<p class="ex-fix"><b>Corrected:</b> ' + esc(e.fix) + '</p>';
    return h + '</article>';
  }
  function examples(key, list) {
    if (!open[key]) return '';
    return '<div class="ex-box"><div class="ex-list">' + list.map(exampleHtml).join('') + '</div></div>';
  }
  // The text that opens and closes a set of examples.
  function exLink(key, cls, text) {
    return '<button type="button" class="' + cls + ' ex-link" data-ex="' + key + '" aria-expanded="' + !!open[key] + '">' + esc(text) + '</button>';
  }
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
        var key = o.op.toString(16).toUpperCase().padStart(2, '0');
        html += '<div class="op-row" id="op-' + key + '">' +
          '<div class="oc">' + hx(o.op) + '</div>' +
          '<div class="nm">' + esc(o.name) + '</div>' +
          '<div class="ops">' + (esc(o.operands) || '—') + '</div>' +
          (byOp[key] ? exLink(key, 'ds', o.desc) : '<div class="ds">' + esc(o.desc) + '</div>') +
          '</div>';
        if (byOp[key]) html += examples(key, byOp[key]);
      });
      html += '</div>';
    });
    if (whole.length && !activeGroup && !q) {
      html += '<div class="op-group"><h3>Whole programs<span class="rng">several opcodes, several VMs</span></h3>' +
        '<div class="op-row whole">' + exLink('all', 'ds', 'Programs that use several opcodes together, some across several VMs') + '</div>' + examples('all', whole) + '</div>';
    }
    listEl.innerHTML = html || '<p class="muted">No opcodes match.</p>';
    countEl.textContent = shown + ' of ' + OPS.length + ' opcodes';

    // if navigated with a #hash, reveal it
    if (location.hash) {
      var t = document.getElementById(location.hash.slice(1));
      if (t) t.scrollIntoView({ block: 'start' });
    }
  }

  listEl.addEventListener('click', function (e) {
    var b = e.target.closest ? e.target.closest('.ex-link') : null;
    if (!b) return;
    var key = b.dataset.ex, y = b.getBoundingClientRect().top;
    open[key] = !open[key];
    render();
    var again = listEl.querySelector('.ex-link[data-ex="' + key + '"]');
    if (again) { window.scrollBy(0, again.getBoundingClientRect().top - y); again.focus({ preventScroll: true }); }
  });
  // A link to one opcode opens its examples.
  function openHash() {
    var m = /^#op-([0-9A-F]{2})$/.exec(location.hash);
    if (m && byOp[m[1]]) open[m[1]] = true;
  }

  qEl.addEventListener('input', render);
  window.addEventListener('hashchange', function () { openHash(); render(); });
  openHash();
  render();
})();
