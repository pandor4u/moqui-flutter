import asyncio
from playwright.async_api import async_playwright

async def run():
    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)
        page = await browser.new_page()
        
        print("Logging in...")
        await page.goto("http://localhost:8181")
        await asyncio.sleep(3)
        
        try:
            print("Trying to type username...")
            # For Moqui-Flutter, it might use specific input names
            try:
                await page.fill("input[name='username']", "john.doe")
                await page.fill("input[name='password']", "moqui")
            except:
                inputs = await page.locator("input").count()
                print("Inputs found:", inputs)
                if inputs >= 2:
                    await page.locator("input").nth(0).fill("john.doe")
                    await page.locator("input").nth(1).fill("moqui")
            
            await page.click("button:has-text('Login')")
            
            print("Wait for page to load...")
            await asyncio.sleep(5)
            
            print("Navigating to Find Party...")
            await page.goto("http://localhost:8181/#/fapps/marble/Party/FindParty")
            await asyncio.sleep(4)
            
            print("Clicking 'Create Person'...")
            create_btn = page.locator("button", has_text="Create Person")
            if await create_btn.count() == 0:
                 print("Create Person button not found!")
            else:
                 await create_btn.first.click()
                 await asyncio.sleep(2)
                 
                 print("Filling form...")
                 # Moqui-Flutter uses matching inputs by name for variables
                 await page.fill("input[name='firstName']", "Test")
                 await page.fill("input[name='lastName']", "PersonPlaywright")
                 
                 save_btn = page.locator("button", has_text="Save")
                 await save_btn.first.click()
                 await asyncio.sleep(3)
                 
                 print("Success check...")
                 try:
                     dialog_count = await page.locator("dialog").count()
                     print("Open dialogs:", dialog_count)
                     if dialog_count == 0:
                         print("Create Person form closed successfully.")
                 except Exception:
                     pass
        except Exception as e:
            print("Error:", e)
             
        await browser.close()

if __name__ == "__main__":
    asyncio.run(run())
