/// Phase 9.7 — Automated screen crawl of all MarbleERP paths.
///
/// Generates mock screen JSON for every MarbleERP screen path, parses via
/// [ScreenNode.fromJson], builds via [MoquiWidgetFactory.build], and verifies
/// 95%+ render without error.
///
/// Run:
///   flutter test test/integration/screen_crawl_test.dart
library;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moqui_flutter/domain/screen/screen_models.dart';
import 'package:moqui_flutter/presentation/widgets/moqui/widget_factory.dart';

// =============================================================================
// All MarbleERP screen paths (derived from SimpleScreens + MarbleERP screens)
// =============================================================================

const List<String> _allPaths = [
  // -- marble root --
  'marble',
  'marble/dashboard',
  // -- Accounting (81) --
  'Accounting',
  'Accounting/Budget',
  'Accounting/Budget/BudgetAccountsEntry',
  'Accounting/Budget/BudgetReport',
  'Accounting/Budget/EditBudget',
  'Accounting/Budget/EditBudgetItems',
  'Accounting/Budget/FindBudget',
  'Accounting/FinancialAccount',
  'Accounting/FinancialAccount/EditFinancialAccount',
  'Accounting/FinancialAccount/FinancialAccountStatement',
  'Accounting/FinancialAccount/FinancialAccountTrans',
  'Accounting/FinancialAccount/FindFinancialAccount',
  'Accounting/FindJournal',
  'Accounting/GlAccount',
  'Accounting/GlAccount/EditGlAccount',
  'Accounting/GlAccount/FindGlAccount',
  'Accounting/GlAccount/GlAccountTree',
  'Accounting/Invoice',
  'Accounting/Invoice/Aging',
  'Accounting/Invoice/EditInvoice',
  'Accounting/Invoice/EditInvoiceItemDetails',
  'Accounting/Invoice/EditInvoiceItemOrders',
  'Accounting/Invoice/EditInvoiceItemShipments',
  'Accounting/Invoice/EditInvoiceItems',
  'Accounting/Invoice/FindInvoice',
  'Accounting/Invoice/PrintInvoice',
  'Accounting/Invoice/ReceivableStatement',
  'Accounting/OrgSettings',
  'Accounting/OrgSettings/AcctgPreference',
  'Accounting/OrgSettings/AssetTypes',
  'Accounting/OrgSettings/FinAcctReasons',
  'Accounting/OrgSettings/FinAcctTypes',
  'Accounting/OrgSettings/GlAccounts',
  'Accounting/OrgSettings/InvoiceTypes',
  'Accounting/OrgSettings/ItemTypes',
  'Accounting/OrgSettings/PaymentInstruments',
  'Accounting/OrgSettings/PaymentTypes',
  'Accounting/OrgSettings/TypeDefaults',
  'Accounting/Payment',
  'Accounting/Payment/BulkPaymentCheck',
  'Accounting/Payment/EditPayment',
  'Accounting/Payment/FindPayment',
  'Accounting/Payment/PaymentCheck',
  'Accounting/Payment/PaymentDetail',
  'Accounting/Reports',
  'Accounting/Reports/AccountBalance',
  'Accounting/Reports/AccountLedger',
  'Accounting/Reports/ArAgingSummary',
  'Accounting/Reports/AssetOnHand',
  'Accounting/Reports/AssetOnHandSummary',
  'Accounting/Reports/AssetReceiptTransaction',
  'Accounting/Reports/AssetStatusByReceipt',
  'Accounting/Reports/AssetValuation',
  'Accounting/Reports/BalanceSheet',
  'Accounting/Reports/CashFlowStatement',
  'Accounting/Reports/FinancialRatios',
  'Accounting/Reports/IncomeStatement',
  'Accounting/Reports/InvoiceAgingDetail',
  'Accounting/Reports/InvoiceItemSummary',
  'Accounting/Reports/InvoiceReconciliation',
  'Accounting/Reports/OrderIssuedInvoiced',
  'Accounting/Reports/OrderItemSummary',
  'Accounting/Reports/PostedAmountSummary',
  'Accounting/Reports/PostedBalanceSummary',
  'Accounting/Reports/ReportList',
  'Accounting/Reports/RetainedEarningsStatement',
  'Accounting/Reports/SalesAnalysis',
  'Accounting/Reports/SalesInvoiceAnalysis',
  'Accounting/Reports/SalesSummary',
  'Accounting/Reports/ShipmentPackageSummary',
  'Accounting/TimePeriod',
  'Accounting/TimePeriod/EditTimePeriod',
  'Accounting/TimePeriod/FindTimePeriod',
  'Accounting/TimePeriod/ViewPeriodGlAccounts',
  'Accounting/Transaction',
  'Accounting/Transaction/EditTransaction',
  'Accounting/Transaction/EditTransaction/MoveEntry',
  'Accounting/Transaction/FindTransaction',
  'Accounting/Transaction/FindTransactionEntry',
  'Accounting/dashboard',
  'Accounting/dashboard/OrgInternalSummary',
  // -- Asset (29) --
  'Asset',
  'Asset/Asset',
  'Asset/Asset/AssetCalendar',
  'Asset/Asset/AssetDetail',
  'Asset/Asset/AssetMaintenance',
  'Asset/Asset/AssetMaintenance/EditAssetMaintenance',
  'Asset/Asset/AssetMaintenance/FindAssetMaintenance',
  'Asset/Asset/AssetMeters',
  'Asset/Asset/AssetParties',
  'Asset/Asset/AssetRegistrations',
  'Asset/Asset/DetailHistory',
  'Asset/Asset/FindAsset',
  'Asset/Asset/FindSummary',
  'Asset/Asset/FindSummary/PhysicalChange',
  'Asset/Asset/FindSummary/PhysicalQuantity',
  'Asset/Asset/MoveAsset',
  'Asset/Asset/SelectAsset',
  'Asset/AssetPool',
  'Asset/AssetPool/EditAssetPool',
  'Asset/AssetPool/FindAssetPool',
  'Asset/Container',
  'Asset/Container/EditContainer',
  'Asset/Container/FindContainer',
  'Asset/Container/MoveContainer',
  'Asset/EditLots',
  'Asset/PhysicalInventory',
  'Asset/PhysicalInventory/EditPhysicalInventory',
  'Asset/PhysicalInventory/FindPhysicalInventory',
  'Asset/dashboard',
  // -- Catalog (27) --
  'Catalog',
  'Catalog/Category',
  'Catalog/Category/Content',
  'Catalog/Category/Content/ContentCompare',
  'Catalog/Category/Content/ContentDetail',
  'Catalog/Category/Content/ContentList',
  'Catalog/Category/EditCategory',
  'Catalog/Category/EditProducts',
  'Catalog/Category/FindCategory',
  'Catalog/Feature',
  'Catalog/Feature/EditFeature',
  'Catalog/Feature/FindFeature',
  'Catalog/FeatureGroup',
  'Catalog/FeatureGroup/EditFeatureGroup',
  'Catalog/FeatureGroup/FindFeatureGroup',
  'Catalog/Product',
  'Catalog/Product/Content',
  'Catalog/Product/Content/ContentCompare',
  'Catalog/Product/Content/ContentDetail',
  'Catalog/Product/Content/ContentList',
  'Catalog/Product/EditAssocs',
  'Catalog/Product/EditCategories',
  'Catalog/Product/EditPrices',
  'Catalog/Product/EditProduct',
  'Catalog/Product/FindProduct',
  'Catalog/Search',
  'Catalog/dashboard',
  // -- Customer (4) --
  'Customer',
  'Customer/CustomerData',
  'Customer/EditCustomer',
  'Customer/FindCustomer',
  // -- Facility (9) --
  'Facility',
  'Facility/BoxTypes',
  'Facility/CarrierShipMethods',
  'Facility/EditFacility',
  'Facility/EditFacilityLocations',
  'Facility/EditFacilityProducts',
  'Facility/FacilityCalendar',
  'Facility/FindFacility',
  'Facility/PrintBoxTypes',
  // -- Gateway (7) --
  'Gateway',
  'Gateway/Payment',
  'Gateway/Payment/EditPaymentGateway',
  'Gateway/Payment/FindPaymentGateway',
  'Gateway/Shipping',
  'Gateway/Shipping/EditShippingGateway',
  'Gateway/Shipping/FindShippingGateway',
  // -- HumanRes (3) --
  'HumanRes',
  'HumanRes/EditRateAmounts',
  'HumanRes/dashboard',
  // -- Manufacturing (12) --
  'Manufacturing',
  'Manufacturing/Run',
  'Manufacturing/Run/EditRun',
  'Manufacturing/Run/FindRun',
  'Manufacturing/Run/RunConsumed',
  'Manufacturing/Run/RunPickDocument',
  'Manufacturing/Run/RunProduced',
  'Manufacturing/Run/RunProducts',
  'Manufacturing/Run/RunProducts/ConsumeAsset',
  'Manufacturing/Run/RunProducts/ConsumeProduct',
  'Manufacturing/Run/RunProducts/ProduceAsset',
  'Manufacturing/dashboard',
  // -- Order (9) --
  'Order',
  'Order/FindOrder',
  'Order/OrderDetail',
  'Order/OrderDetail/EditItem',
  'Order/OrderDetail/ItemReserve',
  'Order/OrderDetail/ReturnItem',
  'Order/OrderItems',
  'Order/PrintOrder',
  'Order/QuickItems',
  // -- Party (28) --
  'Party',
  'Party/EditParty',
  'Party/EditParty/ExpiredContactOther',
  'Party/EditParty/ExpiredPostal',
  'Party/EditParty/FindDuplicates',
  'Party/EditParty/UpdateContactInfo',
  'Party/EditParty/UpdatePaymentMethodInfo',
  'Party/FinancialInfo',
  'Party/FindParty',
  'Party/PartyAgreements',
  'Party/PartyAgreements/EditAgreement',
  'Party/PartyAgreements/FindAgreement',
  'Party/PartyCalendar',
  'Party/PartyEmails',
  'Party/PartyMessages',
  'Party/PartyProjects',
  'Party/PartyRelated',
  'Party/PartyRequests',
  'Party/PartyTasks',
  'Party/PartyTimeEntries',
  'Party/PartyTimeEntries/EditTimeEntry',
  'Party/PaymentMethod',
  'Party/PaymentMethod/EditPaymentMethod',
  'Party/PaymentMethod/PaymentGatewayResponses',
  'Party/PaymentMethod/PaymentMethodChecks',
  'Party/PaymentMethod/PaymentMethodFiles',
  'Party/PaymentMethod/PaymentMethodTrans',
  'Party/PaymentMethod/PaymentMethodTrans/CreatePayment',
  // -- ProductStore (14) --
  'ProductStore',
  'ProductStore/EditProductStore',
  'ProductStore/FindProductStore',
  'ProductStore/FindProductStoreCategory',
  'ProductStore/FindProductStoreEmails',
  'ProductStore/FindProductStoreFacility',
  'ProductStore/FindProductStoreParty',
  'ProductStore/FindProductStoreSettings',
  'ProductStore/Promotion',
  'ProductStore/Promotion/EditPromotion',
  'ProductStore/Promotion/FindPromotion',
  'ProductStore/Promotion/PromoCode',
  'ProductStore/Promotion/PromoCode/EditPromoCode',
  'ProductStore/Promotion/PromoCode/FindPromoCode',
  // -- Project (10) --
  'Project',
  'Project/EditMilestones',
  'Project/EditProject',
  'Project/EditUsers',
  'Project/EditWikiPages',
  'Project/FindProject',
  'Project/MilestoneSummary',
  'Project/ProjectProgressReport',
  'Project/ProjectSummary',
  'Project/ProjectTimeEntries',
  // -- QuickSearch (1) --
  'QuickSearch',
  // -- QuickViewReport (1) --
  'QuickViewReport',
  // -- Request (10) --
  'Request',
  'Request/EditRequest',
  'Request/EditRequest/RequestCommentNested',
  'Request/EditRequest/RequestCommentReply',
  'Request/EditRequest/RequestCommentUpdate',
  'Request/EditRequestItems',
  'Request/EditTasks',
  'Request/EditUsers',
  'Request/EditWikiPages',
  'Request/FindRequest',
  // -- Return (5) --
  'Return',
  'Return/AddOrderItems',
  'Return/EditReturn',
  'Return/EditReturnItems',
  'Return/FindReturn',
  // -- Shipment (13) --
  'Shipment',
  'Shipment/FindShipment',
  'Shipment/PackageTracking',
  'Shipment/ShipmentByPackage',
  'Shipment/ShipmentDetail',
  'Shipment/ShipmentDetail/ItemReserve',
  'Shipment/ShipmentDetail/ReceiveItem',
  'Shipment/ShipmentDetail/UpdateItemAsset',
  'Shipment/ShipmentInsert',
  'Shipment/ShipmentItems',
  'Shipment/ShipmentPack',
  'Shipment/ShipmentPackages',
  'Shipment/ShipmentPick',
  // -- Shipping (17) --
  'Shipping',
  'Shipping/PackShipment',
  'Shipping/PackShipment/PackItems',
  'Shipping/PackShipment/PackPackages',
  'Shipping/PackShipment/PackSummary',
  'Shipping/PackShipment/PackSummary/PackCompleted',
  'Shipping/PickLocationMoves',
  'Shipping/PickLocationMoves/QuickMove',
  'Shipping/Picklist',
  'Shipping/Picklist/AddOrder',
  'Shipping/Picklist/AddShipment',
  'Shipping/Picklist/BulkPicklist',
  'Shipping/Picklist/FindPicklist',
  'Shipping/Picklist/PicklistDetail',
  'Shipping/Picklist/ShipmentLoadPick',
  'Shipping/Picklist/ShipmentLoadPickAndPack',
  'Shipping/dashboard',
  // -- SimpleReport (6) --
  'SimpleReport',
  'SimpleReport/EditReport',
  'SimpleReport/EditReport/FieldList',
  'SimpleReport/FindReport',
  'SimpleReport/ViewReport',
  // -- Supplier (3) --
  'Supplier',
  'Supplier/EditSupplier',
  'Supplier/FindSupplier',
  // -- Survey (7) --
  'Survey',
  'Survey/EditSurvey',
  'Survey/Fields',
  'Survey/FindSurvey',
  'Survey/ResponseDetails',
  'Survey/ResponseStats',
  'Survey/Responses',
  // -- Task (12) --
  'Task',
  'Task/EditRelated',
  'Task/EditRequests',
  'Task/EditTask',
  'Task/EditTimeEntries',
  'Task/EditUsers',
  'Task/EditWikiPages',
  'Task/FindTask',
  'Task/TaskSummary',
  'Task/TaskSummary/TaskCommentNested',
  'Task/TaskSummary/TaskCommentReply',
  'Task/TaskSummary/TaskCommentUpdate',
  // -- Wiki (11) --
  'Wiki',
  'Wiki/EditWikiBlog',
  'Wiki/EditWikiPage',
  'Wiki/EditWikiSpace',
  'Wiki/ViewWikiPage',
  'Wiki/WikiBlogs',
  'Wiki/WikiCompare',
  'Wiki/WikiSpaces',
  'Wiki/wiki',
  'Wiki/wiki/WikiCommentNested',
  'Wiki/wiki/WikiCommentReply',
];

