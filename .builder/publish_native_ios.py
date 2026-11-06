"""Publish only identity- and hash-verified unsigned native iPhone packages."""
import hashlib,json,os,re,subprocess
from pathlib import Path

def verify(folder,env):
    pid=env['PROJECT_ID'];request=env['REQUEST_ID'];sha=env['SOURCE_SHA']
    if not re.fullmatch(r'[a-z][a-z0-9_]{1,39}',pid)or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_-]{5,63}',request)or not re.fullmatch(r'[a-f0-9]{40}',sha):raise ValueError('Invalid release identity')
    report=folder/'Build-Report.json'
    if report.is_symlink():raise ValueError('Unsafe report')
    data=json.loads(report.read_text())
    expected={'project_id':pid,'request_id':request,'source_sha':sha,'platform':'native_ios_unsigned','project_type':'native_ios','build_result':'success','compile_passed':True,'analyze_passed':True,'device_build_verified':True,'package_verified':True,'code_signing':'unsigned','signature_verified':False,'requires_signing':True,'install_ready':False}
    if any(data.get(k)!=v for k,v in expected.items()):raise ValueError('Native report identity or validation failed')
    if data.get('source_package_verified') is not True:raise ValueError('Source archive not verified')
    actual=[];packages=[]
    for entry in data.get('files',[]):
        name=entry.get('name','')
        if not re.fullmatch(r'[A-Za-z][A-Za-z0-9_]{0,49}-iOS-\d+\.\d+\.\d+-build\d{1,9}-(?:ios-unsigned\.ipa|source\.zip)',name):raise ValueError('Invalid versioned filename')
        if '-iOS-'+data['version']+'-build'+str(data['build_number'])+'-' not in name:raise ValueError('Filename/version mismatch')
        package=folder/name
        if package.is_symlink()or not package.is_file():raise ValueError('Missing/unsafe package')
        packages.append(package);actual.append({'name':name,'size_bytes':package.stat().st_size,'sha256':hashlib.sha256(package.read_bytes()).hexdigest()})
    if len(packages)!=2 or sum(f.suffix=='.ipa' for f in packages)!=1 or sum(f.name.endswith('-source.zip') for f in packages)!=1:raise ValueError('IPA and matching source ZIP required')
    if data.get('files')!=actual:raise ValueError('Native package hash or size mismatch')
    sums=folder/'SHA256SUMS.txt';sums.write_text(''.join(f['sha256']+'  '+f['name']+'\n' for f in actual))
    return [*packages,report,sums,*([folder/'CHANGELOG.md'] if (folder/'CHANGELOG.md').is_file() else [])]

def main():
    folder=Path('native-release');files=verify(folder,os.environ);repo=os.environ['GITHUB_REPOSITORY']
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+',repo):raise ValueError('Invalid repository')
    tag='builds/'+os.environ['PROJECT_ID']+'/'+os.environ['REQUEST_ID']+'/native_ios_unsigned'
    data=json.loads((folder/'Build-Report.json').read_text())
    title=data.get('app_name',os.environ['PROJECT_ID'])+' iOS '+data['version']+' (build '+str(data['build_number'])+')'
    notes=folder/'release-notes.txt';notes.write_text(title+'\nNative Swift iPhone device build from '+os.environ['SOURCE_SHA']+'. Compilation, static analysis, arm64 device bundle and IPA Payload checks passed. Matching source ZIP and SHA256SUMS included.\n\nMUST BE SIGNED BEFORE INSTALLATION. No credentials or UDIDs were used. See tests_status in Build-Report.json for the exact test scope. Full app/UI tests, Cloudflare completion and physical-device behavior were not verified.\n')
    subprocess.run(['gh','release','create',tag,*map(str,files),'--repo',repo,'--draft','--target',os.environ['SOURCE_SHA'],'--title',title,'--notes-file',str(notes),'--latest=false'],check=True)
    subprocess.run(['gh','release','edit',tag,'--repo',repo,'--draft=false','--latest=false'],check=True)

if __name__=='__main__':main()
