"""Controlled Kotlin/Android build: reviewed dependencies, read-only CI, no uploaded Gradle scripts."""
import hashlib,json,os,re,shutil,subprocess,zipfile,xml.etree.ElementTree as ET
from pathlib import Path

def config(source):
 c=json.loads((source/'project.json').read_text())
 for k,p in [('project_id',r'[a-z][a-z0-9_]{1,39}'),('bundle_id',r'[A-Za-z][\w]*(?:\.[A-Za-z][\w]*){2,}'),('namespace',r'[A-Za-z][\w]*(?:\.[A-Za-z][\w]*){2,}'),('version',r'\d+\.\d+\.\d+'),('build_number',r'\d{1,9}')]:
  if not re.fullmatch(p,str(c.get(k,''))):raise ValueError('Invalid '+k)
 if c.get('project_type')!='native_android' or c.get('minimum_android')!=26 or c.get('target_android')!=35:raise ValueError('Unsupported native Android configuration')
 return c

def prepare(source,work):
 c=config(source);work.mkdir(parents=True,exist_ok=False)
 for p in source.rglob('*'):
  if p.is_symlink():raise ValueError('Symlink refused')
  if not p.is_file():continue
  rel=p.relative_to(source)
  if not str(rel).startswith(('app/src/main/','app/src/test/')):continue
  if p.suffix.lower() not in {'.kt','.java','.xml','.json','.txt','.png','.webp','.jpg','.jpeg','.svg'} or p.stat().st_size>1048576:raise ValueError('Unsupported source/resource')
  q=work/rel;q.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,q)
 if not (work/'app/src/main/AndroidManifest.xml').is_file():raise ValueError('Missing manifest')
 # Build scripts and dependency repositories are controlled, not imported from uploads.
 (work/'settings.gradle.kts').write_text('pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }\ndependencyResolutionManagement { repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS); repositories { google(); mavenCentral() } }\nrootProject.name="NativeAndroid"\ninclude(":app")\n')
 (work/'build.gradle.kts').write_text('plugins { id("com.android.application") version "8.9.2" apply false; id("org.jetbrains.kotlin.android") version "2.1.10" apply false }\n')
 (work/'gradle.properties').write_text('org.gradle.jvmargs=-Xmx3072m -Dfile.encoding=UTF-8\nandroid.useAndroidX=true\nkotlin.code.style=official\norg.gradle.caching=true\n')
 text='''plugins { id("com.android.application"); id("org.jetbrains.kotlin.android") }
android {
 namespace = "__NAMESPACE__"
 compileSdk = 35
 defaultConfig { applicationId = "__ID__"; minSdk = 26; targetSdk = 35; versionCode = __NUMBER__; versionName = "__VERSION__" }
 compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
 kotlinOptions { jvmTarget = "17" }
 buildTypes { release { isMinifyEnabled = false } }
 testOptions { unitTests.isIncludeAndroidResources = true; unitTests.all { it.systemProperty("robolectric.dependency.repo.url","https://repo.maven.apache.org/maven2"); it.maxHeapSize="2g" } }
}
dependencies {
 implementation("androidx.activity:activity-ktx:1.10.1")
 implementation("androidx.core:core-ktx:1.15.0")
 implementation("androidx.webkit:webkit:1.12.1")
 implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
 implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
 implementation("com.squareup.okhttp3:okhttp:4.12.0")
 implementation("org.jsoup:jsoup:1.18.3")
 implementation("androidx.media3:media3-exoplayer:1.5.1")
 implementation("androidx.media3:media3-exoplayer-hls:1.5.1")
 implementation("androidx.media3:media3-exoplayer-dash:1.5.1")
 implementation("androidx.media3:media3-datasource-okhttp:1.5.1")
 implementation("androidx.media3:media3-ui:1.5.1")
 testImplementation("junit:junit:4.13.2")
 testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.9.0")
 testImplementation("org.robolectric:robolectric:4.14.1")
 testImplementation("com.squareup.okhttp3:mockwebserver:4.12.0")
}
'''
 for a,b in [('__NAMESPACE__',c['namespace']),('__ID__',c['bundle_id']),('__NUMBER__',c['build_number']),('__VERSION__',c['version'])]:text=text.replace(a,str(b))
 (work/'app/build.gradle.kts').write_text(text)
 return c


def artifact_prefix(app_name):
 value=re.sub(r'[^A-Za-z0-9_]','',str(app_name))[:50]
 return value if re.fullmatch(r'[A-Za-z][A-Za-z0-9_]{0,49}',value)else 'App'+value[:47]

