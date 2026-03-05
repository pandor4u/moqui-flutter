#!/usr/bin/env python3
"""
Comprehensive Moqui Flutter Screen Crawler & Issue Detector v2.

Fetches .fjson data for all screens reachable from the Marble ERP app,
analyzes the JSON widget tree for known rendering issues, and produces
a structured report.
"""

import json
import subprocess
import sys
import re
from collections import defaultdict

COOKIE = "/tmp/moqui_ct2"
BASE = "http://localhost:8080"

# Widget types handled by widget_factory.dart's main switch
HANDLED_TYPES = {
    'form-single', 'form-list', 'section', 'section-iterate',
    'container', 'container-box', 'container-row', 'container-panel',
    'container-dialog', 'subscreens-panel', 'subscreens-menu',
    'subscreens-active', 'link', 'label', 'image', 'dynamic-dialog',
    'dynamic-container', 'button-menu', 'tree', 'text',
    'include-screen', 'section-include',
    # Meta types handled:
    'widgets', 'screen', 'render-html',
}

HTML_TAG_PATTERN = re.compile(r'<(strong|em|b|i|br|span|div|p|a|ul|ol|li|h[1-6]|font|small|big|sub|sup|mark|del|ins|pre|code|blockquote|table|tr|td|th|img|hr)\b[^>]*>', re.IGNORECASE)
TEMPLATE_VAR_PATTERN = re.compile(r'\$\{[^}]+\}')
RAW_FIELD_NAME_PATTERN = re.compile(r'^[a-z][a-zA-Z0-9]*[A-Z][a-zA-Z0-9]*$')  # camelCase

def fetch_json(path):
    """Fetch JSON from Moqui API."""
    cmd = ["curl", "-s", "-b", COOKIE, f"{BASE}{path}"]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    try:
        return json.loads(result.stdout)
    except (json.JSONDecodeError, ValueError):
        return None

