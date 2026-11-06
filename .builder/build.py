"""Private GitHub Actions build worker controlled by the TypingMind plugin."""
import base64,datetime,hashlib,json,os,plistlib,re,secrets,shutil,subprocess,sys,zipfile
from pathlib import Path
import xml.etree.ElementTree as ET

ANDROID_KEYS=['ANDROID_KEYSTORE_BASE64','ANDROID_KEYSTORE_PASSWORD','ANDROID_KEY_ALIAS','ANDROID_KEY_PASSWORD']
APPLE_KEYS=['APPLE_CERTIFICATE_P12_BASE64','APPLE_CERTIFICATE_PASSWORD','APPLE_PROVISIONING_PROFILE_BASE64','APPLE_TEAM_ID']

def validate():
    if not re.fullmatch(r'[a-z][a-z0-9_]{1,39}',os.environ['PROJECT_ID']):raise ValueError('Invalid project ID')
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_-]{5,63}',os.environ['REQUEST_ID']):raise ValueError('Invalid request ID')
    if not re.fullmatch(r'[a-f0-9]{40}',os.environ['SOURCE_SHA']):raise ValueError('Invalid source SHA')
    if os.environ['PLATFORM'] not in {'android','ios','both','windows','extension','ios_unsigned'}:raise ValueError('Invalid platform')

def readiness():
    validate();platform=os.environ['PLATFORM'];report={'project_id':os.environ['PROJECT_ID'],'request_id':os.environ['REQUEST_ID'],'source_sha':os.environ['SOURCE_SHA']}
    for name,keys in [('android',ANDROID_KEYS),('ios',APPLE_KEYS)]:
        missing=[k for k in keys if os.environ.get('HAS_'+k)!='true'] if platform in {name,'both'} else []
        report[name+'_ready']=platform in {name,'both'} and not missing
        report[name+'_missing_signing']=missing
    report['windows_ready']=platform=='windows';report['extension_ready']=platform=='extension'
    report['ios_unsigned_ready']=platform=='ios_unsigned'
    report['ios_unsigned_note']='Device IPA export without signing credentials. Must be signed with a compatible certificate/profile before installation.'
    report['windows_signing']='Unsigned installer unless a trusted code-signing service is added. No self-signed trust changes.'
    report['note']='Presence check only. Skipped/missing platforms have produced no installable app. Actual signing is validated later.'
    Path('readiness').mkdir(exist_ok=True);Path('readiness/Build-Readiness.json').write_text(json.dumps(report,indent=2))
    with open(os.environ['GITHUB_OUTPUT'],'a')as f:
        for name in ['android','ios','windows','extension','ios_unsigned']:f.write(name+'='+str(report[name+'_ready']).lower()+'\n')
    with open(os.environ['GITHUB_STEP_SUMMARY'],'a')as f:f.write('```json\n'+json.dumps(report,indent=2)+'\n```\n')

