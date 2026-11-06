"""Build reviewed native Swift source without signing credentials or uploaded scripts."""
import hashlib,json,os,plistlib,re,shutil,subprocess,sys,zipfile
from pathlib import Path

def identity(env):
    for key,pattern in [('PROJECT_ID',r'[a-z][a-z0-9_]{1,39}'),('REQUEST_ID',r'[A-Za-z0-9][A-Za-z0-9_-]{5,63}'),('SOURCE_SHA',r'[a-f0-9]{40}')]:
        if not re.fullmatch(pattern,env.get(key,'')):raise ValueError('Invalid '+key)

def config(source):
    cfg=json.loads((source/'project.json').read_text())
    if cfg.get('project_type')!='native_ios':raise ValueError('Not a native iOS project')
    for key,pattern in [('project_id',r'[a-z][a-z0-9_]{1,39}'),('bundle_id',r'[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*){2,}'),('scheme',r'[A-Za-z][A-Za-z0-9_]{0,49}'),('version',r'\d+\.\d+\.\d+'),('build_number',r'\d{1,9}'),('minimum_ios',r'\d{1,2}\.\d+')]:
        if not re.fullmatch(pattern,str(cfg.get(key,''))):raise ValueError('Invalid native '+key)
    if not isinstance(cfg.get('app_name'),str)or not 1<=len(cfg['app_name'])<=80 or any(ord(c)<32 for c in cfg['app_name']):raise ValueError('Invalid app name')
    if float(cfg['minimum_ios'])<15:raise ValueError('Minimum supported deployment target is iOS 15')
    if not list((source/'Sources').rglob('*.swift')):raise ValueError('Missing Swift source')
    return cfg

def prepare(source,work):
    if source.is_symlink()or not source.is_dir():raise ValueError('Unsafe source directory')
    cfg=config(source)
    if work.exists():raise ValueError('Build directory already exists')
    work.mkdir(parents=True)
    # Generate a controlled project spec; never run uploaded project scripts or packages.
    for p in source.rglob('*'):
        if p.is_symlink():raise ValueError('Symlink source refused')
        if not p.is_file():continue
        rel=p.relative_to(source)
        if rel.parts[0] not in {'Sources','Resources'}:continue
        if p.stat().st_size>1048576:raise ValueError('Native source file too large')
        if p.suffix.lower()not in {'.swift','.json','.plist','.strings','.stringsdict','.storyboard','.xib','.xml','.txt','.md','.svg','.png','.jpg','.jpeg'}:raise ValueError('Unsupported native source file')
        target=work/rel;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,target)
    scheme=cfg['scheme']
    info={'CFBundleDevelopmentRegion':'en','CFBundleDisplayName':cfg['app_name'],'CFBundleExecutable':'$(EXECUTABLE_NAME)','CFBundleIdentifier':'$(PRODUCT_BUNDLE_IDENTIFIER)','CFBundleInfoDictionaryVersion':'6.0','CFBundleName':'$(PRODUCT_NAME)','CFBundlePackageType':'APPL','CFBundleShortVersionString':cfg['version'],'CFBundleVersion':str(cfg['build_number']),'LSRequiresIPhoneOS':True,'UILaunchScreen':{},'UIBackgroundModes':['audio'],'UIStatusBarStyle':'UIStatusBarStyleLightContent','UISupportedInterfaceOrientations':['UIInterfaceOrientationPortrait','UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight'],'UISupportedInterfaceOrientations~ipad':['UIInterfaceOrientationPortrait','UIInterfaceOrientationPortraitUpsideDown','UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight']}
    (work/'Info.plist').write_bytes(plistlib.dumps(info))
    target={'type':'application','platform':'iOS','sources':[{'path':'Sources'}],'settings':{'base':{'PRODUCT_BUNDLE_IDENTIFIER':cfg['bundle_id'],'MARKETING_VERSION':cfg['version'],'CURRENT_PROJECT_VERSION':str(cfg['build_number']),'SWIFT_VERSION':'5.0','TARGETED_DEVICE_FAMILY':'1,2','INFOPLIST_FILE':'Info.plist','CODE_SIGNING_ALLOWED':'NO','CODE_SIGNING_REQUIRED':'NO','CODE_SIGN_IDENTITY':'','ENABLE_USER_SCRIPT_SANDBOXING':'YES'}}}
    if(work/'Resources').is_dir():target['sources'].append({'path':'Resources'})
    spec={'name':scheme,'options':{'deploymentTarget':{'iOS':cfg['minimum_ios']},'createIntermediateGroups':True},'targets':{scheme:target},'schemes':{scheme:{'build':{'targets':{scheme:'all'}},'run':{'config':'Debug'},'archive':{'config':'Release'}}}}
    (work/'native-project.json').write_text(json.dumps(spec,indent=2))
    return cfg

