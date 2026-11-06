"""Controlled, unsigned WidgetKit target generation and archive validation.

This requests App Group entitlements in build source. It does not register an Apple
App Group, grant access, sign code, or verify shared-container access on a device.
"""
import json, plistlib, re, zipfile
from pathlib import Path

PROFILE = 'widgetkit_v1'
ENTRY = 'WidgetSources/WidgetBundle.swift'
GENERATED = ['native-project.json', 'Info.plist', 'Widget-Info.plist', 'App.entitlements', 'Widget.entitlements']

def enabled(cfg):
    return cfg.get('widget_profile', 'none') == PROFILE

def widget_identity(cfg):
    return {'name':cfg['scheme']+'Widgets', 'bundle_id':cfg['bundle_id']+'.widgets', 'app_group_id':'group.'+cfg['bundle_id']}

def validate_profile(source, cfg):
    if cfg.get('widget_profile', 'none') not in {'none', PROFILE}:
        raise ValueError('Unsupported WidgetKit profile')
    if not enabled(cfg):
        return
    if not (source/ENTRY).is_file() or (source/ENTRY).is_symlink():
        raise ValueError('widgetkit_v1 requires '+ENTRY)
    actual = cfg.get('widget_extension')
    if actual is not None and actual != widget_identity(cfg):
        raise ValueError('Widget identity/App Group must match the containing app')

def configure_spec(work, spec, cfg):
    app = spec['targets'][cfg['scheme']]
    if (work/'Shared').is_dir():
        app['sources'].append({'path':'Shared'})
    if not enabled(cfg):
        return
    identity = widget_identity(cfg)
    groups = {'com.apple.security.application-groups':[identity['app_group_id']]}
    for name in ['App.entitlements','Widget.entitlements']:
        (work/name).write_bytes(plistlib.dumps(groups))
    app['settings']['base']['CODE_SIGN_ENTITLEMENTS'] = 'App.entitlements'
    app['settings']['base']['ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES'] = 'YES'
    info = plistlib.loads((work/'Info.plist').read_bytes())
    scheme = re.sub(r'[^a-z0-9+.-]', '-', cfg['bundle_id'].lower())
    info['CFBundleURLTypes'] = [{'CFBundleURLName':cfg['bundle_id'], 'CFBundleURLSchemes':[scheme]}]
    (work/'Info.plist').write_bytes(plistlib.dumps(info))
    widget_info = {'CFBundleDevelopmentRegion':'en', 'CFBundleDisplayName':cfg['app_name']+' Widgets',
        'CFBundleExecutable':'$(EXECUTABLE_NAME)', 'CFBundleIdentifier':'$(PRODUCT_BUNDLE_IDENTIFIER)',
        'CFBundleInfoDictionaryVersion':'6.0', 'CFBundleName':'$(PRODUCT_NAME)',
        'CFBundlePackageType':'XPC!', 'CFBundleShortVersionString':cfg['version'],
        'CFBundleVersion':str(cfg['build_number']),
        'NSExtension':{'NSExtensionPointIdentifier':'com.apple.widgetkit-extension'}}
    (work/'Widget-Info.plist').write_bytes(plistlib.dumps(widget_info))
    sources = [{'path':'WidgetSources'}]
    if (work/'Shared').is_dir():
        sources.append({'path':'Shared'})
    if (work/'Sources/RequestPolicy.swift').is_file():
        sources.append({'path':'Sources/RequestPolicy.swift'})
    spec['targets'][identity['name']] = {'type':'app-extension', 'platform':'iOS',
        'sources':sources, 'settings':{'base':{
        'PRODUCT_BUNDLE_IDENTIFIER':identity['bundle_id'], 'PRODUCT_NAME':identity['name'],
        'MARKETING_VERSION':cfg['version'], 'CURRENT_PROJECT_VERSION':str(cfg['build_number']),
        'SWIFT_VERSION':'5.0', 'TARGETED_DEVICE_FAMILY':'1,2',
        'INFOPLIST_FILE':'Widget-Info.plist', 'CODE_SIGN_ENTITLEMENTS':'Widget.entitlements',
        'APPLICATION_EXTENSION_API_ONLY':'YES', 'SKIP_INSTALL':'YES',
        'CODE_SIGNING_ALLOWED':'NO', 'CODE_SIGNING_REQUIRED':'NO', 'CODE_SIGN_IDENTITY':'',
        'ENABLE_USER_SCRIPT_SANDBOXING':'YES', 'ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES':'NO'}}}
    app['dependencies'] = [{'target':identity['name'], 'embed':True, 'codeSign':False}]

