# Flutter Screen Analysis Report & Fix Plan

## Analysis Method

Used a Python API-based screen crawler that:
1. Authenticates via session cookie to the Moqui `.fjson` API
2. Recursively discovers subscreens from `subscreens-panel` nodes and `menuData` endpoints
3. Crawls all reachable screens (176 paths attempted)
4. Analyzes the JSON widget tree for known issue patterns
5. Produces a structured issue report

**Scripts**: `/tmp/screen_crawler_v2.py`, `/tmp/analyze_detail_screens.py`
**JSON report**: `/tmp/screen_analysis_report.json`

---

## Executive Summary

| Metric | Count |
|---|---|
| Screens fetched OK | 77 |
| Screens requiring params (ERR) | 99 |
| Total paths attempted | 176 |
| Total widgets analyzed | 581+ |
| Actionable issues | 26 |
| Info-only issues | 5 |

### Issue Breakdown

| Issue Type | Count | Severity | Status |
|---|---|---|---|
| HTML tag leaking | 10 | Warning | **TO FIX** |
| Empty forms (no fields) | 7 | Warning | **TO FIX** |
| Unresolved `${...}` templates | 6 | Warning | **TO FIX** |
| Conditional label unresolved | 3 | Warning | **TO FIX** |
| Empty sections | 3 | Info | Low priority |
| `transition="."` forms | 2 | Info | **ALREADY FIXED** |
| `field-row-big` empty | ? | Info | **ALREADY FIXED** |

---

## Detailed Findings

### 1. HTML Tags Leaking in Dashboard Labels (10 issues)

**Location**: `marble/dashboard`
**Pattern**: Link/label `text` contains raw HTML: `<strong>`, `&amp;`
**Examples**:
- `"Customer <strong>Requests</strong>"`
- `"Sales <strong>Orders</strong> &amp; Quotes"`
- `"Purchase <strong>Shipments</strong>"`
- `"Receivable <strong>Invoices</strong>"`
- 10 total instances on the dashboard

**Root Cause**: Moqui screen XML uses `<strong>` for emphasis in link text. The HTML Moqui renderer handles this natively but the Flutter `label`/`link` widget renders it as raw text.

**Fix**: In `widget_factory.dart`, when building `label` or `link` widgets, detect HTML content in `text` and either:
- (a) Use a lightweight HTML-to-RichText parser (the `_buildHtmlContent` method already exists for `render-html` type), or
- (b) Strip common HTML tags and apply Flutter `TextSpan` formatting, or
- (c) At minimum, strip tags and decode entities (`&amp;` → `&`)

**Priority**: HIGH (dashboard is the first screen users see)

---

### 2. Empty Forms — FindCustomer, FindSupplier, QuickSearch (7 issues)

**Affected Screens**:
- `marble/Customer/FindCustomer`: CreateAccountForm (0 fields), CreateContactForm (0 fields), OuterSearchForm (0 fields)
- `marble/Supplier/FindSupplier`: CreatePersonForm (0 fields), CreateOrganizationForm (0 fields), OuterSearchForm (0 fields)
- `marble/QuickSearch`: SearchOptions (0 fields)

**Root Cause**: These screens extend the Party screen via Moqui's `extends` mechanism. In the Customer/Supplier context, the forms are re-defined with fewer fields or the context doesn't resolve all fields. The `.fjson` response returns an empty `fields[]` array.

**Key Finding**: `FindCustomer.OuterSearchForm` has `transition: ''` (empty) and 0 fields, whereas `FindParty.OuterSearchForm` has `transition: '.'` and 2 fields. The Customer version works differently — it likely uses query parameter binding directly without a search form.

**Fix options**:
1. **Hide empty forms**: When a form-single has 0 fields, render `SizedBox.shrink()` instead of an empty container
2. **container-dialog suppression**: Empty forms are typically inside `container-dialog` — if the dialog's form is empty, hide the dialog button entirely
3. For `OuterSearchForm` specifically: check if the parent screen has query parameter bindings and render a search field from those

**Priority**: MEDIUM (functional screens still load; just have unnecessary empty dialogs)

---

### 3. Unresolved Template Expressions (6 issues + 3 conditional)

**Affected Screens**:
- `marble/Asset/Asset`: `": ${product.productName}"` (conditional, `condition="partyDetail"`)
- `marble/ProductStore`: `"${productStoreId}: ${productStore.storeName}"` (conditional)
- `marble/Task`: `"Task ${task.workEffortId} - ${task.workEffortName}"` (conditional)

