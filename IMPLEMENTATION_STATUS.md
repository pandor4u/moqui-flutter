# Moqui Flutter - Implementation Status

## Overview

The moqui-flutter component provides a Flutter web/mobile client for Moqui Framework, with a custom JSON renderer (`ScreenWidgetRenderJson.groovy`) that converts Moqui XML screen widgets to JSON consumed by the Flutter `widget_factory.dart`.

## Bug Fixes (Feb 2025)

### Server-Side (`ScreenWidgetRenderJson.groovy`)

1. **Container-box header title serialization** — The `box-header` `title` attribute was not being extracted and serialized. Fixed by reading the `box-header` child node's `title` attribute and putting it as `boxTitle` in the JSON output.

2. **Form-list data via `getFormListRowValues()`** — Form-list widgets were returning empty data because the renderer was not using the proper Moqui API chain. Fixed by using `getForm()` → `getFormInstance()` → `makeFormListRenderInfo()` → `sri.getFormListRowValues(renderInfo)` with pagination support.

3. **Section actions execution and condition evaluation** — `renderSection()` was not running section actions or evaluating conditions. Fixed to: (a) run `ScreenSection.actions.run(ec)`, (b) evaluate the `condition` attribute via `ec.resourceFacade.expression()`, and (c) render only `widgets` or `failWidgets` based on the condition result.

4. **Section-iterate list iteration with context** — `renderSectionIterate()` was not iterating over the list. Fixed to: (a) run section actions, (b) evaluate the list from context, (c) create an Iterator and iterate with `ec.contextStack.push()/pop()` per entry (setting entry, key, index, has\_next), (d) render widget children for each iteration, and (e) output an `iterations` array in the JSON.

5. **Expression expansion (`${...}`) in widget attributes** — Added an `expand()` helper method that resolves `${...}` expressions using `ec.resourceFacade.expand()`. Applied to:
   - `renderLink()`: `url`, `text`, `confirmation`, `tooltip`
   - `renderLabel()`: `text`
   - `renderContainerDialog()`: `buttonText`, `dialogTitle`

6. **Subscreens-panel content rendering** — `renderSubscreensPanel()` was not including the list of available subscreens or the active subscreen content. Fixed to: (a) get the active screen definition and call `getMenuSubscreensItems()`, (b) serialize each subscreen's `name`, `menuTitle`, `menuIndex`, `menuInclude`, `disabled` into a `subscreens` array, (c) read the `default-item` from the `<subscreens>` config and include as `defaultItem`, (d) render the active subscreen content inline via `sri.renderSubscreen()` as `preloadedActiveSubscreen`.

7. **Cache-Control headers for `.fjson` responses** — The server was sending `Cache-Control: max-age=86400` for `.fjson` responses, causing browsers to cache screen data for 24 hours. Fixed by overriding response headers in `render()` with `Cache-Control: no-cache, no-store, must-revalidate, private` + `Pragma: no-cache` + `Expires: 0`.

### Flutter-Side (`widget_factory.dart` / `moqui_api_client.dart`)

8. **Container-box title fallback** — `_buildContainerBox()` now checks for the `boxTitle` attribute when no header children exist, and renders the title text in the header.

9. **`_display` suffix field value resolution** — `_buildCellWidget()` and `_buildCellDisplay()` now check `row['${field.name}_display']` before falling back to `row[field.name]`, matching how Moqui's `addFormFieldValue()` stores display-widget values with a `_display` suffix.

10. **Section-iterate iterations array handling** — `_buildSectionIterate()` now checks for the server-provided `iterations` array first. Each iteration's widgets are rendered via `iterations.expand<Widget>((iteration) => ...)`. Falls back to `node.children` or client-side `widgetTemplate` iteration.

11. **Subscreens-panel widget implementation** — `_buildSubscreensPanel()` now normalizes the server response (mapping `menuTitle` → `title`, `name` → `path`), marks the `defaultItem` as active, creates a `_SubscreensPanelWidget` StatefulWidget with popup-style sidebar navigation (8 menu buttons + content area), and renders the `preloadedActiveSubscreen` from the server response.

12. **Cache-busting for `.fjson` requests** — Added a `_t` timestamp query parameter to all `fetchScreen()` Dio requests to prevent the browser's HTTP cache from serving stale `.fjson` responses.

## Verification Results

### Unit Tests
- **410 Flutter tests** — All passing

### Playwright End-to-End Verification

| Screen | Result | Details |
|--------|--------|---------|
| **Entity List** (`/fapps/tools/Entity/DataEdit/EntityList`) | PASS | 20 rows displayed with package, entityName, isView columns populated. Pagination shows "1-20 of 876". |
| **Service Reference** (`/fapps/tools/Service/ServiceReference`) | PASS | 20 rows with service names. Pagination shows "1-20 of 966". Link columns present. |
| **Dashboard** (`/fapps/tools/dashboard`) | PASS | All section headers rendered (General Tools, REST API: Swagger UI, Entity Tools, Generated Diagrams). Section-iterate expressions resolved: "Moqui Tools REST API (89)", "Mantle USL REST API (416)", "Entity Master API". No raw `${...}` templates. |
| **Tools** (`/fapps/tools`) | PASS | Subscreens panel renders 8 subscreen buttons (Dashboard, Auto Screen, Artifact Stats, Groovy Shell, Status Flows, Data View, Entity, Service). Dashboard loads by default with all sections visible. |
| **Marble ERP** (`/fapps/marble`) | PASS | Subscreens panel renders 23 subscreen buttons. Dashboard loads by default. |

### cURL Response Header Verification
- `Cache-Control: no-cache, no-store, must-revalidate, private` ✓
- `Pragma: no-cache` ✓
- `Expires: Thu, 01 Jan 1970 00:00:00 GMT` ✓

## Known Limitations

1. **Header-field filter forms** — `header-field` widgets in form-list (e.g., filter textboxes, dropdowns) are not yet rendered in the Flutter client.

2. **Link condition evaluation** — Link `condition` attributes (e.g., `ec.user.hasPermission('GROOVY_SHELL_WEB')`) are serialized but not server-side evaluated, so conditional links may appear when they shouldn't.

3. **Tooltip rendering** — Tooltips with `${...}` expressions are now correctly expanded on the server side. The Flutter client renders tooltip text as part of container-box semantics but does not yet show native tooltip on hover.

4. **RenderFlex overflow** — Some subscreens-panel buttons overflow by ~27 pixels when text is too long for the available width. Needs `Flexible`/`Expanded` wrapping or `TextOverflow.ellipsis`.