def policy_sources(work, configured):
    if configured != ['Sources/RequestPolicy.swift','Tests/PolicyTests.swift']:
        raise ValueError('Unsupported standalone policy test inputs')
    result = [work/p for p in configured]
    result += sorted((work/'Shared').rglob('*.swift')) if (work/'Shared').is_dir() else []
    return result

def widget_test_sources(work, cfg):
    if not enabled(cfg):
        return []
    required = ['Tests/WidgetKitTests.swift','Tests/WidgetKitTestMain.swift']
    if any(not (work/p).is_file() for p in required):
        raise ValueError('widgetkit_v1 requires the controlled WidgetKit test pair')
    return [work/'Sources/RequestPolicy.swift', *sorted((work/'Shared').rglob('*.swift')), *[work/p for p in required]]

def initial_report(cfg):
    return {'widget_profile':cfg.get('widget_profile','none'),
        'widget_extension_expected':enabled(cfg), 'widget_extension_verified':False,
        'widget_extensions':[], 'app_group_runtime_verified':False,
        'widget_gallery_tested':False, 'widget_timeline_device_tested':False,
        'live_activities_included':False}

def validate_widget_info(info, cfg):
    identity = widget_identity(cfg)
    if info.get('CFBundleIdentifier') != identity['bundle_id']:
        raise ValueError('Widget bundle identity mismatch')
    if info.get('CFBundleShortVersionString') != cfg['version'] or info.get('CFBundleVersion') != str(cfg['build_number']):
        raise ValueError('Widget version/build mismatch')
    if info.get('CFBundlePackageType') != 'XPC!' or info.get('NSExtension',{}).get('NSExtensionPointIdentifier') != 'com.apple.widgetkit-extension':
        raise ValueError('Not a WidgetKit extension bundle')
    if info.get('DTPlatformName') != 'iphoneos' or 'iPhoneOS' not in info.get('CFBundleSupportedPlatforms',[]):
        raise ValueError('Widget is not an iPhone device extension')
    executable = info.get('CFBundleExecutable','')
    if not executable or Path(executable).name != executable:
        raise ValueError('Unsafe widget executable name')
    return executable

def verify_archived_extensions(app, cfg, run, report):
    bundles = sorted((app/'PlugIns').glob('*.appex'))
    if not enabled(cfg):
        if bundles:
            raise ValueError('Unrequested app extension in single-target profile')
        return
    identity = widget_identity(cfg)
    if len(bundles) != 1 or bundles[0].name != identity['name']+'.appex':
        raise ValueError('Requested WidgetKit extension is not embedded')
    extension = bundles[0]
    if extension.is_symlink() or list(extension.rglob('embedded.mobileprovision')) or list(extension.rglob('*.appex')):
        raise ValueError('Unsafe unsigned WidgetKit bundle')
    info = plistlib.loads((extension/'Info.plist').read_bytes())
    executable = validate_widget_info(info,cfg)
    if not (extension/executable).is_file():
        raise ValueError('Missing WidgetKit executable')
    archs = run(['xcrun','lipo','-archs',extension/executable]).strip().split()
    if 'arm64' not in archs or any(a in {'x86_64','i386'} for a in archs):
        raise ValueError('Widget is not an arm64 device binary')
    report.update(widget_extension_verified=True, app_group_id=identity['app_group_id'],
        app_group_entitlements_declared=True, widget_extensions=[{
        'name':extension.name, 'bundle_id':identity['bundle_id'], 'version':cfg['version'],
        'build_number':str(cfg['build_number']), 'architectures':archs,
        'extension_point':'com.apple.widgetkit-extension'}])

