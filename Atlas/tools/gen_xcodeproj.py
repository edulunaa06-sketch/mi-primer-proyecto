import hashlib, sys, os
def I(name): return hashlib.md5(("atlas-"+name).encode()).hexdigest()[:24].upper()
ids = {n: I(n) for n in """PROJECT APPTARGET TESTTARGET APPPRODUCT TESTPRODUCT INFOPLIST ENTITLEMENTS XCCONFIG
APPSRCGROUP TESTSRCGROUP MAINGROUP CONFIGGROUP PRODUCTSGROUP APPSOURCES APPFRAMEWORKS APPRESOURCES
TESTSOURCES TESTFRAMEWORKS TESTRESOURCES TESTPROXY TESTDEPENDENCY PROJECTCONFIGLIST APPCONFIGLIST TESTCONFIGLIST
PROJDEBUG PROJRELEASE APPDEBUG APPRELEASE TESTDEBUG TESTRELEASE
UITESTTARGET UITESTPRODUCT UITESTSRCGROUP UITESTSOURCES UITESTFRAMEWORKS UITESTRESOURCES UITESTPROXY
UITESTDEPENDENCY UITESTCONFIGLIST UITESTDEBUG UITESTRELEASE""".split()}
assert len(set(ids.values()))==len(ids)
def S(n): return ids[n]

