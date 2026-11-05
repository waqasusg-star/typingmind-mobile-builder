const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),crypto=require('node:crypto'),zlib=require('node:zlib');
const backend={};for(const p of ['.builder/build.py','.github/workflows/mobile-builder.yml'])backend[p]=fs.readFileSync(__dirname+'/../'+p,'utf8');
const settings={githubOwner:'testuser',githubRepo:'builder',githubToken:'private-test-token'},sha='a'.repeat(40),tree='b'.repeat(40),next='c'.repeat(40);let calls=[],handler;
const context=vm.createContext({TextEncoder,TextDecoder,Uint8Array,DataView,ArrayBuffer,Blob,DecompressionStream,AbortController,crypto:crypto.webcrypto,setTimeout,clearTimeout,atob,btoa,fetch:async(u,o)=>{calls.push({u,o});return handler(u,o);}});
vm.runInContext(fs.readFileSync(__dirname+'/../typingmind-plugin/plugin.js','utf8')+'\nconst MB_BACKEND='+JSON.stringify(backend)+';',context);
const response=(v,status=200)=>new Response(JSON.stringify(v),{status,headers:{'Content-Type':'application/json'}});
function base(u,o){const p=new URL(u).pathname;
 if(p.endsWith('/testuser/builder'))return response({private:true,full_name:'testuser/builder'});
 if(p.includes('/git/ref/'))return response({object:{sha}});
 if(p.endsWith('/git/commits/'+sha))return response({tree:{sha:tree}});
 if(o.method==='POST'&&p.endsWith('/git/trees'))return response({sha:tree});
 if(o.method==='POST'&&p.endsWith('/git/commits'))return response({sha:next});
 if(o.method==='PATCH'&&p.includes('/git/refs/'))return response({object:{sha:next}});
 if(p.includes('/contents/'))return response({message:'Not found'},404);
 throw Error('Unexpected request '+p);
}
function zip(entries){let offset=0;const chunks=[],central=[];for(const[name,value]of entries){const filename=Buffer.from(name),raw=Buffer.from(value),packed=zlib.deflateRawSync(raw),crc=context.mb_crc(raw),local=Buffer.alloc(30),dir=Buffer.alloc(46);
 local.writeUInt32LE(0x04034b50);local.writeUInt16LE(8,8);local.writeUInt32LE(crc,14);local.writeUInt32LE(packed.length,18);local.writeUInt32LE(raw.length,22);local.writeUInt16LE(filename.length,26);
 dir.writeUInt32LE(0x02014b50);dir.writeUInt16LE(8,10);dir.writeUInt32LE(crc,16);dir.writeUInt32LE(packed.length,20);dir.writeUInt32LE(raw.length,24);dir.writeUInt16LE(filename.length,28);dir.writeUInt32LE(offset,42);
 chunks.push(local,filename,packed);central.push(dir,filename);offset+=local.length+filename.length+packed.length;}
 const size=central.reduce((n,b)=>n+b.length,0),end=Buffer.alloc(22);end.writeUInt32LE(0x06054b50);end.writeUInt16LE(entries.length,8);end.writeUInt16LE(entries.length,10);end.writeUInt32LE(size,12);end.writeUInt32LE(offset,16);return new Uint8Array(Buffer.concat([...chunks,...central,end]));}