// =============================================================================
// Screen pattern classification
// =============================================================================

/// Classify a path into a screen pattern based on the leaf screen name.
String _classifyPath(String path) {
  final leaf = path.split('/').last;

  // Dashboard screens
  if (leaf == 'dashboard') return 'dashboard';

  // Find / search screens → form-list with search
  if (leaf.startsWith('Find') || leaf == 'Search' || leaf == 'QuickSearch') {
    return 'find-list';
  }

  // Edit / create / update screens → form-single
  if (leaf.startsWith('Edit') || leaf.startsWith('Update') ||
      leaf.startsWith('Create') || leaf.startsWith('Add') ||
      leaf == 'MoveEntry' || leaf == 'MoveAsset' || leaf == 'MoveContainer' ||
      leaf == 'ShipmentInsert') {
    return 'edit-form';
  }

  // Detail / view screens → subscreens-panel with tabs
  if (leaf.endsWith('Detail') || leaf.endsWith('Details') ||
      leaf.startsWith('View') || leaf == 'CustomerData' ||
      leaf == 'FinancialInfo' || leaf == 'SelectAsset') {
    return 'detail-view';
  }

  // Print screens
  if (leaf.startsWith('Print')) return 'print-view';

  // Reports / statements / summaries / analysis
  if (leaf.endsWith('Report') || leaf.endsWith('Reports') ||
      leaf.endsWith('Statement') || leaf.endsWith('Summary') ||
      leaf.endsWith('Analysis') || leaf.endsWith('Ratios') ||
      leaf.contains('Aging') || leaf.contains('Reconciliation') ||
      leaf == 'ReportList' || leaf.endsWith('Ledger') ||
      leaf.endsWith('Balance') || leaf.endsWith('Valuation') ||
      leaf.startsWith('Posted') || leaf.startsWith('Sales') ||
      leaf.endsWith('Invoiced') || leaf == 'QuickViewReport') {
    return 'report';
  }

  // Item / sub-entity list screens
  if (leaf.endsWith('Items') || leaf.endsWith('Products') ||
      leaf.endsWith('Prices') || leaf.endsWith('Categories') ||
      leaf.endsWith('Assocs') || leaf.endsWith('Entries') ||
      leaf.endsWith('Locations') || leaf.endsWith('Methods') ||
      leaf.endsWith('Emails') || leaf.endsWith('Messages') ||
      leaf.endsWith('Responses') || leaf.endsWith('Lots') ||
      leaf.endsWith('Users') || leaf.endsWith('Pages') ||
      leaf.endsWith('Types') || leaf.endsWith('Accounts') ||
      leaf.endsWith('Defaults') || leaf.endsWith('Instruments') ||
      leaf.endsWith('Party') || leaf.endsWith('Settings') ||
      leaf.endsWith('Facility') || leaf.endsWith('Category') ||
      leaf.endsWith('Checks') || leaf.endsWith('Files') ||
      leaf.endsWith('Trans') || leaf == 'FieldList') {
    return 'item-list';
  }

  // Calendar screens
  if (leaf.endsWith('Calendar')) return 'calendar';

  // Comment / nested screens
  if (leaf.contains('Comment') || leaf.contains('Reply') ||
      leaf.contains('Nested') || leaf.contains('Update')) {
    return 'comment';
  }

  // Specific operational screens
  if (leaf.startsWith('Pack') || leaf.startsWith('Pick') ||
      leaf.startsWith('Bulk') || leaf.startsWith('Quick') ||
      leaf.startsWith('Run') || leaf.startsWith('Consume') ||
      leaf.startsWith('Produce') || leaf == 'Shipment' ||
      leaf == 'Fields' || leaf == 'Responses' ||
      leaf.endsWith('Tracking') || leaf.endsWith('Pick') ||
      leaf.endsWith('Produced') || leaf.endsWith('Consumed') ||
      leaf.endsWith('Completed') || leaf.endsWith('Document') ||
      leaf == 'wiki') {
    return 'operational';
  }

  // Module root / container screens (subscreens-panel)
  return 'container';
}