def verify_packaged_widget(archive, app_prefix, cfg):
    names = archive.namelist()
    embedded = {name.split('/')[0] for name in [n[len(app_prefix+'PlugIns/'):] for n in names if n.startswith(app_prefix+'PlugIns/')] if '.appex' in name.split('/')[0]}
    if not enabled(cfg):
        if embedded:
            raise ValueError('Unrequested extension in IPA')
        return
    identity = widget_identity(cfg)
    if embedded != {identity['name']+'.appex'}:
        raise ValueError('IPA is missing the requested WidgetKit extension')
    prefix = app_prefix+'PlugIns/'+identity['name']+'.appex/'
    if prefix+'Info.plist' not in names:
        raise ValueError('Widget Info.plist missing from IPA')
    executable = validate_widget_info(plistlib.loads(archive.read(prefix+'Info.plist')),cfg)
    if prefix+executable not in names:
        raise ValueError('Widget executable missing from IPA')

def signing_requirements(cfg):
    identity = widget_identity(cfg)
    return {'code_signing':'unsigned', 'install_ready':False, 'requires_signing':True,
        'app_bundle_id':cfg['bundle_id'], 'widget_bundle_id':identity['bundle_id'],
        'app_group_id':identity['app_group_id'],
        'requested_entitlements':{'com.apple.security.application-groups':[identity['app_group_id']]},
        'instructions':'Sign the widget and containing app with the same Apple team and matching profiles authorizing this App Group. Preserve PlugIns/*.appex. Register/authorize the App Group through your signing provider or Apple Developer account. This build does not create account resources or verify runtime access.'}

def rebuild_notes(cfg):
    text = '# Rebuild the exact reviewed native project\n\nRequires macOS, Xcode and XcodeGen. From this folder:\n\n'
    text += '    xcodegen generate --spec native-project.json\n'
    text += '    xcodebuild -project '+cfg['scheme']+'.xcodeproj -scheme '+cfg['scheme']+' -configuration Release -sdk iphoneos -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO archive\n\n'
    text += 'The generated native-project.json, Info.plist and entitlements are the actual controlled CI inputs. No private signing files are included.\n'
    if enabled(cfg):
        text += '\nA real WidgetKit target is embedded. See WIDGET-SIGNING.json for both bundle IDs and the App Group. This archive is UNSIGNED and MUST BE SIGNED BEFORE INSTALLATION. App Group access, the widget gallery and physical-device behavior have not been verified. Live Activities/Dynamic Island are not included.\n'
    return text

def verify_release_widget(report, package):
    profile = report.get('widget_profile','none')
    if profile not in {'none',PROFILE}:
        raise ValueError('Unknown WidgetKit release profile')
    if profile != PROFILE:
        return
    if report.get('widget_extension_expected') is not True or report.get('widget_extension_verified') is not True or report.get('app_group_entitlements_declared') is not True:
        raise ValueError('WidgetKit release lacks extension verification')
    cfg = {key:report[key] for key in ['scheme','bundle_id','version','build_number']}
    cfg['widget_profile'] = PROFILE
    identity = widget_identity(cfg)
    if report.get('app_group_id') != identity['app_group_id']:
        raise ValueError('WidgetKit release App Group mismatch')
    if not re.fullmatch(r'[A-Za-z][A-Za-z0-9_]{0,49}',cfg['scheme']):
        raise ValueError('Unsafe widget release scheme')
    with zipfile.ZipFile(package) as archive:
        if archive.testzip():
            raise ValueError('Widget IPA integrity failed')
        verify_packaged_widget(archive,'Payload/'+cfg['scheme']+'.app/',cfg)