(async()=>{
 handler=base;assert.equal(JSON.parse(context.mobile_builder_setup_status({},{})).token_configured,false);assert.equal(calls.length,0);
 await assert.rejects(()=>context.mobile_builder_connect({},{}),/Settings/);assert.equal(calls.length,0);
 for(const path of ['../evil','lib/../../escape','assets/private.key','/lib/main.dart'])assert.throws(()=>context.mb_path(path));
 assert.throws(()=>context.mb_id('bad;curl'));
 handler=()=>response({private:false});await assert.rejects(()=>context.mobile_builder_connect({},settings),/Public source/);
 handler=(u,o)=>u.endsWith('/testuser/builder')?response({private:false,full_name:'testuser/builder'}):base(u,o);const publicStatus=JSON.parse(await context.mobile_builder_connect({},{...settings,allowPublicSource:'on'}));assert.equal(publicStatus.visibility,'public');handler=base;calls=[];const project={project_id:'test_app',app_name:'Test App',bundle_id:'com.worldgate.test',files:[{path:'lib/main.dart',content:'void main() {}'}]};
 const saved=JSON.parse(await context.mobile_builder_save_project(project,settings));assert.equal(saved.commit,next);
 const created=JSON.parse(calls.find(c=>c.o.method==='POST'&&c.u.endsWith('/git/trees')).o.body);assert.equal(created.base_tree,tree);assert(created.tree.every(f=>f.path.startsWith('projects/test_app/')));assert.equal(JSON.parse(calls.find(c=>c.o.method==='PATCH').o.body).force,false);assert(!JSON.stringify(saved).includes(settings.githubToken));
 calls=[];await assert.rejects(()=>context.mobile_builder_save_project({...project,expected_commit:'d'.repeat(40)},settings),/changed/);assert(!calls.some(c=>c.o.method==='POST'));
 await assert.rejects(()=>context.mobile_builder_save_project({...project,files:[{path:'lib/main.dart',content:'github_pat_credential'}]},settings),/credential/);
 handler=(u,o)=>u.includes('/contents/')?response({content:btoa('different backend')}):base(u,o);calls=[];await assert.rejects(()=>context.mobile_builder_install_pipeline({},settings),/differs/);assert(!calls.some(c=>c.o.method==='POST'));
 handler=(u,o)=>{const p=new URL(u).pathname;if(p.endsWith('/mobile-builder.yml/runs'))return response({workflow_runs:[]});if(p.includes('/contents/'))return response({content:Buffer.from(backend[decodeURIComponent(p.split('/contents/')[1])]||'{}','utf8').toString('base64')});if(p.endsWith('/dispatches'))throw new DOMException('Timeout','AbortError');return base(u,o);};
 const uncertain=JSON.parse(await context.mobile_builder_start_build({project_id:'test_app',platform:'both',request_id:'request_test01',source_sha:sha},settings));assert.equal(uncertain.status,'submission_unknown');
 const read=await context.mb_unzip(zip([['build.log','verified error '.repeat(20)]]),10000);assert.equal(read[0].bytes.length,300);
 await assert.rejects(()=>context.mb_unzip(zip([['../bad.apk','123']]),1000),/Unsafe/);
 await assert.rejects(()=>context.mb_unzip(zip([['big.apk','a'.repeat(100)]]),50),/limit/);
 const broken=zip([['app.apk','abcdef']]);broken[35]^=8;await assert.rejects(()=>context.mb_unzip(broken,1000));
 let archive=zip([['app.apk','unit-test-bytes']]);
 handler=(u,o)=>{const p=new URL(u).pathname;if(p.endsWith('/actions/runs/10'))return response({path:'.github/workflows/mobile-builder.yml'});if(p.endsWith('/runs/10/artifacts'))return response({artifacts:[{id:20,expired:false,size_in_bytes:archive.length}]});if(p.endsWith('/artifacts/20/zip'))return new Response(archive);throw Error('Unexpected artifact request');};
 await assert.rejects(()=>context.mobile_builder_get_download({run_id:10,artifact_id:20},settings),/signing report/);
 const bytes='unit-test-bytes',report={build_result:'success',signature_verified:true,files:[{name:'app.apk',sha256:crypto.createHash('sha256').update(bytes).digest('hex')}]};archive=zip([['app.apk',bytes],['Build-Report.json',JSON.stringify(report)]]);
 const download=await context.mobile_builder_get_download({run_id:10,artifact_id:20},settings);assert(download.content.some(c=>c.type==='resource'&&c.resource.uri.endsWith('app.apk')));
 report.files[0].sha256='0'.repeat(64);archive=zip([['app.apk',bytes],['Build-Report.json',JSON.stringify(report)]]);await assert.rejects(()=>context.mobile_builder_get_download({run_id:10,artifact_id:20},settings),/hash/);
 assert(calls.every(c=>c.u.startsWith('https://api.github.com/repos/testuser/builder')&&c.o.credentials==='omit'));
 console.log('PASS: settings/privacy, public-source opt-in and private repositories, safe paths, credential guards, atomic non-force writes, stale edits, immutable pipeline, uncertain submissions, bounded ZIP/CRC/deflate, signing-report gate, package hashes and attachment output.');
})().catch(e=>{console.error(e);process.exit(1)});