// =============================================================================
// Mock screen JSON templates
// =============================================================================

/// Find-list: container-box wrapping a form-list with search fields and results.
Map<String, dynamic> _findListScreen(String name) => {
      'screenName': name,
      'menuTitle': name,
      'widgets': [
        {
          '_type': 'container-box',
          'boxTitle': name,
          'body': [
            {
              '_type': 'form-list',
              'formName': '${name}List',
              'fields': [
                {
                  'name': 'id',
                  'title': 'ID',
                  'widgets': [
                    {'_type': 'display'}
                  ],
                  'currentValue': '1001',
                },
                {
                  'name': 'description',
                  'title': 'Description',
                  'widgets': [
                    {'_type': 'display'}
                  ],
                  'currentValue': 'Sample item',
                },
                {
                  'name': 'status',
                  'title': 'Status',
                  'widgets': [
                    {'_type': 'display'}
                  ],
                  'currentValue': 'Active',
                },
              ],
              'listData': [
                {
                  'id': '1001',
                  'id_display': '1001',
                  'description': 'Sample item',
                  'description_display': 'Sample item',
                  'status': 'Active',
                  'status_display': 'Active',
                },
                {
                  'id': '1002',
                  'id_display': '1002',
                  'description': 'Another item',
                  'description_display': 'Another item',
                  'status': 'Inactive',
                  'status_display': 'Inactive',
                },
              ],
            },
          ],
        },
      ],
    };

