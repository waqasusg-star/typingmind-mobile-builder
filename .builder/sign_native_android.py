"""Sign verified native APK in a job that does not execute app code, then publish downloads."""
import base64,hashlib,json,os,re,subprocess
from pathlib import Path

def record(p):return dict(name=p.name,size_bytes=p.stat().st_size,sha256=hashlib.sha256(p.read_bytes()).hexdigest())
def validate(folder,env):
 r=json.loads((folder/'Build-Report.json').read_text())
 for key in ['PROJECT_ID','REQUEST_ID','SOURCE_SHA']:
  if r.get(key.lower())!=env[key]:raise ValueError('Artifact identity mismatch')
 for k in ['compile_passed','analyze_passed','tests_passed','lint_passed','package_verified','source_package_verified']:
  if r.get(k) is not True:raise ValueError('Missing '+k)
 if r.get('build_result')!='success' or r.get('platform')!='native_android':raise ValueError('Not a successful native Android build')
 if len(r.get('files',[]))!=2:raise ValueError('Expected unsigned APK and source ZIP')
 for f in r['files']:
  if not re.fullmatch(r'HDrama-Android-\d+\.\d+\.\d+-build\d+-(?:unsigned\.apk|source\.zip)',f['name']):raise ValueError('Unexpected artifact name')
  p=folder/f['name']
  if p.is_symlink() or record(p)!=f:raise ValueError('Artifact hash mismatch')
 return r

def main():
 folder=Path('native-android-release');r=validate(folder,os.environ);report=folder/'Build-Report.json';log=folder/'signing.log';lines=[];keyfile=Path(os.environ['RUNNER_TEMP'])/'native-android.keystore'
 def run(args):
  p=subprocess.run(list(map(str,args)),stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=120)
  # Passwords are passed by environment-variable name and never printed.
  lines.append('$ '+' '.join(map(str,args))+'\n'+p.stdout)
  if p.returncode:raise RuntimeError(str(args[0])+' exit '+str(p.returncode))
  return p.stdout
 try:
  required=['ANDROID_KEYSTORE_BASE64','ANDROID_KEYSTORE_PASSWORD','ANDROID_KEY_ALIAS','ANDROID_KEY_PASSWORD']
  missing=[k for k in required if not os.environ.get(k)]
  if missing:raise ValueError('Signing unavailable; configure existing matching key in repository Secrets: '+', '.join(missing))
  keyfile.write_bytes(base64.b64decode(os.environ['ANDROID_KEYSTORE_BASE64'],validate=True));keyfile.chmod(0o600)
  original=folder/next(f['name'] for f in r['files'] if f['name'].endswith('.apk'));package=folder/original.name.replace('-unsigned.apk','.apk');tools=Path(os.environ['ANDROID_HOME'])/'build-tools/35.0.0'
  aligned=Path(os.environ['RUNNER_TEMP'])/'native-aligned.apk';run([tools/'zipalign','-p','-f','4',original,aligned])
  run([tools/'apksigner','sign','--ks',keyfile,'--ks-key-alias',os.environ['ANDROID_KEY_ALIAS'],'--ks-pass','env:ANDROID_KEYSTORE_PASSWORD','--key-pass','env:ANDROID_KEY_PASSWORD','--out',package,aligned])
  verified=run([tools/'apksigner','verify','--verbose','--print-certs',package]);certificate=re.search(r'Signer #1 certificate SHA-256 digest: ([a-fA-F0-9]+)',verified)
  if not certificate:raise ValueError('Signing certificate fingerprint missing')
  digest=certificate.group(1).lower();r.update(signature_verified=True,code_signing='configured_repository_key',certificate_sha256=digest,upgrade_compatible=digest==r.get('original_certificate_sha256'),install_ready=True)
  source=folder/next(f['name'] for f in r['files'] if f['name'].endswith('-source.zip'));original.unlink();r['files']=[record(p) for p in [package,source]];r['signing_result']='success';report.write_text(json.dumps(r,indent=2))
  sums=folder/'SHA256SUMS.txt';sums.write_text(''.join(f['sha256']+'  '+f['name']+'\n' for f in r['files']))
  notes=folder/'release-notes.txt';notes.write_text('HDrama Android '+r['version']+' build '+r['build_number']+'\nSource '+r['source_sha']+'\nUnit/Robolectric tests, lint, compilation and package/signature checks passed. Physical-device behavior was not tested.\n'+('Signing certificate matches the supplied APK.\n' if r['upgrade_compatible'] else 'SIGNING CERTIFICATE DIFFERS FROM THE SUPPLIED APK: this file cannot update that installed copy. Preserve existing data; do not uninstall to replace without an appropriate backup. The original signing key is needed for a compatible update.\n'))
  repo=os.environ['GITHUB_REPOSITORY'];tag='builds/'+r['project_id']+'/'+r['request_id']+'/native_android';files=[package,source,report,sums,*([folder/'CHANGELOG.md'] if(folder/'CHANGELOG.md').is_file() else [])]
  run(['gh','release','create',tag,*files,'--repo',repo,'--draft','--target',r['source_sha'],'--title','HDrama Android '+r['version']+' (build '+r['build_number']+')','--notes-file',notes,'--latest=false'])
  run(['gh','release','edit',tag,'--repo',repo,'--draft=false','--latest=false'])
 except Exception as e:r.update(signing_result='failure',error=str(e));report.write_text(json.dumps(r,indent=2));raise
 finally:
  keyfile.unlink(missing_ok=True)
  text='\n'.join(lines)
  for k in ['ANDROID_KEYSTORE_BASE64','ANDROID_KEYSTORE_PASSWORD','ANDROID_KEY_PASSWORD']:
   if os.environ.get(k):text=text.replace(os.environ[k],'[REDACTED]')
  log.write_text(text[-100000:])
if __name__=='__main__':main()
