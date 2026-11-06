const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const path = require('node:path');
const kotlin = fs.readFileSync(path.join(__dirname, '../app/src/main/java/com/waqas/hdrama/BrowserScripts.kt'), 'utf8');
function script(name) {
  const start = kotlin.indexOf('val ' + name + ' = "' + '"' + '"');
  const body = kotlin.slice(start).split('"' + '"' + '"')[1];
  if (!body) throw new Error('Script missing: ' + name);
  return body.trim();
}
const install = script('install');
const inspect = script('inspect');
function fixture(route='/series/story/episode-2') {
  const handlers = {};
  const styles = [];
  const videos = [];
  const footers = [];
  class Element { constructor(play=true) { this.play=play; } closest() { return this.play ? this : null; } }
  const document = {
    title: 'Story Episode 2', head: {appendChild(x) {styles.push(x);}},
    documentElement: {outerHTML:'<h1>Story</h1><a href="/series/story/episode-2">Episode 2</a>'},
    createElement() {return {};}, addEventListener(name, fn) {handlers[name] = fn;},
    querySelectorAll(selector) {return selector.startsWith("nav,") ? footers : videos;}, querySelector() {return {href:'https://en.hdrama.net'+route};}
  };
  const context = {innerHeight:800,innerWidth:360,getComputedStyle:n=>n.style,window:{}, document, Element, location:{pathname:route,href:'https://en.hdrama.net'+route},
    MutationObserver:class {constructor(fn) {handlers.mutation=fn;} observe() {}},
    requestAnimationFrame(fn) {fn();}};
  vm.createContext(context);
  return {context,handlers,styles,videos,footers,Element};
}
function click(f, play=true) {
  const event={target:new f.Element(play),preventDefault() {this.prevented=true;},stopImmediatePropagation() {this.stopped=true;}};
  f.handlers.click(event);return event;
}
let passed=0;
function test(name,fn) {fn();passed++;process.stdout.write('PASS '+name+'\n');}
test('Episode Play requests native handoff and stops website playback handlers',()=>{
 const f=fixture();vm.runInContext(install,f.context);const e=click(f);
 assert.equal(f.context.location.href,'hdrama-native://play');assert.equal(e.prevented,true);assert.equal(e.stopped,true);
});
test('A series Play requests the same native player',()=>{
 const f=fixture('/series/story');vm.runInContext(install,f.context);click(f);
 assert.equal(f.context.location.href,'hdrama-native://play');
});
test('Homepage and ordinary controls retain browser behavior',()=>{
 const f=fixture('/');vm.runInContext(install,f.context);assert.equal(click(f).prevented,undefined);
 const g=fixture();vm.runInContext(install,g.context);assert.equal(click(g,false).prevented,undefined);
});
test('Web video remains silent and paused, including subsequent play attempts',()=>{
 const f=fixture();const v={muted:false,dataset:{},events:{},paused:0,pause() {this.paused++;},removeAttribute(x) {this.removed=x;},addEventListener(k,fn) {this.events[k]=fn;}};
 f.videos.push(v);vm.runInContext(install,f.context);
 assert.equal(v.muted,true);assert.equal(v.removed,'autoplay');assert.equal(v.paused,1);
 v.events.play();assert.equal(v.paused,2);
});
test('DOM cleanup is installed once per document',()=>{
 const f=fixture();vm.runInContext(install,f.context);const listener=f.handlers.click;vm.runInContext(install,f.context);
 assert.equal(f.styles.length,1);assert.equal(f.handlers.click,listener);
});
test('Validated pages use lightweight snapshots; new episodes include HTML',()=>{
 const f=fixture();const cached=inspect.replace('__KNOWN_PAGE__',JSON.stringify(f.context.location.href));
 assert.equal(JSON.parse(vm.runInContext(cached,f.context)).html,'');
 const changed=inspect.replace('__KNOWN_PAGE__',JSON.stringify('https://en.hdrama.net/series/other'));
 assert.match(JSON.parse(vm.runInContext(changed,f.context)).html,/<h1>Story/);
 f.context.document.title='Just a moment…';assert.equal(JSON.parse(vm.runInContext(cached,f.context)).blocked,true);
});
test('Footer measurements track fixed menus without treating small floating buttons as navigation',()=>{
 const f=fixture('/');
 f.footers.push({style:{position:'fixed',display:'block'},getBoundingClientRect:()=>({top:728,bottom:800,width:360})});
 f.footers.push({style:{position:'fixed',display:'block'},getBoundingClientRect:()=>({top:680,bottom:800,width:60})});
 const data=JSON.parse(vm.runInContext(inspect.replace('__KNOWN_PAGE__',JSON.stringify(f.context.location.href)),f.context));
 assert.equal(data.footerHeight,72);assert.equal(data.viewportHeight,800);
 f.footers[0].querySelectorAll=()=>[{style:{display:'block',visibility:'visible'},getBoundingClientRect:()=>({top:704,bottom:800,width:60,height:96})}];
 assert.equal(JSON.parse(vm.runInContext(inspect.replace('__KNOWN_PAGE__','""'),f.context)).footerHeight,96);
 f.footers.length=0;
 assert.equal(JSON.parse(vm.runInContext(inspect.replace('__KNOWN_PAGE__','""'),f.context)).footerHeight,0);
});
console.log(passed+' browser script checks passed.');
