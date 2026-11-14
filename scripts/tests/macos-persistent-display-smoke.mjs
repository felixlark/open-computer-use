#!/usr/bin/env node
// Real installed-runtime acceptance; requires two installed copies of the
// MacOSPersistentDisplayFixture, with Web/Native bundle IDs used below.
// Usage: node macos-persistent-display-smoke.mjs <installed-ocu> <evidence-dir> <web-app> <native-app>
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {mkdirSync, readFileSync, writeFileSync, existsSync} from 'node:fs';
import path from 'node:path';
import {JsonLinePeer} from '../node-repl/open-computer-use-repl.mjs';

const [binary, directory, webApp, nativeApp] = process.argv.slice(2);
assert.ok(binary && directory && webApp && nativeApp, 'Expected installed binary, evidence directory and installed fixture apps');
mkdirSync(directory, {recursive:true});
const env = {...process.env};
const webBundle = 'local.ocu.PersistentWebProbe', nativeBundle = 'local.ocu.PersistentNativeProbe';
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
const ad = args => JSON.parse(execFileSync('agent-desktop', args, {env, encoding:'utf8', timeout:15000}));
const fixtureNames={web:'OCU Persistent Web Probe',native:'OCU Persistent Native Probe'};
const windows = (apps=Object.values(fixtureNames)) => apps.flatMap(app=>ad(['list-windows','--app',app]).data).filter(w => w.visible);
const displays = () => ad(['list-displays']).data;
const state = kind => JSON.parse(readFileSync(path.join(directory, `${kind}-state.json`), 'utf8'));
const ownWindow = kind => windows([fixtureNames[kind]]).find(w => w.id === `w-${state(kind).window_id}`);
const peers = [];
const result = {events:[]};
function event(name, data={}) { const item={name,time:Date.now(),...data}; result.events.push(item); console.log(JSON.stringify(item)); }
async function waitUntil(test, message) {
  const end=Date.now()+30000;
  while (!test()) { assert.ok(Date.now()<end,message); await pause(100); }
}
async function connect() {
  const peer = new JsonLinePeer({command:binary,args:['mcp'],env});peers.push(peer);
  const info=await peer.initialize();event('mcp-connected',{version:info.serverInfo.version});return peer;
}
async function snapshot(peer, app, placement='keep') {
  const reply=await peer.request('tools/call',{name:'get_app_state',arguments:{app,window_placement:placement,allow_activation:false,include_screenshot:false}});
  assert.ok(!reply.isError,JSON.stringify(reply));
  return reply.content.filter(c=>c.type==='text').map(c=>c.text).join('\n');
}
function inside(window, display) {
  return window && window.bounds.x >= display.bounds.x && window.bounds.y >= display.bounds.y &&
    window.bounds.x < display.bounds.x+display.bounds.width && window.bounds.y < display.bounds.y+display.bounds.height;
}
function flatten(tree) { return [tree,...(tree.children||[]).flatMap(flatten)]; }

