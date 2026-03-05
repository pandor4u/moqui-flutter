import re

with open("test/e2e/playwright_flutter_test_patched.py", "r") as f:
    orig = f.read()

new_content = orig.replace(
    '''            # Test each module
            for module_key, module_def in MODULE_SCREENS.items():
                await self._test_module(page, module_key, module_def)''',
    '''            # SKIP MODULE TESTS FOR SPEED
'''
)

# And drop the demo data creation! We only care about flutter ui login and crud test!
new_content = new_content.replace(
    '''        # Phase 1: Create background demo data via Moqui REST API
        print("[Phase 1] Creating missing demo data via API...")
        creator = DemoDataCreator(self.api)
        self.entities = creator.create_all()''',
    '''        # Skipped Phase 1
        self.entities = {}'''
)

with open("test/e2e/playwright_flutter_test_fast.py", "w") as f:
    f.write(new_content)
