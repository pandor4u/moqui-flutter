import asyncio
from playwright.async_api import async_playwright

USERNAME = "john.doe"
PASSWORD = "moqui"

async def run():
    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)
        page = await browser.new_page()

        await page.goto("http://localhost:8181/?FLUTTER_WEB_ENABLE_SEMANTICS=true")
        await asyncio.sleep(3)

        print("Logging in...")
        try:
            await page.get_by_role("textbox", name="Username").click(timeout=3000)
        except:
            pass
        for ch in USERNAME:
            await page.keyboard.press(ch)
        await page.keyboard.press("Tab")
        await asyncio.sleep(0.3)
        await page.evaluate(
            """() => {
                const host = document.querySelector('flt-text-editing-host');
                const input = host ? host.querySelector('input') : null;
                if (input) {
                    input.value = '%s';
                    input.dispatchEvent(new Event('input', {bubbles: true}));
                }
            }""" % PASSWORD
        )
        await page.keyboard.press("Enter")
        
        try:
            await page.wait_for_url("**/marble**", timeout=10000)
            print("Login success")
        except:
            print("Login timed out, proceeding anyway")

        print("Navigating to FindParty...")
        await page.goto("http://localhost:8181/?FLUTTER_WEB_ENABLE_SEMANTICS=true#/fapps/marble/Party/FindParty")
        
        await asyncio.sleep(5)
        print("Clicking New Person...")
        await page.locator("text='New Person'").first.click()
        await asyncio.sleep(2)
        
        print("Dumping all semantics...")
        nodes = await page.locator("flt-semantics").element_handles()
        labels = []
        for n in nodes:
            label = await n.get_attribute("aria-label")
            if label:
                labels.append(label)
        print("All aria labels:", labels)
        
        await browser.close()

if __name__ == "__main__":
    asyncio.run(run())
