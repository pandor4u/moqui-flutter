package org.moqui.flutter

import groovy.transform.CompileStatic
import org.moqui.impl.screen.ScreenWidgetRender
import org.moqui.impl.screen.ScreenWidgets
import org.moqui.impl.screen.ScreenRenderImpl
import org.moqui.impl.screen.ScreenForm
import org.moqui.impl.screen.ScreenDefinition
import org.moqui.impl.screen.ScreenSection
import org.moqui.impl.screen.ScreenUrlInfo
import org.moqui.impl.context.ExecutionContextImpl
import org.moqui.entity.EntityFind
import org.moqui.entity.EntityList
import org.moqui.entity.EntityValue
import org.moqui.entity.EntityCondition
import org.moqui.util.MNode
import org.moqui.util.StringUtilities
import com.fasterxml.jackson.databind.ObjectMapper

/**
 * ScreenWidgetRender implementation that outputs JSON for Flutter dynamic screen rendering.
 *
 * Walks the same MNode widget tree that FTL macros consume, but emits a JSON object tree
 * describing widget types, attributes, field definitions, values, and options. The Flutter
 * app deserializes this JSON and builds native widgets dynamically.
 */
@CompileStatic
class ScreenWidgetRenderJson implements ScreenWidgetRender {

    private static final ObjectMapper mapper = new ObjectMapper()

    // Widget types that are standalone field widgets (inside form sub-fields)
    private static final Set<String> FIELD_WIDGET_TYPES = [
        'text-line', 'text-area', 'text-find', 'drop-down', 'date-time', 'date-find',
        'date-period', 'display', 'display-entity', 'hidden', 'ignored', 'check', 'radio',
        'file', 'password', 'range-find', 'submit', 'reset', 'link', 'label', 'image',
        'auto-widget-service', 'auto-widget-entity', 'widget-template-include',
        'container', 'dynamic-dialog', 'editable'
    ] as Set<String>

    // Attributes to always capture from any widget node
    private static final Set<String> COMMON_ATTRS = [
        'id', 'style', 'condition', 'type', 'name', 'title', 'tooltip'
    ] as Set<String>

    ScreenWidgetRenderJson() { }

    @Override
    void render(ScreenWidgets widgets, ScreenRenderImpl sri) {
        MNode widgetsNode = widgets.getWidgetsNode()
        ExecutionContextImpl ec = sri.ec

        // Prevent browser caching of dynamic JSON screen data
        if (ec.web != null) {
            javax.servlet.http.HttpServletResponse response = ec.web.getResponse()
            if (response != null) {
                response.setHeader("Cache-Control", "no-cache, no-store, must-revalidate, private")
                response.setHeader("Pragma", "no-cache")
                response.setDateHeader("Expires", 0)
            }
        }

        Map<String, Object> screenJson = [:]
        screenJson.put('_type', 'screen')
        screenJson.put('renderMode', 'fjson')

        // Screen-level metadata
        ScreenDefinition screenDef = sri.getActiveScreenDef()
        if (screenDef != null) {
            screenJson.put('screenName', screenDef.getScreenName() ?: '')
            MNode screenNode = screenDef.getScreenNode()
            if (screenNode != null) {
                String menuTitle = screenNode.attribute('default-menu-title')
                if (menuTitle) screenJson.put('menuTitle', menuTitle)
            }
        }

        // Build widget tree
        List<Map<String, Object>> children = renderChildren(widgetsNode, sri)
        screenJson.put('widgets', children)

        // Write JSON output
        String jsonStr = mapper.writeValueAsString(screenJson)
        sri.writer.write(jsonStr)
    }

    // --- Widget Tree Rendering ---

    private List<Map<String, Object>> renderChildren(MNode parentNode, ScreenRenderImpl sri) {
        List<Map<String, Object>> childList = []
        if (parentNode == null) return childList

        ArrayList<MNode> children = parentNode.getChildren()
        for (MNode childNode : children) {
            Map<String, Object> childJson = renderWidgetNode(childNode, sri)
            if (childJson != null) childList.add(childJson)
        }
        return childList
    }

    private Map<String, Object> renderWidgetNode(MNode node, ScreenRenderImpl sri) {
        String nodeName = node.getName()
        if (nodeName == null) return null

        switch (nodeName) {
            case 'form-single': return renderFormSingle(node, sri)
            case 'form-list': return renderFormList(node, sri)
            case 'section': return renderSection(node, sri)
            case 'section-iterate': return renderSectionIterate(node, sri)
            case 'section-include': return renderSectionInclude(node, sri)
            case 'container': return renderContainer(node, sri)
            case 'container-box': return renderContainerBox(node, sri)
            case 'container-row': return renderContainerRow(node, sri)
            case 'container-panel': return renderContainerPanel(node, sri)
            case 'container-dialog': return renderContainerDialog(node, sri)
            case 'subscreens-panel': return renderSubscreensPanel(node, sri)
            case 'subscreens-menu': return renderSubscreensMenu(node, sri)
            case 'subscreens-active': return renderSubscreensActive(node, sri)
            case 'link': return renderLink(node, sri)
            case 'label': return renderLabel(node, sri)
            case 'image': return renderImage(node, sri)
            case 'dynamic-dialog': return renderDynamicDialog(node, sri)
            case 'dynamic-container': return renderDynamicContainer(node, sri)
            case 'button-menu': return renderButtonMenu(node, sri)
            case 'tree': return renderTree(node, sri)
            case 'render-mode': return renderRenderMode(node, sri)
            case 'include-screen': return renderIncludeScreen(node, sri)
            case 'text': return renderText(node, sri)
            default:
                // For any unknown widgets, produce a generic node
                return renderGenericNode(node, sri)
        }
    }

    // --- Form Single ---

    private Map<String, Object> renderFormSingle(MNode formNode, ScreenRenderImpl sri) {
        Map<String, Object> json = baseAttrs(formNode)
        json.put('_type', 'form-single')
        String formName = formNode.attribute('name') ?: ''
        json.put('formName', formName)
        json.put('transition', formNode.attribute('transition') ?: '')
        json.put('map', formNode.attribute('map') ?: 'fieldValues')

        // Resolve the fully-merged form node so that extends="" chains are honoured and the
        // extended form's field list is included in the JSON output.
        // sd.getForm() throws if the form is not found (like getSection) so wrap in try-catch.
        MNode mergedFormNode = formNode
        if (formName) {
            try {
                ScreenDefinition screenDef = sri.getActiveScreenDef()
                if (screenDef != null) {
                    ScreenForm screenForm = screenDef.getForm(formName)
                    if (screenForm != null) {
                        MNode resolved = screenForm.getOrCreateFormNode()
                        if (resolved != null) mergedFormNode = resolved
                    }
                }
            } catch (Exception e) { /* fallback to raw formNode */ }
        }

        // Get field layout if defined
        MNode fieldLayout = mergedFormNode.first('field-layout') ?: formNode.first('field-layout')
        if (fieldLayout != null) {
            json.put('fieldLayout', renderFieldLayout(fieldLayout, sri))
        }

        // Process fields from merged node (includes extended form fields)
        List<Map<String, Object>> fields = []
        ArrayList<MNode> fieldNodes = mergedFormNode.children('field')
        for (MNode fieldNode : fieldNodes) {
            Map<String, Object> fieldJson = renderFormField(fieldNode, mergedFormNode, sri, false)
            if (fieldJson != null) fields.add(fieldJson)
        }
        json.put('fields', fields)

        return json
    }

    // --- Form List ---

