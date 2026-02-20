#!/usr/bin/env python3
from __future__ import annotations

import hashlib
from pathlib import Path


def make_id(key: str) -> str:
    return hashlib.sha1(key.encode("utf-8")).hexdigest().upper()[:24]


def main() -> int:
    project_root = Path(__file__).resolve().parents[1]
    src_dir = project_root / "Sources" / "StopmoXcodeGUI"
    if not src_dir.exists():
        raise RuntimeError(f"missing source directory: {src_dir}")

    source_files = sorted(p for p in src_dir.glob("*.swift"))
    if not source_files:
        raise RuntimeError(f"no swift source files found in: {src_dir}")

    xcodeproj = project_root / "StopmoXcodeGUI.xcodeproj"
    pbxproj = xcodeproj / "project.pbxproj"
    scheme_dir = xcodeproj / "xcshareddata" / "xcschemes"
    scheme_path = scheme_dir / "StopmoXcodeGUI.xcscheme"

    xcodeproj.mkdir(parents=True, exist_ok=True)
    scheme_dir.mkdir(parents=True, exist_ok=True)

    project_id = make_id("PBXProject")
    target_id = make_id("PBXNativeTarget")
    sources_phase_id = make_id("PBXSourcesBuildPhase")
    frameworks_phase_id = make_id("PBXFrameworksBuildPhase")
    resources_phase_id = make_id("PBXResourcesBuildPhase")
    main_group_id = make_id("MainGroup")
    products_group_id = make_id("ProductsGroup")
    sources_group_id = make_id("SourcesGroup")
    app_group_id = make_id("AppGroup")
    packaging_group_id = make_id("PackagingGroup")
    product_ref_id = make_id("ProductRef")
    project_cfg_list_id = make_id("ProjectConfigList")
    target_cfg_list_id = make_id("TargetConfigList")
    proj_debug_cfg_id = make_id("ProjectDebugConfig")
    proj_release_cfg_id = make_id("ProjectReleaseConfig")
    tgt_debug_cfg_id = make_id("TargetDebugConfig")
    tgt_release_cfg_id = make_id("TargetReleaseConfig")

    info_plist_ref_id = make_id("InfoPlistRef")
    entitlements_ref_id = make_id("EntitlementsRef")
    entitlements_debug_ref_id = make_id("EntitlementsDebugRef")

    file_ref_ids: dict[Path, str] = {}
    build_file_ids: dict[Path, str] = {}
    for path in source_files:
        rel = path.relative_to(project_root)
        file_ref_ids[path] = make_id(f"FileRef:{rel.as_posix()}")
        build_file_ids[path] = make_id(f"BuildFile:{rel.as_posix()}")

    build_file_entries = []
    for path in source_files:
        rel = path.relative_to(project_root).as_posix()
        build_file_entries.append(
            f"\t\t{build_file_ids[path]} /* {path.name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ref_ids[path]} /* {path.name} */; }};"
        )

    file_ref_entries = [
        f"\t\t{product_ref_id} /* StopmoXcodeGUI.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = StopmoXcodeGUI.app; sourceTree = BUILT_PRODUCTS_DIR; }};",
        f"\t\t{info_plist_ref_id} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = packaging/Info.plist; sourceTree = \"<group>\"; }};",
        f"\t\t{entitlements_ref_id} /* entitlements.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = packaging/entitlements.plist; sourceTree = \"<group>\"; }};",
        f"\t\t{entitlements_debug_ref_id} /* entitlements.debug.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = packaging/entitlements.debug.plist; sourceTree = \"<group>\"; }};",
    ]
    for path in source_files:
        file_ref_entries.append(
            f"\t\t{file_ref_ids[path]} /* {path.name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {path.name}; sourceTree = \"<group>\"; }};"
        )

    sources_build_phase_files = "\n".join(
        f"\t\t\t\t{build_file_ids[path]} /* {path.name} in Sources */," for path in source_files
    )
    app_group_children = "\n".join(
        f"\t\t\t\t{file_ref_ids[path]} /* {path.name} */," for path in source_files
    )

    pbxproj_text = f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 56;
