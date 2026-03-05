#!/usr/bin/env python3
"""
Fixture Regenerator — Fetches .fjson data for all reachable screens from the
live Moqui server and writes them to test/fixtures/screens/ for the Flutter
unit/integration tests.

Usage:
  cd runtime/component/moqui-flutter/flutter
  python3 tools/regenerate_fixtures.py

Requires a running Moqui server at http://localhost:8080
"""

import json
import subprocess
import os
import re
import sys
from collections import defaultdict
from datetime import datetime

MOQUI = "http://localhost:8080"
CF = "/tmp/regen_fixtures_cookies.txt"
FIXTURE_DIR = os.path.join(os.path.dirname(__file__), "..", "test", "fixtures", "screens")

# Entity IDs for detail screens (from previous E2E testing)
ENTITY_IDS = {
    "EditParty": {"partyId": "CustJqp"},
    "PartyCalendar": {"partyId": "CustJqp"},
    "PartyEmails": {"partyId": "CustJqp"},
    "PartyMessages": {"partyId": "CustJqp"},
    "PartyRelated": {"partyId": "CustJqp"},
    "PartyTimeEntries": {"partyId": "CustJqp"},
    "PartyAgreements": {"partyId": "CustJqp"},
    "PartyProjects": {"partyId": "CustJqp"},
    "PartyTasks": {"partyId": "CustJqp"},
    "PartyRequests": {"partyId": "CustJqp"},
    "FinancialInfo": {"partyId": "CustJqp"},
    "EditCustomer": {"partyId": "100051"},
    "EditProduct": {"productId": "DEMO_1_1"},
    "Content": {"productId": "DEMO_1_1"},
    "EditAssocs": {"productId": "DEMO_1_1"},
    "EditCategories": {"productId": "DEMO_1_1"},
    "EditPrices": {"productId": "DEMO_1_1"},
    "EditCategory": {"productCategoryId": "PopcAllProducts"},
    "CategoryProducts": {"productCategoryId": "PopcAllProducts"},
    "CategorySubs": {"productCategoryId": "PopcAllProducts"},
    "OrderDetail": {"orderId": "100006"},
    "OrderItems": {"orderId": "100006"},
    "QuickItems": {"orderId": "100006"},
    "ShipmentDetail": {"shipmentId": "100002"},
    "ShipmentItems": {"shipmentId": "100002"},
    "ShipmentPackages": {"shipmentId": "100002"},
    "EditReturn": {"returnId": "100002"},
    "EditRequest": {"requestId": "100000"},
    "EditProject": {"workEffortId": "100004"},
    "Milestones": {"rootWorkEffortId": "100004"},
    "ProjectSummary": {"workEffortId": "100004"},
    "ProjectTasks": {"rootWorkEffortId": "100004"},
    "ProjectUsers": {"rootWorkEffortId": "100004"},
    "ProjectRequests": {"rootWorkEffortId": "100004"},
    "ProjectWiki": {"rootWorkEffortId": "100004"},
    "EditTask": {"workEffortId": "100004-100000"},
    "EditPayment": {"paymentId": "100002"},
    "EditInvoice": {"invoiceId": "100001"},
    "InvoiceItems": {"invoiceId": "100001"},
    "InvoicePayments": {"invoiceId": "100001"},
    "InvoiceAgingSummary": {"invoiceId": "100001"},
    "EditFinancialAccount": {"finAccountId": "100001"},
    "FinancialAccountTrans": {"finAccountId": "100001"},
    "EditTimePeriod": {"timePeriodId": "100003"},
    "ViewPeriodGlAccounts": {"timePeriodId": "100003"},
    "EditGlAccount": {"glAccountId": "110000"},
    "EditBudget": {"budgetId": "100000"},
    "BudgetItems": {"budgetId": "100000"},
    "BudgetReview": {"budgetId": "100000"},
    "BudgetStatus": {"budgetId": "100000"},
    "EditFacility": {"facilityId": "ZIRET_WH"},
    "FacilityLocations": {"facilityId": "ZIRET_WH"},
    "FacilityCalendar": {"facilityId": "ZIRET_WH"},
    "FacilityContacts": {"facilityId": "ZIRET_WH"},
    "EditProductStore": {"productStoreId": "POPC_DEFAULT"},
    "EditPicklist": {"workEffortId": "100005"},
    "PicklistItems": {"workEffortId": "100005"},
}


def login():
    """Authenticate with the Moqui server."""
    if os.path.exists(CF):
        os.remove(CF)
    r = subprocess.run(
        ["curl", "--max-time", "10", "-s", "-c", CF, f"{MOQUI}/Login"],
        capture_output=True, text=True, timeout=15
    )
    m = re.search(r'name="moquiSessionToken"\s+value="([^"]+)"', r.stdout)
    token = m.group(1) if m else ""
    subprocess.run(
        ["curl", "--max-time", "10", "-s", "-c", CF, "-b", CF,
         "-X", "POST", "-d",
         f"username=john.doe&password=moqui&moquiSessionToken={token}",
         f"{MOQUI}/Login/login"],
        capture_output=True, text=True, timeout=15
    )


def fjson_get(path, params=None):
    """Fetch .fjson data from the Moqui server."""
    url = f"{MOQUI}/fapps/{path}.fjson"
    if params:
        url += "?" + "&".join(f"{k}={v}" for k, v in params.items())
    r = subprocess.run(
        ["curl", "--max-time", "20", "-s", "-b", CF,
         "-H", "Accept: application/json", url],
        capture_output=True, text=True, timeout=25
    )
    try:
        return json.loads(r.stdout)
    except (json.JSONDecodeError, ValueError):
        return None