    private Map<String, Object> renderFormList(MNode formNode, ScreenRenderImpl sri) {
        Map<String, Object> json = baseAttrs(formNode)
        json.put('_type', 'form-list')
        json.put('formName', formNode.attribute('name') ?: '')
        json.put('transition', formNode.attribute('transition') ?: '')
        json.put('list', formNode.attribute('list') ?: '')
        json.put('paginate', formNode.attribute('paginate') ?: 'true')
        json.put('headerDialog', formNode.attribute('header-dialog') ?: '')
        json.put('selectColumns', formNode.attribute('select-columns') ?: '')
        json.put('savedFinds', formNode.attribute('saved-finds') ?: '')
        json.put('showCsvButton', formNode.attribute('show-csv-button') ?: '')
        json.put('showXlsxButton', formNode.attribute('show-xlsx-button') ?: '')
        json.put('showPageSize', formNode.attribute('show-page-size') ?: '')
        json.put('skipForm', formNode.attribute('skip-form') ?: '')

        // Phase 6.1: Detect edit URL from link widgets in field definitions
        // Scan fields for the first link widget that navigates to an edit screen
        try {
            for (MNode fn : formNode.children('field')) {
                MNode df = fn.first('default-field')
                if (df == null) continue
                for (MNode wn : df.getChildren()) {
                    if ('link' == wn.getName()) {
                        String linkUrl = wn.attribute('url') ?: ''
                        String linkUrlType = wn.attribute('url-type') ?: ''
                        if (linkUrl && linkUrlType != 'plain' && linkUrlType != 'content') {
                            json.put('editUrl', linkUrl)
                            break
                        }
                    }
                }
                if (json.containsKey('editUrl')) break
            }
        } catch (Exception e) { /* continue without editUrl */ }

        // Column layout
        MNode columnsNode = formNode.first('columns')
        if (columnsNode != null) {
            List<Map<String, Object>> columns = []
            for (MNode colNode : columnsNode.children('column')) {
                Map<String, Object> col = [:]
                col.put('style', colNode.attribute('style') ?: '')
                List<String> fieldRefs = []
                for (MNode fieldRef : colNode.children('field-ref')) {
                    fieldRefs.add(fieldRef.attribute('name') ?: '')
                }
                col.put('fieldRefs', fieldRefs)
                columns.add(col)
            }
            json.put('columns', columns)
        }

        // Header fields (for search/filter)
        List<Map<String, Object>> headerFields = []
        // Data row fields
        List<Map<String, Object>> fields = []
        ArrayList<MNode> fieldNodes = formNode.children('field')
        for (MNode fieldNode : fieldNodes) {
            // Header field
            MNode headerField = fieldNode.first('header-field')
            if (headerField != null && !headerField.getChildren().isEmpty()) {
                Map<String, Object> hf = renderFormField(fieldNode, formNode, sri, true)
                if (hf != null) headerFields.add(hf)
            }
            // Data row field
            Map<String, Object> fieldJson = renderFormField(fieldNode, formNode, sri, false)
            if (fieldJson != null) fields.add(fieldJson)
        }
        json.put('headerFields', headerFields)
        json.put('fields', fields)

        // List data — use ScreenForm's proper data resolution pipeline
        // This handles entity-find, pagination, row-actions, field value resolution, and aggregation
        String listName = formNode.attribute('list') ?: ''
        String formName = formNode.attribute('name') ?: ''
        try {
            ScreenDefinition screenDef = sri.getActiveScreenDef()
            if (screenDef != null && formName) {
                ScreenForm screenForm = screenDef.getForm(formName)
                ScreenForm.FormInstance formInstance = screenForm.getFormInstance()
                ScreenForm.FormListRenderInfo renderInfo = formInstance.makeFormListRenderInfo()

                // Get raw rows first (runs entity-find, pagination, row-actions).
                // rawRows contains ALL original fields from the source list (e.g. fullEntityName, package, entityName)
                // even though only displayed fields end up in the display-formatted rows.
                ArrayList<Map<String, Object>> rawRows = renderInfo.getListObject(true)
                // Transform raw rows to display-formatted rows (fieldName_display entries)
                ArrayList<Map<String, Object>> rowValues = sri.transformFormListRowList(renderInfo, rawRows)
                // Collect field names referenced in parameter-map attributes of field widgets
                // (e.g., parameter-map="[selectedEntity:fullEntityName]" → "fullEntityName")
                Set<String> paramRefFields = collectParamMapFieldRefs(formNode)
                // Augment display rows with raw values for parameter-map referenced fields
                // so the client can resolve row-specific link parameters
                if (paramRefFields && rawRows.size() == rowValues.size()) {
                    for (int i = 0; i < rowValues.size(); i++) {
                        Map<String, Object> displayRow = rowValues.get(i)
                        Map<String, Object> rawRow = rawRows.get(i)
                        for (String refField : paramRefFields) {
                            if (!displayRow.containsKey(refField) && !displayRow.containsKey("${refField}_display")) {
                                Object rawVal = rawRow?.get(refField)
                                if (rawVal != null) displayRow.put(refField, rawVal.toString())
                            }
                        }
                    }
                }

                // Per-row resolution for link text expressions and link parameters
                // This handles fields like: <link text="${ec.entity.getEntityDefinition(entityName).getPrettyName(null, null)}">
                //                             <parameter name="aen" from="fullEntityName"/>
                // where the text and parameter values depend on each row's data
                if (rawRows.size() == rowValues.size()) {
                    ArrayList<MNode> fieldNodes2 = formNode.children('field')
                    for (MNode fieldNode2 : fieldNodes2) {
                        String fieldName2 = fieldNode2.attribute('name')
                        MNode subField = fieldNode2.first('default-field')
                        if (subField == null) continue
                        for (MNode widgetNode2 : subField.getChildren()) {
                            if (widgetNode2.getName() != 'link') continue
                            String linkText = widgetNode2.attribute('text') ?: ''
                            boolean hasExpression = linkText.contains('${')
                            // Collect <parameter> children for per-row resolution
                            ArrayList<MNode> paramNodes = widgetNode2.children('parameter')
                            if (!hasExpression && paramNodes.isEmpty()) continue
                            for (int i = 0; i < rawRows.size(); i++) {
                                Map<String, Object> rawRow = rawRows.get(i)
                                Map<String, Object> displayRow = rowValues.get(i)
                                // Push raw row data into context for expression resolution
                                sri.ec.context.push(rawRow)
                                try {
                                    // Resolve link text expression per-row
                                    if (hasExpression) {
                                        try {
                                            String resolved = sri.ec.resourceFacade.expand(linkText, '')
                                            displayRow.put(fieldName2 + '_linkText', resolved)
                                        } catch (Exception ex) {
                                            displayRow.put(fieldName2 + '_linkText', linkText)
                                        }
                                    }
                                    // Resolve <parameter> values per-row
                                    for (MNode paramNode : paramNodes) {
                                        String paramName = paramNode.attribute('name') ?: ''
                                        String fromAttr = paramNode.attribute('from') ?: paramName
                                        if (paramName) {
                                            Object paramVal = sri.ec.context.getByString(fromAttr)
                                            if (paramVal != null) {
                                                displayRow.put(fieldName2 + '_param_' + paramName, paramVal.toString())
                                            }
                                        }
                                    }
                                } finally {
                                    sri.ec.context.pop()
                                }
                            }
                        }
                    }
                }

                json.put('listData', rowValues)

                // Pagination info — Moqui uses CamelCase naming: ${listName}PageIndex, ${listName}Count, etc.
                Map<String, Object> paginateInfo = [:]
                Object pageIndex = sri.ec.context.getByString("${listName}PageIndex")
                Object pageSize = sri.ec.context.getByString("${listName}PageSize")
                Object count = sri.ec.context.getByString("${listName}Count")
                Object pageMaxIndex = sri.ec.context.getByString("${listName}PageMaxIndex")
                Object pageRangeLow = sri.ec.context.getByString("${listName}PageRangeLow")
                Object pageRangeHigh = sri.ec.context.getByString("${listName}PageRangeHigh")
                if (pageIndex != null) paginateInfo.put('pageIndex', pageIndex)
                if (pageSize != null) paginateInfo.put('pageSize', pageSize)
                if (count != null) paginateInfo.put('count', count)
                if (pageMaxIndex != null) paginateInfo.put('pageMaxIndex', pageMaxIndex)
                if (pageRangeLow != null) paginateInfo.put('pageRangeLow', pageRangeLow)
                if (pageRangeHigh != null) paginateInfo.put('pageRangeHigh', pageRangeHigh)
                if (!paginateInfo.isEmpty()) json.put('paginateInfo', paginateInfo)
            }
        } catch (Exception e) {
            // Fallback: resolve the raw list from context if FormListRenderInfo fails
            if (listName) {
                Object listObj = sri.ec.context.getByString(listName)
                if (listObj instanceof List) {
                    List<Map<String, Object>> listData = []
                    for (Object rowObj : (List) listObj) {
                        Map<String, Object> row = [:]
                        if (rowObj instanceof Map) {
                            for (Map.Entry entry : ((Map) rowObj).entrySet()) {
                                row.put(entry.key?.toString() ?: '', entry.value)
                            }
                        } else if (rowObj instanceof CharSequence) {
                            // Handle lists of Strings (e.g. service name lists)
                            // Use the list name without trailing 's' or the list entry variable name
                            String entryName = listName.endsWith('s') ? listName.substring(0, listName.length() - 1) : listName + 'Entry'
                            row.put(entryName, rowObj.toString())
                        } else if (rowObj != null) {
                            row.put('value', rowObj.toString())
                        }
                        listData.add(row)
                    }
                    json.put('listData', listData)
                }
            }
        }

        // Row selection support
        MNode rowSelection = formNode.first('row-selection')
        if (rowSelection != null) {
            json.put('rowSelection', baseAttrs(rowSelection))
        }

        // ── Saved Finds: query ScreenFindSaved for current form/user ──
        String savedFindsAttr = formNode.attribute('saved-finds')
        if (savedFindsAttr == 'true') {
            try {
                ExecutionContextImpl ec = sri.ec
                String userId = ec.user?.userId ?: ''
                String screenLocation = sri.getActiveScreenDef()?.getLocation() ?: ''
                if (userId && formName) {
                    def savedFindList = ec.entity.find('moqui.screen.ScreenFindSaved')
                        .condition('userId', userId)
                        .condition('formLocation', screenLocation + '#' + formName)
                        .orderBy('description')
                        .list()
                    List<Map<String, Object>> findsList = []
                    for (def sf : savedFindList) {
                        Map<String, Object> findMap = [:]
                        findMap.put('id', sf.get('screenFindSavedId')?.toString() ?: '')
                        findMap.put('description', sf.get('description')?.toString() ?: '')
                        // Parse savedData map — Moqui stores it as a Groovy map literal string
                        String savedData = sf.get('savedData')?.toString() ?: ''
                        if (savedData) {
                            try {
                                Object parsed = new groovy.json.JsonSlurper().parseText(savedData)
                                if (parsed instanceof Map) findMap.put('filterParams', parsed)
                            } catch (Exception pe) {
                                // savedData may be Groovy map syntax — store as raw string
                                findMap.put('filterParamsRaw', savedData)
                            }
                        }
                        findsList.add(findMap)
                    }
                    if (!findsList.isEmpty()) json.put('formSavedFindsList', findsList)
                }
            } catch (Exception e) { /* saved finds not available, continue */ }
        }

        // ── Select Columns: query ScreenFormListColumn for user preferences ──
        String selectColumnsAttr = formNode.attribute('select-columns')
        if (selectColumnsAttr == 'true') {
            try {
                ExecutionContextImpl ec = sri.ec
                String userId = ec.user?.userId ?: ''
                String screenLocation = sri.getActiveScreenDef()?.getLocation() ?: ''
                if (userId && formName) {
                    // Build allColumns from field definitions
                    List<Map<String, Object>> allCols = []
                    ArrayList<MNode> allFieldNodes = formNode.children('field')
                    int colOrder = 0
                    for (MNode fn : allFieldNodes) {
                        String fName = fn.attribute('name') ?: ''
                        String fHide = fn.attribute('hide') ?: ''
                        // Resolve title: prefer header-field (canonical column header), then default-field / conditional-field
                        MNode hfNode = fn.first('header-field')
                        MNode sub = fn.first('default-field') ?: fn.first('conditional-field')
                        String fTitle = hfNode?.attribute('title') ?: sub?.attribute('title') ?: StringUtilities.camelCaseToPretty(fName)
                        Map<String, Object> colEntry = new LinkedHashMap<>()
                        colEntry.put('name', (Object) fName)
                        colEntry.put('title', (Object) fTitle)
                        colEntry.put('order', (Object) colOrder)
                        colEntry.put('hide', (Object) fHide)
                        allCols.add(colEntry)
                        colOrder++
                    }

                    // Overlay user column preferences
                    def userCols = ec.entity.find('moqui.screen.ScreenFormListColumn')
                        .condition('userId', userId)
                        .condition('formLocation', screenLocation + '#' + formName)
                        .orderBy('columnOrder')
                        .list()
                    if (userCols && !userCols.isEmpty()) {
                        Set<String> visibleNames = new LinkedHashSet<>()
                        for (def uc : userCols) {
                            visibleNames.add(uc.get('fieldName')?.toString() ?: '')
                        }
                        for (Map<String, Object> col : allCols) {
                            col.put('visible', visibleNames.contains(col.get('name')))
                        }
                    } else {
                        // No user preference — all visible by default (except hidden fields)
                        for (Map<String, Object> col : allCols) {
                            col.put('visible', col.get('hide')?.toString() != 'true')
                        }
                    }
                    json.put('allColumns', allCols)
                }
            } catch (Exception e) { /* select columns not available, continue */ }
        }

        // ── Export base URL: construct from current screen URL ──
        if (formNode.attribute('show-csv-button') == 'true' ||
            formNode.attribute('show-xlsx-button') == 'true') {
            try {
                String screenPath = sri.getScreenUrlInfo()?.getFullPathNameList()?.join('/') ?: ''
                if (screenPath) json.put('exportBaseUrl', '/' + screenPath)
            } catch (Exception e) { /* continue without exportBaseUrl */ }
        }

        return json
    }

