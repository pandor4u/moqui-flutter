import asyncio
from playwright.async_api import async_playwright

async def run():
    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)
        page = await browser.new_page()
        
        print("Logging in...")
        await page.goto("http://localhost:8181")
        
        print("Waiting for page load...")
        try:
            await page.wait_for_selector("input", timeout=30000)
            await page.wait_for_selector("button:has-text('Login')", timeout=30000)
        except Exception as e:
            print("Failed to load flutter app. Error:", e)
            await page.screenshot(path="failed_load.png")
            await browser.close()
            return

        print("Trying to type username...")
        inputs = await page.locator("input").count()
        print("Inputs found:", inputs)
        
        if inputs == 2:
            await page.locator("input").nth(0).fill("john.doe")
            await page.locator("input").nth(1).fill("moqui")
        else:
            await page.fill("input[name='username']", "john.doe")
            await page.fill("input[name='password']", "moqui")
        
        await page.click("button:has-text('Login')")
        
        print("Wait for dashboard...")
        await page.wait_for_url("**/marble**", timeout=10000)
        await asyncio.sleep(2)
        
        print("Navigating to Find Party...")
        await page.goto("http://localhost:8181/#/fapps/marble/Party/FindParty")
        
        # We need to wait for Flutter to render the Create Person button
        print("Searching for Create Person button...")
        create_btn = page.locator("button:has-text('Create Person')")
        try:
            await create_btn.first.wait_for(timeout=15000)
        except:
             print("Create Person missing, list of buttons:")
             btns = await page.locator("button").all_text_contents()
             print(btns)
             await browser.close()
             return

        print("Clicking 'Create Person'...")
        await create_btn.first.click()
        
        print("Wait for dialog...")
        await page.wait_for_selector("dialog input, .q-dialog input", timeout=10000)
        
        print("Filling form...")
        # Since field names might not be perfectly matched in flutter dom, we might just try to find them inside dialog
        dialog = page.locator("dialog").first
        if await dialog.count() == 0:
            dialog = page.locator("*").first # fallback
            
        await page.locator("input").nth(0).fill("Playwright") # we will just fill all inputs if needed
        # Or let's assume they map to proper semantics
        try:
             await page.fill("input[name='firstName']", "Playwright")
             await page.fill("input[name='lastName']", "TestPerson")
        except:
             print("Could not find firstName/lastName, filling first two dialog inputs")
             await dialog.locator("input").nth(0).fill("Playwright")
             await dialog.locator("input").nth(1).fill("TestPerson")
        
        save_btn = page.locator("button", has_text="Save").first
        if await save_btn.count() == 0:
            save_btn = page.locator("button:has-text('Create Person')").last
        await save_btn.click()
        
        print("Waiting for success...")
        await asyncio.sleep(5)
        dialog_count = await page.locator("dialog").count()
        print("Open dialogs:", dialog_count)
        if dialog_count == 0:
            print("Create Person form closed successfully. The CRUD Create test passed.")
        else:
            print("Dialog is still open.")
            
        await browser.close()

if __name__ == "__main__":
    asyncio.run(run())
