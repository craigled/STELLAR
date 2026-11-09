// Copyright (C) 2026 Craig Ledbetter
// SPDX-License-Identifier: GPL-3.0-or-later
// The smallest MCP client: starts server.mjs, does the handshake, and calls tools one at a time. For the
// test and the example session.
import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

export async function connect() {
  const child = spawn(process.execPath, [join(dirname(fileURLToPath(import.meta.url)), 'server.mjs')],
                      { stdio: ['pipe', 'pipe', 'inherit'] });
  const waiting = new Map();
  let next = 1;
  createInterface({ input: child.stdout }).on('line', line => {
    const msg = JSON.parse(line), w = waiting.get(msg.id);
    if (w) { waiting.delete(msg.id); w(msg); }
  });
  const request = (method, params) => new Promise(ok => {
    const id = next++;
    waiting.set(id, ok);
    child.stdin.write(JSON.stringify({ jsonrpc: '2.0', id, method, params }) + '\n');
  });
  const init = (await request('initialize', { protocolVersion: '2025-06-18', capabilities: {},
                                              clientInfo: { name: 'elf2k-client', version: '0.1.0' } })).result;
  child.stdin.write(JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized' }) + '\n');
  return {
    init,
    request,
    tools: async () => (await request('tools/list', {})).result.tools,
    // -> { text, data, isError }
    call: async (name, args) => {
      const r = (await request('tools/call', { name, arguments: args || {} })).result;
      return { text: r.content[0].text, data: (r._meta && r._meta.elf2k) || {}, isError: !!r.isError };
    },
    close: () => child.stdin.end()
  };
}