    /**
     * Collect all bare variable names referenced as values in parameter-map attributes of form field widgets.
     * For example, parameter-map="[selectedEntity:fullEntityName]" contributes "fullEntityName".
     * Quoted string literals like parameter-map="[key:'value']" are excluded.
     */
    private static Set<String> collectParamMapFieldRefs(MNode formNode) {
        Set<String> refs = new LinkedHashSet<>()
        for (MNode fieldNode : formNode.children('field')) {
            for (String subFieldName : ['default-field', 'header-field', 'conditional-field']) {
                MNode sub = fieldNode.first(subFieldName)
                if (sub == null) continue
                for (MNode widgetNode : sub.getChildren()) {
                    String paramMapAttr = widgetNode.attribute('parameter-map')
                    if (paramMapAttr) {
                        // Match key:value pairs where value is a bare identifier (not quoted)
                        // e.g. [selectedEntity:fullEntityName, aen:otherField]
                        def matcher = paramMapAttr =~ /\w+\s*:\s*([a-zA-Z_]\w*)/
                        while (matcher.find()) {
                            refs.add(matcher.group(1))
                        }
                    }
                }
            }
        }
        return refs
    }

    // --- Form Field Processing ---

    private Map<String, Object> renderFormField(MNode fieldNode, MNode formNode, ScreenRenderImpl sri, boolean headerMode) {
        String fieldName = fieldNode.attribute('name')
        if (!fieldName) return null

        Map<String, Object> json = [:]
        json.put('name', fieldName)
        json.put('from', fieldNode.attribute('from') ?: '')
        json.put('hide', fieldNode.attribute('hide') ?: '')
        json.put('align', fieldNode.attribute('align') ?: '')

        // Determine the active sub-field node
        MNode subFieldNode
        if (headerMode) {
            subFieldNode = fieldNode.first('header-field')
        } else {
            // Try conditional-field first
            ArrayList<MNode> condFields = fieldNode.children('conditional-field')

            // Phase 4.8: For form-list fields, emit all conditional-field variants
            // with their condition and condition field name so the client can resolve
            // per-row when row data varies
            if ('form-list' == formNode?.getName() && !condFields.isEmpty()) {
                List<Map<String, Object>> conditionalFieldsList = []
                for (MNode condField : condFields) {
                    String condition = condField.attribute('condition') ?: ''
                    Map<String, Object> cfJson = new LinkedHashMap<>()
                    cfJson.put('condition', (Object) condition)

                    // Evaluate condition in current context (form-level)
                    boolean condResult = false
                    if (condition) {
                        try {
                            condResult = sri.ec.resourceFacade.condition(condition, null)
                        } catch (Exception e) { /* condition eval failed */ }
                    }
                    cfJson.put('conditionResult', (Object) condResult)
                    cfJson.put('title', (Object) (condField.attribute('title') ?: ''))

                    List<Map<String, Object>> cfWidgets = []
                    for (MNode wn : condField.getChildren()) {
                        Map<String, Object> wj = renderFieldWidget(wn, fieldNode, sri)
                        if (wj != null) cfWidgets.add(wj)
                    }
                    cfJson.put('widgets', (Object) cfWidgets)
                    conditionalFieldsList.add(cfJson)
                }
                if (!conditionalFieldsList.isEmpty()) {
                    json.put('conditionalFields', conditionalFieldsList)
                }
            }

            for (MNode condField : condFields) {
                String condition = condField.attribute('condition')
                if (condition) {
                    try {
                        boolean result = sri.ec.resourceFacade.condition(condition, null)
                        if (result) { subFieldNode = condField; break }
                    } catch (Exception e) {
                        // If condition eval fails, skip this conditional field
                    }
                }
            }
            if (subFieldNode == null) subFieldNode = fieldNode.first('default-field')
        }

        if (subFieldNode == null) return null

        // Sub-field attributes
        // For form-list body fields the human-readable column title typically lives
        // on <header-field title="..."> while <default-field> often has no title.
        // Check header-field first, then the active sub-field, then fall back to fieldName.
        String fieldTitle = subFieldNode.attribute('title')
        if (!fieldTitle && !headerMode) {
            MNode hf = fieldNode.first('header-field')
            if (hf != null) fieldTitle = hf.attribute('title')
        }
        json.put('title', fieldTitle ?: StringUtilities.camelCaseToPretty(fieldName))
        json.put('tooltip', subFieldNode.attribute('tooltip') ?: '')

        // Process all widget children of the sub-field.
        // First pass: execute <set> elements so context variables (e.g. enumTypeId)
        // are available when sibling <drop-down> entity-options queries run.
        // This mirrors ScreenRenderImpl lines 1792-1800.
        List<Map<String, Object>> widgets = []
        ArrayList<MNode> widgetChildren = subFieldNode.getChildren()
        ArrayList<MNode> setNodeList = new ArrayList<>()
        for (MNode widgetNode : widgetChildren) {
            if ('set' == widgetNode.getName()) setNodeList.add(widgetNode)
        }
        if (setNodeList.size() > 0) {
            sri.ec.contextStack.push()
            for (MNode setNode : setNodeList) {
                sri.setInContext(setNode)
            }
        }
        // Second pass: render all widget children (drop-down options now have context)
        try {
            for (MNode widgetNode : widgetChildren) {
                if ('set' == widgetNode.getName()) continue  // already handled above
                Map<String, Object> widgetJson = renderFieldWidget(widgetNode, fieldNode, sri)
                if (widgetJson != null) widgets.add(widgetJson)
            }
        } finally {
            if (setNodeList.size() > 0) {
                sri.ec.contextStack.pop()
            }
        }
        json.put('widgets', widgets)

        // Multi-row field support: first-row-field, second-row-field, last-row-field
        // These allow a single column to display multiple rows of widgets stacked vertically
        if (!headerMode) {
            List<Map<String, Object>> rowFields = []
            for (String rowType : ['first-row-field', 'second-row-field', 'last-row-field']) {
                MNode rowFieldNode = fieldNode.first(rowType)
                if (rowFieldNode != null) {
                    Map<String, Object> rf = [:]
                    rf.put('rowType', rowType)
                    rf.put('title', rowFieldNode.attribute('title') ?: '')
                    List<Map<String, Object>> rfWidgets = []
                    for (MNode rwn : rowFieldNode.getChildren()) {
                        Map<String, Object> wj = renderFieldWidget(rwn, fieldNode, sri)
                        if (wj != null) rfWidgets.add(wj)
                    }
                    rf.put('widgets', rfWidgets)
                    if (!rfWidgets.isEmpty()) rowFields.add(rf)
                }
            }
            if (!rowFields.isEmpty()) json.put('rowFields', rowFields)
        }

        // Get field value for form-single (resolved server-side)
        if ('form-single' == formNode.getName()) {
            try {
                Object value = sri.getFieldValue(fieldNode, '')
                if (value != null) json.put('currentValue', value.toString())
            } catch (Exception e) {
                // Value resolution may fail for some fields
            }
        }

        return json
    }

