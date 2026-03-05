import asyncio
from playwright.async_api import async_playwright

async def run():
    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)
        page = await browser.new_page()
        
        print("Logging in...")
        await page.goto("http://localhost:8181")
        await page.fill("input[name='username']", "john.doe")
        await page.fill("input[name='password']", "moqui")
        await page.click("button:has-text('Login')")
        
        print("Navigating to Find Party...")
        await page.wait_for_url("**/marble**")
        await page.goto("http://localhost:8181/#/fapps/marble/Party/FindParty")
        
        await asyncio.sleep(2)
        print("Clicking 'Create Person'...")
        create_btn = page.locator("button:has-text('Create Person')")
        if await create_btn.count() == 0:
             print("Create Person button not found!")
             buttons = await page.locator("button").all_text_contents()
             print("Available buttons:", buttons)
        else:
             await create_btn.click()
             await asyncio.sleep(1)
             
             print("Filling form...")
             await page.fill("input[name='firstName']", "Test")
             await page.fill("input[name='lastName']", "PersonPlaywright")
             
             await page.locator("button:has-text('Save')").first.click()
             await asyncio.sleep(2)
             
             print("Success check...")
             snackbars = await page.locator(".snack-bar").all_text_contents()
             print("Snackbars:", snackbars)

             # check if we navigated back to FindParty and dialog is gone
             dialogs = await page.locator("dialog").count()
             print("Open dialogs:", dialogs)
             
             print("Current URL:", page.url)
             
        await browser.close()

if __name__ == "__main__":
    asyncio.run(run())
