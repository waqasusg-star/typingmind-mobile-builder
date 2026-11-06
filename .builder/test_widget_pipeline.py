import copy, json, plistlib, tempfile, unittest, zipfile
from pathlib import Path
import native_ios as worker
import widgetkit_support as widget

class WidgetPipelineTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name);self.source=self.root/'source';self.source.mkdir()
        self.cfg=dict(project_type='native_ios',project_id='test_app',app_name='Test App',bundle_id='com.example.test',scheme='TestApp',version='1.2.3',build_number='4',minimum_ios='15.0',widget_profile='widgetkit_v1')
        for path in ['Sources/App.swift','Sources/RequestPolicy.swift','Shared/Cache.swift','WidgetSources/WidgetBundle.swift','Tests/PolicyTests.swift','Tests/WidgetKitTests.swift','Tests/WidgetKitTestMain.swift']:
            p=self.source/path;p.parent.mkdir(parents=True,exist_ok=True);p.write_text('// fixture\n')
        self.save()
    def save(self): (self.source/'project.json').write_text(json.dumps(self.cfg))
    def prepare(self):return worker.prepare(self.source,self.root/'work')
    def info(self):return dict(CFBundleIdentifier='com.example.test.widgets',CFBundleShortVersionString='1.2.3',CFBundleVersion='4',CFBundlePackageType='XPC!',CFBundleExecutable='TestAppWidgets',DTPlatformName='iphoneos',CFBundleSupportedPlatforms=['iPhoneOS'],NSExtension={'NSExtensionPointIdentifier':'com.apple.widgetkit-extension'})
    def app(self):
        app=self.root/'TestApp.app';ext=app/'PlugIns/TestAppWidgets.appex';ext.mkdir(parents=True)
        (ext/'Info.plist').write_bytes(plistlib.dumps(self.info()));(ext/'TestAppWidgets').write_bytes(b'fixture')
        return app,ext
    def package(self,info=None,binary=True,extension=True):
        p=self.root/'package.ipa'
        with zipfile.ZipFile(p,'w') as z:
            z.writestr('Payload/TestApp.app/Info.plist',b'fixture')
            if extension:
                prefix='Payload/TestApp.app/PlugIns/TestAppWidgets.appex/'
                z.writestr(prefix+'Info.plist',plistlib.dumps(info or self.info()))
                if binary:z.writestr(prefix+'TestAppWidgets',b'fixture')
        return p
    def test_legacy_single_target(self):
        self.cfg.pop('widget_profile');self.save();self.prepare()
        spec=json.loads((self.root/'work/native-project.json').read_text())
        self.assertEqual(list(spec['targets']),['TestApp']);self.assertNotIn('dependencies',spec['targets']['TestApp'])
    def test_canonical_entry_required(self):
        (self.source/widget.ENTRY).unlink()
        with self.assertRaisesRegex(ValueError,'requires'):self.prepare()
    def test_unreviewed_profile_rejected(self):
        self.cfg['widget_profile']='custom';self.save()
        with self.assertRaises(ValueError):self.prepare()
    def test_foreign_app_group_rejected(self):
        self.cfg['widget_extension']={**widget.widget_identity(self.cfg),'app_group_id':'group.foreign'};self.save()
        with self.assertRaises(ValueError):self.prepare()
    def test_real_target_and_entitlements(self):
        self.prepare();work=self.root/'work';spec=json.loads((work/'native-project.json').read_text())
        app=spec['targets']['TestApp'];ext=spec['targets']['TestAppWidgets']
        self.assertEqual(app['dependencies'],[dict(target='TestAppWidgets',embed=True,codeSign=False)])
        self.assertEqual(ext['type'],'app-extension');self.assertEqual(ext['settings']['base']['APPLICATION_EXTENSION_API_ONLY'],'YES')
        self.assertEqual([s['path'] for s in ext['sources']],['WidgetSources','Shared','Sources/RequestPolicy.swift'])
        for p in ['App.entitlements','Widget.entitlements']:
            self.assertEqual(plistlib.loads((work/p).read_bytes()),{'com.apple.security.application-groups':['group.com.example.test']})
    def test_shared_and_widget_tests_controlled(self):
        self.prepare();work=self.root/'work'
        self.assertIn(work/'Shared/Cache.swift',widget.policy_sources(work,['Sources/RequestPolicy.swift','Tests/PolicyTests.swift']))
        self.assertEqual(len(widget.widget_test_sources(work,self.cfg)),4)
        with self.assertRaises(ValueError):widget.policy_sources(work,['custom.swift'])
        (work/'Tests/WidgetKitTests.swift').unlink()
        with self.assertRaises(ValueError):widget.widget_test_sources(work,self.cfg)
    def test_shared_script_rejected(self):
        (self.source/'Shared/run.sh').write_text('echo bad')
        with self.assertRaises(ValueError):self.prepare()
    def test_archive_requires_extension(self):
        with self.assertRaisesRegex(ValueError,'not embedded'):widget.verify_archived_extensions(self.root,self.cfg,lambda _: 'arm64',{})
    def test_archive_verifies_arm64_and_identity(self):
        app,ext=self.app();report={};widget.verify_archived_extensions(app,self.cfg,lambda _: 'arm64',report)
        self.assertTrue(report['widget_extension_verified']);self.assertEqual(report['app_group_id'],'group.com.example.test')
        for key,val in [('CFBundleIdentifier','com.bad.widget'),('CFBundleVersion','3'),('DTPlatformName','iphonesimulator')]:
            info=self.info();info[key]=val;(ext/'Info.plist').write_bytes(plistlib.dumps(info))
            with self.subTest(key=key),self.assertRaises(ValueError):widget.verify_archived_extensions(app,self.cfg,lambda _: 'arm64',{})
    def test_archive_rejects_simulator_architecture(self):
        app,ext=self.app()
        with self.assertRaises(ValueError):widget.verify_archived_extensions(app,self.cfg,lambda _: 'arm64 x86_64',{})
    def test_archive_rejects_extra_extension_and_profiles(self):
        app,ext=self.app();(ext/'embedded.mobileprovision').write_text('not allowed')
        with self.assertRaises(ValueError):widget.verify_archived_extensions(app,self.cfg,lambda _: 'arm64',{})
        (ext/'embedded.mobileprovision').unlink();(app/'PlugIns/Extra.appex').mkdir()
        with self.assertRaises(ValueError):widget.verify_archived_extensions(app,self.cfg,lambda _: 'arm64',{})
    def test_ipa_requires_embedded_executable(self):
        for kwargs in [dict(extension=False),dict(binary=False)]:
            with zipfile.ZipFile(self.package(**kwargs)) as z,self.assertRaises(ValueError):widget.verify_packaged_widget(z,'Payload/TestApp.app/',self.cfg)
        with zipfile.ZipFile(self.package()) as z:widget.verify_packaged_widget(z,'Payload/TestApp.app/',self.cfg)
    def test_rebuildable_source_zip(self):
        self.prepare();out=self.root/'out';out.mkdir();p=worker.package_source(self.source,out,self.cfg,'a'*40,self.root/'work')
        with zipfile.ZipFile(p) as z:
            for name in [*widget.GENERATED,'WidgetSources/WidgetBundle.swift','Shared/Cache.swift','BUILDER-REBUILD.md','WIDGET-SIGNING.json']:
                self.assertIn('TestApp-iOS/'+name,z.namelist())
            self.assertFalse(json.loads(z.read('TestApp-iOS/WIDGET-SIGNING.json'))['install_ready'])
    def test_signing_material_excluded(self):
        (self.source/'Resources').mkdir();(self.source/'Resources/private.p12').write_text('fixture')
        with self.assertRaises(ValueError):worker.package_source(self.source,self.root,self.cfg,'a'*40)
    def test_publisher_requires_proof_and_real_bundle(self):
        report={**self.cfg,**widget.initial_report(self.cfg)}
        with self.assertRaises(ValueError):widget.verify_release_widget(report,self.package())
        report.update(widget_extension_verified=True,app_group_entitlements_declared=True,app_group_id='group.com.example.test')
        with self.assertRaises(ValueError):widget.verify_release_widget(report,self.package(extension=False))
        widget.verify_release_widget(report,self.package())

if __name__=='__main__':unittest.main()