    private Map<String, Object> renderFieldWidget(MNode widgetNode, MNode fieldNode, ScreenRenderImpl sri) {
        String widgetType = widgetNode.getName()
        if (widgetType == null) return null

        Map<String, Object> json = [:]
        json.put('_type', widgetType)

        // Capture all attributes from the widget node
        Map<String, String> attrs = widgetNode.getAttributes()
        for (Map.Entry<String, String> entry : attrs.entrySet()) {
            json.put(entry.getKey(), entry.getValue())
        }

        // Widget-type-specific processing
        switch (widgetType) {
            case 'text-line':
                json.put('inputType', widgetNode.attribute('input-type') ?: 'text')
                json.put('size', widgetNode.attribute('size') ?: '')
                json.put('maxlength', widgetNode.attribute('maxlength') ?: '')
                json.put('mask', widgetNode.attribute('mask') ?: '')
                json.put('prefix', widgetNode.attribute('prefix') ?: '')
                // Autocomplete configuration
                String acTransition = widgetNode.attribute('ac-transition')
                if (acTransition) {
                    json.put('autocomplete', [
                        transition: acTransition,
                        delay: widgetNode.attribute('ac-delay') ?: '300',
                        minLength: widgetNode.attribute('ac-min-length') ?: '1',
                        showValue: widgetNode.attribute('ac-show-value') ?: 'false',
                        useActual: widgetNode.attribute('ac-use-actual') ?: 'false'
                    ])
                }
                // Default-transition (AJAX default value) — Phase 4.3
                MNode defaultTransition = widgetNode.first('default-transition')
                if (defaultTransition != null) {
                    Map<String, Object> dtJson = [:]
                    dtJson.put('transition', defaultTransition.attribute('transition') ?: '')
                    // Parameter map for the default-transition request
                    List<Map<String, String>> dtParams = []
                    for (MNode pn : defaultTransition.children('parameter')) {
                        dtParams.add([name: pn.attribute('name') ?: '', from: pn.attribute('from') ?: ''])
                    }
                    if (dtParams) dtJson.put('parameters', dtParams)
                    addDependsOn(defaultTransition, dtJson)
                    json.put('defaultTransition', dtJson)
                }
                // Depends-on fields
                addDependsOn(widgetNode, json)
                break

            case 'drop-down':
                json.put('allowEmpty', expand(widgetNode.attribute('allow-empty') ?: 'true', sri))
                json.put('allowMultiple', expand(widgetNode.attribute('allow-multiple') ?: 'false', sri))
                json.put('submitOnSelect', expand(widgetNode.attribute('submit-on-select') ?: 'false', sri))
                json.put('current', widgetNode.attribute('current') ?: 'selected')
                json.put('showNot', widgetNode.attribute('show-not') ?: 'false')
                // Resolve static options server-side
                List<Map<String, String>> options = resolveFieldOptions(widgetNode, sri)
                json.put('options', options)
                // Dynamic options config (client must fetch separately)
                MNode dynamicOpts = widgetNode.first('dynamic-options')
                if (dynamicOpts != null) {
                    Map<String, Object> dynJson = [:]
                    dynJson.put('transition', dynamicOpts.attribute('transition') ?: '')
                    dynJson.put('serverSearch', dynamicOpts.attribute('server-search') ?: 'false')
                    dynJson.put('minLength', dynamicOpts.attribute('min-length') ?: '1')
                    addDependsOn(dynamicOpts, dynJson)
                    json.put('dynamicOptions', dynJson)
                }
                addDependsOn(widgetNode, json)
                break

            case 'date-time':
                json.put('dateType', widgetNode.attribute('type') ?: 'timestamp')
                json.put('format', widgetNode.attribute('format') ?: '')
                json.put('minuteStepping', widgetNode.attribute('minute-stepping') ?: '')
                break

            case 'date-find':
                json.put('dateType', widgetNode.attribute('type') ?: 'timestamp')
                json.put('format', widgetNode.attribute('format') ?: '')
                break

            case 'date-period':
                json.put('allowEmpty', widgetNode.attribute('allow-empty') ?: 'true')
                json.put('time', widgetNode.attribute('time') ?: 'false')
                break

            case 'text-area':
                json.put('cols', widgetNode.attribute('cols') ?: '60')
                json.put('rows', widgetNode.attribute('rows') ?: '3')
                json.put('maxlength', widgetNode.attribute('maxlength') ?: '')
                json.put('readOnly', widgetNode.attribute('read-only') ?: 'false')
                json.put('editorType', widgetNode.attribute('editor-type') ?: '')
                json.put('autogrow', widgetNode.attribute('autogrow') ?: 'false')
                break

            case 'display':
                json.put('alsoHidden', widgetNode.attribute('also-hidden') ?: 'true')
                json.put('encode', widgetNode.attribute('encode') ?: 'true')
                json.put('format', widgetNode.attribute('format') ?: '')
                json.put('currencyUnitField', widgetNode.attribute('currency-unit-field') ?: '')
                // Aggregate footer flags (Phase 3.6)
                String showTotal = fieldNode?.attribute('show-total')
                if (showTotal == 'true' || showTotal == 'sum') json.put('showTotal', 'true')
                String showCount = fieldNode?.attribute('show-count')
                if (showCount == 'true') json.put('showCount', 'true')
                String showMin = fieldNode?.attribute('show-min')
                if (showMin == 'true') json.put('showMin', 'true')
                String showMax = fieldNode?.attribute('show-max')
                if (showMax == 'true') json.put('showMax', 'true')
                String showAvg = fieldNode?.attribute('show-avg')
                if (showAvg == 'true') json.put('showAvg', 'true')
                // Resolve display text
                String displayText = widgetNode.attribute('text')
                if (displayText) {
                    try { json.put('resolvedText', sri.ec.resourceFacade.expand(displayText, '')) }
                    catch (Exception e) { json.put('resolvedText', displayText) }
                }
                addDependsOn(widgetNode, json)
                break

            case 'display-entity':
                json.put('entityName', widgetNode.attribute('entity-name') ?: '')
                json.put('keyFieldName', widgetNode.attribute('key-field-name') ?: '')
                json.put('alsoHidden', widgetNode.attribute('also-hidden') ?: 'true')
                json.put('useCache', widgetNode.attribute('use-cache') ?: 'true')
                json.put('defaultText', widgetNode.attribute('default-text') ?: '')
                break

            case 'text-find':
                json.put('size', widgetNode.attribute('size') ?: '')
                json.put('maxlength', widgetNode.attribute('maxlength') ?: '')
                json.put('ignoreCase', widgetNode.attribute('ignore-case') ?: 'true')
                json.put('defaultOperator', widgetNode.attribute('default-operator') ?: 'contains')
                json.put('hideOptions', widgetNode.attribute('hide-options') ?: 'false')
                break

            case 'range-find':
                json.put('size', widgetNode.attribute('size') ?: '')
                json.put('maxlength', widgetNode.attribute('maxlength') ?: '')
                break

            case 'check':
            case 'radio':
                json.put('noCurrentSelectedKey', widgetNode.attribute('no-current-selected-key') ?: '')
                if (widgetType == 'check') json.put('allChecked', widgetNode.attribute('all-checked') ?: 'false')
                List<Map<String, String>> opts = resolveFieldOptions(widgetNode, sri)
                json.put('options', opts)
                break

            case 'file':
                json.put('size', widgetNode.attribute('size') ?: '')
                json.put('maxlength', widgetNode.attribute('maxlength') ?: '')
                json.put('multiple', widgetNode.attribute('multiple') ?: 'false')
                json.put('accept', widgetNode.attribute('accept') ?: '')
                break

            case 'hidden':
                json.put('defaultValue', widgetNode.attribute('default-value') ?: '')
                break

            case 'submit':
                // Pass the explicit text attribute if set; otherwise leave empty so the
                // client can fall back to the parent field's title (e.g. "Find", "Search").
                json.put('text', widgetNode.attribute('text') ?: '')
                json.put('confirmation', widgetNode.attribute('confirmation') ?: '')
                json.put('btnType', widgetNode.attribute('type') ?: '')
                json.put('icon', widgetNode.attribute('icon') ?: '')
                break

            case 'link':
                return renderLink(widgetNode, sri)

            case 'label':
                return renderLabel(widgetNode, sri)

            case 'dynamic-dialog':
                return renderDynamicDialog(widgetNode, sri)

            case 'password':
                json.put('size', widgetNode.attribute('size') ?: '')
                json.put('maxlength', widgetNode.attribute('maxlength') ?: '')
                break
        }

        return json
    }

