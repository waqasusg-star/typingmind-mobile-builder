const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const source=fs.readFileSync('projects/hdrama_ios/Sources/AdBlocker.swift','utf8');
const script=source.split('static let script = #"""')[1].split('"""#')[0];
function fixture({host='en.hdrama.net',path='/',title='HDrama',challenge=false,framed=false,protectedAd=false}={}){
 let removed=0;const original=()=>{};const node={parentNode:{},matches:()=>false,closest:()=>null,querySelector:()=>protectedAd?{}:null,remove:()=>removed++};
 const window={open:original,alert:original,confirm:original,prompt:original};window.top=framed?{}:window;
 const context={window,location:{hostname:host,pathname:path},document:{title,documentElement:{},querySelector:()=>challenge?{}:null,querySelectorAll:()=>[node],addEventListener:()=>{}},MutationObserver:class{observe(){}},requestAnimationFrame:f=>f()};
 vm.runInNewContext(script,context);assert.equal(window.open,original);assert.equal(window.alert,original);return removed;
}
assert.equal(fixture(),1,'Known ad removed on ordinary page');
for(const options of [{host:'challenges.cloudflare.com'},{path:'/cdn-cgi/challenge-platform/'},{title:'Just a moment...'},{challenge:true},{framed:true},{protectedAd:true}])assert.equal(fixture(options),0,'Challenge/frame/protected container untouched');
console.log('PASS: known ads filtered; challenge pages, frames, protected containers and browser APIs untouched.');
