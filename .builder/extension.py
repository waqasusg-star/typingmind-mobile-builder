"""Validate, test in Chromium, and package Manifest V3 extension source."""
import hashlib,importlib.util,json,os,re,shutil,struct,subprocess,zlib,zipfile
from pathlib import Path

spec=importlib.util.spec_from_file_location('worker',Path(__file__).with_name('build.py'));worker=importlib.util.module_from_spec(spec);spec.loader.exec_module(worker)

def safe_path(value):
    if not isinstance(value,str) or not re.fullmatch(r'[A-Za-z0-9_./-]{1,180}',value) or any(p in {'','..','.'}for p in value.split('/')) or value.startswith('.'):
        raise ValueError('Unsafe extension path')
    if Path(value).suffix.lower()not in {'.json','.js','.mjs','.cjs','.html','.css','.svg','.md'}:raise ValueError('Unsupported extension source file')
    if value=='project.json':raise ValueError('Reserved metadata path')
    return value

def png(size):
    def chunk(kind,data):return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
    raw=b''.join(b'\0'+bytes([35,97,210,255])*size for _ in range(size))
    return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',size,size,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(raw))+chunk(b'IEND',b'')

def prepare(source,work):
    cfg=json.loads((source/'project.json').read_text())
    if cfg.get('project_type')!='extension' or cfg.get('project_id')!=os.environ['PROJECT_ID']:raise ValueError('Not the requested extension project')
    if work.exists():raise ValueError('Extension work directory exists')
    work.mkdir(parents=True)
    for p in source.rglob('*'):
        if p.is_symlink():raise ValueError('Symlink source refused')
        if p.is_file() and p!=source/'project.json':
            rel=p.relative_to(source).as_posix();safe_path(rel)
            if p.stat().st_size>262144:raise ValueError('Extension source file too large')
            if rel.startswith('tests/'):continue
            target=work/rel;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,target)
    manifest=json.loads((work/'manifest.json').read_text())
    if manifest.get('manifest_version')!=3 or not isinstance(manifest.get('name'),str)or not manifest['name'].strip():raise ValueError('Manifest V3 and extension name are required')
    if not re.fullmatch(r'(?:0|[1-9][0-9]{0,4})(?:\.(?:0|[1-9][0-9]{0,4})){0,3}',str(manifest.get('version',''))) or any(int(x)>65535 for x in str(manifest['version']).split('.')) or not any(int(x)for x in str(manifest['version']).split('.')):raise ValueError('Invalid extension version')
    if not manifest.get('icons'):
        manifest['icons']={str(n):f'_builder_icons/icon{n}.png' for n in [16,32,48,128]}
        (work/'_builder_icons').mkdir()
        for n,path in manifest['icons'].items():(work/path).write_bytes(png(int(n)))
    if not manifest.get('background'):
        manifest['background']={'service_worker':'_builder_probe.js'}
        (work/'_builder_probe.js').write_text('chrome.runtime.onInstalled.addListener(() => {});\n')
    refs=[manifest['background'].get('service_worker')]
    for obj,key in [(manifest.get('action',{}),'default_popup'),(manifest.get('options_ui',{}),'page')]:
        if obj.get(key):refs.append(obj[key])
    if manifest.get('options_page'):refs.append(manifest['options_page'])
    refs.extend(manifest['icons'].values())
    for content in manifest.get('content_scripts',[]):refs.extend(content.get('js',[])+content.get('css',[]))
    for ref in refs:
        if not isinstance(ref,str)or ref.startswith('/')or '..'in ref.split('/')or not(work/ref).is_file():raise ValueError('Manifest references a missing/unsafe file: '+str(ref))
    (work/'manifest.json').write_text(json.dumps(manifest,indent=2))
    if not(source/'tests/extension.test.cjs').is_file():raise ValueError('Meaningful tests/extension.test.cjs is required')
    return manifest

def build():
    worker.validate();root=Path(os.environ['GITHUB_WORKSPACE']);temp=Path(os.environ['RUNNER_TEMP']);out=root/'output';out.mkdir(exist_ok=True)
    report={'project_id':os.environ['PROJECT_ID'],'request_id':os.environ['REQUEST_ID'],'source_sha':os.environ['SOURCE_SHA'],'platform':'extension','build_result':'failure','analyze_passed':False,'tests_passed':False,'signature_verified':False,'browser_smoke_passed':False,'store_published':False,'code_signing':'unpacked-extension-zip','files':[]};logs=[]
    try:
        source=root/'projects'/report['project_id'];work=temp/'extension-package';manifest=prepare(source,work)
        for p in sorted(work.rglob('*')):
            if p.suffix in {'.js','.mjs','.cjs'}:
                r=subprocess.run(['node','--check',str(p)],capture_output=True,text=True,timeout=30);logs.append(r.stdout+r.stderr)
                if r.returncode:raise ValueError('JavaScript syntax check failed: '+p.name)
        report['analyze_passed']=True
        r=subprocess.run(['node',str(root/'.builder/test_extension.cjs'),str(work),str(source/'tests/extension.test.cjs')],capture_output=True,text=True,timeout=150)
        logs.append(r.stdout+r.stderr)
        if r.returncode:raise ValueError('Chromium extension tests failed')
        report['browser_smoke_passed']=True;report['tests_passed']=True
        report['permissions']=manifest.get('permissions',[]);report['host_permissions']=manifest.get('host_permissions',[])
        package=out/(report['project_id']+'-chrome-extension.zip')
        with zipfile.ZipFile(package,'w',zipfile.ZIP_DEFLATED)as z:
            for p in sorted(work.rglob('*')):
                if p.is_file():z.write(p,p.relative_to(work))
        with zipfile.ZipFile(package)as z:
            if z.testzip()or'manifest.json'not in z.namelist():raise ValueError('Invalid extension ZIP')
        report['files']=[{'name':package.name,'size_bytes':package.stat().st_size,'sha256':hashlib.sha256(package.read_bytes()).hexdigest()}];report['build_result']='success'
    except Exception as e:report['error']=str(e);logs.append(str(e))
    finally:
        (out/'Build-Report.json').write_text(json.dumps(report,indent=2));(out/'build.log').write_text('\n'.join(logs)[-120000:])
    print('Extension result:',report['build_result'])
    if report['build_result']!='success':raise SystemExit(1)

if __name__=='__main__':build()