    // --- Option Resolution ---

    private List<Map<String, String>> resolveFieldOptions(MNode widgetNode, ScreenRenderImpl sri) {
        List<Map<String, String>> optionsList = []

        try {
            LinkedHashMap<String, String> options = sri.getFieldOptions(widgetNode)
            if (options != null) {
                for (Map.Entry<String, String> entry : options.entrySet()) {
                    optionsList.add([key: entry.getKey(), text: entry.getValue()])
                }
            }
        } catch (Exception e) {
            // Options resolution can fail if entity data not loaded; return empty
        }

        // Also check for static <option> children
        if (optionsList.isEmpty()) {
            for (MNode optNode : widgetNode.children('option')) {
                optionsList.add([key: optNode.attribute('key') ?: '', text: optNode.attribute('text') ?: ''])
            }
        }

        return optionsList
    }

    private void addDependsOn(MNode node, Map<String, Object> json) {
        MNode dependsOn = node.first('depends-on')
        if (dependsOn != null) {
            json.put('dependsOnField', dependsOn.attribute('field') ?: '')
            json.put('dependsOnParameter', dependsOn.attribute('parameter-name') ?: '')
        }
        // Multiple depends-on
        ArrayList<MNode> dependsOnList = node.children('depends-on')
        if (dependsOnList.size() > 1) {
            List<Map<String, String>> deps = []
            for (MNode dep : dependsOnList) {
                deps.add([field: dep.attribute('field') ?: '', parameter: dep.attribute('parameter-name') ?: ''])
            }
            json.put('dependsOnList', deps)
        }
    }

    // --- Container Widgets ---

    /** Expand ${...} expressions in attribute values against the current execution context. */
    private String expand(String value, ScreenRenderImpl sri) {
        if (value == null || !value.contains('${')) return value
        try { return sri.ec.resourceFacade.expand(value, '')?.toString() ?: value }
        catch (Exception e) { return value }
    }

    private Map<String, Object> renderSection(MNode node, ScreenRenderImpl sri) {
        Map<String, Object> json = baseAttrs(node)
        json.put('_type', 'section')
        String sectionName = node.attribute('name') ?: ''
        json.put('sectionName', sectionName)

        ExecutionContextImpl ec = sri.ec

        // Push context to isolate section actions and variables (mirrors ScreenSection.render())
        ec.contextStack.push()
        try {
            // Run the section's actions to populate context variables
            if (sectionName) {
                try {
                    ScreenDefinition sd = sri.getActiveScreenDef()
                    ScreenSection section = sd.getSection(sectionName)
                    if (section != null && section.actions != null) {
                        section.actions.run(ec)
                    }
                } catch (Exception e) { /* actions may fail, continue rendering */ }
            }

            // Evaluate condition to choose widgets vs fail-widgets
            boolean conditionPassed = true
            String conditionAttr = node.attribute('condition')
            if (conditionAttr) {
                try {
                    Object result = ec.resourceFacade.expression(conditionAttr, null)
                    conditionPassed = result as boolean
                } catch (Exception e) { conditionPassed = false }
            }

            if (conditionPassed) {
                MNode widgetsNode = node.first('widgets')
                if (widgetsNode != null) {
                    json.put('widgets', renderChildren(widgetsNode, sri))
                }
            } else {
                MNode failWidgets = node.first('fail-widgets')
                if (failWidgets != null) {
                    json.put('failWidgets', renderChildren(failWidgets, sri))
                }
            }
        } finally {
            ec.contextStack.pop()
        }
        return json
    }

    private Map<String, Object> renderSectionIterate(MNode node, ScreenRenderImpl sri) {
        Map<String, Object> json = baseAttrs(node)
        json.put('_type', 'section-iterate')
        String sectionName = node.attribute('name') ?: ''
        json.put('sectionName', sectionName)

        ExecutionContextImpl ec = sri.ec

        // Push context to isolate section actions and variables (mirrors ScreenSection.render())
        ec.contextStack.push()
        try {
            // Run section actions to populate context (e.g. lists)
            if (sectionName) {
                try {
                    ScreenDefinition sd = sri.getActiveScreenDef()
                    ScreenSection section = sd.getSection(sectionName)
                    if (section != null && section.actions != null) {
                        section.actions.run(ec)
                    }
                } catch (Exception e) { /* continue */ }
            }

            // Evaluate list from context
            String listName = node.attribute('list') ?: ''
            String entryName = node.attribute('entry') ?: ''
            String keyName = node.attribute('key') ?: ''
            Object list = listName ? ec.resourceFacade.expression(listName, null) : null

            MNode widgetsNode = node.first('widgets')
            MNode failWidgetsNode = node.first('fail-widgets')
            List<List<Map<String, Object>>> iterations = []

            if (list) {
                Iterator iter = null
                if (list instanceof Iterator) iter = (Iterator) list
                else if (list instanceof Map) iter = ((Map) list).entrySet().iterator()
                else if (list instanceof Iterable) iter = ((Iterable) list).iterator()

                int index = 0
                while (iter != null && iter.hasNext()) {
                    Object entry = iter.next()
                    ec.contextStack.push()
                    try {
                        ec.contextStack.put(entryName, (entry instanceof Map.Entry ? ((Map.Entry) entry).getValue() : entry))
                        if (keyName && entry instanceof Map.Entry) ec.contextStack.put(keyName, ((Map.Entry) entry).getKey())
                        ec.contextStack.put('sectionEntryIndex', index)
                        ec.contextStack.put(entryName + '_index', index)
                        ec.contextStack.put(entryName + '_has_next', iter.hasNext())

                        if (widgetsNode != null) {
                            iterations.add(renderChildren(widgetsNode, sri))
                        }
                    } finally {
                        ec.contextStack.pop()
                    }
                    index++
                }
            }

            json.put('iterations', iterations)
        } finally {
            ec.contextStack.pop()
        }
        return json
    }

    private Map<String, Object> renderSectionInclude(MNode node, ScreenRenderImpl sri) {
        Map<String, Object> json = baseAttrs(node)
        json.put('_type', 'section-include')
        String sectionName = node.attribute('name') ?: ''
        json.put('sectionName', sectionName)

        // Inline render the referenced section (Phase 5.2)
        // NOTE: sd.getSection() throws BaseArtifactException if the section is not found rather than
        // returning null. We must catch that separately so rendering failures of a FOUND section
        // do not look like "section not found" and silently kill the whole widget tree.
        if (sectionName) {
            ScreenDefinition sd = sri.getActiveScreenDef()
            ScreenSection section = null
            try {
                section = sd?.getSection(sectionName)
            } catch (Exception ignored) { /* section not registered in this screen — skip */ }

            if (section != null) {
                // Push context to isolate section variables (mirrors ScreenSection.render())
                sri.ec.contextStack.push()
                try {
                    // Run section actions (errors are non-fatal; context may already hold needed vars)
                    if (section.actions != null) {
                        try { section.actions.run(sri.ec) } catch (Exception ae) { /* ignore */ }
                    }

                    // Evaluate condition to choose widgets vs fail-widgets
                    boolean condOk = true
                    MNode secNode = section.sectionNode
                    if (secNode != null) {
                        String condAttr = secNode.attribute('condition')
                        if (condAttr) {
                            try {
                                condOk = sri.ec.resourceFacade.expression(condAttr, null) as boolean
                            } catch (Exception ce) { condOk = false }
                        }
                        if (condOk) {
                            MNode wn = secNode.first('widgets')
                            if (wn != null) {
                                try { json.put('widgets', renderChildren(wn, sri)) }
                                catch (Exception we) { json.put('widgets', []) }
                            }
                        } else {
                            MNode fn = secNode.first('fail-widgets')
                            if (fn != null) {
                                try { json.put('failWidgets', renderChildren(fn, sri)) }
                                catch (Exception fe) { json.put('failWidgets', []) }
                            }
                        }
                    }
                } finally {
                    sri.ec.contextStack.pop()
                }
            }
        }
        return json
    }