\tobjects = {{

/* Begin PBXBuildFile section */
{chr(10).join(build_file_entries)}
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
{chr(10).join(file_ref_entries)}
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
\t\t{frameworks_phase_id} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
\t\t{main_group_id} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{sources_group_id} /* Sources */,
\t\t\t\t{packaging_group_id} /* Packaging */,
\t\t\t\t{products_group_id} /* Products */,
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{products_group_id} /* Products */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{product_ref_id} /* StopmoXcodeGUI.app */,
\t\t\t);
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{sources_group_id} /* Sources */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{app_group_id} /* StopmoXcodeGUI */,
\t\t\t);
\t\t\tpath = Sources;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{app_group_id} /* StopmoXcodeGUI */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{app_group_children}
\t\t\t);
\t\t\tpath = StopmoXcodeGUI;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{packaging_group_id} /* Packaging */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{info_plist_ref_id} /* Info.plist */,
\t\t\t\t{entitlements_debug_ref_id} /* entitlements.debug.plist */,
\t\t\t\t{entitlements_ref_id} /* entitlements.plist */,
\t\t\t);
\t\t\tpath = packaging;
\t\t\tsourceTree = "<group>";
\t\t}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
\t\t{target_id} /* StopmoXcodeGUI */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {target_cfg_list_id} /* Build configuration list for PBXNativeTarget "StopmoXcodeGUI" */;
\t\t\tbuildPhases = (
\t\t\t\t{sources_phase_id} /* Sources */,
\t\t\t\t{frameworks_phase_id} /* Frameworks */,
\t\t\t\t{resources_phase_id} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = StopmoXcodeGUI;
\t\t\tproductName = StopmoXcodeGUI;
\t\t\tproductReference = {product_ref_id} /* StopmoXcodeGUI.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\t{project_id} /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 2600;
\t\t\t\tLastUpgradeCheck = 2600;
\t\t\t\tTargetAttributes = {{
\t\t\t\t\t{target_id} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 26.2;
\t\t\t\t\t}};
\t\t\t\t}};
\t\t\t}};
\t\t\tbuildConfigurationList = {project_cfg_list_id} /* Build configuration list for PBXProject "StopmoXcodeGUI" */;
\t\t\tcompatibilityVersion = "Xcode 14.0";
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = {main_group_id};
\t\t\tproductRefGroup = {products_group_id} /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{target_id} /* StopmoXcodeGUI */,
\t\t\t);
\t\t}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
\t\t{resources_phase_id} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
\t\t{sources_phase_id} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{sources_build_phase_files}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
\t\t{proj_debug_cfg_id} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;
\t\t\t\tSDKROOT = macosx;
\t\t\t\tSWIFT_VERSION = 6.0;
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{proj_release_cfg_id} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;
\t\t\t\tSDKROOT = macosx;
\t\t\t\tSWIFT_VERSION = 6.0;
\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\t{tgt_debug_cfg_id} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tCODE_SIGN_ENTITLEMENTS = packaging/entitlements.debug.plist;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tDEVELOPMENT_TEAM = "";
\t\t\t\tENABLE_HARDENED_RUNTIME = NO;
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = packaging/Info.plist;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/../Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 0.2.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.stopmo.xcode.gui;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 6.0;
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{tgt_release_cfg_id} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tCODE_SIGN_ENTITLEMENTS = packaging/entitlements.plist;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tDEVELOPMENT_TEAM = "";
\t\t\t\tENABLE_HARDENED_RUNTIME = YES;
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = packaging/Info.plist;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/../Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 0.2.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.stopmo.xcode.gui;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 6.0;
\t\t\t}};
\t\t\tname = Release;
\t\t}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
\t\t{project_cfg_list_id} /* Build configuration list for PBXProject "StopmoXcodeGUI" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{proj_debug_cfg_id} /* Debug */,
\t\t\t\t{proj_release_cfg_id} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{target_cfg_list_id} /* Build configuration list for PBXNativeTarget "StopmoXcodeGUI" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{tgt_debug_cfg_id} /* Debug */,
\t\t\t\t{tgt_release_cfg_id} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
/* End XCConfigurationList section */
\t}};
\trootObject = {project_id} /* Project object */;
}}
"""

    scheme_xml = """<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "2600"
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
               BlueprintIdentifier = "__TARGET_ID__"
               BuildableName = "StopmoXcodeGUI.app"
               BlueprintName = "StopmoXcodeGUI"
               ReferencedContainer = "container:StopmoXcodeGUI.xcodeproj">
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
            BlueprintIdentifier = "__TARGET_ID__"
            BuildableName = "StopmoXcodeGUI.app"
            BlueprintName = "StopmoXcodeGUI"
            ReferencedContainer = "container:StopmoXcodeGUI.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
      <EnvironmentVariables>
         <EnvironmentVariable
            key = "STOPMO_XCODE_ROOT"
            value = "$(SRCROOT)/../.."
            isEnabled = "YES">
         </EnvironmentVariable>
      </EnvironmentVariables>
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
            BlueprintIdentifier = "__TARGET_ID__"
            BuildableName = "StopmoXcodeGUI.app"
            BlueprintName = "StopmoXcodeGUI"
            ReferencedContainer = "container:StopmoXcodeGUI.xcodeproj">
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
""".replace("__TARGET_ID__", target_id)

    pbxproj.write_text(pbxproj_text, encoding="utf-8")
    scheme_path.write_text(scheme_xml, encoding="utf-8")
    print(f"wrote {pbxproj}")
    print(f"wrote {scheme_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
