function mb_context(settings={}) {
 const owner=String(settings.githubOwner||'').trim(),repo=String(settings.githubRepo||'').trim(),token=String(settings.githubToken||'').trim(),branch=String(settings.githubBranch||'main').trim();
 if(!/^[A-Za-z0-9][A-Za-z0-9-]{0,38}$/.test(owner)||!/^[A-Za-z0-9][A-Za-z0-9_.-]{0,99}$/.test(repo))throw new Error('Choose your GitHub owner and dedicated builder repository in Settings.');
 if(!token)throw new Error('Enter a repository-scoped GitHub token in the plugin password setting, never in chat.');
 if(!/^[A-Za-z0-9][A-Za-z0-9_/.-]{0,99}$/.test(branch)||branch.includes('..')||branch.includes('//'))throw new Error('Invalid branch.');
 const base='/repos/'+owner+'/'+repo,web='https://github.com/'+owner+'/'+repo;
 const cap=(['32','64','128'].includes(String(settings.maxDownloadMB))?Number(settings.maxDownloadMB):64)*1048576;
 const clean=s=>String(s).split(token).join('[REDACTED]').replace(/(?:github_pat_|gh[pousr]_)[A-Za-z0-9_]+/g,'[REDACTED]');
 async function api(path,method='GET',data,binary=false){
  if(path!==base&&!path.startsWith(base+'/'))throw new Error('Request outside the configured repository refused.');
  const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),40000);
  try{
   const r=await fetch('https://api.github.com'+path,{method,headers:{Accept:'application/vnd.github+json',Authorization:'Bearer '+token,'X-GitHub-Api-Version':'2022-11-28',...(data?{'Content-Type':'application/json'}:{})},...(data?{body:JSON.stringify(data)}:{}),credentials:'omit',redirect:binary?'follow':'error',signal:controller.signal});
   if(!r.ok){let message='';try{message=(await r.json()).message||'';}catch(_){}const e=new Error(clean('GitHub '+r.status+': '+message).slice(0,800));e.status=r.status;throw e;}
   if(binary){
    if(Number(r.headers.get('content-length')||0)>cap)throw new Error('Artifact exceeds download limit.');
    const reader=r.body.getReader(),chunks=[];let size=0;
    try{while(true){const v=await reader.read();if(v.done)break;size+=v.value.length;if(size>cap){await reader.cancel();throw new Error('Artifact exceeds download limit.');}chunks.push(v.value);}}finally{reader.releaseLock();}
    const result=new Uint8Array(size);let offset=0;for(const part of chunks){result.set(part,offset);offset+=part.length;}return result;
   }
   if(r.status===204)return null;const text=await r.text();return text?JSON.parse(text):null;
  }catch(e){if(e.name==='AbortError')throw new Error('Request timed out; a write or build may have completed. Check status before retrying.');throw e;}
  finally{clearTimeout(timer);}
 }
 return{owner,repo,branch,base,web,cap,clean,api,allowPublic:settings.allowPublicSource==='on'};
}
function mb_id(value){if(typeof value!=='string'||!/^[a-z][a-z0-9_]{1,39}$/.test(value))throw new Error('Project ID must start with a lowercase letter and contain 2–40 lowercase letters, digits or underscores.');return value;}
function mb_path(path){if(typeof path!=='string'||path.length>200||path.includes('\\')||path.includes('\0')||path.split('/').some(x=>!x||x==='.'||x==='..')||!/^(lib\/|test\/|assets\/|pubspec\.yaml$|analysis_options\.yaml$|README\.md$)/.test(path)||/\.(?:p12|pfx|jks|keystore|mobileprovision|pem|key)$/i.test(path))throw new Error('Use safe Flutter lib/, test/, assets/ text paths or supported project-root files. No signing files.');return path;}
function mb_text(value){return new TextDecoder().decode(Uint8Array.from(atob(value.replace(/\s/g,'')),c=>c.charCodeAt(0)));}
function mb_json(value){return JSON.stringify(value,null,2);}
async function mb_repository(c){const r=await c.api(c.base);if(!r.private&&!c.allowPublic)throw new Error('Public source is disabled. Enable Allow public app source only if you want source, logs and build artifacts to be publicly accessible.');if(r.full_name&&r.full_name.toLowerCase()!==(c.owner+'/'+c.repo).toLowerCase())throw new Error('Repository identity differs from the configured owner/name.');return r;}
async function mb_head(c){const r=await c.api(c.base+'/git/ref/heads/'+c.branch.split('/').map(encodeURIComponent).join('/'));const commit=await c.api(c.base+'/git/commits/'+r.object.sha);return{sha:r.object.sha,tree:commit.tree.sha};}
async function mb_file(c,path,ref){return c.api(c.base+'/contents/'+path.split('/').map(encodeURIComponent).join('/')+'?ref='+encodeURIComponent(ref));}
async function mb_commit(c,head,files,message){
 const tree=await c.api(c.base+'/git/trees','POST',{base_tree:head.tree,tree:files.map(f=>({path:f.path,mode:'100644',type:'blob',content:f.content}))});
 const commit=await c.api(c.base+'/git/commits','POST',{message,tree:tree.sha,parents:[head.sha]});
 await c.api(c.base+'/git/refs/heads/'+c.branch.split('/').map(encodeURIComponent).join('/'),'PATCH',{sha:commit.sha,force:false});return commit.sha;
}
function mobile_builder_setup_status(params,settings={}){
 let deflate=false;try{new DecompressionStream('deflate-raw');deflate=true;}catch(_){}
 return mb_json({plugin:'Mobile App Builder',token_configured:!!String(settings.githubToken||'').trim(),owner_configured:!!settings.githubOwner,repository_configured:!!settings.githubRepo,browser_artifact_extraction_supported:deflate,public_source_enabled:settings.allowPublicSource==='on',connection_verified:false,
  required:'A dedicated GitHub repository initialized with a README; repository-scoped Contents/Actions read-write access, plus Workflows write for pipeline installation.',
  signing:'Persistent Android release signing secrets; Apple Distribution certificate plus a matching unexpired ad hoc provisioning profile covering the target iPhone.',
  note:'Offline check only. ChatGPT GitHub access is separate from TypingMind. No native compilation or live build has been verified by this check. Never paste credentials in chat.'});
}
async function mobile_builder_connect(params,settings){
 const c=mb_context(settings),r=await mb_repository(c);let installed=false;
 try{const f=await mb_file(c,'.github/workflows/mobile-builder.yml',c.branch);installed=mb_text(f.content)===MB_BACKEND['.github/workflows/mobile-builder.yml'];}catch(e){if(e.status!==404)throw e;}
 return mb_json({status:'connected',repository:r.full_name,visibility:r.private?'private':'public',pipeline_verified:installed,url:c.web,signing_readiness:'Checked by workflow presence checks and actual signing validation. Secret values are never read by this plugin.'});
}
async function mobile_builder_install_pipeline(params,settings){
 const c=mb_context(settings);await mb_repository(c);const head=await mb_head(c),files=[];
 if(params.expected_commit&&params.expected_commit!==head.sha)throw new Error('Branch changed. Read the latest state first.');
 for(const [path,content]of Object.entries(MB_BACKEND)){
  try{const f=await mb_file(c,path,head.sha);if(mb_text(f.content)!==content)throw new Error('Existing builder file differs; review it before replacement: '+path);}
  catch(e){if(e.status===404)files.push({path,content});else throw e;}
 }
 const sha=files.length?await mb_commit(c,head,files,'Install TypingMind Mobile App Builder'):head.sha;
 return mb_json({status:files.length?'installed':'already_installed',commit:sha,build_started:false,url:c.web+'/actions'});
}
async function mobile_builder_save_project(params,settings){
 const c=mb_context(settings),id=mb_id(params.project_id);
 if(typeof params.app_name!=='string'||!params.app_name.trim()||params.app_name.length>80||/[\x00-\x1f]/.test(params.app_name))throw new Error('Provide an app name of 1–80 characters.');
 if(!/^[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*){2,}$/.test(params.bundle_id||'')||params.bundle_id.length>150)throw new Error('Use an app identifier such as com.worldgate.shipments.');
 if(!Array.isArray(params.files)||!params.files.length||params.files.length>40)throw new Error('Save 1–40 source files at a time.');
 const seen=new Set();let total=0;
 const files=params.files.map(f=>{const path=mb_path(f.path);if(seen.has(path))throw new Error('Duplicate file path.');seen.add(path);
  if(typeof f.content!=='string')throw new Error('Source content must be UTF-8 text.');const size=new TextEncoder().encode(f.content).length;total+=size;if(size>262144)throw new Error('Source file exceeds 256 KiB.');
  if(/github_pat_|ghp_|sk-[a-fA-F0-9]{24,}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/.test(f.content))throw new Error('Potential credential detected. Use secrets/configuration, not source.');
  return{path:'projects/'+id+'/'+path,content:f.content};});
 if(total>2097152)throw new Error('Source save exceeds 2 MiB.');
 await mb_repository(c);const head=await mb_head(c);if(params.expected_commit&&params.expected_commit!==head.sha)throw new Error('Repository changed. Read the latest source before editing.');
 let exists=false;try{await mb_file(c,'projects/'+id+'/project.json',head.sha);exists=true;}catch(e){if(e.status!==404)throw e;}
 if(!exists&&!seen.has('lib/main.dart'))throw new Error('A new app requires its actual lib/main.dart implementation.');
 files.push({path:'projects/'+id+'/project.json',content:mb_json({schema:1,project_id:id,app_name:params.app_name.trim(),bundle_id:params.bundle_id,description:String(params.description||'').slice(0,2000)})+'\n'});
 const sha=await mb_commit(c,head,files,'Update app '+id);return mb_json({status:'saved',project_id:id,commit:sha,file_count:files.length,url:c.web+'/tree/'+sha+'/projects/'+id,build_started:false});
}
async function mobile_builder_read_project(params,settings){
 const c=mb_context(settings),id=mb_id(params.project_id);await mb_repository(c);const head=await mb_head(c),tree=await c.api(c.base+'/git/trees/'+head.tree+'?recursive=1');
 if(tree.truncated)throw new Error('Repository is too large. Use a dedicated builder repository.');
 const prefix='projects/'+id+'/',listing=tree.tree.filter(f=>f.type==='blob'&&f.path.startsWith(prefix)).map(f=>({path:f.path.slice(prefix.length),size:f.size}));
 const paths=params.paths||[];if(paths.length>8)throw new Error('Read up to eight source files at once.');const files=[];
 for(const path of paths){if(path!=='project.json')mb_path(path);const f=await mb_file(c,prefix+path,head.sha);if(f.size>262144)throw new Error('Source file too large.');const text=mb_text(f.content);files.push({path,content:text.slice(0,30000),truncated:text.length>30000});}
 return mb_json({project_id:id,commit:head.sha,files:listing,selected_source:files});
}
async function mb_find_run(c,request){const r=await c.api(c.base+'/actions/workflows/mobile-builder.yml/runs?event=workflow_dispatch&per_page=50');return r.workflow_runs.find(x=>x.display_title&&x.display_title.endsWith(' / '+request));}
async function mobile_builder_start_build(params,settings){
 const c=mb_context(settings),id=mb_id(params.project_id);await mb_repository(c);
 if(!['android','ios','both'].includes(params.platform)||!/^[a-zA-Z0-9][a-zA-Z0-9_-]{5,63}$/.test(params.request_id||'')||!/^[a-f0-9]{40}$/.test(params.source_sha||''))throw new Error('Provide a platform, unique 6–64 character request ID and exact saved commit SHA.');
 const old=await mb_find_run(c,params.request_id);if(old)return mb_json({status:'already_submitted',run_id:old.id,url:old.html_url,request_id:params.request_id});
 const current=await mb_file(c,'.github/workflows/mobile-builder.yml',c.branch);if(mb_text(current.content)!==MB_BACKEND['.github/workflows/mobile-builder.yml'])throw new Error('Install the reviewed build pipeline first.');
 for(const[path,content]of Object.entries(MB_BACKEND)){const f=await mb_file(c,path,params.source_sha);if(mb_text(f.content)!==content)throw new Error('Build helper differs at the requested commit: '+path);}
 await mb_file(c,'projects/'+id+'/project.json',params.source_sha);
 try{const d=await c.api(c.base+'/actions/workflows/mobile-builder.yml/dispatches','POST',{ref:c.branch,inputs:{project_id:id,platform:params.platform,request_id:params.request_id,source_sha:params.source_sha}});
  const r=d?.workflow_run_id?{id:d.workflow_run_id,html_url:d.html_url}:await mb_find_run(c,params.request_id);
  return mb_json({status:'submitted',request_id:params.request_id,run_id:r?.id||null,url:r?.html_url||c.web+'/actions',source_sha:params.source_sha,next_action:'Check this request’s status. Jobs consume GitHub Actions allowance/billing and do not publish to stores.'});
 }catch(e){return mb_json({status:'submission_unknown',request_id:params.request_id,error:c.clean(e.message),next_action:'Check status with this same request ID. Do not automatically dispatch again.'});}
}
async function mobile_builder_build_status(params,settings){
 const c=mb_context(settings);let id=params.run_id;
 if(!id){if(!/^[a-zA-Z0-9][a-zA-Z0-9_-]{5,63}$/.test(params.request_id||''))throw new Error('Provide a run ID or original request ID.');const found=await mb_find_run(c,params.request_id);if(!found)return mb_json({status:'not_visible_yet',request_id:params.request_id,next_action:'Wait briefly and check the same request; do not start a duplicate build.'});id=found.id;}
 if(!Number.isSafeInteger(Number(id))||Number(id)<1)throw new Error('Invalid run ID.');
 const run=await c.api(c.base+'/actions/runs/'+id);if(run.path!=='.github/workflows/mobile-builder.yml')throw new Error('This is not a Mobile App Builder run.');
 const jobs=await c.api(c.base+'/actions/runs/'+id+'/jobs?per_page=100'),artifacts=await c.api(c.base+'/actions/runs/'+id+'/artifacts?per_page=100');
 return mb_json({status:run.status,conclusion:run.conclusion,run_id:run.id,url:run.html_url,workflow_commit:run.head_sha,jobs:jobs.jobs.map(j=>({name:j.name,status:j.status,conclusion:j.conclusion,failed_steps:(j.steps||[]).filter(s=>s.conclusion==='failure').map(s=>s.name),url:j.html_url})),artifacts:artifacts.artifacts.filter(a=>!a.expired).map(a=>({id:a.id,name:a.name,size_bytes:a.size_in_bytes,expires_at:a.expires_at,url:c.web+'/actions/runs/'+id+'/artifacts/'+a.id})),note:'A skipped/missing platform is not successful app delivery. Read Build-Readiness and the actual package report. Workflow commit is not necessarily the source_sha that was built.'});
}
function mb_crc(bytes){let crc=0xffffffff;for(const b of bytes){crc^=b;for(let i=0;i<8;i++)crc=(crc>>>1)^((crc&1)?0xedb88320:0);}return(crc^0xffffffff)>>>0;}
async function mb_unzip(bytes,cap){
 const v=new DataView(bytes.buffer,bytes.byteOffset,bytes.byteLength);let end=-1;
 for(let i=bytes.length-22;i>=Math.max(0,bytes.length-65557);i--)if(v.getUint32(i,true)===0x06054b50){end=i;break;}
 if(end<0)throw new Error('Invalid artifact ZIP.');const count=v.getUint16(end+10,true);let cursor=v.getUint32(end+16,true),total=0;
 if(count>40||cursor===0xffffffff)throw new Error('ZIP64/large artifact directory unsupported.');const files=[];
 for(let n=0;n<count;n++){
  if(cursor+46>bytes.length||v.getUint32(cursor,true)!==0x02014b50)throw new Error('Invalid ZIP directory.');
  const flags=v.getUint16(cursor+8,true),method=v.getUint16(cursor+10,true),crc=v.getUint32(cursor+16,true),packed=v.getUint32(cursor+20,true),size=v.getUint32(cursor+24,true),nl=v.getUint16(cursor+28,true),el=v.getUint16(cursor+30,true),cl=v.getUint16(cursor+32,true),local=v.getUint32(cursor+42,true);
  if(cursor+46+nl+el+cl>bytes.length)throw new Error('Invalid ZIP bounds.');const name=new TextDecoder().decode(bytes.slice(cursor+46,cursor+46+nl));cursor+=46+nl+el+cl;
  if(name.endsWith('/'))continue;
  if(name.startsWith('/')||name.includes('\\')||name.includes('\0')||name.split('/').some(x=>x==='..'||x==='.')||flags&1||![0,8].includes(method)||size===0xffffffff||packed===0xffffffff)throw new Error('Unsafe ZIP entry.');
  if(!/\.(apk|ipa|json|txt|log)$/i.test(name))continue;total+=size;if(total>cap)throw new Error('Expanded artifact exceeds download limit.');
  if(local+30>bytes.length||v.getUint32(local,true)!==0x04034b50)throw new Error('Invalid ZIP header.');const localNameLength=v.getUint16(local+26,true);if(new TextDecoder().decode(bytes.slice(local+30,local+30+localNameLength))!==name||v.getUint16(local+8,true)!==method)throw new Error('ZIP local header mismatch.');const start=local+30+localNameLength+v.getUint16(local+28,true);if(start+packed>bytes.length)throw new Error('Invalid ZIP file bounds.');
  let data=bytes.slice(start,start+packed);
  if(method===8){const reader=new Blob([data]).stream().pipeThrough(new DecompressionStream('deflate-raw')).getReader(),chunks=[];let length=0;
   try{while(true){const r=await reader.read();if(r.done)break;length+=r.value.length;if(length>size||length>cap){await reader.cancel();throw new Error('ZIP decompression limit exceeded.');}chunks.push(r.value);}}finally{reader.releaseLock();}
   data=new Uint8Array(length);let position=0;for(const b of chunks){data.set(b,position);position+=b.length;}}
  if(data.length!==size||mb_crc(data)!==crc)throw new Error('ZIP integrity check failed.');files.push({name:name.split('/').pop(),bytes:data});
 }return files;
}
async function mobile_builder_get_download(params,settings){
 const c=mb_context(settings);if(!Number.isSafeInteger(params.run_id)||!Number.isSafeInteger(params.artifact_id)||params.run_id<1||params.artifact_id<1)throw new Error('Use run/artifact IDs from Build Status.');
 const run=await c.api(c.base+'/actions/runs/'+params.run_id);if(run.path!=='.github/workflows/mobile-builder.yml')throw new Error('Not a builder run.');
 const list=await c.api(c.base+'/actions/runs/'+params.run_id+'/artifacts?per_page=100'),artifact=list.artifacts.find(a=>a.id===params.artifact_id&&!a.expired),url=c.web+'/actions/runs/'+params.run_id+'/artifacts/'+params.artifact_id;
 if(!artifact)throw new Error('Artifact missing, expired or belongs to another build.');if(artifact.size_in_bytes>c.cap)throw new Error('Artifact exceeds download limit. Use '+url);
 let files;try{files=await mb_unzip(await c.api(c.base+'/actions/artifacts/'+params.artifact_id+'/zip','GET',undefined,true),c.cap);}catch(e){throw new Error(c.clean(e.message)+' Official artifact: '+url);}
 let report=null;try{report=JSON.parse(new TextDecoder().decode(files.find(f=>f.name==='Build-Report.json').bytes));}catch(_){}
 for(const f of files.filter(f=>/\.(apk|ipa)$/i.test(f.name))){
  if(!report||report.build_result!=='success'||report.signature_verified!==true)throw new Error('Package lacks a successful signing report. Read build diagnostics; it is not ready.');
  const expected=report.files.find(x=>x.name===f.name),digest=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',f.bytes))).map(x=>x.toString(16).padStart(2,'0')).join('');
  if(!expected||digest!==expected.sha256)throw new Error('Package hash differs from its build report.');
 }
 if(!files.length)throw new Error('No supported package or diagnostic files in artifact.');const content=[{type:'text',text:'Retrieved actual build files. Package hashes/ZIP checks passed where applicable. Phone testing is not implied.'}];
 for(const f of files){const ext=f.name.split('.').pop().toLowerCase(),mime={apk:'application/vnd.android.package-archive',ipa:'application/octet-stream',json:'application/json',txt:'text/plain',log:'text/plain'}[ext];
  if(['json','txt','log'].includes(ext)){const text=c.clean(new TextDecoder().decode(f.bytes)).slice(0,18000);content.push({type:'text',text:f.name+'\n'+text},{type:'resource',resource:{uri:'file:///'+encodeURIComponent(f.name),mimeType:mime,text}});}
  else{let binary='';for(let i=0;i<f.bytes.length;i+=32768)binary+=String.fromCharCode(...f.bytes.subarray(i,i+32768));content.push({type:'resource',resource:{uri:'file:///'+encodeURIComponent(f.name),mimeType:mime,blob:btoa(binary)}});}}
 return{content};
}
