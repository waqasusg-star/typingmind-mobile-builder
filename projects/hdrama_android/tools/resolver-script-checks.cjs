const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const path = require('node:path');
const kotlin = fs.readFileSync(path.join(__dirname, '../app/src/main/java/com/waqas/hdrama/ResolverScripts.kt'), 'utf8');
function script(name) {
  const body = kotlin.slice(kotlin.indexOf('val '+name+' = """')).split('"""')[1];
  return body.trim().replaceAll("${'$'}", '$');
}
function fixture() {
  let time=5000, clicks=0, response={ok:true,url:'https://media.example/play?id=1',headers:{get:()=> 'application/vnd.apple.mpegurl; charset=UTF-8'}};
  const videos=[], resources=[];
  class XHR {
    constructor() {this.status=200;this.responseURL='https://media.example/xhr';this.events={};}
    addEventListener(k,fn) {this.events[k]=fn;}
    getResponseHeader() {return 'application/dash+xml';}
    send() {this.sent=true;}
  }
  const context={URL,XMLHttpRequest:XHR,Date:{now:()=>time},window:{fetch:async()=>response},
    location:{href:'https://en.hdrama.net/series/story/episode-1'},
    performance:{getEntriesByType:()=>resources},document:{title:'Story',readyState:'complete',
      querySelectorAll:()=>videos,querySelector:()=>({click(){clicks++;}})}};
  vm.createContext(context);vm.runInContext(script('observe'),context);
  return {context,videos,resources,response,setTime(x){time=x;},get clicks(){return clicks;},inspect(){return JSON.parse(vm.runInContext(script('inspect'),context));}};
}
let passed=0;
async function test(name,fn) {await fn();passed++;console.log('PASS '+name);}
(async()=>{
await test('Blob HLS video resolves from extensionless fetch response MIME',async()=>{
 const f=fixture();f.videos.push({currentSrc:'blob:https://en.hdrama.net/id',src:'blob:https://en.hdrama.net/id',paused:false,querySelectorAll:()=>[]});
 const r=await f.context.window.fetch('https://media.example/play?id=1');
 assert.equal(r,f.response);assert.equal(f.inspect().sources[0].url,f.response.url);assert.equal(f.clicks,0);
});
await test('XHR response metadata captures DASH without altering the request',()=>{
 const f=fixture();const xhr=new f.context.XMLHttpRequest();xhr.send('body');assert.equal(xhr.sent,true);xhr.events.load();
 assert.equal(f.inspect().sources[0].mimeType,'application/dash+xml');
});
await test('Premature Play is retried after hydration with throttling',()=>{
 const f=fixture();f.inspect();assert.equal(f.clicks,1);f.setTime(5600);f.inspect();assert.equal(f.clicks,1);
 f.setTime(7000);f.inspect();assert.equal(f.clicks,2);
 f.videos.push({currentSrc:'blob:https://en.hdrama.net/id',src:'',paused:false,querySelectorAll:()=>[]});
 f.setTime(9000);f.inspect();assert.equal(f.clicks,2);
});
await test('The loading document is not clicked',()=>{
 const f=fixture();f.context.document.readyState='loading';f.inspect();assert.equal(f.clicks,0);
});
await test('A blob currentSrc does not hide a direct source child',()=>{
 const f=fixture();f.videos.push({currentSrc:'blob:https://en.hdrama.net/id',src:'',paused:true,querySelectorAll:()=>[{src:'https://media.example/direct',type:'video/mp4'}]});
 assert.equal(f.inspect().sources[0].url,'https://media.example/direct');assert.equal(f.inspect().sources[0].mimeType,'video/mp4');
});
await test('Late injection discovers earlier playlist resources',()=>{
 const f=fixture();f.resources.push({name:'https://media.example/master.m3u8?token=1'},{name:'https://media.example/segment.ts'});
 assert.equal(f.inspect().sources.length,1);assert.equal(f.clicks,0);
});
await test('Unsuccessful or non-media responses are not captured',async()=>{
 const f=fixture();f.response.headers.get=()=> 'application/json';await f.context.window.fetch('/api');assert.equal(f.inspect().sources.length,0);
 f.response.ok=false;f.response.headers.get=()=> 'video/mp4';await f.context.window.fetch('/api');assert.equal(f.inspect().sources.length,0);
});
await test('Install once, preserve fetch rejection and report access checks',async()=>{
 const f=fixture();const fetch=f.context.window.fetch;vm.runInContext(script('observe'),f.context);assert.equal(f.context.window.fetch,fetch);
 f.context.document.title='Just a moment...';assert.equal(f.inspect().blocked,true);
 const error=new Error('offline');f.context.window={fetch:async()=>{throw error;}};vm.runInContext(script('observe'),f.context);
 await assert.rejects(f.context.window.fetch('/api'),e=>e===error);
});
console.log(passed+' resolver script checks passed.');
})().catch(e=>{console.error(e);process.exitCode=1;});