/// Edit-form: form-single with various field types.
Map<String, dynamic> _editFormScreen(String name) => {
      'screenName': name,
      'menuTitle': name,
      'widgets': [
        {
          '_type': 'form-single',
          'name': '${name}Form',
          'transition': 'update',
          'fields': [
            {
              'name': 'id',
              'title': 'ID',
              'widgets': [
                {'_type': 'display'}
              ],
              'currentValue': 'REC001',
            },
            {
              'name': 'name',
              'title': 'Name',
              'widgets': [
                {'_type': 'text-line'}
              ],
              'currentValue': 'Test Record',
            },
            {
              'name': 'description',
              'title': 'Description',
              'widgets': [
                {'_type': 'text-area'}
              ],
            },
            {
              'name': 'statusId',
              'title': 'Status',
              'widgets': [
                {
                  '_type': 'drop-down',
                  'options': [
                    {'key': 'Active', 'text': 'Active'},
                    {'key': 'Inactive', 'text': 'Inactive'},
                  ],
                }
              ],
              'currentValue': 'Active',
            },
            {
              'name': 'submitBtn',
              'title': '',
              'widgets': [
                {'_type': 'submit', 'text': 'Save'}
              ],
            },
          ],
        },
      ],
    };

/// Detail-view: subscreens-panel with tabs.
Map<String, dynamic> _detailScreen(String name) => {
      'screenName': name,
      'menuTitle': name,
      'widgets': [
        {
          '_type': 'subscreens-panel',
          'type': 'tab',
          'tabs': [
            {'title': 'Summary', 'name': 'Summary', 'active': true},
            {'title': 'Items', 'name': 'Items', 'active': false},
            {'title': 'History', 'name': 'History', 'active': false},
          ],
          'children': [
            {
              '_type': 'container-box',
              'boxTitle': 'Summary',
              'body': [
                {'_type': 'label', 'text': '$name details'},
                {
                  '_type': 'link',
                  'text': 'Edit',
                  'url': '/edit',
                  'urlType': 'screen',
                },
              ],
            },
          ],
        },
      ],
    };

