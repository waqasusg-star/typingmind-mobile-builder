"""Publish verified packages in a separate job without executing app source."""
import hashlib,json,os,re,subprocess
from pathlib import Path

def verified_files(folder, platform):
    pid=os.environ['PROJECT_ID'];request=os.environ['REQUEST_ID'];sha=os.environ['SOURCE_SHA']
    if not re.fullmatch(r'[a-z][a-z0-9_]{1,39}',pid) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_-]{5,63}',request) or not re.fullmatch(r'[a-f0-9]{40}',sha):
        raise ValueError('Invalid release identity')
    report_path=folder/'Build-Report.json'
    if report_path.is_symlink():raise ValueError('Unsafe report')
    report=json.loads(report_path.read_text())
    expected={'project_id':pid,'request_id':request,'source_sha':sha,'platform':platform,'build_result':'success','analyze_passed':True,'tests_passed':True}
    if platform in {'android','ios'}:expected['signature_verified']=True
    elif platform=='windows':expected.update(installer_smoke_passed=True,runtime_smoke_passed=True,code_signing='unsigned')
    elif platform=='extension':expected.update(browser_smoke_passed=True,code_signing='unpacked-extension-zip')
    else:raise ValueError('Unsupported release platform')
    if any(report.get(k)!=v for k,v in expected.items()):raise ValueError('Build report does not match this successful signed build')
    names={'android':[pid+'-android.apk'],'ios':[pid+'-ios.ipa'],'windows':[pid+'-windows-setup.exe',pid+'-windows-portable.zip'],'extension':[pid+'-chrome-extension.zip']}[platform]
    actual=[];packages=[]
    for name in names:
        package=folder/name
        if package.is_symlink() or not package.is_file():raise ValueError('Missing or unsafe package')
        digest=hashlib.sha256(package.read_bytes()).hexdigest()
        actual.append({'name':name,'size_bytes':package.stat().st_size,'sha256':digest});packages.append(package)
    if report.get('files')!=actual:raise ValueError('Package hash or size differs from build report')
    checksum=folder/'SHA256SUMS.txt';checksum.write_text(''.join(f['sha256']+'  '+f['name']+'\n'for f in actual))
    return [*packages,report_path,checksum]

def main():
    repo=os.environ['GITHUB_REPOSITORY']
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+',repo):raise ValueError('Invalid repository')
    for platform in ['android','ios','windows','extension']:
        folder=Path('release-input')/platform
        if not folder.is_dir():continue
        files=verified_files(folder,platform)
        tag='builds/'+os.environ['PROJECT_ID']+'/'+os.environ['REQUEST_ID']+'/'+platform
        notes=folder/'release-notes.txt'
        verification={'android':'Android signature verified. No physical phone tested.','ios':'Apple signature verified. Installation requires the matching registered iPhone and unexpired profile. No physical phone tested.','windows':'Installer deployment and app launch smoke tests passed on CI. Executables are unsigned; Windows may show an unknown-publisher warning.','extension':'Loaded in Chromium and behavior tests passed. ZIP requires extraction and Load unpacked, or separate Web Store review. No store publication performed.'}[platform]
        notes.write_text('Built from '+os.environ['SOURCE_SHA']+'. Analysis and tests passed. '+verification+'\n\nDownloads have no automatic Actions artifact expiry. Availability depends on the repository and GitHub.\n')
        common=['--repo',repo]
        subprocess.run(['gh','release','create',tag,*map(str,files),*common,'--draft','--target',os.environ['SOURCE_SHA'],'--title',os.environ['PROJECT_ID']+' / '+platform+' / '+os.environ['REQUEST_ID'],'--notes-file',str(notes),'--latest=false'],check=True)
        subprocess.run(['gh','release','edit',tag,*common,'--draft=false','--latest=false'],check=True)
        with open(os.environ['GITHUB_STEP_SUMMARY'],'a')as summary:
            summary.write('Verified '+platform+' download: https://github.com/'+repo+'/releases/tag/'+tag+'\n')

if __name__=='__main__':main()