def verify_bundle(app,cfg,run):
    if app.is_symlink()or not app.is_dir():raise ValueError('Missing device app bundle')
    info=plistlib.loads((app/'Info.plist').read_bytes())
    if info.get('CFBundleIdentifier')!=cfg['bundle_id']:raise ValueError('Bundle identity mismatch')
    if info.get('CFBundleShortVersionString')!=cfg['version'] or info.get('CFBundleVersion')!=str(cfg['build_number']):raise ValueError('Archived app version/build mismatch')
    if info.get('DTPlatformName')!='iphoneos'or'iPhoneOS'not in info.get('CFBundleSupportedPlatforms',[]):raise ValueError('Simulator app is not an iPhone device app')
    executable=info.get('CFBundleExecutable','')
    if not executable or Path(executable).name!=executable or not(app/executable).is_file():raise ValueError('Missing device executable')
    if list(app.rglob('embedded.mobileprovision')):raise ValueError('Unsigned app must not contain provisioning profiles')
    archs=run(['xcrun','lipo','-archs',app/executable]).strip().split()
    if 'arm64'not in archs or any(a in {'x86_64','i386'}for a in archs):raise ValueError('Not an arm64 device app')
    return info,archs

def verify_ipa(package,app_name,executable):
    prefix='Payload/'+app_name+'/'
    with zipfile.ZipFile(package)as z:
        names=z.namelist()
        if z.testzip()or prefix+'Info.plist'not in names or prefix+executable not in names:raise ValueError('Invalid IPA Payload')
        if any(n.startswith('/')or'..'in n.split('/')or n.endswith('embedded.mobileprovision')for n in names):raise ValueError('Unsafe IPA entries')

def artifact_stem(cfg):
    return cfg['scheme']+'-iOS-'+cfg['version']+'-build'+str(cfg['build_number'])

def package_source(source,out,cfg,source_sha):
    package=out/(artifact_stem(cfg)+'-source.zip')
    with zipfile.ZipFile(package,'w',compression=zipfile.ZIP_DEFLATED) as z:
        for p in sorted(source.rglob('*')):
            if p.is_symlink():raise ValueError('Unsafe source archive symlink')
            if not p.is_file():continue
            rel=p.relative_to(source)
            if rel.parts[0] not in {'Sources','Resources'} and str(rel) not in {'project.yml','project.json','README.md','BUILD_NOTES.md'}:continue
            if p.suffix.lower() in {'.p12','.pem','.key','.mobileprovision'}:raise ValueError('Signing files forbidden in source archive')
            z.write(p,cfg['scheme']+'-iOS/'+rel.as_posix())
        z.writestr(cfg['scheme']+'-iOS/SOURCE-COMMIT.txt',source_sha+'\n')
    with zipfile.ZipFile(package) as z:
        if z.testzip():raise ValueError('Source archive integrity failed')
    return package