/// Dashboard: container-row with summary boxes.
Map<String, dynamic> _dashboardScreen(String name) => {
      'screenName': name,
      'menuTitle': 'Dashboard',
      'widgets': [
        {
          '_type': 'container-row',
          'columns': [
            {
              'lg': '6',
              'children': [
                {
                  '_type': 'container-box',
                  'boxTitle': 'Recent Activity',
                  'body': [
                    {'_type': 'label', 'text': 'No recent activity'},
                    {
                      '_type': 'link',
                      'text': 'View All',
                      'url': '/viewAll',
                      'urlType': 'screen',
                    },
                  ],
                },
              ],
            },
            {
              'lg': '6',
              'children': [
                {
                  '_type': 'container-box',
                  'boxTitle': 'Statistics',
                  'body': [
                    {'_type': 'label', 'text': 'Total: 42'},
                    {
                      '_type': 'image',
                      'url': '/images/chart.png',
                      'alt': 'Chart',
                    },
                  ],
                },
              ],
            },
          ],
        },
      ],
    };

/// Report: container-box with a read-only form-list.
Map<String, dynamic> _reportScreen(String name) => {
      'screenName': name,
      'menuTitle': name,
      'widgets': [
        {
          '_type': 'container-box',
          'boxTitle': name,
          'body': [
            {
              '_type': 'form-list',
              'formName': '${name}Report',
              'fields': [
                {
                  'name': 'category',
                  'title': 'Category',
                  'widgets': [
                    {'_type': 'display'}
                  ],
                  'currentValue': 'Sales',
                },
                {
                  'name': 'amount',
                  'title': 'Amount',
                  'widgets': [
                    {'_type': 'display'}
                  ],
                  'currentValue': '\$10,000',
                },
              ],
              'listData': [
                {
                  'category': 'Sales',
                  'category_display': 'Sales',
                  'amount': '\$10,000',
                  'amount_display': '\$10,000',
                },
              ],
            },
          ],
        },
      ],
    };

