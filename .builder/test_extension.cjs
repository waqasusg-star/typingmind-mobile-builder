const {chromium}=require('playwright');
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
(async()=>{
 const extension=path.resolve(process.argv[2]),testFile=path.resolve(process.argv[3]);
 const context=await chromium.launchPersistentContext('',{channel:'chromium',headless:true,args:[`--disable-extensions-except=${extension}`,`--load-extension=${extension}`]});
 context.setDefaultTimeout(15000);
 try{
  let [worker]=context.serviceWorkers();
  if(!worker)worker=await context.waitForEvent('serviceworker',{timeout:20000});
  const extensionId=new URL(worker.url()).host;
  assert.match(extensionId,/^[a-p]{32}$/);
  const manifest=await worker.evaluate(()=>chrome.runtime.getManifest());
  assert.equal(manifest.manifest_version,3);
  const test=require(testFile);assert.equal(typeof test,'function','Export async function({context,extensionId,assert}) from tests/extension.test.cjs');
  await test({context,extensionId,assert});
  console.log('PASS: extension loaded in Chromium and project behavior tests passed.');
 }finally{await context.close();}
})().catch(e=>{console.error(e);process.exit(1)});
