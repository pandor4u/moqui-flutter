import asyncio
from playwright.async_api import async_playwright

async def run():
    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)
        page = await browser.new_page()
        
        print("Loading...")
        await page.goto("http://localhost:8181")
        await asyncio.sleep(5)
        
        content = await page.evaluate("document.body.innerText")
        print("Page text content:", content.strip())
        
        html = await page.evaluate("document.body.innerHTML")
        print("Page HTML size:", len(html))
        
        await browser.close()

if __name__ == "__main__":
    asyncio.run(run())
