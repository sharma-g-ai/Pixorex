"""Help text for the 8-screen SeaStock portal, written for end users.

Each figure names a screenshot; `items` explain its numbered boxes, in the same order as the
boxes recorded in shots.json. build.py refuses to build if the counts differ.
"""

INTRO = {
    'title': 'SeaStock help',
    'lead': (
        'SeaStock shows the paint and thinners on board every vessel, how much has been used, '
        'and what arrived. The crew records stock on the vessel’s tablet; each time the tablet '
        'syncs, the numbers here update. This guide walks through every screen, what each part '
        'shows and what each button does.'
    ),
    'how': [
        'Each screenshot has numbered boxes. The list under it explains each number.',
        'Point at an explanation to light up its box on the screenshot, or click a box to jump to its explanation.',
        'The screenshots are taken as a <b>PPG Admin with access to all customers</b>, who sees every screen and every button. If you have a different role, you see the same screens with only your own customers or vessel, and some screens or buttons are not there.',
        'Where a role sees something different, the guide shows it with its own screenshot (Customer Admin on Overview and Users, a PPG Admin limited to one region on Overview, Ship Admin on Sea Stock) or says so in the text, for example which ways of grouping each role has.',
        'Not sure which screens you have? See <b>Roles</b> below, or the Roles &amp; permissions tab on the Users page.',
    ],
    'preview': (
        'This guide was made from the preview version of SeaStock, which runs on sample data. '
        'Changes you make in the preview are kept until you close the browser tab.'
    ),
}

ROLES = [
    ('PPG Admin', 'PPG staff. With access to all customers, a PPG Admin sees everything and looks after customers, vessels, users and products. A PPG Admin can instead be limited to some regions or some customers (for example the sales team); they see only those customers and cannot change the setup.'),
    ('Customer Admin', 'A shipping company’s Fleet Manager or Procurement. Sees only their own company’s vessels and can add and edit their own company’s users.'),
    ('Ship Admin', 'The Chief Officer of a vessel. Records stock on the vessel’s tablet and, on the website, sees only their own vessel.'),
]

WORDS = [
    ('Sea Stock', 'The paint and thinners on board a vessel.'),
    ('Sync', 'When the vessel’s tablet sends what the crew recorded. Vessels usually sync every 1 to 3 days; numbers on the website are as of each vessel’s last sync.'),
    ('Can and liters', 'Stock is counted in cans. Liters are worked out from the number of cans and the liters in each can.'),
    ('Component type', 'Base or Hardener for two-component paint (2K), or 1K for one-component products, which includes thinners.'),
    ('Article number', 'PPG’s six-digit item number, printed on the label and on the delivery note.'),
    ('Delivery note', 'The paper that comes with a delivery, listing what was sent. The crew scans it, then scans the cans going into the locker.'),
    ('Consumption', 'Cans taken out of the locker for a job. A can that leaves the locker counts as fully used, even if some paint comes back.'),
]