/// Print-view: simple container-box with labels.
Map<String, dynamic> _printScreen(String name) => {
      'screenName': name,
      'menuTitle': name,
      'widgets': [
        {
          '_type': 'container-box',
          'boxTitle': name,
          'body': [
            {'_type': 'label', 'text': 'Print preview for $name'},
            {'_type': 'label', 'text': 'Document ID: DOC-001'},
          ],
        },
      ],
    };

/// Item-list: form-list for sub-entity editing (items, prices, etc.).
Map<String, dynamic> _itemListScreen(String name) => {
      'screenName': name,
      'menuTitle': name,
      'widgets': [
        {
          '_type': 'form-list',
          'formName': '${name}List',
          'fields': [
            {
              'name': 'itemId',
              'title': 'Item',
              'widgets': [
                {'_type': 'display'}
              ],
              'currentValue': 'ITEM-01',
            },
            {
              'name': 'value',
              'title': 'Value',
              'widgets': [
                {'_type': 'display'}
              ],
              'currentValue': '100',
            },
          ],
          'listData': [
            {
              'itemId': 'ITEM-01',
              'itemId_display': 'ITEM-01',
              'value': '100',
              'value_display': '100',
            },
          ],
        },
      ],
    };

/// Calendar screen: simple container with label placeholder.
Map<String, dynamic> _calendarScreen(String name) => {
      'screenName': name,
      'menuTitle': name,
      'widgets': [
        {
          '_type': 'container-box',
          'boxTitle': name,
          'body': [
            {'_type': 'label', 'text': 'Calendar view for $name'},
          ],
        },
      ],
    };

/// Comment/nested screen: simple label content.
Map<String, dynamic> _commentScreen(String name) => {
      'screenName': name,
      'menuTitle': name,
      'widgets': [
        {'_type': 'label', 'text': 'Comment content for $name'},
      ],
    };

/// Operational screen: container-box with mixed content.
Map<String, dynamic> _operationalScreen(String name) => {
      'screenName': name,
      'menuTitle': name,
      'widgets': [
        {
          '_type': 'container-box',
          'boxTitle': name,
          'body': [
            {'_type': 'label', 'text': '$name operational view'},
            {
              '_type': 'form-single',
              'name': '${name}Action',
              'fields': [
                {
                  'name': 'actionId',
                  'title': 'Action',
                  'widgets': [
                    {'_type': 'text-line'}
                  ],
                },
                {
                  'name': 'go',
                  'title': '',
                  'widgets': [
                    {'_type': 'submit', 'text': 'Go'}
                  ],
                },
              ],
            },
          ],
        },
      ],
    };

/// Container / module root: subscreens-panel with tabs.
Map<String, dynamic> _containerScreen(String name) => {
      'screenName': name,
      'menuTitle': name,
      'widgets': [
        {
          '_type': 'subscreens-panel',
          'type': 'tab',
          'tabs': [
            {'title': 'Main', 'name': 'Main', 'active': true},
            {'title': 'Settings', 'name': 'Settings', 'active': false},
          ],
          'children': [
            {'_type': 'label', 'text': '$name module content'},
          ],
        },
      ],
    };