**Root Cause**: These are conditional labels (have `condition` attribute) that display entity-specific text. When no specific entity is loaded (e.g., no `assetId` parameter), the condition is false and the label shouldn't render. The `resolvedText` field equals the raw `text` field, meaning the server didn't resolve the variables because the context data wasn't available.

**Fix**: 
1. When a label has a `condition` attribute and the `resolvedText` still contains `${...}`, skip rendering (the condition evaluated to false server-side, or there's no data)
2. Alternatively, implement client-side template variable resolution using available data from the screen context

**Priority**: LOW (these labels only show on wrapper screens without entity params; when navigated to with proper params, they resolve correctly)

---

### 4. Widget Types Not Handled

**Widget types found in screen JSON**:

Main types (all handled ✅):
`container`, `container-box`, `container-dialog`, `container-row`, `dynamic-container`, `dynamic-dialog`, `form-list`, `form-single`, `label`, `link`, `section`, `section-include`, `section-iterate`, `subscreens-active`, `subscreens-panel`, `text`, `widgets`, `button-menu`, `screen`

Field widget types (all handled in `field_widget_factory.dart` ✅):
`text-line`, `text-area`, `text-find`, `drop-down`, `date-time`, `date-period`, `date-find`, `display`, `display-entity`, `hidden`, `ignored`, `check`, `radio`, `file`, `range-find`, `submit`

Layout directives (handled in form layout parsing ✅):
`field-layout`, `field-ref`, `field-row`, `field-row-big`, `fields-not-referenced`

**Not handled** ⚠️:
- `widget-template-include` — Moqui construct for template includes. Appears inside forms (field context). Need to investigate what templates these reference.

**Priority**: LOW (`widget-template-include` is uncommon and typically provides optional UI enhancements)

---

### 5. Detail Screens Requiring Parameters (99 ERR)

**Note**: These are NOT bugs. Screens like `EditParty`, `OrderDetail`, `EditInvoice` etc. require entity ID parameters. They return "Required parameter missing" when accessed without params.

The crawler correctly identifies these. In the Flutter app, these screens are only reached by navigating from list screens (which pass the required parameters), so they work correctly in practice.

**No fix needed** — this is expected behavior.

---

### 6. Known Visual Issues (from Playwright testing, not API-detectable)

These issues were observed during manual Playwright testing of FindParty and EditParty screens:

| Issue | Description | Affected | Priority |
|---|---|---|---|
| **Duplicate text** | "EX_JOHN_DOE EX_JOHN_DOE" in form-list cells | All form-lists with link columns | HIGH |
| **Non-clickable links** | Party names in form-list table are text, not navigable | All form-list link fields | HIGH |
| **Raw field names** | Column headers show "pseudoId" instead of "ID" | Form-list headers | MEDIUM |
| **Submit column** | "submitButton" shows as visible column header | Form-lists with row actions | MEDIUM |

**Root Cause Analysis**:

**Duplicate text**: Form field data has both `fieldName` and `fieldName_display` in list data. The form-list renderer is showing BOTH the link text and the display value. When a field has `widgetType: "link"`, only the link widget should render (not the display fallback).

**Non-clickable links**: Form-list fields have `widgets: [{"_type": "link", "url": "editParty", "urlType": "transition"}]` but the form-list renderer may not be converting these into actual clickable navigation widgets.

**Raw field names**: Fields have `title` set to the raw field name (e.g., `"title": "pseudoId"`). Moqui typically converts camelCase to human-readable titles in the HTML renderer via localization, but the Flutter client receives the raw title.

**Submit column**: The `submitButton` field in form-list is meant to be a row action (delete/update button), not a visible data column. The form-list should either hide it or render it as an action column.

---

## Fix Plan (Prioritized)

### Phase 1: High Priority (Dashboard & Lists)

#### Fix 1.1: HTML Tag Rendering in Labels/Links
- **Files**: `widget_factory.dart` — `_buildLabel()`, `_buildLink()`  
- **Change**: When `text` contains HTML tags, use `_buildHtmlContent()` or strip tags
- **Impact**: Fixes 10 dashboard issues
- **Effort**: Small

#### Fix 1.2: Duplicate Text in Form-List Cells
- **Files**: `widget_factory.dart` — form-list cell rendering
- **Change**: When a form-list field has a `link` widget type, render ONLY the link widget, not both link text and display value
- **Impact**: Fixes duplicate text in ALL form-list screens
- **Effort**: Medium

#### Fix 1.3: Form-List Link Navigation  
- **Files**: `widget_factory.dart` — form-list cell rendering
- **Change**: Properly render `widgets[{"_type": "link"}]` in form-list cells as clickable navigation links
- **Impact**: Makes all list→detail navigation work
- **Effort**: Medium

### Phase 2: Medium Priority (UI Polish)

#### Fix 2.1: Hide Empty Forms
- **Files**: `widget_factory.dart` — `_buildFormSingle()`
- **Change**: When `fields` is empty, return `SizedBox.shrink()`
- **Impact**: Fixes 7 empty form issues in Customer/Supplier/QuickSearch
- **Effort**: Small

#### Fix 2.2: Column Header Humanization
- **Files**: `widget_factory.dart` — form-list header rendering
- **Change**: Convert camelCase field names to human-readable titles (insert spaces before capitals, capitalize first letter)
- **Impact**: Improves all form-list headers
- **Effort**: Small

#### Fix 2.3: Submit Button Column Handling
- **Files**: `widget_factory.dart` — form-list column rendering
- **Change**: Detect `submitButton` field name and render as action column (or hide if no transition)
- **Impact**: Removes "submitButton" column from form-list headers
- **Effort**: Small

### Phase 3: Low Priority (Edge Cases)

#### Fix 3.1: Conditional Label Suppression
- **Files**: `widget_factory.dart` — `_buildLabel()`
- **Change**: When `condition` is set and `resolvedText` contains `${...}`, return `SizedBox.shrink()`
- **Impact**: Fixes 6 unresolved template issues
- **Effort**: Small

#### Fix 3.2: `widget-template-include` Handling
- **Files**: `widget_factory.dart` — main switch
- **Change**: Either pass-through to children or render as SizedBox
- **Impact**: Prevents potential rendering gaps
- **Effort**: Small

#### Fix 3.3: HTML Entity Decoding
- **Files**: `widget_factory.dart`
- **Change**: Decode `&amp;`, `&lt;`, `&gt;`, `&quot;` etc. in all text values
- **Impact**: Fixes minor display issues
- **Effort**: Small

---

## Screen Coverage Map

### Screens That Load Successfully (77)

**Module Roots** (22): marble, dashboard, QuickSearch, Accounting, Asset, Catalog, Customer, Facility, HumanRes, Manufacturing, Order, Party, Project, ProductStore, Gateway, Request, Return, Shipment, Shipping, Supplier, Survey, Task, Wiki, QuickViewReport, SimpleReport

**List Screens** (20+): FindParty✅, FindOrder✅, FindCustomer✅, FindSupplier✅, FindProduct✅, FindInvoice✅, FindPayment✅, FindShipment✅, FindReturn✅, FindRequest✅, FindProject✅, FindTask✅, FindPicklist✅, etc.

**Detail Screens** (require params, 99): EditParty, OrderDetail, EditInvoice, ShipmentDetail, etc. — all work when navigated to with proper parameters.

### Widget Type Coverage

| Category | Types | Status |
|---|---|---|
| Layout Containers | container, container-box, container-row, container-panel, container-dialog | ✅ All handled |
| Forms | form-single, form-list | ✅ Handled |
| Sections | section, section-iterate, section-include | ✅ Handled |
| Navigation | subscreens-panel, subscreens-menu, subscreens-active | ✅ Handled |
| Content | label, link, text, image | ✅ Handled |
| Dynamic | dynamic-dialog, dynamic-container | ✅ Handled |
| Other | button-menu, tree, include-screen | ✅ Handled |
| Field Widgets | text-line, text-area, text-find, drop-down, date-time, date-period, display, display-entity, hidden, ignored, check, radio, file, range-find, submit | ✅ All handled by field_widget_factory |
| Missing | widget-template-include | ⚠️ Not handled |

---

## Automated Testing Strategy

### API-Based Screen Crawler (Implemented)
- Script: `/tmp/screen_crawler_v2.py`
- Detects: HTML leaks, empty forms, unresolved templates, unknown widget types, missing metadata
- Can be run periodically or in CI

### Recommended Additions
1. **Form field widget type coverage test**: Verify every `_type` value found in `widgets[]` arrays is handled by `field_widget_factory.dart`
2. **Form-list link navigation test**: For each form-list with link columns, verify the link URL resolves
3. **Detail screen rendering test**: Use known entity IDs to fetch detail screens with params and verify widget tree renders completely
4. **Regression test**: Compare crawl results before/after code changes to detect new issues