def discover_subscreens(data):
    """Extract subscreen names from a subscreens-panel in the JSON tree."""
    names = set()
    default = None

    def walk(node):
        nonlocal default
        if isinstance(node, dict):
            if node.get("_type") == "subscreens-panel":
                for sub in node.get("subscreens", []):
                    name = sub.get("name", "")
                    if name:
                        names.add(name)
                d = node.get("defaultItem", "")
                if d:
                    names.add(d)
                    default = d
            for v in node.values():
                walk(v)
        elif isinstance(node, list):
            for i in node:
                walk(i)

    walk(data)
    return names, default


def count_widgets(node):
    """Count total widgets in a JSON tree."""
    cnt = 0
    if isinstance(node, dict):
        if "_type" in node:
            cnt += 1
        for v in node.values():
            cnt += count_widgets(v)
    elif isinstance(node, list):
        for i in node:
            cnt += count_widgets(i)
    return cnt


def count_forms(node):
    """Count form-single and form-list in a JSON tree."""
    cnt = 0
    if isinstance(node, dict):
        t = node.get("_type", "")
        if t in ("form-single", "form-list"):
            cnt += 1
        for v in node.values():
            cnt += count_forms(v)
    elif isinstance(node, list):
        for i in node:
            cnt += count_forms(i)
    return cnt


def count_data_rows(node):
    """Count data rows in form-list elements."""
    cnt = 0
    if isinstance(node, dict):
        if node.get("_type") == "form-list":
            cnt += len(node.get("listData", []))
        for v in node.values():
            cnt += count_data_rows(v)
    elif isinstance(node, list):
        for i in node:
            cnt += count_data_rows(i)
    return cnt


def main():
    print("=" * 70)
    print("Moqui Flutter Fixture Regenerator")
    print("=" * 70)

    login()

    # Verify login
    test = fjson_get("marble/dashboard")
    if not test or not test.get("screenName"):
        print("ERROR: Login failed or dashboard not reachable")
        sys.exit(1)
    print("Login OK\n")

    os.makedirs(FIXTURE_DIR, exist_ok=True)

    all_screens = {}  # path -> json data
    manifest_entries = []
    crawled = set()

    def crawl(path, depth=0, max_depth=6):
        if path in crawled or depth > max_depth:
            return
        crawled.add(path)

        # Determine params for detail screens
        screen_name = path.split("/")[-1]
        params = ENTITY_IDS.get(screen_name)

        data = fjson_get(path, params)
        if data is None:
            print(f"  SKIP {path} (fetch failed)")
            return

        if "errorCode" in data or "errorMessage" in data:
            err = data.get("errorMessage", data.get("errors", ""))
            if err and "Required parameter missing" in str(err):
                print(f"  SKIP {path} (needs entity ID)")
                return
            # Still save error screens for testing error handling
            pass

        sn = data.get("screenName", "")
        wc = count_widgets(data)
        fc = count_forms(data)
        dr = count_data_rows(data)

        all_screens[path] = data
        manifest_entries.append({
            "path": path,
            "screenName": sn,
            "widgets": wc,
            "forms": fc,
            "dataRows": dr,
            "params": params or {},
        })

        status = "OK" if wc > 0 else "EMPTY"
        print(f"  [{status}] {path} (widgets={wc}, forms={fc}, rows={dr})")

        # Discover and crawl subscreens
        sub_names, default_name = discover_subscreens(data)
        for sub_name in sorted(sub_names):
            sub_path = f"{path}/{sub_name}"
            crawl(sub_path, depth + 1, max_depth)

    # Start crawling from marble root
    print("Crawling screens...")
    crawl("marble")

    print(f"\nCrawled {len(all_screens)} screens total.")

    # Write fixtures
    print(f"\nWriting fixtures to {FIXTURE_DIR}/")
    written = 0
    for path, data in sorted(all_screens.items()):
        filename = path.replace("/", "__") + ".fjson"
        filepath = os.path.join(FIXTURE_DIR, filename)
        with open(filepath, "w") as f:
            json.dump(data, f, indent=2)
        written += 1

    # Write manifest
    manifest = {
        "generated": datetime.now().isoformat(),
        "moqui_url": MOQUI,
        "total_screens": len(all_screens),
        "screens": manifest_entries,
    }
    with open(os.path.join(FIXTURE_DIR, "_manifest.json"), "w") as f:
        json.dump(manifest, f, indent=2)

    # Write entity IDs reference
    with open(os.path.join(FIXTURE_DIR, "_entity_ids.json"), "w") as f:
        json.dump(ENTITY_IDS, f, indent=2)

    # Write screen tree
    tree = {}
    for entry in manifest_entries:
        parts = entry["path"].split("/")
        for i in range(len(parts)):
            parent = "/".join(parts[:i + 1])
            if parent not in tree:
                tree[parent] = []
            if i + 1 < len(parts):
                child = "/".join(parts[:i + 2])
                if child not in tree[parent]:
                    tree[parent].append(child)
    with open(os.path.join(FIXTURE_DIR, "_screen_tree.json"), "w") as f:
        json.dump(tree, f, indent=2)

    print(f"\nWrote {written} fixture files + _manifest.json + _entity_ids.json + _screen_tree.json")
    print("Done!")


if __name__ == "__main__":
    main()
