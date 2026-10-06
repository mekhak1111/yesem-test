#!/usr/bin/env python3
"""Adds the `desktop` and `pincode` flavors to macos/Runner.xcodeproj.

For every existing build configuration (Debug, Release, Profile) on every
target this script creates `<Mode>-desktop` and `<Mode>-pincode` copies.
The Runner target copies point at a flavor xcconfig that overrides the
product name and bundle identifier. It is idempotent: running it twice is a
no-op.
"""
from __future__ import annotations

import hashlib
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PBXPROJ = ROOT / "macos" / "Runner.xcodeproj" / "project.pbxproj"
SCHEMES_DIR = ROOT / "macos" / "Runner.xcodeproj" / "xcshareddata" / "xcschemes"

FLAVORS = {
    # flavor name -> (product name, xcconfig file name)
    "desktop": ("YesEm Desktop", "Desktop.xcconfig"),
    "pincode": ("YesEm Pin Code Manager", "PinCodeManager.xcconfig"),
}
MODES = ["Debug", "Release", "Profile"]

# Existing configuration object ids from the Flutter macOS template.
PROJECT_CONFIGS = {"Debug": "33CC10F92044A3C60003C045", "Release": "33CC10FA2044A3C60003C045", "Profile": "338D0CE9231458BD00FA5F75"}
RUNNER_CONFIGS = {"Debug": "33CC10FC2044A3C60003C045", "Release": "33CC10FD2044A3C60003C045", "Profile": "338D0CEA231458BD00FA5F75"}
TESTS_CONFIGS = {"Debug": "331C80DB294CF71000263BE5", "Release": "331C80DC294CF71000263BE5", "Profile": "331C80DD294CF71000263BE5"}
ASSEMBLE_CONFIGS = {"Debug": "33CC111C2044C6BA0003C045", "Release": "33CC111D2044C6BA0003C045", "Profile": "338D0CEB231458BD00FA5F75"}

CONFIG_LISTS = {
    "project": "33CC10E82044A3C60003C045",
    "runner": "33CC10FB2044A3C60003C045",
    "tests": "331C80DE294CF71000263BE5",
    "assemble": "33CC111B2044C6BA0003C045",
}
CONFIGS_GROUP_ID = "33BA886A226E78AF003329D5"
ORIGINAL_PRODUCT = "yesem"


def stable_id(seed: str) -> str:
    """Deterministic 24-hex-char Xcode object id derived from a seed."""
    return hashlib.sha1(seed.encode()).hexdigest()[:24].upper()


def config_block(text: str, object_id: str) -> str:
    match = re.search(
        rf"\t\t{object_id} /\* [^*]+ \*/ = \{{\n\t\t\tisa = XCBuildConfiguration;\n.*?\n\t\t\}};\n",
        text,
        re.DOTALL,
    )
    if not match:
        sys.exit(f"Could not find XCBuildConfiguration {object_id}")
    return match.group(0)


def clone_config(block: str, old_id: str, new_id: str, new_name: str, edits) -> str:
    cloned = block.replace(old_id, new_id)
    cloned = re.sub(r"/\* [^*]+ \*/ = \{", f"/* {new_name} */ = {{", cloned, count=1)
    cloned = re.sub(r"\n\t\t\tname = [^;]+;\n", f"\n\t\t\tname = \"{new_name}\";\n", cloned)
    for edit in edits:
        cloned = edit(cloned)
    return cloned


