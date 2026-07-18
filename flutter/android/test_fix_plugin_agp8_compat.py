import unittest

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


if __name__ == "__main__":
    unittest.main()