SCREENS = [
    {
        'id': 'sign-in',
        'title': 'Sign in',
        'intro': 'Sign in with your work e-mail and password. Where you land depends on your role: PPG Admins and Customer Admins open on the Overview, Ship Admins open on their vessel’s Sea Stock. If you open any page while signed out, you are asked to sign in first and then taken back to that page.',
        'figures': [
            {'shot': '01-sign-in', 'caption': 'The sign-in page', 'items': [
                'Your work e-mail, the one your administrator registered for you.',
                'Your password.',
                '<b>Sign in</b> checks your e-mail and password and opens SeaStock.',
                '<b>Forgot password?</b> lets you ask for a link to choose a new password.',
                'Preview version only: <b>Reset sample data</b> puts all sample data back to how it started, undoing any changes made in the preview.',
            ]},
            {'shot': '02-sign-in-error', 'caption': 'When sign-in does not work', 'items': [
                'A red message says what went wrong. <b>E-mail or password is incorrect</b>: check both and try again. <b>This account is disabled</b>: ask your administrator to turn it back on. <b>This account is not set up yet</b>: open your invite e-mail and set your password first. <b>Enter your e-mail and password</b>: one of the boxes is empty.',
            ]},
            {'shot': '03-forgot-password', 'caption': 'Forgot password', 'items': [
                'Type your work e-mail.',
                '<b>Send reset link</b> asks for a link to choose a new password.',
                '<b>Back to sign in</b> returns to the sign-in page.',
            ]},
            {'shot': '04-check-email', 'caption': 'After asking for a reset link', 'items': [
                'SeaStock confirms that, if an account exists for that e-mail, a link is on its way; the link works for one hour. <b>Back to sign in</b> returns to the sign-in page. In the preview version no e-mail is actually sent.',
            ]},
        ],
    },
    {
        'id': 'overview',
        'title': 'Overview',
        'intro': 'The first page for PPG Admins and Customer Admins. It shows the headline numbers for everything you can see, and the things that need someone’s attention. Ship Admins do not have this page; they open straight on their vessel.',
        'figures': [
            {'shot': '10-overview', 'caption': 'Overview for a PPG Admin with all customers', 'items': [
                '<b>Scope card</b>: what you can see. “All regions” means every customer. A limited PPG Admin sees their region or customers here, a Customer Admin their company, a Ship Admin their vessel.',
                '<b>Menu</b>: the pages you can open. The <b>Administration</b> part appears only for roles that manage the setup: Customers &amp; vessels and Products for a PPG Admin with all customers, Users for a PPG Admin with all customers and for a Customer Admin.',
                'Your name and role. The arrow on the right signs you out and returns to the sign-in page.',
                'The page title, with your role and what you can see.',
                '<b>Summary tiles</b>, left to right: number of customers (shown only when you can see more than one); number of vessels; total Sea Stock in liters and cans; liters and cans used in the last 30 days; vessels with a late sync or no sync; and items that need review. Tiles with an arrow open the matching page: Vessels and Sea Stock open Sea Stock, Consumed opens Consumption. A number in orange means something needs attention.',
                '<b>Late or no sync</b>: vessels whose tablet has not synced for more than 3 days, or never. Their numbers may be out of date. Each row shows the vessel and its company, its tablet, whether the opening stock count has been done, and when it last synced. Click a vessel name to see its stock.',
                '<b>Negative stock</b>: products where more cans were scanned out than the vessel has on record, which cannot be right. It usually means a delivery was not scanned in, a can was missed in the opening count, or a can was scanned out twice. The crew corrects it with a stock adjustment on the tablet. Click a vessel name to see its stock.',
                '<b>Unrecognised scans</b>: cans the crew scanned whose label did not match any product on the master item list, for example because the article number was misread or the product is new. They are held aside and not counted in Sea Stock until they are matched. Each row shows the vessel and who scanned it, whether it was a receipt or consumption, what was read from the label, the number of cans and when.',
                '<b>Match to article</b> opens a pop-up to say which product the scan really was (see below). Only a PPG Admin with all customers can do this; others see “PPG admin to match”.',
                '<b>Recent activity</b>: the latest things recorded on board, newest first. Each line shows the type (Receipt, Consumption, Adjustment or Baseline), the change in cans and the product, the vessel and time, and the change in liters. <b>All activity</b> opens the Activity page.',
            ]},
            {'shot': '12-overview-customer-admin', 'caption': 'The same page for a Customer Admin', 'items': [
                'The scope card shows your company.',
                'The menu has Users under Administration, to manage your own company’s people.',
                'There is no Customers tile, because you see one company. All numbers and lists cover only your company’s vessels.',
            ]},
            {'shot': '80-ppg-admin-limited', 'caption': 'The same page for a PPG Admin limited to one region', 'items': [
                'The scope card shows the region (or the customers) this person can see. Every number and list covers only those customers.',
                'There is no Administration part in the menu: a limited PPG Admin views and exports, but does not change customers, users or products.',
            ]},
        ],
        'popups': [
            {'shot': '11-match-to-article', 'title': 'Match to article', 'caption': 'Opened from Match to article on an unrecognised scan', 'items': [
                'What the tablet read from the label, and how many cans.',
                'When the product name and shade match a product on the list, SeaStock suggests it: here the article number was most likely misread.',
                'Choose the product the cans really are. Only active products are listed. If it is not there, add it on the Products page first (the link under the list goes there).',
                '<b>Match and post</b> saves the match: the scan leaves the review list and is counted in the vessel’s Sea Stock, as a receipt (cans added) or consumption (cans taken off), as it was scanned. It then shows on the Activity page with who matched it. <b>Cancel</b> closes without changing anything.',
            ]},
        ],
    },
    {
        'id': 'sea-stock',
        'title': 'Sea Stock',
        'intro': 'What is on board right now, as of each vessel’s last sync. You can look at it by product, or roll it up by vessel, customer or region, and download it.',
        'figures': [
            {'shot': '20-sea-stock-by-product', 'caption': 'Sea Stock by product', 'items': [
                '<b>Filters</b>. Region, Customer and Vessel narrow down which vessels are counted; each one appears only when you can choose between more than one. <b>Component type</b> shows only Base, Hardener or 1K products. <b>Search</b> finds products by article number, product name or shade.',
                '<b>Export summary</b> downloads the table you are looking at as a CSV file, which opens in Excel.',
                '<b>Export detail</b> downloads one row for every product on every vessel shown, with region, customer, vessel, IMO number, product details, cans, liters and last sync, so you can build your own totals.',
                '<b>Group by</b>: By product, By vessel, By customer, By region. Customer Admins see By product and By vessel; Ship Admins see their vessel by product only.',
                'Totals for what is shown: number of vessels, cans and liters.',
                'One row per product: article number, product, shade (a dash when the label has none, as for hardeners and thinners), component type, pack size, how many vessels have it, cans and liters. A negative number shows in red and means the record needs correcting (see Negative stock on the Overview).',
                'The total of all rows.',
            ]},
            {'shot': '21-sea-stock-by-vessel', 'caption': 'Sea Stock by vessel', 'items': [
                'Each vessel with its company. Click the vessel name to see that vessel on its own, with its details.',
                'When the vessel last synced. Orange means more than 3 days ago, so its stock may be out of date; “Never synced” means its tablet has not sent anything yet.',
            ]},
            {'shot': '22-sea-stock-by-customer', 'caption': 'Sea Stock by customer', 'items': [
                'One row per customer, with how many vessels, products, cans and liters. <b>Oldest sync</b> is the vessel of that customer that synced longest ago, so you can tell how fresh the total is.',
            ]},
            {'shot': '23-sea-stock-by-region', 'caption': 'Sea Stock by region (PPG Admins only)', 'items': [
                'One row per PPG sales region (APAC, EMEA, USCA), with the same columns as by customer.',
            ]},
            {'shot': '24-sea-stock-one-vessel', 'caption': 'One vessel, picked in the Vessel filter or by clicking its name', 'items': [
                '<b>Vessel details</b>: the vessel’s name, IMO number and vessel ID; its customer and customer ID; its region; its tablet (ID, Android or iOS, app version); the date of its opening stock count; and its last sync. The line underneath reminds you that anything recorded since the last sync shows after the next one.',
                '<b>Consumption →</b> and <b>Activity →</b> open those pages already filtered to this vessel.',
                'When the vessel last synced.',
                'The stock on this vessel, product by product, with the total underneath.',
            ]},
            {'shot': '25-sea-stock-ship-admin', 'caption': 'What a Ship Admin sees', 'items': [
                'A Ship Admin’s menu has Sea Stock, Consumption and Activity, all for their own vessel only.',
                'Their vessel’s details and stock open straight away. There are no region, customer or vessel filters.',
            ]},
            {'shot': '26-sea-stock-no-opening-stock', 'caption': 'A vessel without an opening stock count yet', 'items': [
                'A new vessel starts with an opening count of everything already in its locker, done on the tablet. Until that count is synced, the vessel shows no stock and this message appears.',
            ]},
        ],
    },
    {
        'id': 'consumption',
        'title': 'Consumption',
        'intro': 'How much paint and thinner was taken from the lockers in a period, rolled up the way you need. A can that leaves the locker counts as fully used; cans put back are not scanned.',
        'figures': [
            {'shot': '30-consumption-by-product', 'caption': 'Consumption by product', 'items': [
                '<b>Period</b>: Last 30 days, this month, last month, or Custom dates.',
                '<b>Filters</b>: Region, Customer and Vessel, shown when you can choose between more than one.',
                '<b>Export summary</b> downloads the table you are looking at (name, scans, cans, liters) as a CSV file.',
                '<b>Export detail</b> downloads every consumption scan in the period: date, customer, vessel, vessel ID, product details, cans and liters.',
                '<b>Group by</b>: By product, By vessel, By customer, By region. Customer Admins see By product and By vessel; Ship Admins by product only.',
                'The dates covered and the total cans and liters used.',
                'One row per product (or vessel, customer or region), most liters first. <b>Scans</b> is how many times cans were scanned out; one scan can cover several cans.',
                'The bar shows each row’s liters compared with the biggest row, so the main users stand out.',
                'A reminder of how consumption is counted.',
            ]},
            {'shot': '31-consumption-by-vessel', 'caption': 'Consumption by vessel', 'items': [
                'One row per vessel, so you can see which vessels use the most.',
            ]},
            {'shot': '32-consumption-custom-dates', 'caption': 'Choosing your own dates', 'items': [
                'With <b>Custom dates</b> chosen in Period, pick the first day here…',
                '…and the last day here. Both days are included.',
            ]},
        ],
    },
    {
        'id': 'activity',
        'title': 'Activity',
        'intro': 'Everything recorded on board, with who did it, when, on which tablet and how. It has two tabs: Transactions and Delivery notes.',
        'figures': [
            {'shot': '40-activity-transactions', 'caption': 'Transactions', 'items': [
                'Switch between <b>Transactions</b> (every change to stock) and <b>Delivery notes</b> (each delivery and how it tallied).',
                '<b>Filters</b>: Period; Region, Customer and Vessel; <b>Type</b> (Receipt, Consumption, Adjustment or Baseline); and <b>Source</b> (DN scan, Label scan or Manual adjustment).',
                '<b>Export CSV</b> downloads the rows shown, with all their details.',
                'How many rows match. All times are in UTC.',
                'When the crew recorded it on the tablet, and underneath when it reached SeaStock.',
                'The type. <b>Receipt</b>: cans put into the locker from a delivery. <b>Consumption</b>: cans taken out. <b>Adjustment</b>: a correction the crew made on the tablet, with a reason. <b>Baseline</b>: the opening count when the vessel started using SeaStock.',
                'The product, with its shade, article number, component type and pack size.',
                'The change: cans added in green, cans taken out in orange, and the liters.',
                'Who recorded it and on which tablet.',
                'How it was recorded: <b>DN scan</b> (from a delivery note; click the number to open it), <b>Label scan</b>, or <b>Manual adjustment</b>. Any reason the crew gave is shown underneath.',
            ]},
            {'shot': '41-activity-delivery-notes', 'caption': 'Delivery notes', 'items': [
                'Besides Period and the region, customer and vessel filters: <b>Tally</b> (All, All matched, or With differences) and <b>Search</b> by delivery note number or customer reference.',
                'The delivery note number and its date. Click it to open the delivery note.',
                'How the delivery tallied: <b>All matched</b> when everything on the note was received, or the number of lines that differed.',
                'When the crew confirmed the delivery on the tablet, and who did it. The other columns show the vessel, the customer’s order reference, the number of lines and the cans put into the locker.',
            ]},
        ],
        'popups': [
            {'shot': '42-delivery-note', 'title': 'Delivery note', 'caption': 'Opened from a delivery note number', 'items': [
                '<b>Header</b>, as read from the delivery note: its number and date, the vessel’s IMO number and name, the customer and their order reference; who received it, when it was confirmed on the tablet and when it synced; the number of lines, the cans put into the locker and how many lines differed.',
                '<b>Tally</b>: each line on the note against what was scanned into the locker: the product, the quantity on the note, the quantity received, the difference and the liters received.',
                'The result of each line. <b>Matched</b>: as on the note. <b>Short</b>: fewer received. <b>Over</b>: more received. <b>Not on note</b>: received but not listed. <b>Not received</b>: listed but not delivered.',
                'The reason the crew gave for a difference. The crew sorts out differences on the tablet before confirming; this shows what they decided. <b>Close</b> returns to the list.',
            ]},
        ],
    },
    {
        'id': 'customers-vessels',
        'title': 'Customers & vessels',
        'intro': 'Who PPG supplies, their vessels, and the PPG sales region each customer belongs to. Only PPG Admins with access to all customers have this page. Changes show straight away on every page.',
        'figures': [
            {'shot': '50-customers', 'caption': 'Customers tab', 'items': [
                'Tabs: <b>Customers</b>, <b>Vessels</b> and <b>Regions</b>.',
                '<b>Add customer</b> opens a pop-up to add a new customer.',
                'Filter by Region, or search by name or customer ID.',
                'Each customer with its customer ID, region, number of vessels, number of users (company users and Chief Officers), whether it is Active or Inactive, and when it was added.',
                '<b>Edit</b> opens the same pop-up to change a customer.',
            ]},
            {'shot': '53-vessels', 'caption': 'Vessels tab', 'items': [
                '<b>Add vessel</b> opens a pop-up to add a new vessel.',
                'Filter by Region or Customer, or search by vessel name, vessel ID or IMO number.',
                'The vessel’s tablet: its ID, Android or iOS, and app version. Each vessel has one tablet.',
                'The date of the vessel’s opening stock count, or <b>Not captured</b> if it has not been done.',
                'When the tablet last synced; orange if more than 3 days ago. Each row also has the vessel name (click it to see its stock), IMO number, vessel ID, customer and an <b>Edit</b> button.',
                'A note on how tablets are supplied.',
            ]},
            {'shot': '55-regions', 'caption': 'Regions tab', 'items': [
                'The PPG sales regions, with how many customers, vessels and region-limited PPG Admins each has.',
                '<b>Edit</b> changes a region’s name. Region codes stay the same.',
            ]},
        ],
        'popups': [
            {'shot': '51-add-customer', 'title': 'Add customer', 'caption': 'Opened from Add customer', 'items': [
                'The customer’s name.',
                'The customer ID used in PPG’s own systems.',
                'The PPG sales region the customer belongs to. It decides which region-limited PPG Admins can see it.',
                '<b>Add customer</b> saves it; the button works once all three are filled in. <b>Cancel</b> closes without saving.',
            ]},
            {'shot': '52-edit-customer', 'title': 'Edit customer', 'caption': 'Opened from Edit on a customer', 'items': [
                'The same fields, plus <b>Status</b>: Active or Inactive. <b>Save changes</b> saves.',
            ]},
            {'shot': '54-add-vessel', 'title': 'Add vessel', 'caption': 'Opened from Add vessel, here with an incomplete IMO number', 'items': [
                'The vessel’s name.',
                'The vessel ID used in PPG’s own systems.',
                'The vessel’s IMO number: 7 digits, numbers only. A red message shows until it has 7 digits. Delivery notes are matched to the vessel by IMO number first, then by name.',
                'The customer the vessel belongs to. <b>Add vessel</b> saves once everything is filled in correctly. A new vessel starts with no tablet, no opening stock and no sync. <b>Edit</b> on a vessel opens the same pop-up.',
            ]},
            {'shot': '56-edit-region', 'title': 'Edit region', 'caption': 'Opened from Edit on a region', 'items': [
                'The region’s name. <b>Save changes</b> saves it.',
            ]},
        ],
    },
    {
        'id': 'users',
        'title': 'Users',
        'intro': 'Who can use SeaStock, their role, what they can see, and whether they can sign in. PPG Admins with all customers see everyone; Customer Admins see and manage only their own company’s people.',
        'figures': [
            {'shot': '60-users', 'caption': 'Users tab, for a PPG Admin', 'items': [
                'Tabs: <b>Users</b> and <b>Roles &amp; permissions</b>.',
                '<b>Add user</b> opens a pop-up to add someone and send them an invite.',
                'Filter by Role or Status, or search by name or e-mail.',
                'The user’s role, with their job title underneath.',
                'What the user can see: all regions, a region, chosen customers, their company or their vessel.',
                '<b>Active</b>: can sign in. <b>Invited</b>: has not set up their account yet. <b>Disabled</b>: cannot sign in. Each row also shows the level (PPG, Customer or Vessel), the last sign-in and an <b>Edit</b> button.',
            ]},
            {'shot': '66-users-customer-admin', 'caption': 'Users tab, for a Customer Admin', 'items': [
                'Only your own company’s people. When you add someone, you can make them a Customer Admin or a Ship Admin for one of your vessels.',
            ]},
            {'shot': '65-roles', 'caption': 'Roles & permissions tab', 'items': [
                'The three roles: who holds each one, what they see, and how many people have it.',
                'What each role can do. A tick means yes. The PPG Admin has two columns: one with all customers, one limited to some regions or customers.',
            ]},
        ],
        'popups': [
            {'shot': '61-add-user-ppg-admin', 'title': 'Add user: PPG Admin', 'caption': 'Opened from Add user, with PPG Admin chosen', 'items': [
                'The person’s full name, job title (for example Chief Officer) and work e-mail. They sign in with this e-mail.',
                'The role: PPG Admin, Customer Admin or Ship Admin. The boxes below change with the role.',
                'For a PPG Admin, what they can see: <b>All customers</b> (they also look after the setup), <b>Whole regions</b> or <b>Specific customers</b> (for example the sales team; view only).',
                'Tick the regions (or customers) they can see.',
                '<b>Add and send invite</b> adds them as Invited; it works once every box is filled in. They can sign in after setting up their account from the invite.',
            ]},
            {'shot': '62-add-user-customer-admin', 'title': 'Add user: Customer Admin', 'caption': 'With Customer Admin chosen', 'items': [
                'The company they belong to. For a Customer Admin adding someone, this is fixed to their own company.',
            ]},
            {'shot': '63-add-user-ship-admin', 'title': 'Add user: Ship Admin', 'caption': 'With Ship Admin chosen', 'items': [
                'The vessel they look after. A Customer Admin can pick only their own company’s vessels.',
            ]},
            {'shot': '64-edit-user', 'title': 'Edit user', 'caption': 'Opened from Edit on a user', 'items': [
                'The same boxes, plus <b>Status</b>. Set <b>Disabled</b> to stop someone signing in; set <b>Active</b> to let them back in. <b>Save changes</b> saves.',
            ]},
        ],
    },
    {
        'id': 'products',
        'title': 'Products',
        'intro': 'The PPG products SeaStock recognises, and how the tablet reads can labels. Only PPG Admins with access to all customers have this page.',
        'figures': [
            {'shot': '70-master-item-list', 'caption': 'Master item list tab', 'items': [
                'Tabs: <b>Master item list</b> and <b>Label schema</b>.',
                '<b>Bulk load</b> opens a pop-up to add many products at once from PPG’s list.',
                '<b>Add item</b> opens a pop-up to add one product.',
                'Filter by Component type and Status (Active, Retired or All), or search by article number, product or shade. Only active products show at first.',
                'Base, Hardener or 1K.',
                '<b>Pack size</b> as printed on the can, and <b>Unit volume</b>, the liters in each can, which SeaStock uses to turn cans into liters. Each row also shows the article number, product, shade and status.',
                '<b>Retire</b> takes a product off the list for new scans (it asks first). On a retired product, <b>Restore</b> brings it back.',
            ]},
            {'shot': '75-label-schema', 'caption': 'Label schema tab', 'items': [
                'The version the tablets use now, when it was published and by whom.',
                '<b>Publish</b> makes your changes the next version, used by every tablet. <b>Discard</b> throws your changes away. Both work only when there are changes.',
                'The details the tablet reads from each can label: whether each one must always be there, what it is used for, and the rule it must follow. <b>Edit</b> changes a field’s rules.',
                'How the component type is decided: one-component products, including thinners, are 1K; two-component products are Base or Hardener, as printed on the label.',
                'How a scanned can is matched to a product: by article number first; if that cannot be read, by product name and shade; if neither matches, the scan is held for review on the Overview.',
            ]},
        ],
        'popups': [
            {'shot': '71-add-item', 'title': 'Add item', 'caption': 'Opened from Add item, here with an article number already in use', 'items': [
                'The six-digit article number. A red message shows if it is already on the list. Next to it, the pack size in liters; above the product type you also enter the product name and the shade (left empty for hardeners and thinners).',
                '<b>Product type</b>: one component (1K) or two components (2K).',
                '<b>Component type</b>: set to 1K automatically for a 1K product; for a 2K product choose Base or Hardener. <b>Add item</b> works once everything is filled in correctly.',
            ]},
            {'shot': '72-bulk-load-empty', 'title': 'Bulk load', 'caption': 'Opened from Bulk load', 'items': [
                'Choose PPG’s product list as an Excel (.xlsx) or CSV file, with the columns article number, product, shade, component type, pack size and unit volume.',
            ]},
            {'shot': '73-bulk-load-preview', 'title': 'Bulk load: check before loading', 'caption': 'After choosing a file', 'items': [
                'What the file would do: how many products are new, how many are already on the list, and how many rows have errors and will be skipped, with the reason. Products missing from the file are not retired.',
                '<b>Load … new items</b> adds the new products. In the preview version the file’s contents are a fixed sample.',
            ]},
            {'shot': '74-retire-item', 'title': 'Retire item', 'caption': 'Opened from Retire on a product', 'items': [
                '<b>Retire item</b> confirms. Cans already on board stay in Sea Stock; new scans of this product are held for review. <b>Cancel</b> keeps it active.',
            ]},
            {'shot': '76-edit-label-field', 'title': 'Edit a label field', 'caption': 'Opened from Edit on a label field', 'items': [
                '<b>Required</b>: Always, Where present, or Base and 1K only.',
                '<b>Rule</b>: what the value must look like. <b>Save to draft</b> keeps the change without sending it to tablets yet.',
            ]},
            {'shot': '77-label-schema-unpublished', 'title': 'Unpublished changes', 'caption': 'After saving a change to draft', 'items': [
                '<b>Unpublished changes</b> means your edits are not on the tablets yet. Click <b>Publish version …</b> to send them, or <b>Discard</b> to throw them away.',
            ]},
        ],
    },
]