try {
  const beforeDisplays=displays();
  const oldWindows=windows(['Preview','TextEdit']);
  for(const [kind,app] of [['web',webApp],['native',nativeApp]]) {
    const file=path.join(directory,`${kind}-state.json`);
    const previousPID=existsSync(file)?state(kind).pid:null;
    let running=false;
    if(existsSync(file)){try{process.kill(state(kind).pid,0);running=true;}catch{}}
    if(!running) execFileSync('/usr/bin/open',['-g','-a',app,'--args',...(kind==='web'?['--web']:[]),file],{env});
    await waitUntil(()=>existsSync(file) && (running || state(kind).pid!==previousPID),`${kind} fixture did not start`);
  }
  const original = {web:ownWindow('web').bounds,native:ownWindow('native').bounds};
  let first=await connect();
  await snapshot(first,webBundle,'agent_display');
  let display=displays().find(d=>inside(ownWindow('web'),d) && !state('web').physical_displays.map(String).includes(d.id));
  assert.ok(display,'No new virtual display');
  assert.equal(displays().find(d=>d.id===display.id).is_primary,false,'Invisible display became primary');
  let webText=await snapshot(first,webBundle);
  for(let i=0;i<30 && !webText.includes('Example Domain');i++){await pause(200);webText=await snapshot(first,webBundle);}
  assert.match(webText,/Example Domain/,'Web content was not initially available');
  await snapshot(first,nativeBundle,'agent_display');
  assert.ok(inside(ownWindow('web'),display) && inside(ownWindow('native'),display));
  const native=ownWindow('native'),web=ownWindow('web');
  assert.ok(native.bounds.width>=web.bounds.width && native.bounds.height>=web.bounds.height,'Native fixture must cover web fixture');
  first.notify('notifications/turn-ended');await first.request('ping');
  assert.ok(inside(ownWindow('web'),display) && inside(ownWindow('native'),display),'Turn end restored a window');
  first.close();await pause(200);
  assert.ok(inside(ownWindow('web'),display) && inside(ownWindow('native'),display),'Disconnect restored a window');
  event('turn-and-disconnect-retained',{displayID:display.id,webWindow:web.id,nativeWindow:native.id});
  execFileSync(binary,['turn-ended'],{env,timeout:10000});await pause(300);
  assert.ok(inside(ownWindow('web'),display) && inside(ownWindow('native'),display),'CLI Stop hook restored a window');
  const current=windows(['Preview','TextEdit']);
  for(const old of oldWindows) {
    const live=current.find(w=>w.id===old.id);
    // User-controlled physical windows may legitimately move. Verify only the
    // pre-existing hidden display windows, identified by the non-primary layout.
    const oldDisplay=beforeDisplays.find(d=>inside(old,d) && d.bounds.y===0 && d.bounds.x>0 && d.scale===1);
    if(oldDisplay && live) {
      const nowDisplay=displays().find(d=>d.id===oldDisplay.id);
      if(nowDisplay) assert.deepEqual(
        {x:live.bounds.x-nowDisplay.bounds.x,y:live.bounds.y-nowDisplay.bounds.y,width:live.bounds.width,height:live.bounds.height},
        {x:old.bounds.x-oldDisplay.bounds.x,y:old.bounds.y-oldDisplay.bounds.y,width:old.bounds.width,height:old.bounds.height},
        'Namespaced hook moved an old-instance window relative to its display');
    }
  }
  event('namespaced-cli-stop-retained');
  let second=await connect();
  assert.match(await snapshot(second,webBundle),/Example Domain/,'Overlapped web tree disappeared after cleanup');
  const marker=`after-reconnect-${Date.now()}`, expectedCommits=state('native').commits+1;
  const session=ad(['session','start','--name','persistent-display-acceptance','--no-trace']).data.session_id;
  try {
    const run=args=>ad(['--session',session,...args]);
    const tree=run(['snapshot','--app','OCU Persistent Native Probe','--window-id',native.id,'--max-depth','6']);assert.ok(tree.ok,JSON.stringify(tree));
    const field=flatten(tree.data.tree).find(n=>n.role==='textfield' && n.ref_id);assert.ok(field,'Missing native field');
    const edit=run(['set-value',field.ref_id,marker]);assert.ok(edit.ok,JSON.stringify(edit));
    const fresh=run(['snapshot','--app','OCU Persistent Native Probe','--window-id',native.id,'--max-depth','6']);
    const button=flatten(fresh.data.tree).find(n=>n.name==='Commit marker');assert.ok(button,'Missing commit button');
    const click=run(['click',button.ref_id]);assert.ok(click.ok,JSON.stringify(click));
    await waitUntil(()=>state('native').marker===marker && state('native').commits===expectedCommits,'Native commit was not observed');
  } finally { ad(['session','end',session]); }
  event('new-client-semantic-edit-verified');
  // Interleave CLI snapshots (a separate request path) with client teardown.
  for(let i=0;i<3;i++) {
    const transient=await connect();await transient.request('ping');transient.close();
    const output=execFileSync(binary,['snapshot',webBundle,'--include-screenshot','false'],{env,encoding:'utf8',timeout:20000});
    assert.match(output,/Example Domain/);
  }
  assert.match(await snapshot(second,webBundle),/Example Domain/);
  await snapshot(second,nativeBundle,'restore');
  const restored=ownWindow('native');
  assert.ok(!inside(restored,display),'Explicit restore left native window hidden');
  assert.ok(displays().some(d=>state('native').physical_displays.map(String).includes(d.id) && inside(restored,d)),'Restore did not reach a user display');
  await snapshot(second,webBundle,'restore');
  // A released/unmanaged window (including a floating panel) may still own this
  // display. Only actual empty-screen observation permits idle destruction.
  assert.ok(!inside(ownWindow('web'),display),'Last explicit restore left the web receiver hidden');
  await waitUntil(()=>state('native').physical_displays.includes(state('native').main_display),'After display removal main was not physical');
  await snapshot(second,webBundle,'agent_display');
  display=displays().find(d=>inside(ownWindow('web'),d) && !state('web').physical_displays.map(String).includes(d.id));assert.ok(display);
  await snapshot(second,nativeBundle,'agent_display');
  second.notify('notifications/turn-ended');await second.request('ping');second.close();await pause(200);
  assert.ok(inside(ownWindow('native'),display));
  const third=await connect();assert.match(await snapshot(third,webBundle),/Example Domain/);third.close();
  event('explicit-restore-and-repark-verified');
  result.ok=true;result.display=display;result.original=original;
} finally {
  for(const peer of peers)peer.close();
  writeFileSync(path.join(directory,'result.json'),JSON.stringify(result,null,2)+'\n');
}