def main() -> None:
    text = PBXPROJ.read_text()
    if "Debug-desktop" in text:
        print("Flavors already present; nothing to do.")
        return

    new_blocks: list[str] = []
    list_additions: dict[str, list[str]] = {key: [] for key in CONFIG_LISTS}
    file_refs: list[str] = []
    group_children: list[str] = []

    for flavor, (product_name, xcconfig_name) in FLAVORS.items():
        xcconfig_id = stable_id(f"fileref:{xcconfig_name}")
        file_refs.append(
            f"\t\t{xcconfig_id} /* {xcconfig_name} */ = {{isa = PBXFileReference; "
            f"lastKnownFileType = text.xcconfig; path = {xcconfig_name}; sourceTree = \"<group>\"; }};\n"
        )
        group_children.append(f"\t\t\t\t{xcconfig_id} /* {xcconfig_name} */,\n")

        for mode in MODES:
            name = f"{mode}-{flavor}"

            # Project-level configuration: identical copy.
            pid = stable_id(f"project:{name}")
            new_blocks.append(clone_config(config_block(text, PROJECT_CONFIGS[mode]), PROJECT_CONFIGS[mode], pid, name, []))
            list_additions["project"].append(f"\t\t\t\t{pid} /* {name} */,\n")

            # Runner target: swap the base xcconfig for the flavor one.
            rid = stable_id(f"runner:{name}")
            def use_flavor_xcconfig(block: str, _id=xcconfig_id, _name=xcconfig_name) -> str:
                return re.sub(
                    r"baseConfigurationReference = [0-9A-F]+ /\* AppInfo\.xcconfig \*/;",
                    f"baseConfigurationReference = {_id} /* {_name} */;",
                    block,
                )
            new_blocks.append(clone_config(config_block(text, RUNNER_CONFIGS[mode]), RUNNER_CONFIGS[mode], rid, name, [use_flavor_xcconfig]))
            list_additions["runner"].append(f"\t\t\t\t{rid} /* {name} */,\n")

            # RunnerTests target: point TEST_HOST at the flavored app.
            tid = stable_id(f"tests:{name}")
            def fix_test_host(block: str, _product=product_name) -> str:
                return block.replace(
                    f"$(BUILT_PRODUCTS_DIR)/{ORIGINAL_PRODUCT}.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/{ORIGINAL_PRODUCT}",
                    f"$(BUILT_PRODUCTS_DIR)/{_product}.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/{_product}",
                )
            new_blocks.append(clone_config(config_block(text, TESTS_CONFIGS[mode]), TESTS_CONFIGS[mode], tid, name, [fix_test_host]))
            list_additions["tests"].append(f"\t\t\t\t{tid} /* {name} */,\n")

            # Flutter Assemble aggregate target: identical copy.
            aid = stable_id(f"assemble:{name}")
            new_blocks.append(clone_config(config_block(text, ASSEMBLE_CONFIGS[mode]), ASSEMBLE_CONFIGS[mode], aid, name, []))
            list_additions["assemble"].append(f"\t\t\t\t{aid} /* {name} */,\n")

    # Insert cloned configurations.
    marker = "/* End XCBuildConfiguration section */"
    text = text.replace(marker, "".join(new_blocks) + marker)

    # Register the new xcconfig files and add them to the Configs group.
    marker = "/* End PBXFileReference section */"
    text = text.replace(marker, "".join(file_refs) + marker)
    group_pattern = rf"(\t\t{CONFIGS_GROUP_ID} /\* Configs \*/ = \{{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = \(\n)"
    text, count = re.subn(group_pattern, lambda m: m.group(1) + "".join(group_children), text)
    if count != 1:
        sys.exit("Could not find the Configs group")

    # Append to each configuration list.
    for key, list_id in CONFIG_LISTS.items():
        pattern = rf"(\t\t{list_id} /\* [^*]+ \*/ = \{{\n\t\t\tisa = XCConfigurationList;\n\t\t\tbuildConfigurations = \(\n(?:\t\t\t\t[^\n]+\n)+)"
        text, count = re.subn(pattern, lambda m: m.group(1) + "".join(list_additions[key]), text)
        if count != 1:
            sys.exit(f"Could not find configuration list {key}")

    # Sandbox is off for these apps (see README); keep the Xcode capability flag in sync.
    text = text.replace("com.apple.Sandbox = {\n\t\t\t\t\t\t\t\tenabled = 1;", "com.apple.Sandbox = {\n\t\t\t\t\t\t\t\tenabled = 0;")

    PBXPROJ.write_text(text)

    # Schemes: one per flavor, derived from the template Runner scheme.
    base_scheme = (SCHEMES_DIR / "Runner.xcscheme").read_text()
    for flavor, (product_name, _) in FLAVORS.items():
        scheme = base_scheme
        for mode in MODES:
            scheme = scheme.replace(f'buildConfiguration = "{mode}"', f'buildConfiguration = "{mode}-{flavor}"')
        scheme = scheme.replace(f'BuildableName = "{ORIGINAL_PRODUCT}.app"', f'BuildableName = "{product_name}.app"')
        (SCHEMES_DIR / f"{flavor}.xcscheme").write_text(scheme)

    print("Added flavors:", ", ".join(FLAVORS))


if __name__ == "__main__":
    main()