def build():
    identity(os.environ);root=Path(os.environ['GITHUB_WORKSPACE']);temp=Path(os.environ['RUNNER_TEMP']);out=root/'native-output';out.mkdir(exist_ok=True)
    report={'project_id':os.environ['PROJECT_ID'],'request_id':os.environ['REQUEST_ID'],'source_sha':os.environ['SOURCE_SHA'],'project_type':'native_ios','platform':'native_ios_unsigned','build_result':'failure','code_signing':'unsigned','requires_signing':True,'install_ready':False,'signature_verified':False,'compile_passed':False,'analyze_passed':False,'tests_passed':False,'tests_status':'not_run_no_test_target','device_build_verified':False,'package_verified':False,'physical_phone_tested':False,'files':[]};logs=[]
    def run(args,cwd=None):
        result=subprocess.run(list(map(str,args)),cwd=cwd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8',errors='replace',timeout=1500)
        logs.append('$ '+' '.join(map(str,args))+'\n'+result.stdout)
        (out/'build.log').write_text('\n'.join(logs)[-500000:])
        if result.returncode:raise RuntimeError('Command failed: '+str(args[0])+' (exit '+str(result.returncode)+')')
        return result.stdout
    try:
        source=root/'projects'/report['project_id'];work=temp/('native-ios-'+report['request_id']);cfg=prepare(source,work)
        if cfg['project_id']!=report['project_id']:raise ValueError('Project ID mismatch')
        report.update(app_name=cfg['app_name'],bundle_id=cfg['bundle_id'],version=cfg['version'],build_number=str(cfg['build_number']))
        report['xcode_version']=run(['xcodebuild','-version']).strip();report['xcodegen_version']=run(['xcodegen','--version']).strip()
        run(['xcodegen','generate','--spec','native-project.json'],work)
        common=['xcodebuild','-project',cfg['scheme']+'.xcodeproj','-scheme',cfg['scheme'],'-configuration','Release','-sdk','iphoneos','-destination','generic/platform=iOS','CODE_SIGNING_ALLOWED=NO','CODE_SIGNING_REQUIRED=NO','CODE_SIGN_IDENTITY=','COMPILER_INDEX_STORE_ENABLE=NO']
        archive=temp/(report['request_id']+'.xcarchive')
        run(common+['-archivePath',archive,'archive'],work);report['compile_passed']=True
        run(common+['analyze'],work);report['analyze_passed']=True
        apps=list((archive/'Products/Applications').glob('*.app'))
        if len(apps)!=1:raise ValueError('Expected one archived iPhone app')
        app=apps[0];info,archs=verify_bundle(app,cfg,run);report['device_build_verified']=True;report['architectures']=archs
        payload=temp/(report['request_id']+'-payload')/'Payload';payload.mkdir(parents=True)
        run(['ditto',app,payload/app.name])
        package=out/(artifact_stem(cfg)+'-ios-unsigned.ipa');run(['ditto','-c','-k','--keepParent',payload,package])
        verify_ipa(package,app.name,info['CFBundleExecutable']);report['package_verified']=True
        source_zip=package_source(source,out,cfg,report['source_sha']);report['source_package_verified']=True
        report['files']=[{'name':f.name,'size_bytes':f.stat().st_size,'sha256':hashlib.sha256(f.read_bytes()).hexdigest()} for f in [package,source_zip]]
        (out/'SIGN-BEFORE-INSTALL.txt').write_text('UNSIGNED arm64 iPhone device IPA. MUST BE SIGNED BEFORE INSTALLATION.\nUse your compatible UDID certificate/profile signing service. No signing credentials or device ID were used by this build. Physical-device behavior and signing-service compatibility have not been tested.\n')
        report['build_result']='success'
    except Exception as exc:report['error']=str(exc);logs.append(str(exc))
    finally:
        (out/'Build-Report.json').write_text(json.dumps(report,indent=2));(out/'build.log').write_text('\n'.join(logs)[-500000:])
    print('Native iPhone build:',report['build_result'],'— see Build-Report.json and build.log')
    if report['build_result']!='success':raise SystemExit(1)

if __name__=='__main__':build()
