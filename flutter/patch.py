import re

with open("test/e2e/playwright_flutter_test.py", "r") as f:
    orig = f.read()

insert_code = """
        # --- TEST 0: Create Person from Find Party ---
        start = time.time()
        result = CrudResult(entity_type="person", operation="create")
        print("\\n    Testing Create Person from Find Party...")
        try:
            await page.goto(f"{FLUTTER_BASE}/#/fapps/marble/Party/FindParty")
            await asyncio.sleep(2.0)
            
            # Click Create Person
            await page.get_by_role("button", name="Create Person").click(timeout=5000)
            await asyncio.sleep(2.0)
            
            # Fill form
            await page.get_by_role("textbox", name="First Name").click(timeout=5000)
            for ch in "Playwright":
                await page.keyboard.press(ch)
            await asyncio.sleep(0.5)

            await page.get_by_role("textbox", name="Last Name").click(timeout=5000)
            for ch in "TestPerson":
                await page.keyboard.press(ch)
            await asyncio.sleep(0.5)
            
            # Submit
            await page.get_by_role("button", name="Save").last.click(timeout=5000)
            await asyncio.sleep(3.0)
            
            # check dialog closed
            info = await get_page_info(page)
            if "Save" not in info["buttons"]:
                result.status = "pass"
                print("      ✓ Create Person: dialog closed correctly")
            else:
                result.status = "fail"
                result.error = "Dialog still open"
                print("      ✗ Create Person: Dialog still open")
                
        except Exception as e:
            result.status = "error"
            result.error = str(e)[:200]
            print(f"      ✗ Create Person error: {e}")
            
        result.duration_ms = int((time.time() - start) * 1000)
        self.crud_results.append(result)
        
"""

new_content = orig.replace(
    'async def _test_crud_operations(self, page: Page):\n        """Test CRUD operations through the Flutter UI."""\n',
    'async def _test_crud_operations(self, page: Page):\n        """Test CRUD operations through the Flutter UI."""\n' + insert_code
)

with open("test/e2e/playwright_flutter_test_patched.py", "w") as f:
    f.write(new_content)