    private Map<String, Object> renderContainer(MNode node, ScreenRenderImpl sri) {
        Map<String, Object> json = baseAttrs(node)
        json.put('_type', 'container')
        json.put('containerType', node.attribute('type') ?: 'div')
        json.put('children', renderChildren(node, sri))
        return json
    }

    private Map<String, Object> renderContainerBox(MNode node, ScreenRenderImpl sri) {
        Map<String, Object> json = baseAttrs(node)
        json.put('_type', 'container-box')

        MNode header = node.first('box-header')
        if (header != null) {
            // Extract the title attribute from box-header (e.g. <box-header title="General Tools"/>)
            String headerTitle = header.attribute('title')
            if (headerTitle) json.put('boxTitle', headerTitle)
            json.put('header', renderChildren(header, sri))
        }
        MNode toolbar = node.first('box-toolbar')
        if (toolbar != null) json.put('toolbar', renderChildren(toolbar, sri))
        MNode body = node.first('box-body')
        if (body != null) json.put('body', renderChildren(body, sri))
        MNode bodyNoPad = node.first('box-body-nopad')
        if (bodyNoPad != null) json.put('bodyNoPad', renderChildren(bodyNoPad, sri))

        return json
    }

    private Map<String, Object> renderContainerRow(MNode node, ScreenRenderImpl sri) {
        Map<String, Object> json = baseAttrs(node)
        json.put('_type', 'container-row')

        List<Map<String, Object>> cols = []
        for (MNode colNode : node.children('row-col')) {
            Map<String, Object> col = [:]
            col.put('lg', colNode.attribute('lg') ?: '')
            col.put('md', colNode.attribute('md') ?: '')
            col.put('sm', colNode.attribute('sm') ?: '')
            col.put('xs', colNode.attribute('xs') ?: '')
            col.put('style', colNode.attribute('style') ?: '')
            col.put('children', renderChildren(colNode, sri))
            cols.add(col)
        }
        json.put('columns', cols)

        return json
    }

    private Map<String, Object> renderContainerPanel(MNode node, ScreenRenderImpl sri) {
        Map<String, Object> json = baseAttrs(node)
        json.put('_type', 'container-panel')

        // Collapse hints (Phase 5.1)
        String collapsible = node.attribute('collapsible')
        if (collapsible == 'true') json.put('collapsible', true)
        String initiallyCollapsed = node.attribute('initially-collapsed')
        if (initiallyCollapsed == 'true') json.put('defaultOpen', false)

        MNode header = node.first('panel-header')
        if (header != null) json.put('header', renderChildren(header, sri))
        MNode left = node.first('panel-left')
        if (left != null) {
            Map<String, Object> leftJson = [:]
            leftJson.put('size', left.attribute('size') ?: '180')
            leftJson.put('sizeUnit', left.attribute('size-unit') ?: 'px')
            leftJson.put('children', renderChildren(left, sri))
            json.put('left', leftJson)
        }
        MNode center = node.first('panel-center')
        if (center != null) json.put('center', renderChildren(center, sri))
        MNode right = node.first('panel-right')
        if (right != null) {
            Map<String, Object> rightJson = [:]
            rightJson.put('size', right.attribute('size') ?: '180')
            rightJson.put('sizeUnit', right.attribute('size-unit') ?: 'px')
            rightJson.put('children', renderChildren(right, sri))
            json.put('right', rightJson)
        }
        MNode footer = node.first('panel-footer')
        if (footer != null) json.put('footer', renderChildren(footer, sri))

        return json
    }

    private Map<String, Object> renderContainerDialog(MNode node, ScreenRenderImpl sri) {
        Map<String, Object> json = baseAttrs(node)
        json.put('_type', 'container-dialog')
        json.put('buttonText', expand(node.attribute('button-text') ?: '', sri))
        json.put('dialogTitle', expand(node.attribute('title') ?: '', sri))
        json.put('width', node.attribute('width') ?: '')
        json.put('icon', node.attribute('icon') ?: '')
        json.put('btnType', node.attribute('type') ?: '')
        json.put('children', renderChildren(node, sri))
        return json
    }

    // --- Subscreen Widgets ---

    private Map<String, Object> renderSubscreensPanel(MNode node, ScreenRenderImpl sri) {
        Map<String, Object> json = baseAttrs(node)
        json.put('_type', 'subscreens-panel')
        json.put('menuType', node.attribute('type') ?: 'tab')
        json.put('noMenu', node.attribute('no-menu') ?: 'false')

        // Build the subscreens menu items list
        ScreenDefinition screenDef = sri.getActiveScreenDef()
        if (screenDef != null) {
            try {
            ArrayList<ScreenDefinition.SubscreensItem> menuItems = screenDef.getMenuSubscreensItems()
            List<Map<String, Object>> menuItemsList = []
            for (ScreenDefinition.SubscreensItem item : menuItems) {
                Map<String, Object> itemMap = [:]
                itemMap.put('name', item.getName())
                itemMap.put('menuTitle', item.getMenuTitle() ?: item.getName())
                Integer menuIndex = item.getMenuIndex()
                if (menuIndex != null) itemMap.put('menuIndex', menuIndex)
                itemMap.put('menuInclude', item.getMenuInclude())
                itemMap.put('disabled', item.getDisable(sri.ec))
                menuItemsList.add(itemMap)
            }
            json.put('subscreens', menuItemsList)

            // Include default subscreen name
            MNode subscreensNode = screenDef.getScreenNode()?.first('subscreens')
            if (subscreensNode != null) {
                String defaultItem = subscreensNode.attribute('default-item')
                if (defaultItem) json.put('defaultItem', defaultItem)
            }
            } catch (Throwable t2) {
                json.put('subscreenError', "Error loading subscreens: ${t2.toString()}")
            }
        }

        // Render the active subscreen content inline
        if (sri.getActiveScreenHasNext()) {
            // There is an explicit next subscreen in the URL path — render it
            Writer originalWriter = sri.internalWriter
            StringWriter captureWriter = new StringWriter()
            sri.internalWriter = captureWriter
            try {
                sri.renderSubscreen()
                captureWriter.flush()
                String subscreenJson = captureWriter.toString()
                if (subscreenJson != null && subscreenJson.length() > 0) {
                    Map<String, Object> subscreenData = mapper.readValue(subscreenJson, Map.class)
                    json.put('activeSubscreen', subscreenData)
                }
            } catch (Throwable t) {
                json.put('subscreenError', t.toString())
            } finally {
                sri.internalWriter = originalWriter
            }
        } else if (screenDef != null) {
            // No explicit subscreen in URL path — render the default-item if one exists.
            // This handles the common pattern where Find screens (e.g. FindParty, FindProduct)
            // are set as default-item but have default-menu-include="false", so they must be
            // rendered automatically when the parent module screen is requested.
            String defaultItemName = null
            try {
                MNode subscreensNode = screenDef.getScreenNode()?.first('subscreens')
                if (subscreensNode != null) defaultItemName = subscreensNode.attribute('default-item')
            } catch (Throwable ignored) { }

            if (defaultItemName) {
                try {
                    ScreenDefinition.SubscreensItem ssi = screenDef.getSubscreensItem(defaultItemName)
                    if (ssi != null) {
                        String loc = ssi.getLocation()
                        if (loc) {
                            Writer originalWriter = sri.internalWriter
                            StringWriter captureWriter = new StringWriter()
                            sri.internalWriter = captureWriter
                            try {
                                sri.renderIncludeScreen(loc, 'true')
                                captureWriter.flush()
                                String subscreenJson = captureWriter.toString()
                                if (subscreenJson != null && subscreenJson.length() > 0) {
                                    Map<String, Object> subscreenData = mapper.readValue(subscreenJson, Map.class)
                                    json.put('activeSubscreen', subscreenData)
                                    json.put('activeSubscreenName', defaultItemName)
                                }
                            } finally {
                                sri.internalWriter = originalWriter
                            }
                        }
                    }
                } catch (Throwable t) {
                    json.put('subscreenError', "Error rendering default subscreen '${defaultItemName}': ${t.toString()}")
                }
            }
        }

        return json
    }

    private Map<String, Object> renderSubscreensMenu(MNode node, ScreenRenderImpl sri) {
        Map<String, Object> json = baseAttrs(node)
        json.put('_type', 'subscreens-menu')
        json.put('menuType', node.attribute('type') ?: 'tab')

        // Build the subscreens menu items
        ScreenDefinition screenDef = sri.getActiveScreenDef()
        if (screenDef != null) {
            ArrayList<ScreenDefinition.SubscreensItem> menuItems = screenDef.getMenuSubscreensItems()
            List<Map<String, Object>> menuItemsList = []
            for (ScreenDefinition.SubscreensItem item : menuItems) {
                Map<String, Object> itemMap = [:]
                itemMap.put('name', item.getName())
                itemMap.put('menuTitle', item.getMenuTitle() ?: item.getName())
                Integer menuIndex = item.getMenuIndex()
                if (menuIndex != null) itemMap.put('menuIndex', menuIndex)
                menuItemsList.add(itemMap)
            }
            json.put('subscreens', menuItemsList)
        }

        return json
    }

