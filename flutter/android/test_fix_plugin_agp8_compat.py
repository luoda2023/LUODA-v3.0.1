import unittest
from pathlib import Path

from fix_plugin_agp8_compat import fix_compile_sdk, fix_missing_compile_sdk


class FixPluginAgp8CompatTest(unittest.TestCase):
    def test_replaces_flutter_compile_sdk_reference_with_supported_sdk(self):
        original = """android {
    compileSdkVersion flutter.compileSdkVersion
}
"""

        patched, modified = fix_compile_sdk(original)

        self.assertTrue(modified)
        self.assertIn("compileSdkVersion 35", patched)
        self.assertNotIn("flutter.compileSdkVersion", patched)

    def test_missing_compile_sdk_uses_supported_sdk(self):
        original = """android {
    namespace = \"com.example.plugin\"
}
"""

        patched, modified = fix_missing_compile_sdk(original)

        self.assertTrue(modified)
        self.assertIn("compileSdkVersion 35", patched)

    def test_root_build_supplies_missing_plugin_namespaces_for_agp8(self):
        root_build = Path(__file__).with_name("build.gradle.kts").read_text(
            encoding="utf-8"
        )

        self.assertIn('plugins.withId("com.android.library")', root_build)
        self.assertIn("if (namespace == null)", root_build)
        self.assertIn("namespace = project.group.toString()", root_build)

    def test_root_build_forces_cached_agp_for_legacy_plugins(self):
        root_build = Path(__file__).with_name("build.gradle.kts").read_text(
            encoding="utf-8"
        )

        self.assertIn('requested.group == "com.android.tools.build"', root_build)
        self.assertIn('requested.name == "gradle"', root_build)
        self.assertIn('useVersion("8.1.0")', root_build)

    def test_root_build_exposes_flutter_compile_sdk_to_plugins(self):
        root_build = Path(__file__).with_name("build.gradle.kts").read_text(
            encoding="utf-8"
        )

        self.assertIn("org.gradle.api.plugins.ExtensionAware", root_build)
        self.assertIn('"compileSdkVersion" to 35', root_build)

if __name__ == "__main__":
    unittest.main()