class ScreenCrawler:
    def __init__(self):
        self.issues = []
        self.all_screens = {}
        self.all_widget_types = set()
        self.all_field_widget_types = set()
        self.total_widgets = 0
        self.crawled_paths = set()
        self.transition_dot_forms = []
        self.form_list_screens = []
        self.screens_with_errors = []
        self.subscreens_found = defaultdict(list)  # parent -> [child names]
        self.max_depth = 6

    def add_issue(self, screen_path, issue_type, severity, description, widget_path="", details=None):
        self.issues.append({
            "screen": screen_path,
            "type": issue_type,
            "severity": severity,
            "desc": description,
            "widget_path": widget_path,
            "details": details or {},
        })

    def crawl_screen(self, path, depth=0):
        """Fetch and analyze a screen at the given path."""
        if path in self.crawled_paths:
            return
        if depth > self.max_depth:
            return
        self.crawled_paths.add(path)

        fjson_path = f"/fapps/{path}.fjson"
        data = fetch_json(fjson_path)
        if data is None:
            self.add_issue(path, "fetch_error", "critical", f"Failed to fetch .fjson")
            self.screens_with_errors.append(path)
            return

        if isinstance(data, dict) and "errorCode" in data:
            err = str(data.get("errors", data.get("errorCode", "")))[:100]
            self.add_issue(path, "server_error", "critical", f"Server error: {err}")
            self.screens_with_errors.append(path)
            return

        self.all_screens[path] = data

        # Analyze widgets
        widgets = data.get("widgets", [])
        if isinstance(widgets, list):
            for i, widget in enumerate(widgets):
                self._analyze_widget(path, widget, f"widgets[{i}]", depth=0)

        # Discover and crawl subscreens
        self._discover_and_crawl_subscreens(path, data, depth)

    def _discover_and_crawl_subscreens(self, parent_path, data, depth):
        """Find subscreens from JSON and crawl them."""
        # Find all subscreens-panel nodes
        subscreen_names = set()
        self._collect_subscreens(data, subscreen_names)

        # Also get menuData subscreens
        menu_data = fetch_json(f"/menuData/fapps/{parent_path}")
        if menu_data and isinstance(menu_data, list):
            last = menu_data[-1] if menu_data else {}
            for sub in last.get("subscreens", []):
                name = sub.get("name", "")
                if name:
                    subscreen_names.add(name)

        self.subscreens_found[parent_path] = list(subscreen_names)

        for sub_name in subscreen_names:
            sub_path = f"{parent_path}/{sub_name}"
            self.crawl_screen(sub_path, depth + 1)

    def _collect_subscreens(self, obj, names):
        """Recursively find all subscreen names from subscreens-panel nodes."""
        if isinstance(obj, dict):
            if obj.get("_type") == "subscreens-panel":
                # NEW: subscreens are in obj["subscreens"], not obj["tabs"]
                for sub in obj.get("subscreens", []):
                    name = sub.get("name", "")
                    if name:
                        names.add(name)
                # Also check defaultItem
                default = obj.get("defaultItem", "")
                if default:
                    names.add(default)
            for v in obj.values():
                self._collect_subscreens(v, names)
        elif isinstance(obj, list):
            for item in obj:
                self._collect_subscreens(item, names)

    def _analyze_widget(self, screen_path, widget, widget_path, depth=0):
        """Recursively analyze a widget node for issues."""
        if not isinstance(widget, dict):
            return
        if depth > 20:
            return

        self.total_widgets += 1
        wtype = widget.get("_type", "")

        if wtype:
            self.all_widget_types.add(wtype)

        # 1. Unknown widget type
        if wtype and wtype not in HANDLED_TYPES:
            self.add_issue(screen_path, "unknown_type", "warning",
                          f"Unknown widget type '{wtype}'", widget_path, {"type": wtype})

        # 2. transition="." forms
        if wtype in ('form-single', 'form-list'):
            transition = widget.get("transition", "")
            if transition == ".":
                self.transition_dot_forms.append(screen_path)
                self.add_issue(screen_path, "transition_dot", "info",
                              f"Form uses transition='.' (handled by fix)", widget_path)

        # 3. Empty field-row-big/field-row
        if wtype in ('form-single', 'form-list'):
            self._check_form_layout(screen_path, widget, widget_path)

        # 4. Unresolved template expressions
        self._check_template_vars(screen_path, widget, widget_path)

        # 5. HTML tags leaking
        self._check_html_leaks(screen_path, widget, widget_path)

        # 6. Form-list analysis
        if wtype == 'form-list':
            self.form_list_screens.append(screen_path)
            self._check_form_list_links(screen_path, widget, widget_path)
            self._check_form_list_data(screen_path, widget, widget_path)

        # 7. Field title checks
        if wtype in ('form-single', 'form-list'):
            self._check_field_titles(screen_path, widget, widget_path)

        # 8. Empty section
        if wtype == 'section':
            sw = widget.get("widgets", [])
            if not sw:
                self.add_issue(screen_path, "empty_section", "info",
                              f"Section has no widgets", widget_path)

        # 9. subscreens-panel with no subscreens
        if wtype == 'subscreens-panel':
            subs = widget.get("subscreens", [])
            default = widget.get("defaultItem", "")
            if not subs and not default:
                self.add_issue(screen_path, "no_subscreens", "warning",
                              f"subscreens-panel has no subscreens defined", widget_path)

        # 10. container-dialog missing buttonText
        if wtype == 'container-dialog':
            btn = widget.get("buttonText", "") or widget.get("title", "")
            if not btn:
                self.add_issue(screen_path, "dialog_no_button", "warning",
                              f"container-dialog has no buttonText/title", widget_path)

        # 11. Link with no text
        if wtype == 'link':
            txt = widget.get("text", "")
            img = widget.get("image", "")
            icon = widget.get("icon", "")
            children = widget.get("children", [])
            has_child_label = any(c.get("_type") == "label" for c in children if isinstance(c, dict))
            if not txt and not img and not icon and not has_child_label:
                self.add_issue(screen_path, "empty_link", "warning",
                              f"Link has no text/image/icon", widget_path)

        # 12. Conditional label with unresolved text
        if wtype == 'label':
            condition = widget.get("condition", "")
            text = widget.get("text", "")
            resolved = widget.get("resolvedText", text)
            if condition and text and text == resolved and TEMPLATE_VAR_PATTERN.search(text):
                self.add_issue(screen_path, "conditional_unresolved", "warning",
                              f"Conditional label text unresolved: {text[:80]}", widget_path)

        # 13. Form with no fields
        if wtype in ('form-single', 'form-list'):
            fields = widget.get("fields", [])
            if not fields:
                fname = widget.get("formName", widget.get("name", "??"))
                self.add_issue(screen_path, "empty_form", "warning",
                              f"Form '{fname}' has no fields", widget_path)

        # 14. Dynamic-dialog with missing URL
        if wtype == 'dynamic-dialog':
            url = widget.get("url", "") or widget.get("transition", "")
            if not url:
                self.add_issue(screen_path, "dynamic_dialog_no_url", "warning",
                              f"dynamic-dialog has no url/transition", widget_path)

        # Recurse
        for key in ("children", "widgets", "body", "header", "footer",
                     "first", "second", "center", "left", "right",
                     "headerForm", "bodyWidgets"):
            child = widget.get(key)
            if isinstance(child, list):
                for i, c in enumerate(child):
                    self._analyze_widget(screen_path, c, f"{widget_path}.{key}[{i}]", depth + 1)
            elif isinstance(child, dict):
                self._analyze_widget(screen_path, child, f"{widget_path}.{key}", depth + 1)

        for col in widget.get("columns", []):
            if isinstance(col, dict):
                for i, c in enumerate(col.get("children", [])):
                    self._analyze_widget(screen_path, c, f"{widget_path}.col[{i}]", depth + 1)

        # Form field sub-widgets
        for field in widget.get("fields", []):
            if isinstance(field, dict):
                for fa_key in ("defaultField", "headerField", "conditionalField",
                               "firstRowField", "secondRowField", "lastRowField"):
                    fa = field.get(fa_key)
                    if isinstance(fa, dict):
                        fwt = fa.get("widgetType", "")
                        if fwt:
                            self.all_field_widget_types.add(fwt)
                        self._check_template_vars(screen_path, fa, f"{widget_path}.{fa_key}")
                        self._check_html_leaks(screen_path, fa, f"{widget_path}.{fa_key}")
                    elif isinstance(fa, list):
                        for i, item in enumerate(fa):
                            if isinstance(item, dict):
                                fwt = item.get("widgetType", "")
                                if fwt:
                                    self.all_field_widget_types.add(fwt)
                                self._check_template_vars(screen_path, item, f"{widget_path}.{fa_key}[{i}]")
                                self._check_html_leaks(screen_path, item, f"{widget_path}.{fa_key}[{i}]")

    def _check_form_layout(self, screen_path, form_widget, widget_path):
        layout = form_widget.get("fieldLayout", {})
        if isinstance(layout, dict):
            rows = layout.get("rows", [])
            if isinstance(rows, list):
                for i, row in enumerate(rows):
                    if isinstance(row, dict):
                        rtype = row.get("type", "")
                        refs = row.get("fieldRefs", [])
                        if rtype in ("field-row-big", "field-row") and not refs:
                            self.add_issue(screen_path, "empty_field_row", "info",
                                          f"Empty {rtype} in layout (handled by fix)", widget_path)

    def _check_template_vars(self, screen_path, widget, widget_path):
        for key in ("text", "title", "label", "buttonText", "condition", "url",
                     "tooltip", "placeholder", "headerTitle", "resolvedText"):
            val = widget.get(key, "")
            if isinstance(val, str) and TEMPLATE_VAR_PATTERN.search(val):
                # Skip 'condition' which is expected to have Groovy expressions
                if key == "condition":
                    continue
                self.add_issue(screen_path, "unresolved_template", "warning",
                              f"Unresolved template in '{key}': {val[:100]}", widget_path,
                              {"key": key, "value": val[:200]})

    def _check_html_leaks(self, screen_path, widget, widget_path):
        for key in ("text", "title", "label", "buttonText", "tooltip", "resolvedText"):
            val = widget.get(key, "")
            if isinstance(val, str) and HTML_TAG_PATTERN.search(val):
                self.add_issue(screen_path, "html_leak", "warning",
                              f"HTML tags in '{key}': {val[:100]}", widget_path,
                              {"key": key, "value": val[:200]})

    def _check_form_list_links(self, screen_path, form_widget, widget_path):
        fields = form_widget.get("fields", [])
        for field in fields:
            if not isinstance(field, dict):
                continue
            for fa_key in ("defaultField",):
                fa = field.get(fa_key, {})
                if isinstance(fa, dict) and fa.get("widgetType") == "link":
                    url = fa.get("url", "")
                    if not url:
                        self.add_issue(screen_path, "link_no_url", "warning",
                                      f"Link field '{field.get('name','')}' has no URL", widget_path)

    def _check_form_list_data(self, screen_path, form_widget, widget_path):
        """Check form-list for data quality issues."""
        list_data = form_widget.get("listData", [])
        fields = form_widget.get("fields", [])
        form_name = form_widget.get("formName", form_widget.get("name", ""))

        # Check for duplicate display values (e.g., both 'field' and 'field_display' in data row)
        if list_data and isinstance(list_data, list) and len(list_data) > 0:
            row = list_data[0]
            if isinstance(row, dict):
                for field in fields:
                    if not isinstance(field, dict):
                        continue
                    fname = field.get("name", "")
                    if fname:
                        val = row.get(fname, "")
                        disp = row.get(f"{fname}_display", "")
                        if val and disp and str(val) == str(disp):
                            # This can cause duplicate display if both are rendered
                            pass  # This is expected for simple values, only flag if different patterns
                        # Check for the actual duplicated rendering pattern detected in Playwright
                        # where "EX_JOHN_DOE EX_JOHN_DOE" appears

    def _check_field_titles(self, screen_path, form_widget, widget_path):
        fields = form_widget.get("fields", [])
        for field in fields:
            if not isinstance(field, dict):
                continue
            name = field.get("name", "")
            title = field.get("title", "")
            if not title and name and RAW_FIELD_NAME_PATTERN.match(name):
                self.add_issue(screen_path, "raw_field_name", "info",
                              f"Field '{name}' has no title (camelCase name)", widget_path)

    def report(self):
        """Generate the analysis report."""
        print("=" * 80)
        print("MOQUI FLUTTER SCREEN ANALYSIS REPORT v2")
        print("=" * 80)

        print(f"\nScreens crawled: {len(self.all_screens)}")
        print(f"Screens with errors: {len(self.screens_with_errors)}")
        print(f"Paths attempted: {len(self.crawled_paths)}")
        print(f"Total widgets analyzed: {self.total_widgets}")
        print(f"Total issues found: {len(self.issues)}")

        by_severity = defaultdict(list)
        for issue in self.issues:
            by_severity[issue["severity"]].append(issue)

        print(f"\n  Critical: {len(by_severity['critical'])}")
        print(f"  Warning:  {len(by_severity['warning'])}")
        print(f"  Info:     {len(by_severity['info'])}")

        by_type = defaultdict(list)
        for issue in self.issues:
            by_type[issue["type"]].append(issue)

        print(f"\nIssues by type:")
        for itype in sorted(by_type.keys()):
            print(f"  {itype}: {len(by_type[itype])}")

        print(f"\nWidget types found ({len(self.all_widget_types)}):")
        for t in sorted(self.all_widget_types):
            handled = "OK" if t in HANDLED_TYPES else "NOT HANDLED"
            print(f"  {t} [{handled}]")

        if self.all_field_widget_types:
            print(f"\nField widget types found ({len(self.all_field_widget_types)}):")
            for t in sorted(self.all_field_widget_types):
                print(f"  {t}")

        if self.transition_dot_forms:
            print(f"\nForms using transition='.' ({len(set(self.transition_dot_forms))}):")
            for p in sorted(set(self.transition_dot_forms)):
                print(f"  {p}")

        if self.form_list_screens:
            print(f"\nScreens with form-list ({len(set(self.form_list_screens))}):")
            for p in sorted(set(self.form_list_screens)):
                print(f"  {p}")

        # Subscreen tree
        print(f"\nSubscreen tree:")
        self._print_tree("marble", depth=0)

        print(f"\n{'=' * 80}")
        print("DETAILED ISSUES (excluding info)")
        print("=" * 80)

        by_screen = defaultdict(list)
        for issue in self.issues:
            by_screen[issue["screen"]].append(issue)

        for sp in sorted(by_screen.keys()):
            issues = [i for i in by_screen[sp] if i["severity"] != "info"]
            if not issues:
                continue
            print(f"\n--- {sp} ({len(issues)} issues) ---")
            for issue in sorted(issues, key=lambda i: {"critical": 0, "warning": 1, "info": 2}[i["severity"]]):
                d = ""
                if issue["details"]:
                    d = f" | {json.dumps(issue['details'])[:80]}"
                print(f"  [{issue['severity'].upper()}] {issue['type']}: {issue['desc']}{d}")

        # All issues (including info) to a separate section
        print(f"\n{'=' * 80}")
        print("ALL ISSUES (INCLUDING INFO)")
        print("=" * 80)

        for sp in sorted(by_screen.keys()):
            issues = by_screen[sp]
            print(f"\n--- {sp} ({len(issues)} issues) ---")
            for issue in sorted(issues, key=lambda i: {"critical": 0, "warning": 1, "info": 2}[i["severity"]]):
                print(f"  [{issue['severity'].upper()}] {issue['type']}: {issue['desc']}")

        # Error screens
        if self.screens_with_errors:
            print(f"\nScreens that FAILED ({len(self.screens_with_errors)}):")
            for sp in sorted(self.screens_with_errors):
                print(f"  {sp}")

        clean = [p for p in self.all_screens if p not in by_screen]
        if clean:
            print(f"\nClean screens ({len(clean)}):")
            for p in sorted(clean):
                print(f"  {p}")

        print(f"\n{'=' * 80}")
        print("END OF REPORT")
        print("=" * 80)

    def _print_tree(self, path, depth=0):
        indent = "  " * depth
        subs = self.subscreens_found.get(path, [])
        status = "OK" if path in self.all_screens else "ERR" if path in self.screens_with_errors else "?"
        n_issues = sum(1 for i in self.issues if i["screen"] == path and i["severity"] != "info")
        issue_str = f" ({n_issues} issues)" if n_issues else ""
        print(f"{indent}{path} [{status}]{issue_str}")
        for sub in sorted(subs):
            sub_path = f"{path}/{sub}"
            self._print_tree(sub_path, depth + 1)


def main():
    crawler = ScreenCrawler()

    # Start with marble root
    print("Starting deep screen crawl...")
    crawler.crawl_screen("marble")

    print(f"\nCrawl complete. {len(crawler.all_screens)} screens fetched, {len(crawler.crawled_paths)} paths attempted.")
    print()

    crawler.report()

    # Also write JSON report
    report_data = {
        "screens_crawled": len(crawler.all_screens),
        "screens_with_errors": crawler.screens_with_errors,
        "total_widgets": crawler.total_widgets,
        "total_issues": len(crawler.issues),
        "widget_types": sorted(crawler.all_widget_types),
        "field_widget_types": sorted(crawler.all_field_widget_types),
        "issues": crawler.issues,
        "subscreen_tree": dict(crawler.subscreens_found),
    }
    with open("/tmp/screen_analysis_report.json", "w") as f:
        json.dump(report_data, f, indent=2)
    print(f"\nJSON report written to /tmp/screen_analysis_report.json")


if __name__ == "__main__":
    main()