    private Map<String, Object> renderSubscreensActive(MNode node, ScreenRenderImpl sri) {
        Map<String, Object> json = baseAttrs(node)
        json.put('_type', 'subscreens-active')

        // Include the default subscreen name so the client can load it if needed
        ScreenDefinition screenDef = sri.getActiveScreenDef()
        if (screenDef != null) {
            MNode subscreensNode = screenDef.getScreenNode()?.first('subscreens')
            if (subscreensNode != null) {
                String defaultItem = subscreensNode.attribute('default-item')
                if (defaultItem) json.put('defaultItem', defaultItem)
            }
        }

        // Render the active subscreen content inline
        if (sri.getActiveScreenHasNext()) {
            Writer originalWriter = sri.internalWriter
            StringWriter captureWriter = new StringWriter()
            sri.internalWriter = captureWriter
            try {
                sri.renderSubscreen()
                captureWriter.flush()
                String subscreenJson = captureWriter.toString()
                if (subscreenJson != null && subscreenJson.length() > 0) {
                    Map<String, Object> subscreenData = mapper.readValue(subscreenJson, Map.class)
                    json.put('activeSubscreen', subscreenData)
                }
            } catch (Throwable t) {
                json.put('subscreenError', t.toString())
            } finally {
                sri.internalWriter = originalWriter
            }
        }

        return json
    }

    // --- Standalone Widgets ---

    private Map<String, Object> renderLink(MNode node, ScreenRenderImpl sri) {
        Map<String, Object> json = baseAttrs(node)
        json.put('_type', 'link')

        String origUrl = expand(node.attribute('url') ?: '', sri)
        String urlType = node.attribute('url-type') ?: 'transition'
        String linkType = node.attribute('link-type') ?: 'auto'

        json.put('urlType', urlType)
        json.put('text', expand(node.attribute('text') ?: '', sri))
        json.put('linkType', linkType)
        json.put('icon', node.attribute('icon') ?: '')
        json.put('badge', expand(node.attribute('badge') ?: '', sri))
        json.put('confirmation', expand(node.attribute('confirmation') ?: '', sri))
        json.put('tooltip', expand(node.attribute('tooltip') ?: '', sri))
        json.put('btnType', node.attribute('btn-type') ?: '')
        json.put('targetWindow', node.attribute('target-window') ?: '')
        json.put('dynamicLoadId', node.attribute('dynamic-load-id') ?: '')

        // Also put resolvedText for backward compat
        String text = json.get('text')?.toString()
        if (text && text.contains('${')) {
            json.put('resolvedText', text)
        }

        // Resolve URL to full absolute path using makeUrlByType.
        // Raw URL attributes like '../ArtifactStats' are resolved relative to the current
        // screen context, producing a full path like '/fapps/tools/ArtifactStats'.
        String resolvedUrl = origUrl
        boolean isAnchorLink = false
        if (origUrl) {
            try {
                ScreenUrlInfo.UrlInstance urlInstance = sri.makeUrlByType(origUrl, urlType, node, 'false')
                // getPath() returns the full path including the transition name (e.g. /fapps/tools/reloadEcfi)
                // getScreenOnlyPath() strips the transition and returns just the screen (e.g. /fapps/tools)
                // For navigation we want getPath() — the full resolved path.
                String fullPath = urlInstance.getPath() ?: ''
                if (fullPath && fullPath != '#') {
                    resolvedUrl = fullPath
                }
                // Determine if this is a simple anchor/navigation link or a form-post transition
                isAnchorLink = sri.isAnchorLink(node, urlInstance)
                // Emit resolved server-side parameter values so the client doesn't need to
                // resolve context variable references (e.g. from="entityName").
                Map<String, String> resolvedParams = urlInstance.getParameterMap()
                if (resolvedParams && !resolvedParams.isEmpty()) {
                    json.put('parameterMap', new HashMap<String, String>(resolvedParams))
                }
            } catch (Exception e) {
                // URL resolution can fail for external URLs or missing screens — keep origUrl
            }
        }
        json.put('url', resolvedUrl)
        json.put('isAnchorLink', isAnchorLink)

        // Raw link parameters (kept for backwards compatibility; prefer parameterMap above)
        List<Map<String, String>> params = []
        for (MNode paramNode : node.children('parameter')) {
            params.add([name: paramNode.attribute('name') ?: '', value: paramNode.attribute('value') ?: '',
                        from: paramNode.attribute('from') ?: ''])
        }
        if (params) json.put('parameters', params)

        // Parse parameter-map attribute (Groovy map literal syntax) to emit parameterFromFields.
        // Tells the client which row field to use for each parameter value at runtime.
        // e.g., parameter-map="[selectedEntity:fullEntityName]" → parameterFromFields={selectedEntity:fullEntityName}
        String parameterMapAttr = node.attribute('parameter-map')
        if (parameterMapAttr) {
            Map<String, String> paramFromFields = [:]
            // Extract key:value pairs where value is a bare identifier (variable reference, not quoted string)
            def matcher = parameterMapAttr =~ /(\w+)\s*:\s*([a-zA-Z_]\w*)/
            while (matcher.find()) {
                paramFromFields.put(matcher.group(1), matcher.group(2))
            }
            if (!paramFromFields.isEmpty()) {
                json.put('parameterFromFields', paramFromFields)
            }
        }

        return json
    }

    private Map<String, Object> renderLabel(MNode node, ScreenRenderImpl sri) {
        Map<String, Object> json = baseAttrs(node)
        json.put('_type', 'label')
        String text = expand(node.attribute('text') ?: '', sri)
        json.put('text', text)
        json.put('resolvedText', text)
        json.put('labelType', node.attribute('type') ?: 'span')
        json.put('encode', node.attribute('encode') ?: 'true')

        return json
    }

    private Map<String, Object> renderImage(MNode node, ScreenRenderImpl sri) {
        Map<String, Object> json = baseAttrs(node)
        json.put('_type', 'image')
        json.put('url', node.attribute('url') ?: '')
        json.put('urlType', node.attribute('url-type') ?: 'content')
        json.put('alt', node.attribute('alt') ?: '')
        json.put('width', node.attribute('width') ?: '')
        json.put('height', node.attribute('height') ?: '')
        json.put('hover', node.attribute('hover') ?: '')
        return json
    }

    private Map<String, Object> renderDynamicDialog(MNode node, ScreenRenderImpl sri) {
        Map<String, Object> json = baseAttrs(node)
        json.put('_type', 'dynamic-dialog')
        json.put('dialogId', node.attribute('id') ?: '')
        json.put('buttonText', node.attribute('button-text') ?: '')
        json.put('transition', node.attribute('transition') ?: '')
        json.put('dialogTitle', node.attribute('title') ?: '')
        json.put('width', node.attribute('width') ?: '')
        json.put('height', node.attribute('height') ?: '')
        json.put('icon', node.attribute('icon') ?: '')

        // Parameters
        List<Map<String, String>> params = []
        for (MNode paramNode : node.children('parameter')) {
            params.add([name: paramNode.attribute('name') ?: '', value: paramNode.attribute('value') ?: '',
                        from: paramNode.attribute('from') ?: ''])
        }
        if (params) json.put('parameters', params)

        return json
    }

    private Map<String, Object> renderDynamicContainer(MNode node, ScreenRenderImpl sri) {
        Map<String, Object> json = baseAttrs(node)
        json.put('_type', 'dynamic-container')
        json.put('containerId', node.attribute('id') ?: '')
        json.put('transition', node.attribute('transition') ?: '')
        return json
    }

    private Map<String, Object> renderButtonMenu(MNode node, ScreenRenderImpl sri) {
        Map<String, Object> json = baseAttrs(node)
        json.put('_type', 'button-menu')
        json.put('text', node.attribute('text') ?: '')
        json.put('icon', node.attribute('icon') ?: '')
        json.put('badge', expand(node.attribute('badge') ?: '', sri))
        json.put('btnType', node.attribute('btn-type') ?: '')
        json.put('children', renderChildren(node, sri))
        return json
    }

    private Map<String, Object> renderTree(MNode node, ScreenRenderImpl sri) {
        Map<String, Object> json = baseAttrs(node)
        json.put('_type', 'tree')
        json.put('treeName', node.attribute('name') ?: '')
        json.put('openPath', node.attribute('open-path') ?: '')

        // Build a lookup map of tree-node definitions by name
        Map<String, MNode> nodeTypeMap = [:]
        List<Map<String, Object>> treeNodes = []
        for (MNode treeNodeDef : node.children('tree-node')) {
            String nodeName = treeNodeDef.attribute('name') ?: ''
            nodeTypeMap.put(nodeName, treeNodeDef)

            Map<String, Object> tn = [:]
            tn.put('name', nodeName)
            tn.put('entryName', treeNodeDef.attribute('entry-name') ?: '')

            MNode link = treeNodeDef.first('link')
            if (link != null) tn.put('link', renderLink(link, sri))

            List<Map<String, Object>> subNodes = []
            for (MNode subNode : treeNodeDef.children('tree-sub-node')) {
                Map<String, Object> snMap = [:]
                snMap.put('nodeType', subNode.attribute('node-name') ?: '')
                snMap.put('list', subNode.attribute('list') ?: '')
                subNodes.add(snMap)
            }
            tn.put('subNodes', subNodes)
            treeNodes.add(tn)
        }
        json.put('treeNodes', treeNodes)

        // Evaluate actual tree data starting from root node type
        MNode rootNodeDef = node.children('tree-node') ? node.children('tree-node')[0] : null
        if (rootNodeDef != null) {
            try {
                List<Map<String, Object>> rootItems = evaluateTreeLevel(rootNodeDef, nodeTypeMap, sri, 0, 2)
                json.put('items', rootItems)
            } catch (Exception e) {
                json.put('items', (List) [])
                json.put('treeError', e.message ?: 'Tree evaluation error')
            }
        }

        return json
    }