def package_source(source,work,out,stem,report):
 archive=out/(stem+'-source.zip');prefix=report['artifact_prefix']+'Native/';entries={}
 for p in sorted(work.rglob('*')):
  rel=p.relative_to(work)
  if any(part in {'.gradle','build','.idea','.git'}for part in rel.parts)or p.name=='local.properties':continue
  if p.is_symlink():raise ValueError('Source archive refuses symlinks')
  if not p.is_file():continue
  if p.suffix.lower()in {'.jks','.keystore','.pem','.key','.p12','.pfx','.mobileprovision'}:raise ValueError('Signing material refused in source archive')
  if p.stat().st_size>2097152:raise ValueError('Oversized source file')
  entries[prefix+rel.as_posix()]=p.read_bytes()
 for name in ['project.json','README.md','CHANGELOG.md']:
  p=source/name
  if not p.is_file()or p.is_symlink():raise ValueError('Complete source delivery requires '+name)
  entries[prefix+name]=p.read_bytes()
 entries[prefix+'SOURCE-COMMIT.txt']=(report['source_sha']+'\n').encode()
 entries[prefix+'BUILDING.md']=('Rebuild this exact Android project\n\nRequires JDK 17, Android SDK 35/build-tools 35.0.0 and network access to the declared public Maven/Gradle repositories.\nSet ANDROID_HOME to your SDK, then run ./gradlew testDebugUnitTest lintRelease assembleDebug (Windows: gradlew.bat).\nFor an unsigned release use ./gradlew assembleRelease. Release signing uses the owner existing private key in a separate process; no signing material is included.\nSource '+report['source_sha']+'\n').encode()
 required={prefix+name for name in ['gradlew','gradlew.bat','gradle/wrapper/gradle-wrapper.jar','gradle/wrapper/gradle-wrapper.properties','settings.gradle.kts','build.gradle.kts','app/build.gradle.kts','app/src/main/AndroidManifest.xml']}
 if not required<=set(entries):raise ValueError('Incomplete standalone Gradle source project')
 if sum(map(len,entries.values()))>20971520:raise ValueError('Source archive exceeds 20 MiB')
 with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED)as z:
  for name,data in sorted(entries.items()):
   item=zipfile.ZipInfo(name);item.compress_type=zipfile.ZIP_DEFLATED;item.external_attr=(0o100755 if name.endswith('/gradlew')else 0o100644)<<16;z.writestr(item,data)
 with zipfile.ZipFile(archive)as z:
  if z.testzip()or set(z.namelist())!=set(entries):raise ValueError('Invalid source archive')
 return archive

def file_record(p):return dict(name=p.name,size_bytes=p.stat().st_size,sha256=hashlib.sha256(p.read_bytes()).hexdigest())

def build():
 for k,p in [('PROJECT_ID',r'[a-z][a-z0-9_]{1,39}'),('REQUEST_ID',r'[A-Za-z0-9][A-Za-z0-9_-]{5,63}'),('SOURCE_SHA',r'[a-f0-9]{40}')]:
  if not re.fullmatch(p,os.environ.get(k,'')):raise ValueError('Invalid '+k)
 root=Path(os.environ['GITHUB_WORKSPACE']);out=root/'native-android-output';out.mkdir(exist_ok=True);logs=[]
 r=dict(project_id=os.environ['PROJECT_ID'],request_id=os.environ['REQUEST_ID'],source_sha=os.environ['SOURCE_SHA'],platform='native_android',project_type='native_android',build_result='failure',compile_passed=False,analyze_passed=False,tests_passed=False,signature_verified=False,install_ready=False,physical_phone_tested=False,files=[])
 def run(args,cwd=None):
  p=subprocess.run(list(map(str,args)),cwd=cwd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=1800);logs.append('$ '+' '.join(map(str,args))+'\n'+p.stdout);(out/'build.log').write_text('\n'.join(logs)[-1000000:])
  if p.returncode:raise RuntimeError(str(args[0])+' exit '+str(p.returncode))
  return p.stdout
 try:
  source=root/'projects'/r['project_id'];work=Path(os.environ['RUNNER_TEMP'])/('native-android-'+r['request_id']);c=prepare(source,work)
  if c['project_id']!=r['project_id']:raise ValueError('Project ID mismatch')
  r.update(app_name=c['app_name'],bundle_id=c['bundle_id'],version=c['version'],build_number=str(c['build_number']),original_certificate_sha256=c.get('original_certificate_sha256',''))
  run(['gradle','--version'],work);run(['gradle','wrapper','--gradle-version','8.11.1','--distribution-type','bin','--no-daemon'],work);run(['gradle','testDebugUnitTest','lintRelease','assembleRelease','--no-daemon','--stacktrace'],work)
  suites=[ET.parse(p).getroot() for p in (work/'app/build/test-results/testDebugUnitTest').glob('TEST-*.xml')]
  count=sum(int(s.get('tests','0')) for s in suites);fail=sum(int(s.get('failures','0'))+int(s.get('errors','0')) for s in suites)
  if count<1 or fail:raise ValueError('No passing native unit tests')
  r.update(compile_passed=True,analyze_passed=True,tests_passed=True,tests_status='junit_robolectric_passed',test_count=count,lint_passed=True)
  apk=work/'app/build/outputs/apk/release/app-release-unsigned.apk';sdk=Path(os.environ['ANDROID_HOME'])/'build-tools/35.0.0';badging=run([sdk/'aapt','dump','badging',apk])
  for field,val in [('name',c['bundle_id']),('versionCode',c['build_number']),('versionName',c['version'])]:
   if field+"='"+str(val)+"'" not in badging.splitlines()[0]:raise ValueError('APK identity/version mismatch')
  r['package_verified']=True;r['artifact_prefix']=artifact_prefix(c['app_name']);stem=r['artifact_prefix']+'-Android-'+c['version']+'-build'+str(c['build_number']);package=out/(stem+'-unsigned.apk');shutil.copy2(apk,package)
  archive=package_source(source,work,out,stem,r)
  r['source_package_verified']=True;r['files']=[file_record(p) for p in [package,archive]]
  if(source/'CHANGELOG.md').is_file():shutil.copy2(source/'CHANGELOG.md',out/'CHANGELOG.md')
  r['build_result']='success'
 except Exception as e:r['error']=str(e)
 finally:(out/'Build-Report.json').write_text(json.dumps(r,indent=2));(out/'build.log').write_text('\n'.join(logs)[-1000000:])
 print('Native Android build:',r['build_result'])
 if r['build_result']!='success':raise SystemExit(1)
if __name__=='__main__':build()