def prepare(source,work,run,platforms='android,ios'):
    if source.is_symlink() or not source.is_dir():raise ValueError('Missing/unsafe source directory')
    cfg=json.loads((source/'project.json').read_text());pid=cfg['project_id']
    if pid!=os.environ['PROJECT_ID']:raise ValueError('Project metadata mismatch')
    bundle=cfg.get('bundle_id','');name=cfg.get('app_name','')
    if not re.fullmatch(r'[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*){2,}',bundle)or len(bundle)>150:raise ValueError('Invalid bundle ID')
    if not name or len(name)>80 or any(ord(c)<32 for c in name):raise ValueError('Invalid app name')
    for p in source.rglob('*'):
        if p.is_symlink():raise ValueError('Symlink source refused')
        if p.is_file()and p.stat().st_size>1048576:raise ValueError('Source file too large')
    if not(source/'lib/main.dart').is_file():raise ValueError('Missing app implementation')
    if work.exists():raise ValueError('Build directory already exists')
    if cfg.get('project_type','flutter')!='flutter':raise ValueError('This is not a Flutter app')
    run(['flutter','create','--project-name',pid,'--org','com.worldgate','--platforms',platforms,'--no-pub',str(work)])
    shutil.rmtree(work/'test',ignore_errors=True)
    for p in source.iterdir():
        if p.name in {'lib','test','assets'}:
            if not p.is_dir():raise ValueError('Expected source directory')
            shutil.rmtree(work/p.name,ignore_errors=True);shutil.copytree(p,work/p.name)
        elif p.name in {'pubspec.yaml','analysis_options.yaml','README.md','CHANGELOG.md'}:shutil.copy2(p,work/p.name)
        elif p.name!='project.json':raise ValueError('Unsupported project-root file')
    if not(source/'pubspec.yaml').exists():
        (work/'pubspec.yaml').write_text(f'name: {pid}\ndescription: App built from TypingMind\npublish_to: none\nversion: 1.0.0+1\nenvironment:\n  sdk: ">=3.4.0 <4.0.0"\ndependencies:\n  flutter:\n    sdk: flutter\ndev_dependencies:\n  flutter_test:\n    sdk: flutter\nflutter:\n  uses-material-design: true\n')
    if not re.search(r'^name:\s*[\'\"]?'+re.escape(pid)+r'[\'\"]?\s*$',(work/'pubspec.yaml').read_text(),re.M):raise ValueError('pubspec name must match project ID')
    if not(source/'analysis_options.yaml').exists():(work/'analysis_options.yaml').write_text('analyzer:\n  errors:\n    unused_import: warning\n')
    if not list((work/'test').glob('**/*_test.dart')):raise ValueError('Add a meaningful Flutter test before building')
    if platforms=='windows':return cfg
    kts=work/'android/app/build.gradle.kts';groovy=work/'android/app/build.gradle';gradle=kts if kts.exists()else groovy
    text=gradle.read_text()
    if kts.exists():
        text=re.sub(r'applicationId\s*=\s*"[^"]+"',f'applicationId = "{bundle}"',text)
        text+='''\nandroid {
 signingConfigs { create("premiumRelease") {
  storeFile = file(System.getenv("MAB_KEYSTORE_PATH"))
  storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
  keyAlias = System.getenv("ANDROID_KEY_ALIAS")
  keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
 } }
 buildTypes.getByName("release") { signingConfig = signingConfigs.getByName("premiumRelease") }
}\n'''
    else:
        text=re.sub(r'applicationId\s+[\'\"][^\'\"]+[\'\"]',f'applicationId "{bundle}"',text)
        text+='''\nandroid {
 signingConfigs { premiumRelease {
  storeFile file(System.getenv('MAB_KEYSTORE_PATH'))
  storePassword System.getenv('ANDROID_KEYSTORE_PASSWORD')
  keyAlias System.getenv('ANDROID_KEY_ALIAS')
  keyPassword System.getenv('ANDROID_KEY_PASSWORD')
 } }
 buildTypes { release { signingConfig signingConfigs.premiumRelease } }
}\n'''
    gradle.write_text(text)
    manifest=work/'android/app/src/main/AndroidManifest.xml';tree=ET.parse(manifest);ns='http://schemas.android.com/apk/res/android';ET.register_namespace('android',ns)
    app=tree.getroot().find('application');app.set('{'+ns+'}label',name);app.set('{'+ns+'}usesCleartextTraffic','false')
    if not any(p.get('{'+ns+'}name')=='android.permission.INTERNET'for p in tree.getroot().findall('uses-permission')):ET.SubElement(tree.getroot(),'uses-permission',{'{'+ns+'}name':'android.permission.INTERNET'})
    tree.write(manifest,encoding='utf-8',xml_declaration=True)
    pbx=work/'ios/Runner.xcodeproj/project.pbxproj';pbx.write_text(pbx.read_text().replace('com.worldgate.'+pid,bundle))
    info=work/'ios/Runner/Info.plist'
    with info.open('rb')as f:plist=plistlib.load(f)
    plist['CFBundleDisplayName']=name
    with info.open('wb')as f:plistlib.dump(plist,f)
    return cfg


def app_version(work):
    match=re.search(r"""(?m)^version:\s*['"]?(\d+\.\d+\.\d+)\+(\d{1,9})['"]?\s*(?:#.*)?$""",(work/'pubspec.yaml').read_text())
    if not match:raise ValueError('Set pubspec version explicitly as MAJOR.MINOR.PATCH+BUILD')
    return match.group(1),match.group(2)