    /** Recursively evaluate one tree level by running entity-find queries and expanding link templates. */
    private List<Map<String, Object>> evaluateTreeLevel(MNode treeNodeDef, Map<String, MNode> nodeTypeMap,
            ScreenRenderImpl sri, int depth, int maxDepth) {
        if (depth > maxDepth) return (List<Map<String, Object>>) []

        List<Map<String, Object>> items = (List<Map<String, Object>>) []
        String entryName = treeNodeDef.attribute('entry-name') ?: 'entry'

        MNode entityFindNode = treeNodeDef.first('entity-find')
        if (entityFindNode == null) return items

        String entityName = entityFindNode.attribute('entity-name')
        if (!entityName) return items

        try {
            EntityFind ef = sri.ec.entity.find(entityName)

            // Apply econditions
            for (MNode econd : entityFindNode.children('econdition')) {
                String fieldName = econd.attribute('field-name')
                String value = econd.attribute('value')
                String from = econd.attribute('from')
                boolean ignoreIfEmpty = 'true'.equals(econd.attribute('ignore-if-empty'))

                Object condValue = null
                if (value != null && !value.isEmpty()) {
                    condValue = value
                } else if (from != null && !from.isEmpty()) {
                    condValue = sri.ec.context.getByString(from)
                }

                if (ignoreIfEmpty && (condValue == null || condValue.toString().isEmpty())) {
                    continue
                }
                if (fieldName && condValue != null) {
                    ef.condition(fieldName, EntityCondition.ComparisonOperator.EQUALS, condValue)
                }
            }

            // Apply order-by
            for (MNode orderBy : entityFindNode.children('order-by')) {
                String orderField = orderBy.attribute('field-name')
                if (orderField) ef.orderBy(orderField)
            }

            ef.limit(200)
            EntityList resultList = ef.list()

            MNode linkNode = treeNodeDef.first('link')

            for (EntityValue ev : resultList) {
                Map<String, Object> item = [:]

                // Push entity data into context for template expansion
                sri.ec.context.push()
                Map<String, Object> evMap = ev.getMap()
                sri.ec.context.put(entryName, evMap)
                for (Map.Entry<String, Object> field : evMap.entrySet()) {
                    sri.ec.context.put(field.key, field.value)
                }

                try {
                    // Expand link text and URL templates
                    if (linkNode != null) {
                        String linkText = linkNode.attribute('text') ?: ''
                        String linkUrl = linkNode.attribute('url') ?: ''
                        if (linkText.contains('${')) {
                            linkText = sri.ec.resourceFacade.expand(linkText, '')
                        }
                        if (linkUrl.contains('${')) {
                            linkUrl = sri.ec.resourceFacade.expand(linkUrl, '')
                        }
                        item.put('text', linkText)
                        item.put('url', linkUrl)
                        item.put('urlType', linkNode.attribute('url-type') ?: 'transition')
                    }

                    item.put('data', evMap)
                    item.put('nodeType', treeNodeDef.attribute('name') ?: '')

                    // Recursively evaluate child nodes
                    List<Map<String, Object>> children = (List<Map<String, Object>>) []
                    for (MNode subNodeDef : treeNodeDef.children('tree-sub-node')) {
                        String childNodeType = subNodeDef.attribute('node-name') ?: ''
                        MNode childTreeNodeDef = nodeTypeMap.get(childNodeType)
                        if (childTreeNodeDef != null) {
                            for (MNode param : subNodeDef.children('parameter')) {
                                String paramName = param.attribute('name')
                                String paramFrom = param.attribute('from')
                                if (paramName && paramFrom) {
                                    sri.ec.context.put(paramName, sri.ec.context.getByString(paramFrom))
                                }
                            }
                            List<Map<String, Object>> subItems = evaluateTreeLevel(
                                childTreeNodeDef, nodeTypeMap, sri, depth + 1, maxDepth)
                            children.addAll(subItems)
                        }
                    }
                    if (!children.isEmpty()) item.put('children', children)
                    item.put('hasChildren', !children.isEmpty())
                } finally {
                    sri.ec.context.pop()
                }

                items.add(item)
            }
        } catch (Exception e) {
            sri.ec.logger.warn("Tree evaluation error for ${entityName}: ${e.message}")
        }

        return items
    }

    private Map<String, Object> renderRenderMode(MNode node, ScreenRenderImpl sri) {
        // Find the text child that matches 'fjson' or falls back to no-type
        MNode textNode = node.first('text', 'type', 'fjson')
        if (textNode == null) textNode = node.first('text', 'type', 'json')
        if (textNode == null) textNode = node.first('text', 'type', 'html')
        if (textNode == null) textNode = node.first('text')

        if (textNode == null) return null

        return renderText(textNode, sri)
    }

    private Map<String, Object> renderText(MNode node, ScreenRenderImpl sri) {
        Map<String, Object> json = [:]
        json.put('_type', 'text')
        json.put('textType', node.attribute('type') ?: '')
        json.put('location', node.attribute('location') ?: '')
        json.put('template', node.attribute('template') ?: 'true')
        String textContent = node.getText()
        if (textContent) json.put('content', textContent)
        return json
    }

    private Map<String, Object> renderIncludeScreen(MNode node, ScreenRenderImpl sri) {
        Map<String, Object> json = baseAttrs(node)
        json.put('_type', 'include-screen')
        json.put('location', node.attribute('location') ?: '')
        json.put('shareScopeWith', node.attribute('share-scope-with') ?: '')
        return json
    }

    private Map<String, Object> renderFieldLayout(MNode layoutNode, ScreenRenderImpl sri) {
        Map<String, Object> json = [:]
        json.put('_type', 'field-layout')
        List<Map<String, Object>> rows = []
        for (MNode child : layoutNode.getChildren()) {
            Map<String, Object> rowJson = [:]
            rowJson.put('_type', child.getName())
            if (child.getName() == 'field-ref') {
                rowJson.put('name', child.attribute('name') ?: '')
            } else if (child.getName() == 'field-row') {
                List<Map<String, Object>> rowFields = []
                for (MNode fieldRef : child.children('field-ref')) {
                    Map<String, Object> rfMap = [:]
                    rfMap.put('name', fieldRef.attribute('name') ?: '')
                    rowFields.add(rfMap)
                }
                rowJson.put('fields', rowFields)
            } else if (child.getName() == 'field-group') {
                rowJson.put('title', child.attribute('title') ?: '')
                rowJson.put('style', child.attribute('style') ?: '')
                List<Map<String, Object>> groupChildren = []
                for (MNode gc : child.getChildren()) {
                    if (gc.getName() == 'field-ref') {
                        Map<String, Object> frMap = [:]
                        frMap.put('_type', 'field-ref')
                        frMap.put('name', gc.attribute('name') ?: '')
                        groupChildren.add(frMap)
                    } else if (gc.getName() == 'field-row') {
                        List<Map<String, Object>> rowFields = []
                        for (MNode fr : gc.children('field-ref')) {
                            Map<String, Object> rfMap = [:]
                            rfMap.put('name', fr.attribute('name') ?: '')
                            rowFields.add(rfMap)
                        }
                        Map<String, Object> frRowMap = [:]
                        frRowMap.put('_type', 'field-row')
                        frRowMap.put('fields', rowFields)
                        groupChildren.add(frRowMap)
                    }
                }
                rowJson.put('children', groupChildren)
            }
            rows.add(rowJson)
        }
        json.put('rows', rows)
        return json
    }

    // --- Utilities ---

    private Map<String, Object> renderGenericNode(MNode node, ScreenRenderImpl sri) {
        Map<String, Object> json = baseAttrs(node)
        json.put('_type', node.getName())
        if (node.getChildren() && !node.getChildren().isEmpty()) {
            json.put('children', renderChildren(node, sri))
        }
        String text = node.getText()
        if (text) json.put('text', text)
        return json
    }

    private Map<String, Object> baseAttrs(MNode node) {
        Map<String, Object> json = [:]
        Map<String, String> attrs = node.getAttributes()
        if (attrs != null) {
            for (Map.Entry<String, String> entry : attrs.entrySet()) {
                if (COMMON_ATTRS.contains(entry.getKey())) {
                    json.put(entry.getKey(), entry.getValue())
                }
            }
        }
        return json
    }
}
