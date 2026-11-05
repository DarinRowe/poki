import test from 'node:test';
import assert from 'node:assert/strict';
import {setImmediate} from 'node:timers/promises';
import {Client} from '@modelcontextprotocol/client';
import {McpServer, InMemoryTransport} from '@modelcontextprotocol/server';
import {z} from 'zod';
import {PokiClient} from '../poki-client.mjs';

test('Phone calls finish within 30 seconds or cancel the pending MCP request', async t => {
  const server = new McpServer({name:'timeout-fixture',version:'1'});
  let started, cancelled = false;
  server.registerTool('wait_fixture', {inputSchema:z.object({delay:z.number().optional()})}, async (args, extra) => {
    started?.();
    return await new Promise(resolve => {
      if (args.delay !== undefined) setTimeout(() => resolve({content:[{type:'text',text:'finished'}]}),args.delay);
      (extra.mcpReq?.signal ?? extra.signal).addEventListener('abort', () => {
        cancelled = true;
        resolve({isError:true,content:[{type:'text',text:'cancelled'}]});
      }, {once:true});
    });
  });
  const phone = new PokiClient();
  phone.client = new Client({name:'timeout-client',version:'1'});
  const [clientTransport,serverTransport] = InMemoryTransport.createLinkedPair();
  t.after(async () => {await phone.close();await server.close();});
  await Promise.all([server.connect(serverTransport),phone.client.connect(clientTransport)]);
  t.mock.timers.enable({apis:['setTimeout']});
  let ready = new Promise(resolve => {started=resolve;});
  const fast = phone.call('wait_fixture',{delay:29999});
  await ready;
  t.mock.timers.tick(29999);
  assert.equal((await fast).content[0].text,'finished');
  assert.equal(cancelled,false);
  ready = new Promise(resolve => {started=resolve;});
  let outcome;
  const slow = phone.call('wait_fixture').then(result => {outcome={result};},error => {outcome={error};});
  await ready;
  t.mock.timers.tick(29999);
  await setImmediate();
  assert.equal(outcome,undefined,'Do not time out before the 30 second limit');
  t.mock.timers.tick(1);
  await setImmediate();
  assert.ok(outcome?.error,'An unfinished request must fail at 30 seconds');
  assert.match(outcome.error.message,/timed out|timeout/i);
  assert.equal(cancelled,true,'The MCP server must receive cancellation');
  await slow;
});