project_common = """				ALWAYS_SEARCH_USER_PATHS = NO;
				ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_ENABLE_OBJC_WEAK = YES;
				CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;
				CLANG_WARN_BOOL_CONVERSION = YES;
				CLANG_WARN_COMMA = YES;
				CLANG_WARN_CONSTANT_CONVERSION = YES;
				CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;
				CLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;
				CLANG_WARN_DOCUMENTATION_COMMENTS = YES;
				CLANG_WARN_EMPTY_BODY = YES;
				CLANG_WARN_ENUM_CONVERSION = YES;
				CLANG_WARN_INFINITE_RECURSION = YES;
				CLANG_WARN_INT_CONVERSION = YES;
				CLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
				CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;
				CLANG_WARN_OBJC_LITERAL_CONVERSION = YES;
				CLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
				CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
				CLANG_WARN_RANGE_LOOP_ANALYSIS = YES;
				CLANG_WARN_STRICT_PROTOTYPES = YES;
				CLANG_WARN_SUSPICIOUS_MOVE = YES;
				CLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
				CLANG_WARN_UNREACHABLE_CODE = YES;
				CLANG_WARN__DUPLICATE_METHOD_MATCH = YES;
				COPY_PHASE_STRIP = NO;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				ENABLE_USER_SCRIPT_SANDBOXING = YES;
				GCC_C_LANGUAGE_STANDARD = gnu17;
				GCC_NO_COMMON_BLOCKS = YES;
				GCC_WARN_64_TO_32_BIT_CONVERSION = YES;
				GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
				GCC_WARN_UNDECLARED_SELECTOR = YES;
				GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
				GCC_WARN_UNUSED_FUNCTION = YES;
				GCC_WARN_UNUSED_VARIABLE = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				LOCALIZATION_PREFERS_STRING_CATALOGS = YES;
				MTL_FAST_MATH = YES;
				SDKROOT = iphoneos;
"""
project_debug = project_common + """				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_TESTABILITY = YES;
				GCC_DYNAMIC_NO_PIC = NO;
				GCC_OPTIMIZATION_LEVEL = 0;
				GCC_PREPROCESSOR_DEFINITIONS = (
					"DEBUG=1",
					"$(inherited)",
				);
				MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
				ONLY_ACTIVE_ARCH = YES;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
"""
project_release = project_common + """				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				ENABLE_NS_ASSERTIONS = NO;
				MTL_ENABLE_DEBUG_INFO = NO;
				SWIFT_COMPILATION_MODE = wholemodule;
				VALIDATE_PRODUCT = YES;
"""
app = """				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_ENTITLEMENTS = Config/Atlas.entitlements;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 2;
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_FILE = Config/Info.plist;
				INFOPLIST_KEY_CFBundleDisplayName = "Now or Never";
				INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.healthcare-fitness";
				INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
				INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = UIInterfaceOrientationPortrait;
				INFOPLIST_KEY_UIUserInterfaceStyle = Light;
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 1.1;
				PRODUCT_BUNDLE_IDENTIFIER = "$(BUNDLE_ID_PREFIX).atlas";
				PRODUCT_NAME = "$(TARGET_NAME)";
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SUPPORTS_MACCATALYST = NO;
				SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = 1;
"""
test = """				BUNDLE_LOADER = "$(TEST_HOST)";
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 2;
				GENERATE_INFOPLIST_FILE = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				MARKETING_VERSION = 1.1;
				PRODUCT_BUNDLE_IDENTIFIER = "$(BUNDLE_ID_PREFIX).atlas.tests";
				PRODUCT_NAME = "$(TARGET_NAME)";
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SWIFT_EMIT_LOC_STRINGS = NO;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = 1;
				TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Atlas.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Atlas";
"""
uitest = """				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 2;
				GENERATE_INFOPLIST_FILE = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				MARKETING_VERSION = 1.1;
				PRODUCT_BUNDLE_IDENTIFIER = "$(BUNDLE_ID_PREFIX).atlas.uitests";
				PRODUCT_NAME = "$(TARGET_NAME)";
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SWIFT_EMIT_LOC_STRINGS = NO;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = 1;
				TEST_TARGET_NAME = Atlas;
"""
def bc(key, name, settings, base=None):
    b = f"\t\t\tbaseConfigurationReference = {S('XCCONFIG')} /* Signing.xcconfig */;\n" if base else ""
    return f"""		{S(key)} /* {name} */ = {{
			isa = XCBuildConfiguration;
{b}			buildSettings = {{
{settings}			}};
			name = {name};
		}};
"""
def phase(key, isa, comment):
    return f"""		{S(key)} /* {comment} */ = {{
			isa = {isa};
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
"""
def cl(key, comment, d, r):
    return f"""		{S(key)} /* Build configuration list for {comment} */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{S(d)} /* Debug */,
				{S(r)} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
"""
out = f"""// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{
	}};
	objectVersion = 77;
	objects = {{

/* Begin PBXContainerItemProxy section */
		{S('TESTPROXY')} /* PBXContainerItemProxy */ = {{
			isa = PBXContainerItemProxy;
			containerPortal = {S('PROJECT')} /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = {S('APPTARGET')};
			remoteInfo = Atlas;
		}};
		{S('UITESTPROXY')} /* PBXContainerItemProxy */ = {{
			isa = PBXContainerItemProxy;
			containerPortal = {S('PROJECT')} /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = {S('APPTARGET')};
			remoteInfo = Atlas;
		}};
/* End PBXContainerItemProxy section */

/* Begin PBXFileReference section */
		{S('APPPRODUCT')} /* Atlas.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Atlas.app; sourceTree = BUILT_PRODUCTS_DIR; }};
		{S('TESTPRODUCT')} /* AtlasTests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = AtlasTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};
		{S('UITESTPRODUCT')} /* AtlasUITests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = AtlasUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};
		{S('INFOPLIST')} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; }};
		{S('ENTITLEMENTS')} /* Atlas.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = Atlas.entitlements; sourceTree = "<group>"; }};
		{S('XCCONFIG')} /* Signing.xcconfig */ = {{isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Signing.xcconfig; sourceTree = "<group>"; }};
/* End PBXFileReference section */

/* Begin PBXFileSystemSynchronizedRootGroup section */
		{S('APPSRCGROUP')} /* Atlas */ = {{
			isa = PBXFileSystemSynchronizedRootGroup;
			path = Atlas;
			sourceTree = "<group>";
		}};
		{S('TESTSRCGROUP')} /* AtlasTests */ = {{
			isa = PBXFileSystemSynchronizedRootGroup;
			path = AtlasTests;
			sourceTree = "<group>";
		}};
		{S('UITESTSRCGROUP')} /* AtlasUITests */ = {{
			isa = PBXFileSystemSynchronizedRootGroup;
			path = AtlasUITests;
			sourceTree = "<group>";
		}};
/* End PBXFileSystemSynchronizedRootGroup section */

/* Begin PBXFrameworksBuildPhase section */
{phase('APPFRAMEWORKS','PBXFrameworksBuildPhase','Frameworks')}{phase('TESTFRAMEWORKS','PBXFrameworksBuildPhase','Frameworks')}{phase('UITESTFRAMEWORKS','PBXFrameworksBuildPhase','Frameworks')}/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		{S('MAINGROUP')} = {{
			isa = PBXGroup;
			children = (
				{S('APPSRCGROUP')} /* Atlas */,
				{S('TESTSRCGROUP')} /* AtlasTests */,
				{S('UITESTSRCGROUP')} /* AtlasUITests */,
				{S('CONFIGGROUP')} /* Config */,
				{S('PRODUCTSGROUP')} /* Products */,
			);
			sourceTree = "<group>";
		}};
		{S('CONFIGGROUP')} /* Config */ = {{
			isa = PBXGroup;
			children = (
				{S('INFOPLIST')} /* Info.plist */,
				{S('ENTITLEMENTS')} /* Atlas.entitlements */,
				{S('XCCONFIG')} /* Signing.xcconfig */,
			);
			path = Config;
			sourceTree = "<group>";
		}};
		{S('PRODUCTSGROUP')} /* Products */ = {{
			isa = PBXGroup;
			children = (
				{S('APPPRODUCT')} /* Atlas.app */,
				{S('TESTPRODUCT')} /* AtlasTests.xctest */,
				{S('UITESTPRODUCT')} /* AtlasUITests.xctest */,
			);
			name = Products;
			sourceTree = "<group>";
		}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		{S('APPTARGET')} /* Atlas */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {S('APPCONFIGLIST')} /* Build configuration list for PBXNativeTarget "Atlas" */;
			buildPhases = (
				{S('APPSOURCES')} /* Sources */,
				{S('APPFRAMEWORKS')} /* Frameworks */,
				{S('APPRESOURCES')} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			fileSystemSynchronizedGroups = (
				{S('APPSRCGROUP')} /* Atlas */,
			);
			name = Atlas;
			packageProductDependencies = (
			);
			productName = Atlas;
			productReference = {S('APPPRODUCT')} /* Atlas.app */;
			productType = "com.apple.product-type.application";
		}};
		{S('TESTTARGET')} /* AtlasTests */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {S('TESTCONFIGLIST')} /* Build configuration list for PBXNativeTarget "AtlasTests" */;
			buildPhases = (
				{S('TESTSOURCES')} /* Sources */,
				{S('TESTFRAMEWORKS')} /* Frameworks */,
				{S('TESTRESOURCES')} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
				{S('TESTDEPENDENCY')} /* PBXTargetDependency */,
			);
			fileSystemSynchronizedGroups = (
				{S('TESTSRCGROUP')} /* AtlasTests */,
			);
			name = AtlasTests;
			packageProductDependencies = (
			);
			productName = AtlasTests;
			productReference = {S('TESTPRODUCT')} /* AtlasTests.xctest */;
			productType = "com.apple.product-type.bundle.unit-test";
		}};
		{S('UITESTTARGET')} /* AtlasUITests */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {S('UITESTCONFIGLIST')} /* Build configuration list for PBXNativeTarget "AtlasUITests" */;
			buildPhases = (
				{S('UITESTSOURCES')} /* Sources */,
				{S('UITESTFRAMEWORKS')} /* Frameworks */,
				{S('UITESTRESOURCES')} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
				{S('UITESTDEPENDENCY')} /* PBXTargetDependency */,
			);
			fileSystemSynchronizedGroups = (
				{S('UITESTSRCGROUP')} /* AtlasUITests */,
			);
			name = AtlasUITests;
			packageProductDependencies = (
			);
			productName = AtlasUITests;
			productReference = {S('UITESTPRODUCT')} /* AtlasUITests.xctest */;
			productType = "com.apple.product-type.bundle.ui-testing";
		}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		{S('PROJECT')} /* Project object */ = {{
			isa = PBXProject;
			attributes = {{
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 1600;
				LastUpgradeCheck = 1600;
				TargetAttributes = {{
					{S('APPTARGET')} = {{
						CreatedOnToolsVersion = 16.0;
					}};
					{S('TESTTARGET')} = {{
						CreatedOnToolsVersion = 16.0;
						TestTargetID = {S('APPTARGET')};
					}};
					{S('UITESTTARGET')} = {{
						CreatedOnToolsVersion = 16.0;
						TestTargetID = {S('APPTARGET')};
					}};
				}};
			}};
			buildConfigurationList = {S('PROJECTCONFIGLIST')} /* Build configuration list for PBXProject "Atlas" */;
			developmentRegion = es;
			hasScannedForEncodings = 0;
			knownRegions = (
				es,
				Base,
			);
			mainGroup = {S('MAINGROUP')};
			minimizedProjectReferenceProxies = 1;
			preferredProjectObjectVersion = 77;
			productRefGroup = {S('PRODUCTSGROUP')} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				{S('APPTARGET')} /* Atlas */,
				{S('TESTTARGET')} /* AtlasTests */,
				{S('UITESTTARGET')} /* AtlasUITests */,
			);
		}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
{phase('APPRESOURCES','PBXResourcesBuildPhase','Resources')}{phase('TESTRESOURCES','PBXResourcesBuildPhase','Resources')}{phase('UITESTRESOURCES','PBXResourcesBuildPhase','Resources')}/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
{phase('APPSOURCES','PBXSourcesBuildPhase','Sources')}{phase('TESTSOURCES','PBXSourcesBuildPhase','Sources')}{phase('UITESTSOURCES','PBXSourcesBuildPhase','Sources')}/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
		{S('TESTDEPENDENCY')} /* PBXTargetDependency */ = {{
			isa = PBXTargetDependency;
			target = {S('APPTARGET')} /* Atlas */;
			targetProxy = {S('TESTPROXY')} /* PBXContainerItemProxy */;
		}};
		{S('UITESTDEPENDENCY')} /* PBXTargetDependency */ = {{
			isa = PBXTargetDependency;
			target = {S('APPTARGET')} /* Atlas */;
			targetProxy = {S('UITESTPROXY')} /* PBXContainerItemProxy */;
		}};
/* End PBXTargetDependency section */

/* Begin XCBuildConfiguration section */
{bc('PROJDEBUG','Debug',project_debug)}{bc('PROJRELEASE','Release',project_release)}{bc('APPDEBUG','Debug',app,True)}{bc('APPRELEASE','Release',app,True)}{bc('TESTDEBUG','Debug',test,True)}{bc('TESTRELEASE','Release',test,True)}{bc('UITESTDEBUG','Debug',uitest,True)}{bc('UITESTRELEASE','Release',uitest,True)}/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
{cl('PROJECTCONFIGLIST','PBXProject "Atlas"','PROJDEBUG','PROJRELEASE')}{cl('APPCONFIGLIST','PBXNativeTarget "Atlas"','APPDEBUG','APPRELEASE')}{cl('TESTCONFIGLIST','PBXNativeTarget "AtlasTests"','TESTDEBUG','TESTRELEASE')}{cl('UITESTCONFIGLIST','PBXNativeTarget "AtlasUITests"','UITESTDEBUG','UITESTRELEASE')}/* End XCConfigurationList section */
	}};
	rootObject = {S('PROJECT')} /* Project object */;
}}
"""
# Sin argumento, genera en la carpeta actual (es lo que dice INSTALAR_EN_IPHONE.md).
root = sys.argv[1] if len(sys.argv) > 1 else '.'
open(os.path.join(root,'Atlas.xcodeproj/project.pbxproj'),'w').write(out)
scheme = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1600"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{S('APPTARGET')}"
               BuildableName = "Atlas.app"
               BlueprintName = "Atlas"
               ReferencedContainer = "container:Atlas.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference
            skipped = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{S('TESTTARGET')}"
               BuildableName = "AtlasTests.xctest"
               BlueprintName = "AtlasTests"
               ReferencedContainer = "container:Atlas.xcodeproj">
            </BuildableReference>
         </TestableReference>
         <TestableReference
            skipped = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{S('UITESTTARGET')}"
               BuildableName = "AtlasUITests.xctest"
               BlueprintName = "AtlasUITests"
               ReferencedContainer = "container:Atlas.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{S('APPTARGET')}"
            BuildableName = "Atlas.app"
            BlueprintName = "Atlas"
            ReferencedContainer = "container:Atlas.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{S('APPTARGET')}"
            BuildableName = "Atlas.app"
            BlueprintName = "Atlas"
            ReferencedContainer = "container:Atlas.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""
d=os.path.join(root,'Atlas.xcodeproj/xcshareddata/xcschemes'); os.makedirs(d,exist_ok=True)
open(os.path.join(d,'Atlas.xcscheme'),'w').write(scheme)
ws=os.path.join(root,'Atlas.xcodeproj/project.xcworkspace'); os.makedirs(ws,exist_ok=True)
open(os.path.join(ws,'contents.xcworkspacedata'),'w').write('<?xml version="1.0" encoding="UTF-8"?>\n<Workspace\n   version = "1.0">\n   <FileRef\n      location = "self:">\n   </FileRef>\n</Workspace>\n')
print("ok")