def package_source(source,work,out,platform,report):
    excluded={'.git','.dart_tool','.idea','.vscode','build','ephemeral'}
    entries={}
    def add_tree(base,prefix=''):
        for p in sorted(base.rglob('*')):
            rel=p.relative_to(base)
            if any(part in excluded for part in rel.parts):continue
            if p.is_symlink():raise ValueError('Source archive refuses symlinks')
            if not p.is_file():continue
            if p.suffix.lower() in {'.p12','.pfx','.jks','.keystore','.mobileprovision','.pem','.key'}:raise ValueError('Signing material refused in source archive')
            if p.stat().st_size>2097152:raise ValueError('Source archive contains an oversized file')
            entries[prefix+rel.as_posix()]=p.read_bytes()
    add_tree(work)
    if platform=='extension':
        if (source/'tests').is_dir():add_tree(source/'tests','tests/')
        entries['tools/test_extension.cjs']=Path(__file__).with_name('test_extension.cjs').read_bytes()
    for name in ['project.json','README.md','CHANGELOG.md']:
        p=source/name
        if not p.is_file() or p.is_symlink():raise ValueError('Complete source delivery requires '+name)
        entries[name]=p.read_bytes()
        if name!='project.json':shutil.copy2(p,out/name)
    entries['BUILDER-SOURCE.json']=json.dumps({'schema':1,'project_id':report['project_id'],'source_sha':report['source_sha'],'platform':platform,'version':report.get('version'),'build_number':report.get('build_number'),'build_tools':'Flutter SDK and platform toolchain' if platform=='windows' else 'Chrome Manifest V3; optional Playwright test harness in tools/'},indent=2).encode()
    if sum(map(len,entries.values()))>20971520:raise ValueError('Source archive exceeds 20 MiB')
    package=out/(report['project_id']+'-'+platform+'-source.zip')
    with zipfile.ZipFile(package,'w',zipfile.ZIP_DEFLATED)as z:
        for name,data in sorted(entries.items()):z.writestr(name,data)
    with zipfile.ZipFile(package)as z:
        if z.testzip()or set(z.namelist())!=set(entries):raise ValueError('Source archive validation failed')
    report['source_package_verified']=True
    return package

