// StellarMachine: the always-running machine behind the home page.
//
// It is the same emulator as everywhere else on the site (StellarVMLib.CPU running
// the real firmware image, cold-booted through CIDP by MultiVM), with the
// instrumentation a visualisation needs and a debugger does not:
//
//   * a CLOCK. Every 1802 instruction is charged its machine cycles (8 clocks
//     each), so the page can run at exactly the speed of Craig's 3 MHz Elf2K, or
//     any multiple of it, and say how long the same work takes on the hardware.
//   * HEAT. The address of every instruction fetched is marked in a 32 KB heat
//     map, tagged with the VM being served; memory WRITES are found by diffing
//     against a shadow copy once per frame. That is what lights the die picture.
//   * PER-VM SERIAL. There is one UART. Each byte written to it is tagged with
//     the VM that was running when it went out, so four programs can have four
//     screens. Keystrokes are queued per VM and only handed to that VM's SERIN.
//     On the real Elf2K all four would share one terminal - the page says so.
//   * SLICES. Every change of running VM is logged, for the scheduler timeline.
//   * TRACE. For one chosen VM, the address of every 1802 instruction executed
//     on its behalf, cut into segments at each STELLAR opcode boundary (the core
//     command counter at core+$33..$36 ticks once per opcode).
(function (root, factory) {
  var api = factory();
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  if (typeof window !== 'undefined') window.StellarMachine = api;
})(this, function () {
  'use strict';

  var LIB = (typeof window !== 'undefined' && window.StellarVMLib) || require('./stellar-vm.js');
  var COS = (typeof window !== 'undefined' && window.Cosmac) || require('./cosmac.js');

  var CLOCK_HZ = 3000000;               // Craig's Elf2K
  var CYCLES_PER_SEC = CLOCK_HZ / 8;    // 1802 machine cycle = 8 clocks
  var RAM = 0x8000;                      // the die shows the low 32 KB
  var RING = 1 << 16;                    // trace ring (traced VM only)
  var SLICES = 1024;

  // cycles per opcode byte for the base ISA; $68 is resolved per instruction
  var CYC = new Uint8Array(256);
  for (var i = 0; i < 256; i++) CYC[i] = ((i & 0xF0) === 0xC0) ? 3 : 2;

  function coreBase(vm) { return 0x3000 + (vm - 1) * 0x400; }

  // programs: [{ text: lstText, input: 'keys to pre-queue' }, ...] (1-4)
  function Machine(opts) {
    this.firmware = opts.firmware || (typeof window !== 'undefined' && window.STELLAR_FIRMWARE);
    this.programs = opts.programs;
    this.traceVM = opts.traceVM || 1;
    this.reset();
  }

  Machine.prototype.reset = function () {
    var self = this;
    // Each program is a VM1 .lst ($4000-$4FFF) that MultiVM moves up into its own block. Only
    // the bytes inside that block are kept: the "D X000 00" claim lines at the end of every .lst
    // would otherwise land on the blocks above once it is moved, and a RUN after the program
    // finishes (which reloads it) would clear the running VMs' START bytes and stop them.
    this.mvm = new LIB.MultiVM({
      firmware: this.firmware,
      // each program keeps its own block - or blocks: a SETSIZE 2 app (Life Lab) sits in VM1 and
      // keeps $5000-$5FFF too, and VM2's slot is then empty ({ text: '' }), as on the Elf2K
      programs: this.programs.map(function (p) {
        var end = 0x4000 + (p.blocks || 1) * 0x1000;
        return p.text ? LIB.parseLst(p.text).filter(function (q) { return q[0] >= 0x4000 && q[0] < end; }) : [];
      })
    });
    var c = this.cpu = this.mvm.cpu, M = this.M = c.M;
    // per-VM keyboard: SERIN in VM n only ever sees VM n's keys
    this.keys = [[], [], [], [], []];
    this.programs.forEach(function (p, i) {
      var s = p.input || '';
      for (var k = 0; k < s.length; k++) self.keys[i + 1].push(s.charCodeAt(k) & 0xFF);
    });
    var keys = this.keys;
    c.io_in[3] = { pop: function () {
      var sel2 = c.io_out[2], sel = sel2 && sel2.length ? sel2[sel2.length - 1] : null;
      var q = keys[M[0x2F52]] || [];
      if (sel === 0x15) return 0x20 | (q.length ? 1 : 0);
      if (sel === 0x10) return q.length ? q.shift() : 0;
      return 0;
    } };
    this.out = [[], [], [], [], []];        // undrained serial bytes per VM
    this.heat = new Uint8Array(RAM);         // exec heat 0-255
    this.heatVM = new Uint8Array(RAM);       // which VM the fetch was for
    this.wheat = new Uint8Array(RAM);        // write heat
    this.shadow = new Uint8Array(RAM);
    this.cycles = 0; this.instr = 0;
    this.vmCycles = new Float64Array(5);
    this.sliceVM = new Uint8Array(SLICES);
    this.sliceCyc = new Uint32Array(SLICES);
    this.sliceHead = 0; this.sliceCount = 0;
    this.curSliceVM = 0; this.curSliceCyc = 0;
    this.ring = new Uint16Array(RING); this.ringN = 0;   // monotonically increasing index
    this.ops = [];                                       // completed opcode records (traced VM)
    this.opCount = 0;
    this.mvm.bootUntilReady();
    // what a VM looks like before its first opcode - RUN puts a finished VM back to this
    this.bootSnap = {
      cores: M.slice(0x3000, 0x4000),        // all four 1KB VM cores
      cidp: M.slice(0x2F00, 0x2F60),         // the four entries and the system bytes
      cpu: { R: Array.prototype.slice.call(c.R), D: c.D, DF: c.DF, X: c.X, P: c.P, T: c.T, Q: c.Q, IE: c.IE }
    };
    this.shadow.set(M.subarray(0, RAM));
    this._ccAddr = coreBase(this.traceVM) + 0x36;
    this._cc = M[this._ccAddr];
    this._opStart = this.ringN;
    this._opPL = this._pl(this.traceVM);
  };

  Machine.prototype._pl = function (vm) {
    var b = coreBase(vm);
    return (this.M[b + 0x31] << 8) | this.M[b + 0x32];
  };

  Machine.prototype.setTraceVM = function (vm) {
    this.traceVM = vm;
    this._ccAddr = coreBase(vm) + 0x36;
    this._cc = this.M[this._ccAddr];
    this._opStart = this.ringN;
    this._opPL = this._pl(vm);
    this.ops = [];
  };

  // Run until `budget` machine cycles are used, the wall clock passes
  // `deadline` (performance.now() ms), or the machine halts.
  Machine.prototype.run = function (budget, deadline) {
    var c = this.cpu, M = this.M, R = c.R;
    var heat = this.heat, heatVM = this.heatVM, ring = this.ring, out = this.out;
    var tvm = this.traceVM, ccAddr = this._ccAddr;
    var used = 0, n = 0, ringN = this.ringN;
    var sliceVM = this.curSliceVM, sliceCyc = this.curSliceCyc;
    var o3 = c.io_out[3] || (c.io_out[3] = []);
    var now = (typeof performance !== 'undefined') ? function () { return performance.now(); } : Date.now;
    while (used < budget) {
      var cur = M[0x2F52], pc = R[c.P], op = M[pc];
      var cyc = op === 0x68 ? COS.cycles(M, pc) : CYC[op];
      if (pc < RAM) { heat[pc] = 255; heatVM[pc] = cur; }
      if (cur === tvm) { ring[ringN & (RING - 1)] = pc; ringN++; }
      if (!c.step()) { this.halted = true; break; }
      used += cyc; n++;
      this.vmCycles[cur] += cyc;
      if (cur !== sliceVM) {
        this._pushSlice(sliceVM, sliceCyc);
        sliceVM = cur; sliceCyc = 0;
      }
      sliceCyc += cyc;
      if (o3.length) {
        var q = out[cur] || out[0];
        for (var k = 0; k < o3.length; k++) q.push(o3[k]);
        o3.length = 0;
      }
      if (cur === tvm && M[ccAddr] !== this._cc) {
        this._cc = M[ccAddr];
        this._closeOp(ringN);
      }
      if ((n & 4095) === 0 && deadline && now() > deadline) break;
    }
    this.ringN = ringN;
    this.curSliceVM = sliceVM; this.curSliceCyc = sliceCyc;
    this.cycles += used; this.instr += n;
    var o2 = c.io_out[2]; if (o2 && o2.length > 64) o2.splice(0, o2.length - 8);
    for (var p in c.io_out) {
      if (p !== '2' && p !== '3' && c.io_out[p].length > 256) c.io_out[p].splice(0, c.io_out[p].length - 16);
    }
    return used;
  };

  Machine.prototype._pushSlice = function (vm, cyc) {
    if (!cyc) return;
    this.sliceVM[this.sliceHead] = vm;
    this.sliceCyc[this.sliceHead] = cyc;
    this.sliceHead = (this.sliceHead + 1) % SLICES;
    if (this.sliceCount < SLICES) this.sliceCount++;
  };

  // Last `n` slices, oldest first, including the one in progress.
  Machine.prototype.recentSlices = function (n) {
    var out = [], cnt = Math.min(n - 1, this.sliceCount);
    for (var i = cnt; i >= 1; i--) {
      var j = (this.sliceHead - i + SLICES) % SLICES;
      out.push([this.sliceVM[j], this.sliceCyc[j]]);
    }
    out.push([this.curSliceVM, this.curSliceCyc]);
    return out;
  };

  Machine.prototype._closeOp = function (ringN) {
    var pl = this._opPL, M = this.M;
    this.ops.push({ pl: pl, op: M[pl], start: this._opStart, end: ringN, n: this.opCount++ });
    if (this.ops.length > 64) this.ops.shift();
    this._opStart = ringN;
    this._opPL = this._pl(this.traceVM);
  };

  // The 1802 program counter values of one opcode record, or null if the ring
  // has already overwritten them.
  Machine.prototype.opTrace = function (rec) {
    if (this.ringN - rec.start > RING) return null;
    var a = [];
    for (var i = rec.start; i < rec.end; i++) a.push(this.ring[i & (RING - 1)]);
    return a;
  };

  // Find memory written since the last call and mark it hot.
  Machine.prototype.sampleWrites = function () {
    var M = this.M, sh = this.shadow, w = this.wheat;
    for (var a = 0; a < RAM; a++) {
      var v = M[a];
      if (v !== sh[a]) { sh[a] = v; w[a] = 255; }
    }
  };

  Machine.prototype.drain = function (vm) {
    var q = this.out[vm];
    if (!q.length) return null;
    var b = q.slice(); q.length = 0;
    return b;
  };

  Machine.prototype.sendKeys = function (vm, bytes) {
    for (var i = 0; i < bytes.length; i++) this.keys[vm].push(bytes[i]);
  };

  // Commands executed so far by VM n (its core's own counter).
  Machine.prototype.vmOps = function (vm) {
    var M = this.M, b = coreBase(vm) + 0x33;
    return M[b] * 0x1000000 + (M[b + 1] << 16) + (M[b + 2] << 8) + M[b + 3];
  };
  // Single-step the clock: run until any VM's opcode counter (core+$33) moves on,
  // i.e. exactly one STELLAR opcode has completed - whichever VM holds the CPU.
  // Returns the VM that ran it, or 0 if nothing completed (halted, or all idle).
  Machine.prototype.stepOpcode = function () {
    var before = [0, this.vmOps(1), this.vmOps(2), this.vmOps(3), this.vmOps(4)];
    for (var guard = 0; guard < 400000 && !this.halted; guard++) {
      this.run(1);
      for (var v = 1; v <= 4; v++) if (this.vmOps(v) !== before[v]) return v;
    }
    return 0;
  };

  // A finished VM ($00 done, $05 killed, $06 stopped on error) can be RUN again.
  Machine.prototype.vmFinished = function (vm) {
    if (vm < 1 || vm > this.programs.length) return false;
    var st = this.vmState(vm);
    return st === 0x00 || st === 0x05 || st === 0x06;
  };

  // RUN: start a finished VM's program again from the top, the others undisturbed.
  // Reload its bytes into its own 4KB block (the app may have written over its data),
  // put its core and CIDP entry back as they were after the cold boot, and re-queue its
  // preset input. The firmware changes nothing else when a VM finishes - the system
  // bytes at $2F50 stay as they were - so the scheduler simply finds it active again.
  // If EVERY VM had finished, the 1802 left the scheduler through R1; it is put back
  // where it stood after the boot, which is inside the scheduler.
  Machine.prototype.rerun = function (vm) {
    if (!this.vmFinished(vm)) return false;
    var M = this.M, snap = this.bootSnap, off = (vm - 1) * 0x1000, c = this.cpu;
    this.mvm.programs[vm - 1].forEach(function (p) { M[(p[0] + off) & 0xFFFF] = p[1]; });
    var core = (vm - 1) * 0x400;
    M.set(snap.cores.subarray(core, core + 0x400), 0x3000 + core);
    M.set(snap.cidp.subarray((vm - 1) * 16, vm * 16), 0x2F00 + (vm - 1) * 16);
    if (this.halted) {
      M.set(snap.cidp.subarray(0x50, 0x60), 0x2F50);
      for (var i = 0; i < 16; i++) c.R[i] = snap.cpu.R[i];
      ['D', 'DF', 'X', 'P', 'T', 'Q', 'IE'].forEach(function (k) { c[k] = snap.cpu[k]; });
      c.halted = false; this.halted = false;
    }
    var q = this.keys[vm], s = this.programs[vm - 1].input || '';
    q.length = 0;
    for (var k = 0; k < s.length; k++) q.push(s.charCodeAt(k) & 0xFF);
    this.out[vm].length = 0;
    return true;
  };

  Machine.prototype.vmState = function (vm) { return this.M[0x2F00 + (vm - 1) * 0x10 + 5]; };
  Machine.prototype.currentVM = function () { return this.M[0x2F52]; };

  Machine.CLOCK_HZ = CLOCK_HZ;
  Machine.CYCLES_PER_SEC = CYCLES_PER_SEC;
  Machine.RAM = RAM;
  Machine.coreBase = coreBase;
  return Machine;
});
