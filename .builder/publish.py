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
    expected={'project_id':pid,'request_id':request,'source_sha':sha,'platform':platform,'build_result':'success','analyze_passed':True,'tests_passed':True,'signature_verified':True}
    if any(report.get(k)!=v for k,v in expected.items()):raise ValueError('Build report does not match this successful signed build')
    name=pid+('-android.apk' if platform=='android' else '-ios.ipa');package=folder/name
    if package.is_symlink() or not package.is_file():raise ValueError('Missing or unsafe package')
    digest=hashlib.sha256(package.read_bytes()).hexdigest()
    if report.get('files')!=[{'name':name,'size_bytes':package.stat().st_size,'sha256':digest}]:raise ValueError('Package hash or size differs from build report')
    checksum=folder/'SHA256SUMS.txt';checksum.write_text(digest+'  '+name+'\n')
    return [package,report_path,checksum]

def main():
    repo=os.environ['GITHUB_REPOSITORY']
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+',repo):raise ValueError('Invalid repository')
    for platform in ['android','ios']:
        folder=Path('release-input')/platform
        if not folder.is_dir():continue
        files=verified_files(folder,platform)
        tag='builds/'+os.environ['PROJECT_ID']+'/'+os.environ['REQUEST_ID']+'/'+platform
        notes=folder/'release-notes.txt'
        notes.write_text('Built from '+os.environ['SOURCE_SHA']+'. Analysis, tests and package signature verification passed. Physical phone testing is not implied.\n\nDownloads have no automatic Actions artifact expiry. Availability depends on the repository and GitHub. Apple signing validity remains separate.\n')
        common=['--repo',repo]
        subprocess.run(['gh','release','create',tag,*map(str,files),*common,'--draft','--target',os.environ['SOURCE_SHA'],'--title',os.environ['PROJECT_ID']+' / '+platform+' / '+os.environ['REQUEST_ID'],'--notes-file',str(notes),'--latest=false'],check=True)
        subprocess.run(['gh','release','edit',tag,*common,'--draft=false','--latest=false'],check=True)
        with open(os.environ['GITHUB_STEP_SUMMARY'],'a')as summary:
            summary.write('Verified '+platform+' download: https://github.com/'+repo+'/releases/tag/'+tag+'\n')

if __name__=='__main__':main()
