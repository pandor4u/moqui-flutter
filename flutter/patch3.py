with open("test/e2e/playwright_flutter_test_fast.py", "r") as f:
    orig = f.read()

insert = """
def on_response(response):
    if response.status >= 400:
        print(f"FAILED RESPONSE {response.status}: {response.url}")

async def _test_crud_operations(self, page: Page):
    page.on("response", on_response)
"""
orig = orig.replace("async def _test_crud_operations(self, page: Page):", insert)

with open("test/e2e/playwright_flutter_test_fast.py", "w") as f:
    f.write(orig)