def build(platform):
    validate();root=Path(os.environ['GITHUB_WORKSPACE']);temp=Path(os.environ['RUNNER_TEMP']);output=root/'output';output.mkdir(exist_ok=True)
    work=temp/'mobile-app';logs=[];sensitive=[os.environ[k]for k in ANDROID_KEYS+APPLE_KEYS if os.environ.get(k)]
    report={'project_id':os.environ['PROJECT_ID'],'request_id':os.environ['REQUEST_ID'],'source_sha':os.environ['SOURCE_SHA'],'platform':platform,'build_result':'failure','analyze_passed':False,'tests_passed':False,'signature_verified':False,'physical_phone_tested':False,'store_published':False,'files':[]}
    keychain=None;profile_path=None;keyfile=None
    def run(args,cwd=None):
        result=subprocess.run([str(x)for x in args],cwd=cwd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
        logs.append('$ '+' '.join(str(x)for x in args)+'\n'+result.stdout)
        if result.returncode:raise RuntimeError('Command failed: '+str(args[0]))
        return result.stdout
    try:
        required=ANDROID_KEYS if platform=='android'else APPLE_KEYS
        if any(not os.environ.get(k)for k in required):raise ValueError('Required signing configuration is missing')
        if platform=='android':
            keyfile=temp/'android-release.keystore';keyfile.write_bytes(base64.b64decode(os.environ['ANDROID_KEYSTORE_BASE64'],validate=True));keyfile.chmod(0o600);os.environ['MAB_KEYSTORE_PATH']=str(keyfile)
        cfg=prepare(root/'projects'/os.environ['PROJECT_ID'],work,run)
        report['flutter_sdk']=json.loads(run(['flutter','--version','--machine']))
        run(['flutter','pub','get'],work)
        run(['flutter','analyze'],work);report['analyze_passed']=True
        run(['flutter','test'],work);report['tests_passed']=True
        number=os.environ['GITHUB_RUN_NUMBER']
        if platform=='android':
            run(['flutter','build','apk','--release','--build-number',number],work)
            package=output/(cfg['project_id']+'-android.apk');shutil.copy2(work/'build/app/outputs/flutter-apk/app-release.apk',package)
            sdk=Path(os.environ.get('ANDROID_HOME',os.environ.get('ANDROID_SDK_ROOT','')))
            signers=sorted((sdk/'build-tools').glob('*/apksigner'))
            if not signers:raise RuntimeError('Android signature verifier missing')
            run([signers[-1],'verify','--verbose','--print-certs',package]);report['signature_verified']=True
        else:
            run(['flutter','build','ios','--release','--no-codesign','--build-number',number],work)
            team=os.environ['APPLE_TEAM_ID']
            if not re.fullmatch(r'[A-Z0-9]{10}',team):raise ValueError('Invalid Apple Team ID')
            keyfile=temp/'signing.p12';keyfile.write_bytes(base64.b64decode(os.environ['APPLE_CERTIFICATE_P12_BASE64'],validate=True));keyfile.chmod(0o600)
            profile=temp/'signing.mobileprovision';profile.write_bytes(base64.b64decode(os.environ['APPLE_PROVISIONING_PROFILE_BASE64'],validate=True))
            raw=subprocess.run(['security','cms','-D','-i',str(profile)],check=True,capture_output=True).stdout;provision=plistlib.loads(raw)
            if provision.get('Entitlements',{}).get('application-identifier')!=team+'.'+cfg['bundle_id']or team not in provision.get('TeamIdentifier',[]):raise ValueError('Apple profile app ID/team mismatch')
            if provision.get('ExpirationDate',datetime.datetime.min)<=datetime.datetime.utcnow():raise ValueError('Apple profile expired')
            if not provision.get('ProvisionedDevices')or provision.get('Entitlements',{}).get('get-task-allow'):raise ValueError('A matching ad hoc distribution profile covering the target iPhone is required')
            uuid=provision['UUID']
            if not re.fullmatch(r'[A-Fa-f0-9-]{36}',uuid):raise ValueError('Invalid profile UUID')
            profile_path=Path.home()/'Library/MobileDevice/Provisioning Profiles'/f'{uuid}.mobileprovision';profile_path.parent.mkdir(parents=True,exist_ok=True);profile_path.write_bytes(profile.read_bytes())
            keychain=temp/'mobile-builder.keychain-db';password=secrets.token_urlsafe(32);sensitive.append(password)
            run(['security','create-keychain','-p',password,keychain]);run(['security','set-keychain-settings','-lut','21600',keychain]);run(['security','unlock-keychain','-p',password,keychain])
            run(['security','import',keyfile,'-P',os.environ['APPLE_CERTIFICATE_PASSWORD'],'-T','/usr/bin/codesign','-T','/usr/bin/security','-t','cert','-f','pkcs12','-k',keychain])
            run(['security','list-keychains','-d','user','-s',keychain,'login.keychain-db']);run(['security','set-key-partition-list','-S','apple-tool:,apple:,codesign:','-s','-k',password,keychain])
            options=temp/'ExportOptions.plist'
            with options.open('wb')as f:plistlib.dump({'method':'release-testing','teamID':team,'signingStyle':'manual','signingCertificate':'Apple Distribution','provisioningProfiles':{cfg['bundle_id']:uuid},'manageAppVersionAndBuildNumber':False},f)
            archive=temp/'MobileApp.xcarchive';export=temp/'ipa-export'
            run(['xcodebuild','-workspace','ios/Runner.xcworkspace','-scheme','Runner','-configuration','Release','-destination','generic/platform=iOS','-archivePath',archive,'DEVELOPMENT_TEAM='+team,'CODE_SIGN_STYLE=Manual','CODE_SIGN_IDENTITY=Apple Distribution','PROVISIONING_PROFILE_SPECIFIER='+uuid,'archive'],work)
            run(['xcodebuild','-exportArchive','-archivePath',archive,'-exportPath',export,'-exportOptionsPlist',options],work)
            package=output/(cfg['project_id']+'-ios.ipa');shutil.copy2(export/'Runner.ipa',package)
            verify=temp/'verify-ipa'
            run(['unzip','-q',package,'-d',verify]);run(['codesign','--verify','--deep','--strict',verify/'Payload/Runner.app']);report['signature_verified']=True
        report['files']=[{'name':package.name,'size_bytes':package.stat().st_size,'sha256':hashlib.sha256(package.read_bytes()).hexdigest()}]
        report['build_result']='success'
    except Exception as exc:
        report['error']=str(exc);logs.append(str(exc))
    finally:
        if keychain:subprocess.run(['security','delete-keychain',str(keychain)],capture_output=True)
        if profile_path:profile_path.unlink(missing_ok=True)
        if keyfile:keyfile.unlink(missing_ok=True)
        text='\n'.join(logs)
        for value in sensitive:text=text.replace(value,'[REDACTED]')
        text=re.sub(r'(?:github_pat_|gh[pousr]_)[A-Za-z0-9_]+','[REDACTED]',text)
        (output/'build.log').write_text(text[-120000:])
        (output/'Build-Report.json').write_text(json.dumps(report,indent=2))
    print('Build result:',report['build_result'],'— see build report and diagnostics.')
    if report['build_result']!='success':raise SystemExit(1)

if __name__=='__main__':
    if sys.argv[1]=='readiness':readiness()
    elif sys.argv[1]in {'android','ios'}:build(sys.argv[1])
    else:raise SystemExit('Unknown build operation')
