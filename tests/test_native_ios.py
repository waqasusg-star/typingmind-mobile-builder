import hashlib,importlib.util,json,plistlib,tempfile,unittest,zipfile
from pathlib import Path

ROOT=Path(__file__).resolve().parent.parent
def load(name,path):
 spec=importlib.util.spec_from_file_location(name,ROOT/path);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
worker=load('native_worker','.builder/native_ios.py');publisher=load('native_publisher','.builder/publish_native_ios.py')

class NativeTests(unittest.TestCase):
 def fixture(self,root):
  cfg={'project_id':'test_app','project_type':'native_ios','app_name':'Native App','bundle_id':'com.worldgate.nativeapp','scheme':'NativeApp','version':'1.2.3','build_number':'7','minimum_ios':'15.0'}
  source=root/'source';source.mkdir();(source/'project.json').write_text(json.dumps(cfg));(source/'Sources').mkdir();(source/'Sources/App.swift').write_text('import UIKit\n')
  return source,cfg
 def test_controlled_spec_preserves_identity_and_ignores_uploaded_scripts(self):
  with tempfile.TemporaryDirectory()as d:
   root=Path(d);source,cfg=self.fixture(root);(source/'project.yml').write_text('preBuildScripts: [{script: unsafe}]')
   worker.prepare(source,root/'work');spec=json.loads((root/'work/native-project.json').read_text());info=plistlib.loads((root/'work/Info.plist').read_bytes())
   self.assertNotIn('preBuildScripts',json.dumps(spec));self.assertEqual(spec['targets']['NativeApp']['settings']['base']['PRODUCT_BUNDLE_IDENTIFIER'],cfg['bundle_id']);self.assertEqual(info['CFBundleShortVersionString'],'1.2.3');self.assertEqual(info['CFBundleVersion'],'7');self.assertEqual(info['UIBackgroundModes'],['audio']);self.assertNotIn('UIBackgroundModes',spec['targets']['NativeApp']['settings']['base'])
 def test_symlinks_and_bad_identity_are_refused(self):
  with tempfile.TemporaryDirectory()as d:
   root=Path(d);source,cfg=self.fixture(root);(source/'Sources/unsafe.swift').symlink_to(source/'Sources/App.swift')
   with self.assertRaisesRegex(ValueError,'Symlink'):worker.prepare(source,root/'work')
   with self.assertRaisesRegex(ValueError,'Invalid SOURCE_SHA'):worker.identity({'PROJECT_ID':'test_app','REQUEST_ID':'request01','SOURCE_SHA':'main'})
 def test_device_verifier_rejects_simulators_and_provisioning_profiles(self):
  with tempfile.TemporaryDirectory()as d:
   root=Path(d);source,cfg=self.fixture(root);app=root/'NativeApp.app';app.mkdir();(app/'NativeApp').write_bytes(b'fixture')
   info={'CFBundleIdentifier':cfg['bundle_id'],'CFBundleExecutable':'NativeApp','DTPlatformName':'iphoneos','CFBundleSupportedPlatforms':['iPhoneOS']};(app/'Info.plist').write_bytes(plistlib.dumps(info))
   worker.verify_bundle(app,cfg,lambda args:'arm64\n');info['DTPlatformName']='iphonesimulator';(app/'Info.plist').write_bytes(plistlib.dumps(info))
   with self.assertRaisesRegex(ValueError,'Simulator'):worker.verify_bundle(app,cfg,lambda args:'arm64')
   info['DTPlatformName']='iphoneos';(app/'Info.plist').write_bytes(plistlib.dumps(info));(app/'embedded.mobileprovision').write_bytes(b'fixture')
   with self.assertRaisesRegex(ValueError,'provisioning'):worker.verify_bundle(app,cfg,lambda args:'arm64')
 def test_payload_integrity_and_traversal(self):
  with tempfile.TemporaryDirectory()as d:
   package=Path(d)/'app.ipa'
   with zipfile.ZipFile(package,'w')as z:z.writestr('Payload/App.app/Info.plist',b'plist');z.writestr('Payload/App.app/App',b'executable')
   worker.verify_ipa(package,'App.app','App')
   with zipfile.ZipFile(package,'a')as z:z.writestr('../escape',b'fixture')
   with self.assertRaisesRegex(ValueError,'Unsafe'):worker.verify_ipa(package,'App.app','App')
 def test_publisher_enforces_identity_checks_and_hash(self):
  with tempfile.TemporaryDirectory()as d:
   folder=Path(d);env={'PROJECT_ID':'test_app','REQUEST_ID':'request01','SOURCE_SHA':'a'*40};package=folder/'test_app-ios-unsigned.ipa';package.write_bytes(b'fixture')
   data=dict(project_id='test_app',request_id='request01',source_sha='a'*40,platform='native_ios_unsigned',project_type='native_ios',build_result='success',compile_passed=True,analyze_passed=True,device_build_verified=True,package_verified=True,code_signing='unsigned',signature_verified=False,requires_signing=True,install_ready=False,tests_passed=False,files=[{'name':package.name,'size_bytes':7,'sha256':hashlib.sha256(b'fixture').hexdigest()}]);report=folder/'Build-Report.json';report.write_text(json.dumps(data))
   self.assertEqual(publisher.verify(folder,env)[0],package)
   package.write_bytes(b'tampered')
   with self.assertRaisesRegex(ValueError,'hash'):publisher.verify(folder,env)
   package.write_bytes(b'fixture');data['install_ready']=True;report.write_text(json.dumps(data))
   with self.assertRaisesRegex(ValueError,'validation'):publisher.verify(folder,env)

if __name__=='__main__':unittest.main()
