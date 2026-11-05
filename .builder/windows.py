"""Build, install and launch a real Windows package on the Windows CI worker."""
import hashlib,importlib.util,json,os,shutil,subprocess,time,uuid,zipfile
from pathlib import Path

spec=importlib.util.spec_from_file_location('worker',Path(__file__).with_name('build.py'));worker=importlib.util.module_from_spec(spec);spec.loader.exec_module(worker)

def build():
    worker.validate();root=Path(os.environ['GITHUB_WORKSPACE']);temp=Path(os.environ['RUNNER_TEMP']);out=root/'output';out.mkdir(exist_ok=True)
    report={'project_id':os.environ['PROJECT_ID'],'request_id':os.environ['REQUEST_ID'],'source_sha':os.environ['SOURCE_SHA'],'platform':'windows','build_result':'failure','analyze_passed':False,'tests_passed':False,'signature_verified':False,'code_signing':'unsigned','installer_smoke_passed':False,'runtime_smoke_passed':False,'physical_device_tested':False,'files':[]};logs=[]
    def run(args,cwd=None):
        args=list(map(str,args))
        if args[0]=='flutter':args[0]=shutil.which('flutter') or 'flutter'
        r=subprocess.run(args,cwd=cwd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8',errors='replace',timeout=1200)
        logs.append('$ '+' '.join(args)+'\n'+r.stdout)
        if r.returncode:raise RuntimeError('Command failed: '+Path(args[0]).name)
        return r.stdout
    try:
        work=temp/'windows-app';cfg=worker.prepare(root/'projects'/report['project_id'],work,run,'windows')
        report['flutter_sdk']=json.loads(run(['flutter','--version','--machine']))
        run(['flutter','pub','get'],work);run(['flutter','analyze'],work);report['analyze_passed']=True
        run(['flutter','test'],work);report['tests_passed']=True
        run(['flutter','build','windows','--release','--build-number',os.environ['GITHUB_RUN_NUMBER']],work)
        release=work/'build/windows/x64/runner/Release';pid=report['project_id']
        if not(release/(pid+'.exe')).is_file() or not(release/'flutter_windows.dll').is_file() or not(release/'data').is_dir():raise ValueError('Incomplete Windows runtime bundle')
        vswhere=Path(os.environ['ProgramFiles(x86)'])/'Microsoft Visual Studio/Installer/vswhere.exe'
        vs=Path(run([vswhere,'-latest','-products','*','-property','installationPath']).strip())
        candidates=sorted((vs/'VC/Redist/MSVC').glob('*/x64/Microsoft.VC*.CRT'))
        if not candidates:raise ValueError('Visual C++ runtime DLLs unavailable')
        for dll in candidates[-1].glob('*.dll'):shutil.copy2(dll,release/dll.name)
        for name in ['msvcp140.dll','vcruntime140.dll','vcruntime140_1.dll']:
            if not(release/name).is_file():raise ValueError('Missing C++ runtime '+name)
        portable=out/(pid+'-windows-portable.zip')
        with zipfile.ZipFile(portable,'w',zipfile.ZIP_DEFLATED)as z:
            for p in sorted(release.rglob('*')):
                if p.is_file():z.write(p,p.relative_to(release))
        installer_name=pid+'-windows-setup'
        appname=cfg['app_name'].replace('{','{{').replace('"','""')
        script=temp/'installer.iss'
        script.write_text(f'''[Setup]
AppId={uuid.uuid5(uuid.NAMESPACE_DNS,cfg['bundle_id'])}
AppName={appname}
AppVersion=1.0.{os.environ['GITHUB_RUN_NUMBER']}
DefaultDirName={{localappdata}}\\Programs\\{pid}
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir={out}
OutputBaseFilename={installer_name}
Compression=lzma2
SolidCompression=yes
UninstallDisplayIcon={{app}}\\{pid}.exe
[Files]
Source: "{release}\\*"; DestDir: "{{app}}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{{autoprograms}}\\{pid}"; Filename: "{{app}}\\{pid}.exe"
''',encoding='utf-8-sig')
        iscc=shutil.which('ISCC') or str(Path(os.environ['ProgramFiles(x86)'])/'Inno Setup 6/ISCC.exe')
        run([iscc,script]);installer=out/(installer_name+'.exe')
        if not installer.is_file() or installer.read_bytes()[:2]!=b'MZ':raise ValueError('Missing executable installer')
        installed=temp/'installed-smoke';run([installer,'/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-','/DIR='+str(installed)])
        exe=installed/(pid+'.exe')
        if not exe.is_file() or not(installed/'data').is_dir():raise ValueError('Installer did not deploy the app')
        report['installer_smoke_passed']=True
        proc=subprocess.Popen([str(exe)],cwd=installed,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        try:
            time.sleep(8)
            if proc.poll()is not None:raise ValueError('Installed app exited during launch smoke test')
            report['runtime_smoke_passed']=True
        finally:
            if proc.poll()is None:proc.terminate();proc.wait(timeout=15)
        run([installed/'unins000.exe','/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART'])
        report['files']=[{'name':p.name,'size_bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in [installer,portable]]
        report['build_result']='success'
    except Exception as e:report['error']=str(e);logs.append(str(e))
    finally:
        (out/'Build-Report.json').write_text(json.dumps(report,indent=2),encoding='utf-8');(out/'build.log').write_text('\n'.join(logs)[-120000:],encoding='utf-8')
    print('Windows result:',report['build_result'])
    if report['build_result']!='success':raise SystemExit(1)

if __name__=='__main__':build()