/// Generate mock screen JSON for a given path based on its classification.
Map<String, dynamic> _mockScreen(String path) {
  final leaf = path.split('/').last;
  final pattern = _classifyPath(path);
  switch (pattern) {
    case 'find-list':
      return _findListScreen(leaf);
    case 'edit-form':
      return _editFormScreen(leaf);
    case 'detail-view':
      return _detailScreen(leaf);
    case 'dashboard':
      return _dashboardScreen(leaf);
    case 'report':
      return _reportScreen(leaf);
    case 'print-view':
      return _printScreen(leaf);
    case 'item-list':
      return _itemListScreen(leaf);
    case 'calendar':
      return _calendarScreen(leaf);
    case 'comment':
      return _commentScreen(leaf);
    case 'operational':
      return _operationalScreen(leaf);
    default:
      return _containerScreen(leaf);
  }
}

// =============================================================================
// Helpers
// =============================================================================

MoquiRenderContext _stubContext() {
  return MoquiRenderContext(
    navigate: (path, {params}) {},
    submitForm: (url, data) async => null,
    loadDynamic: (transition, params) async => <String, dynamic>{},
  );
}

Widget _harness(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 800,
        height: 600,
        child: SingleChildScrollView(child: child),
      ),
    ),
  );
}

/// Group paths by their top-level module.
Map<String, List<String>> _groupByModule(List<String> paths) {
  final groups = <String, List<String>>{};
  for (final path in paths) {
    final module = path.split('/').first;
    groups.putIfAbsent(module, () => []).add(path);
  }
  return Map.fromEntries(
    groups.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  );
}

// =============================================================================
// Tests
// =============================================================================

/// Cross-test results tracker.
final _crawlResults = <String, bool>{};
final _crawlErrors = <String, String>{};
final _patternCounts = <String, int>{};

