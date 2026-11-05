"""Compile a real iPhone device app and export a clearly labelled unsigned IPA."""
import hashlib,importlib.util,json,os,plistlib,subprocess,zipfile
from pathlib import Path

spec=importlib.util.spec_from_file_location('worker',Path(__file__).with_name('build.py'));worker=importlib.util.module_from_spec(spec);spec.loader.exec_module(worker)

def inspect_bundle(app,bundle_id):
    if app.is_symlink()or not app.is_dir():raise ValueError('Missing device app bundle')
    with(app/'Info.plist').open('rb')as f:info=plistlib.load(f)
    if info.get('CFBundleIdentifier')!=bundle_id:raise ValueError('Device bundle ID differs from the project')
    if info.get('DTPlatformName')!='iphoneos' or 'iPhoneOS'not in info.get('CFBundleSupportedPlatforms',[]):raise ValueError('Simulator bundles are not unsigned iPhone IPAs')
    executable=info.get('CFBundleExecutable','')
    if not executable or Path(executable).name!=executable or not(app/executable).is_file():raise ValueError('Missing app executable')
    if any(app.rglob('embedded.mobileprovision')):raise ValueError('Unsigned export must not include a provisioning profile')
    return info,app/executable

def inspect_ipa(package,app_name,executable_name):
    with zipfile.ZipFile(package)as z:
        names=z.namelist();prefix='Payload/'+app_name+'/'
        if z.testzip()or prefix+'Info.plist'not in names or prefix+executable_name not in names:raise ValueError('Invalid IPA Payload structure')
        if any(n.startswith('/')or '..'in n.split('/')or n.endswith('embedded.mobileprovision')for n in names):raise ValueError('Unsafe IPA or unexpected provisioning profile')

def build():
    worker.validate();root=Path(os.environ['GITHUB_WORKSPACE']);temp=Path(os.environ['RUNNER_TEMP']);out=root/'output';out.mkdir(exist_ok=True)
    report={'project_id':os.environ['PROJECT_ID'],'request_id':os.environ['REQUEST_ID'],'source_sha':os.environ['SOURCE_SHA'],'platform':'ios_unsigned','build_result':'failure','analyze_passed':False,'tests_passed':False,'signature_verified':False,'code_signing':'unsigned','requires_signing':True,'install_ready':False,'device_build_verified':False,'package_verified':False,'physical_phone_tested':False,'files':[]};logs=[]
    def run(args,cwd=None):
        r=subprocess.run(list(map(str,args)),cwd=cwd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8',errors='replace',timeout=1500)
        logs.append('$ '+' '.join(map(str,args))+'\n'+r.stdout)
        if r.returncode:raise RuntimeError('Command failed: '+str(args[0]))
        return r.stdout
    try:
        work=temp/'unsigned-ios-app';cfg=worker.prepare(root/'projects'/report['project_id'],work,run)
        report['flutter_sdk']=json.loads(run(['flutter','--version','--machine']))
        run(['flutter','pub','get'],work);run(['flutter','analyze'],work);report['analyze_passed']=True
        run(['flutter','test'],work);report['tests_passed']=True
        run(['flutter','build','ios','--release','--no-codesign','--build-number',os.environ['GITHUB_RUN_NUMBER']],work)
        apps=list((work/'build/ios/iphoneos').glob('*.app'))
        if len(apps)!=1:raise ValueError('Expected one iPhone device app bundle')
        app=apps[0];info,executable=inspect_bundle(app,cfg['bundle_id'])
        archs=run(['xcrun','lipo','-archs',executable]).strip().split()
        if 'arm64'not in archs or any(a in {'x86_64','i386'}for a in archs):raise ValueError('Expected an arm64 iPhone device executable')
        report['device_build_verified']=True;report['architectures']=archs;report['bundle_id']=cfg['bundle_id']
        payload=temp/'unsigned-ipa/Payload';payload.mkdir(parents=True)
        run(['ditto',app,payload/app.name])
        package=out/(report['project_id']+'-ios-unsigned.ipa')
        run(['ditto','-c','-k','--keepParent',payload,package])
        inspect_ipa(package,app.name,info['CFBundleExecutable']);report['package_verified']=True
        (out/'SIGN-BEFORE-INSTALL.txt').write_text('UNSIGNED iPhone device IPA. This is not directly installable yet.\n\n1. Download the -ios-unsigned.ipa file.\n2. Open https://www.ipasigner.com/ and use your eligible UDID Registrations signing service.\n3. Upload the IPA, sign it with a valid certificate/profile covering your iPhone and app capabilities, then use the signer installation option.\n\nNo signing certificate, password or device ID was used by this build. Signing-service compatibility and installation must be verified on your device.\n',encoding='utf-8')
        report['files']=[{'name':package.name,'size_bytes':package.stat().st_size,'sha256':hashlib.sha256(package.read_bytes()).hexdigest()}];report['build_result']='success'
    except Exception as e:report['error']=str(e);logs.append(str(e))
    finally:
        (out/'Build-Report.json').write_text(json.dumps(report,indent=2),encoding='utf-8');(out/'build.log').write_text('\n'.join(logs)[-120000:],encoding='utf-8')
    print('Unsigned iPhone IPA result:',report['build_result'],'— sign before installation.')
    if report['build_result']!='success':raise SystemExit(1)

if __name__=='__main__':build()