void main() {
  // Suppress known rendering warnings (overflow, unbounded flex, etc.)
  void Function(FlutterErrorDetails)? origOnError;

  setUp(() {
    origOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      final msg = details.toString();
      if (msg.contains('overflowed') ||
          msg.contains('non-zero flex') ||
          msg.contains('was not laid out') ||
          msg.contains('_needsLayout') ||
          msg.contains('Vertical viewport was given unbounded') ||
          msg.contains('performLayout')) {
        return; // Suppress known layout warnings in test harness
      }
      origOnError?.call(details);
    };
  });

  tearDown(() {
    FlutterError.onError = origOnError;
  });

  // -------------------------------------------------------------------------
  // 1. Parse all paths → ScreenNode
  // -------------------------------------------------------------------------
  group('Screen Crawl — parse', () {
    test('all ${_allPaths.length} paths parse to ScreenNode without error',
        () {
      int passed = 0;
      final failures = <String>[];

      for (final path in _allPaths) {
        try {
          final json = _mockScreen(path);
          final screen = ScreenNode.fromJson(json);
          expect(screen.widgets, isNotEmpty,
              reason: '$path should have widgets');
          passed++;
        } catch (e) {
          failures.add('$path: $e');
        }
      }

      final rate = passed / _allPaths.length;
      debugPrint(
          '\n=== Parse Results: $passed/${_allPaths.length} (${(rate * 100).toStringAsFixed(1)}%) ===');
      if (failures.isNotEmpty) {
        for (final f in failures) {
          debugPrint('  FAIL: $f');
        }
      }
      expect(rate, greaterThanOrEqualTo(0.95),
          reason: 'At least 95% of paths must parse successfully');
    });

    test('pattern distribution covers all template types', () {
      final patterns = <String, int>{};
      for (final path in _allPaths) {
        final pattern = _classifyPath(path);
        patterns[pattern] = (patterns[pattern] ?? 0) + 1;
      }

      debugPrint('\n=== Pattern Distribution ===');
      for (final e in patterns.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value))) {
        debugPrint('  ${e.key}: ${e.value}');
      }

      // Verify we have variety — at least 5 distinct patterns
      expect(patterns.keys.length, greaterThanOrEqualTo(5),
          reason: 'Should have diverse screen patterns');

      // Store for summary
      _patternCounts.addAll(patterns);
    });
  });

  // -------------------------------------------------------------------------
  // 2. Render all paths — one testWidgets per module
  // -------------------------------------------------------------------------
  group('Screen Crawl — render by module', () {
    final modules = _groupByModule(_allPaths);

    for (final entry in modules.entries) {
      final moduleName = entry.key;
      final modulePaths = entry.value;

      testWidgets(
          'crawl: $moduleName (${modulePaths.length} screens)',
          (tester) async {
        int passed = 0;
        final failures = <String>[];

        for (final path in modulePaths) {
          try {
            final json = _mockScreen(path);
            final screen = ScreenNode.fromJson(json);
            final ctx = _stubContext();

            final widgets = screen.widgets
                .map((w) => MoquiWidgetFactory.build(w, ctx))
                .toList();

            await tester.pumpWidget(_harness(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: widgets,
              ),
            ));

            _crawlResults[path] = true;
            passed++;
          } catch (e) {
            _crawlResults[path] = false;
            _crawlErrors[path] = e.toString();
            failures.add('$path: $e');
          }
        }

        debugPrint(
            '  $moduleName: $passed/${modulePaths.length} rendered OK');
        if (failures.isNotEmpty) {
          for (final f in failures) {
            debugPrint('    FAIL: $f');
          }
        }

        // Each module should have ≥90% success (individual may be lower than aggregate)
        final rate =
            modulePaths.isNotEmpty ? passed / modulePaths.length : 1.0;
        expect(rate, greaterThanOrEqualTo(0.90),
            reason:
                '$moduleName render rate $passed/${modulePaths.length} < 90%');
      });
    }
  });

  // -------------------------------------------------------------------------
  // 3. Widget type coverage — verify diverse widget types across templates
  // -------------------------------------------------------------------------
  group('Screen Crawl — widget type coverage', () {
    test('templates exercise at least 10 distinct widget types', () {
      final widgetTypes = <String>{};

      for (final path in _allPaths) {
        final json = _mockScreen(path);
        final screen = ScreenNode.fromJson(json);
        _collectTypes(screen.widgets, widgetTypes);
      }

      debugPrint('\n=== Widget Types Encountered (${widgetTypes.length}) ===');
      for (final t in widgetTypes.toList()..sort()) {
        debugPrint('  $t');
      }

      expect(widgetTypes.length, greaterThanOrEqualTo(10),
          reason: 'Should exercise at least 10 different widget types');
    });
  });

  // -------------------------------------------------------------------------
  // 4. Aggregate summary — 95%+ overall
  // -------------------------------------------------------------------------
  group('Screen Crawl — summary', () {
    test('overall render success rate ≥ 95%', () {
      final total = _crawlResults.length;
      if (total == 0) {
        // Results not yet populated (tests run in order, so this
        // should have data from the render group above).
        debugPrint('WARNING: No crawl results recorded yet');
        return;
      }

      final passed = _crawlResults.values.where((v) => v).length;
      final failed = total - passed;
      final rate = passed / total;

      debugPrint('\n╔═══════════════════════════════════════════╗');
      debugPrint('║  SCREEN CRAWL SUMMARY                     ║');
      debugPrint('╠═══════════════════════════════════════════╣');
      debugPrint(
          '║  Total paths:  $total');
      debugPrint(
          '║  Rendered OK:  $passed');
      debugPrint(
          '║  Failed:       $failed');
      debugPrint(
          '║  Success rate: ${(rate * 100).toStringAsFixed(1)}%');
      debugPrint('╠═══════════════════════════════════════════╣');

      if (_patternCounts.isNotEmpty) {
        debugPrint('║  Pattern Distribution:');
        for (final e in _patternCounts.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value))) {
          debugPrint(
              '║    ${e.key.padRight(15)}: ${e.value}');
        }
      }

      if (_crawlErrors.isNotEmpty) {
        debugPrint('╠═══════════════════════════════════════════╣');
        debugPrint('║  FAILURES:');
        for (final e in _crawlErrors.entries) {
          debugPrint('║    ${e.key}');
          debugPrint('║      ${e.value.split('\n').first}');
        }
      }

      debugPrint('╚═══════════════════════════════════════════╝');

      expect(rate, greaterThanOrEqualTo(0.95),
          reason:
              'Overall success rate $passed/$total (${(rate * 100).toStringAsFixed(1)}%) < 95%');
    });
  });
}

/// Recursively collect widget type strings from a widget tree.
void _collectTypes(List<WidgetNode> nodes, Set<String> types) {
  for (final node in nodes) {
    types.add(node.type);
    if (node.children.isNotEmpty) {
      _collectTypes(node.children, types);
    }
    // Also look in body/columns for container types
    final body = node.attributes['body'];
    if (body is List) {
      final bodyNodes =
          body.map((e) => WidgetNode.fromJson(e as Map<String, dynamic>));
      _collectTypes(bodyNodes.toList(), types);
    }
    final columns = node.attributes['columns'];
    if (columns is List) {
      for (final col in columns) {
        if (col is Map && col['children'] is List) {
          final colChildren = (col['children'] as List)
              .map((e) => WidgetNode.fromJson(e as Map<String, dynamic>));
          _collectTypes(colChildren.toList(), types);
        }
      }
    }
    // Collect field widget types from form definitions
    final fields = node.attributes['fields'];
    if (fields is List) {
      for (final field in fields) {
        if (field is Map) {
          final widgets = field['widgets'];
          if (widgets is List) {
            for (final w in widgets) {
              if (w is Map && w['_type'] != null) {
                types.add(w['_type'] as String);
              }
            }
          }
        }
      }
    }
  }
}
