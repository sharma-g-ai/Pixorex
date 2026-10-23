import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';

const config = window.CLIENT_PORTAL_CONFIG;

const authPanel = document.getElementById('auth-panel');
const mainApp = document.getElementById('main-app');
const loginForm = document.getElementById('login-form');
const magicLinkBtn = document.getElementById('magic-link-btn');
const authMessage = document.getElementById('auth-message');
const recordsBody = document.getElementById('records-body');
const emptyState = document.getElementById('empty-state');
const searchInput = document.getElementById('search-input');
const typeFilter = document.getElementById('type-filter');
const dateFrom = document.getElementById('date-from');
const dateTo = document.getElementById('date-to');
const clearFilters = document.getElementById('clear-filters');
const sessionEmail = document.getElementById('session-email');
const refreshBtn = document.getElementById('refresh-btn');
const exportBtn = document.getElementById('export-btn');
const logoutBtn = document.getElementById('logout-btn');
const recordCount = document.getElementById('record-count');
const appTitle = document.getElementById('app-title');

const detailPanel = document.getElementById('detail-panel');
const detailClose = document.getElementById('detail-close');
const detailTitle = document.getElementById('detail-title');
const detailSchemaLabel = document.getElementById('detail-schema-label');
const detailFields = document.getElementById('detail-fields');
const detailExtraSection = document.getElementById('detail-extra-section');
const detailExtraFields = document.getElementById('detail-extra-fields');
const detailImageWrap = document.getElementById('detail-image-wrap');
const detailImage = document.getElementById('detail-image');
const imgZoomBtn = document.getElementById('img-zoom-btn');
const imgCounter = document.getElementById('img-counter');
const detailImageThumbs = document.getElementById('detail-image-thumbs');

// View switcher (Records vs Paint Basket vs Schemas)
const viewTabs = document.getElementById('view-tabs');
const recordsView = document.getElementById('records-view');
const recordsFilters = document.getElementById('records-filters');
const basketView = document.getElementById('basket-view');
const basketFilters = document.getElementById('basket-filters');
const basketTableBody = document.getElementById('basket-body');
const basketEmpty = document.getElementById('basket-empty');
const basketSearch = document.getElementById('basket-search');
const basketSort = document.getElementById('basket-sort');
const basketSortDir = document.getElementById('basket-sort-dir');
const basketKpis = document.getElementById('basket-kpis');
const schemasView = document.getElementById('schemas-view');
const schemaList = document.getElementById('schema-list');
const customSchemaForm = document.getElementById('custom-schema-form');
const schemaDisplayName = document.getElementById('schema-display-name');
const schemaNameInput = document.getElementById('schema-name');
const schemaDescription = document.getElementById('schema-description');
const schemaFieldsList = document.getElementById('schema-fields-list');
const schemaAddFieldBtn = document.getElementById('schema-add-field');

// Schema save confirmation modal (duplicate key / duplicate display name)
const schemaConfirmModal = document.getElementById('schema-confirm-modal');
const schemaConfirmTitle = document.getElementById('schema-confirm-title');
const schemaConfirmBody = document.getElementById('schema-confirm-body');
const schemaConfirmAction = document.getElementById('schema-confirm-action');
const schemaConfirmCancel = document.getElementById('schema-confirm-cancel');
const schemaLoadExampleBtn = document.getElementById('schema-load-example');
const schemaClearFormBtn = document.getElementById('schema-clear-form');

// AI schema assist (From image tab)
const schemaModeTabs = document.getElementById('schema-mode-tabs');
const schemaImageDrop = document.getElementById('schema-image-drop');
const schemaImageInput = document.getElementById('schema-image-input');
const schemaImageDropEmpty = document.getElementById('schema-image-drop-empty');
const schemaImageDropLoaded = document.getElementById('schema-image-drop-loaded');
const schemaImageThumbnails = document.getElementById('schema-image-thumbnails');
const schemaImageStatusText = document.getElementById('schema-image-status-text');
const schemaImageClear = document.getElementById('schema-image-clear');
const schemaMessage = document.getElementById('schema-message');
const saveSchemaBtn = document.getElementById('save-schema-btn');

// Lightbox (full-screen zoom view with prev/next nav)
const lightbox = document.getElementById('lightbox');
const lightboxImg = document.getElementById('lightbox-img');
const lightboxClose = document.getElementById('lightbox-close');
const lightboxPrevBtn = document.getElementById('lightbox-prev');
const lightboxNextBtn = document.getElementById('lightbox-next');
const lightboxCounter = document.getElementById('lightbox-counter');
const lightboxNewtab = document.getElementById('lightbox-newtab');

let supabase;
let allRecords = [];
let selectedRecord = null;
let recordsSnapshot = '';
let realtimeChannel = null;
let pendingRealtimeRefresh = null;
let backgroundRefreshInFlight = false;
let backgroundRefreshQueued = false;

// Signed storage URLs are short-lived. Cache them for the page session and
// force-refresh on image load errors so a manual browser refresh is not needed.
const IMAGE_SIGN_SECONDS = 3600;
const IMAGE_CACHE_MS = 55 * 60 * 1000;
const imageUrlCache = new Map();

// Current view: 'records' (approved records), 'paint-basket' (paint lookup), or 'schemas'.
let currentView = 'records';

// Paint basket state — rows from paint_basket_view, loaded on demand
let basketRows = [];
let basketLastLoadedAt = 0;

// Split sort state: which column, and which direction. The direction button
// shows the current direction and toggles on click. Selecting a new column
// resets the direction to that column's natural default (descending for
// counts and dates, ascending for text).
let currentBasketSort = 'scanned_qty';
let currentBasketSortDir = 'desc';

const BASKET_SORT_DEFAULT_DIR = {
  scanned_qty:     'desc',
  last_scanned_at: 'desc',
  available_qty:   'desc',
  upc:             'asc',
  product_name:    'asc',
  brand:           'asc',
  stock_status:    'asc',
};

function recordScannedAt(record) {
  return record?.created_at || record?.approved_at || '';
}

function recordApprovedAt(record) {
  return record?.approved_at || record?.created_at || '';
}

function recordIdentifier(record) {
  const fields = record?._fields || {};
  if ((record?.schema_name || record?.record_type) === 'paint_label') {
    return fields.upc_barcode || fields.product_code || fields.part_no || fields.batch_number || '';
  }
  return fields.frame_no || fields.serial_no || fields.part_no || fields.product_code || fields.batch_number || '';
}

// Columns that should compare as numbers rather than strings
const NUMERIC_SORT_KEYS = new Set(['scanned_qty', 'available_qty']);
const STOCK_STATUS_RANK = {
  in_stock: 0,
  low_stock: 1,
  out_of_stock: 2,
  not_in_inventory: 3,
};

function stockStatusLabel(status) {
  return {
    in_stock: 'In stock',
    low_stock: 'Low stock',
    out_of_stock: 'Out of stock',
    not_in_inventory: 'Not in inventory',
  }[status] || 'Unknown';
}

function stockStatusClass(status) {
  return `stock-status stock-${status || 'unknown'}`;
}

function basketThumbId(row) {
  const key = String(row?.upc || 'unknown').replace(/[^a-zA-Z0-9_-]/g, '-');
  return `basket-thumb-${key}`;
}

function sortBasketRows(rows, key, dir) {
  const multiplier = dir === 'asc' ? 1 : -1;
  const isNumeric = NUMERIC_SORT_KEYS.has(key);

  const valueOf = (row) => {
    const raw = row?.[key];
    if (isNumeric) return Number(raw ?? 0);
    if (key === 'stock_status') return STOCK_STATUS_RANK[raw] ?? 99;
    return String(raw ?? '').toLowerCase();
  };

  return [...rows].sort((a, b) => {
    const av = valueOf(a);
    const bv = valueOf(b);
    if (av < bv) return -1 * multiplier;
    if (av > bv) return  1 * multiplier;
    // Stable tiebreaker: UPC ascending
    return String(a.upc || '').localeCompare(String(b.upc || ''));
  });
}

function updateBasketSortDirButton() {
  const arrow = basketSortDir.querySelector('.sort-dir-arrow');
  const label = basketSortDir.querySelector('.sort-dir-label');
  if (arrow) arrow.textContent = currentBasketSortDir === 'asc' ? '\u2191' : '\u2193';
  if (label) label.textContent = currentBasketSortDir === 'asc' ? 'Asc' : 'Desc';
  basketSortDir.dataset.dir = currentBasketSortDir;
}

function shouldAutoRefresh() {
  return supabase && mainApp && !mainApp.hidden && document.visibilityState === 'visible';
}

async function runBackgroundRefresh(reason = 'background') {
  if (currentView === 'schemas') return;
  if (!shouldAutoRefresh()) return;

  if (backgroundRefreshInFlight) {
    backgroundRefreshQueued = true;
    return;
  }

  backgroundRefreshInFlight = true;
  try {
    await refreshCurrentView({ quiet: true, background: true });
  } catch (error) {
    console.warn(`Background refresh failed after ${reason}:`, error);
  } finally {
    backgroundRefreshInFlight = false;
    if (backgroundRefreshQueued) {
      backgroundRefreshQueued = false;
      runBackgroundRefresh(`${reason} queued`);
    }
  }
}

function schedulePortalDataRefresh(reason = 'data-change') {
  // Keep Schemas stable: no background refresh while a user is reading or
  // editing templates, so expanded cards and form state are not disturbed.
  if (currentView === 'schemas') return;
  if (!shouldAutoRefresh()) return;

  if (pendingRealtimeRefresh) {
    window.clearTimeout(pendingRealtimeRefresh);
  }

  // A single mobile submission touches records, record_images, and
  // record_approved. Debounce the events so the dashboard refreshes once
  // after the approved row is likely visible in the read view.
  pendingRealtimeRefresh = window.setTimeout(async () => {
    pendingRealtimeRefresh = null;
    await runBackgroundRefresh(reason);
  }, 500);
}

function setupRealtimeRefresh() {
  if (!supabase || realtimeChannel) return;

  realtimeChannel = supabase
    .channel('client-portal-data-refresh')
    .on('postgres_changes', { event: '*', schema: 'public', table: 'records' }, () => {
      schedulePortalDataRefresh('records change');
    })
    .on('postgres_changes', { event: '*', schema: 'public', table: 'record_approved' }, () => {
      schedulePortalDataRefresh('approved record change');
    })
    .on('postgres_changes', { event: '*', schema: 'public', table: 'record_images' }, () => {
      schedulePortalDataRefresh('record image change');
    })
    .subscribe((status) => {
      if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') {
        console.warn('Realtime refresh channel status:', status);
      }
    });
}

async function teardownRealtimeRefresh() {
  if (pendingRealtimeRefresh) {
    window.clearTimeout(pendingRealtimeRefresh);
    pendingRealtimeRefresh = null;
  }
  backgroundRefreshQueued = false;
  if (!realtimeChannel || !supabase) return;

  const channel = realtimeChannel;
  realtimeChannel = null;
  try {
    await supabase.removeChannel(channel);
  } catch (error) {
    console.warn('Failed to remove realtime refresh channel:', error);
  }
}

// Images for the currently-open detail record. Shared between the inline
// preview (main image + thumb strip) and the fullscreen lightbox so that
// prev/next nav always knows the full set and the current index.
let currentImageUrls = [];
let currentImagePaths = [];
let currentImageIndex = 0;
let detailImageLoadSeq = 0;

// ── Schema registry ───────────────────────────────────────────
// Source of truth: the schema_templates and prompt_templates tables.
// Schemas are fetched at init and again after auth so client-owned custom
// templates are available when RLS is scoped to the signed-in email.
//
// Review decisions rely entirely on per-field GPT confidence written by the
// Flutter capture flow. Schema-level hints are not used here.

const SYSTEM_SCHEMA_NAMES = [
  'motor',
  'generator',
  'transformer',
  'chiller',
  'equipment_label',
  'paint_label',
  'other',
];

const SCHEMAS = {};                // name → schema object
let SCHEMA_NAMES = [...SYSTEM_SCHEMA_NAMES];
let UNION_FIELDS = [];             // ordered union of every field across all schemas (for CSV)

// Fields that should span full width in detail view (long-form text)
const WIDE_FIELDS_BY_KEY = new Set([
  'description', 'hazardous_locations', 'connection_info', 'notes',
  'specification', 'specifications', 'safety_warnings',
  'extra_fields',
]);

const EXTRA_FIELD_SCHEMA_ALIASES = {
  lot: ['batch_number'],
  lot_no: ['batch_number'],
  lot_number: ['batch_number'],
  batch: ['batch_number'],
  batch_no: ['batch_number'],
  batch_number: ['batch_number'],
  expiry: ['expiry_date'],
  exp_date: ['expiry_date'],
  expiration_date: ['expiry_date'],
  expiry_date: ['expiry_date'],
  use_by_date: ['expiry_date'],
  date_of_packaging: ['manufacturing_date'],
  packaging_date: ['manufacturing_date'],
  packaged_date: ['manufacturing_date'],
  mfg_date: ['manufacturing_date'],
  manufacture_date: ['manufacturing_date'],
  manufacturing_date: ['manufacturing_date'],
  net_contents: ['size'],
  net_content: ['size'],
  contents: ['size'],
  package_size: ['size'],
  part_number: ['product_code', 'part_no'],
  part_no: ['product_code', 'part_no'],
  product_code: ['product_code'],
  upc: ['upc_barcode', 'barcode'],
  upc_code: ['upc_barcode', 'barcode'],
  upc_barcode: ['upc_barcode', 'barcode'],
};

// Heuristic: treat as wide if label is long-form OR value is long
function isWideField(key, value) {
  if (WIDE_FIELDS_BY_KEY.has(key)) return true;
  return String(value || '').length > 40;
}

function normalizeFieldKey(key) {
  return String(key || '')
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');
}

function normalizeFieldValue(value) {
  return String(value ?? '')
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '');
}

function isDuplicateExtraField(extraKey, extraValue, fields) {
  const extraValueNorm = normalizeFieldValue(extraValue);
  if (!extraValueNorm) return false;

  const normalizedKey = normalizeFieldKey(extraKey);
  const candidateKeys = new Set([
    normalizedKey,
    ...(EXTRA_FIELD_SCHEMA_ALIASES[normalizedKey] || []),
  ]);

  for (const [fieldKey, fieldValue] of Object.entries(fields || {})) {
    if (!candidateKeys.has(normalizeFieldKey(fieldKey))) continue;
    if (normalizeFieldValue(fieldValue) === extraValueNorm) return true;
  }

  return false;
}

function parseJsonArray(value) {
  if (Array.isArray(value)) return value.map(v => String(v)).filter(Boolean);
  if (typeof value === 'string') {
    const text = value.trim();
    if (!text) return [];
    try {
      const parsed = JSON.parse(text);
      if (Array.isArray(parsed)) return parseJsonArray(parsed);
    } catch (_) {}
    return text.split(',').map(v => v.trim()).filter(Boolean);
  }
  return [];
}

function parseJsonObject(value) {
  if (value && typeof value === 'object' && !Array.isArray(value)) return value;
  if (typeof value === 'string') {
    const text = value.trim();
    if (!text) return {};
    try {
      const parsed = JSON.parse(text);
      if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) return parsed;
    } catch (_) {}
  }
  return {};
}

async function loadSchemas() {
  const fullColumns = `
      schema_name,
      display_name,
      description,
      fields,
      field_descriptions,
      mandatory_fields,
      prompt_key,
      prompt_version,
      schema_version,
      is_system,
      is_active,
      client_email
    `;
  const legacyColumns = `
      schema_name,
      display_name,
      description,
      fields,
      field_descriptions,
      always_review,
      prompt_key,
      prompt_version,
      schema_version,
      is_system,
      is_active,
      client_email
    `;

  let { data, error } = await supabase
    .from('schema_templates')
    .select(fullColumns)
    .eq('is_active', true)
    .order('is_system', { ascending: false })
    .order('display_name', { ascending: true });

  // Backward compatibility for DBs that have not yet re-run 01_complete_setup.sql
  // with the mandatory_fields column. Retry without it so the portal still
  // works until the migration is applied.
  if (error && String(error.message || '').toLowerCase().includes('mandatory_fields')) {
    console.warn('mandatory_fields column missing — falling back to legacy select. Re-run 01_complete_setup.sql to apply the rename.');
    ({ data, error } = await supabase
      .from('schema_templates')
      .select(legacyColumns)
      .eq('is_active', true)
      .order('is_system', { ascending: false })
      .order('display_name', { ascending: true }));
  }

  if (error) {
    console.error('Failed to load schema templates:', error);
    authMessage.textContent = 'Unable to load schema templates. Please try again later.';
    throw error;
  }

  for (const key of Object.keys(SCHEMAS)) delete SCHEMAS[key];

  for (const row of data || []) {
    const name = row.schema_name;
    if (!name) continue;
    SCHEMAS[name] = {
      equipment_type: name,
      schema_name: name,
      display_name: row.display_name || getDisplayName(name),
      description: row.description || '',
      fields: parseJsonArray(row.fields),
      field_descriptions: parseJsonObject(row.field_descriptions),
      mandatory_fields: parseJsonArray(row.mandatory_fields ?? row.always_review),
      prompt_key: row.prompt_key || name,
      prompt_version: row.prompt_version || '1.0',
      schema_version: row.schema_version || '1.0',
      is_system: row.is_system === true,
      client_email: row.client_email || '',
    };
  }

  SCHEMA_NAMES = Object.keys(SCHEMAS);

  // Build ordered union of all fields across schemas (for CSV export)
  const seen = new Set();
  const union = [];
  for (const name of SCHEMA_NAMES) {
    const schema = SCHEMAS[name];
    if (!schema) continue;
    for (const field of schema.fields || []) {
      // Skip meta-bucket fields
      if (field === 'extra_fields') continue;
      if (!seen.has(field)) {
        seen.add(field);
        union.push(field);
      }
    }
  }
  UNION_FIELDS = union;
  renderSchemaList();
  console.log(`Loaded ${Object.keys(SCHEMAS).length} schemas from Supabase, ${UNION_FIELDS.length} union fields`);
}

function getSchemaForRecord(record) {
  const name = record?.schema_name || record?.record_type;
  return SCHEMAS[name] || SCHEMAS.other || { fields: UNION_FIELDS };
}

function getSchemaFields(record) {
  const schema = getSchemaForRecord(record);
  return (schema.fields || []).filter(f => f !== 'extra_fields');
}

// Display name mapping — matches mobile app schemas.
// Falls back to schema.display_name if the schema is loaded, then to a title-cased name.
const EQUIPMENT_DISPLAY_NAMES_FALLBACK = {
  motor: 'Motor Nameplate',
  generator: 'AC Generator Nameplate',
  transformer: 'Current Transformer Nameplate',
  chiller: 'HVAC Chiller Nameplate',
  equipment_label: 'Equipment Label',
  paint_label: 'Paint / Chemical Label',
  other: 'Other',
};

function getDisplayName(type) {
  if (!type) return 'Unknown';
  if (SCHEMAS[type]?.display_name) return SCHEMAS[type].display_name;
  return EQUIPMENT_DISPLAY_NAMES_FALLBACK[type]
    || (type.charAt(0).toUpperCase() + type.slice(1).replace(/_/g, ' '));
}

function normalizeSchemaName(value) {
  return String(value || '')
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/_+/g, '_')
    .replace(/^_+|_+$/g, '');
}

function createSchemaFieldRow({ name = '', description = '', mandatory = false, focus = false } = {}) {
  if (!schemaFieldsList) return null;
  const row = document.createElement('div');
  row.className = 'field-row';

  const nameInput = document.createElement('input');
  nameInput.type = 'text';
  nameInput.className = 'field-row-name';
  nameInput.placeholder = 'field_name';
  nameInput.value = name;
  nameInput.autocapitalize = 'off';
  nameInput.autocomplete = 'off';
  nameInput.spellcheck = false;

  const descInput = document.createElement('input');
  descInput.type = 'text';
  descInput.className = 'field-row-desc';
  descInput.placeholder = 'Optional description';
  descInput.value = description;

  const mandatoryLabel = document.createElement('label');
  mandatoryLabel.className = 'field-row-mandatory';
  mandatoryLabel.title = 'Mark this field as mandatory. Missing values will be flagged for review.';
  const mandatoryInput = document.createElement('input');
  mandatoryInput.type = 'checkbox';
  mandatoryInput.className = 'field-row-mandatory-input';
  mandatoryInput.checked = mandatory === true;
  mandatoryLabel.setAttribute('aria-label', 'Mandatory field');
  const mandatoryText = document.createElement('span');
  mandatoryText.textContent = 'Required';
  mandatoryLabel.appendChild(mandatoryInput);
  mandatoryLabel.appendChild(mandatoryText);

  const removeBtn = document.createElement('button');
  removeBtn.type = 'button';
  removeBtn.className = 'field-row-remove';
  removeBtn.title = 'Remove field';
  removeBtn.setAttribute('aria-label', 'Remove field');
  removeBtn.innerHTML = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="M18 6L6 18M6 6l12 12"/></svg>';
  removeBtn.addEventListener('click', () => {
    if (schemaFieldsList.children.length > 1) {
      row.remove();
      updateFieldRowRemoveButtons();
    }
  });

  // Pressing Enter in the description input appends a new row for fast entry.
  descInput.addEventListener('keydown', (event) => {
    if (event.key === 'Enter') {
      event.preventDefault();
      if (row === schemaFieldsList.lastElementChild) {
        createSchemaFieldRow({ focus: true });
      } else {
        row.nextElementSibling?.querySelector('.field-row-name')?.focus();
      }
    }
  });

  row.appendChild(nameInput);
  row.appendChild(descInput);
  row.appendChild(mandatoryLabel);
  row.appendChild(removeBtn);
  schemaFieldsList.appendChild(row);
  updateFieldRowRemoveButtons();
  if (focus) nameInput.focus();
  return row;
}

function updateFieldRowRemoveButtons() {
  if (!schemaFieldsList) return;
  const disable = schemaFieldsList.children.length <= 1;
  schemaFieldsList.querySelectorAll('.field-row-remove').forEach((btn) => {
    btn.disabled = disable;
  });
}

function readSchemaFieldsFromRows() {
  const fields = [];
  const descriptions = {};
  const mandatoryFields = [];
  const seen = new Set();
  if (!schemaFieldsList) return { fields, descriptions, mandatoryFields };
  schemaFieldsList.querySelectorAll('.field-row').forEach((row) => {
    const nameInput = row.querySelector('.field-row-name');
    const descInput = row.querySelector('.field-row-desc');
    const mandatoryInput = row.querySelector('.field-row-mandatory-input');
    const key = normalizeSchemaName(nameInput?.value || '');
    if (!key || seen.has(key)) return;
    fields.push(key);
    seen.add(key);
    const desc = (descInput?.value || '').trim();
    if (desc) descriptions[key] = desc;
    if (mandatoryInput?.checked) mandatoryFields.push(key);
  });
  return { fields, descriptions, mandatoryFields };
}

function resetSchemaFieldRows() {
  if (!schemaFieldsList) return;
  schemaFieldsList.replaceChildren();
  createSchemaFieldRow();
}

function setSchemaMessage(message, type = '') {
  schemaMessage.textContent = message || '';
  schemaMessage.classList.toggle('error', type === 'error');
  schemaMessage.classList.toggle('success', type === 'success');
}

function schemaAssistUserMessage(message) {
  const text = String(message || '').trim();
  if (!text) {
    return 'Automatic schema generation is unavailable. You can still enter the schema manually.';
  }
  if (/openai|api[_\s-]?key|secret|bearer|authorization|provider|edge function|function/i.test(text)) {
    return 'Automatic schema generation is unavailable. You can still enter the schema manually.';
  }
  return text;
}

// ── AI schema assist ──────────────────────────────────────────
// Uses a Supabase Edge Function to suggest a schema from a photo. Provider
// credentials stay server-side and are never exposed to the portal.

const MAX_IMAGE_BYTES = 10 * 1024 * 1024;
const MAX_SCHEMA_ASSIST_IMAGES = 3;
const SCHEMA_ASSIST_IMAGE_MAX_DIMENSION = 1400;
const SCHEMA_ASSIST_IMAGE_QUALITY = 0.82;
const SCHEMA_ASSIST_TIMEOUT_MS = 90000;
const schemaAssistFunction = String(config?.schemaAssistFunction ?? 'schema-assist').trim();
const schemaAssistUrl = String(config?.schemaAssistUrl ?? '').trim();
const schemaAssistMode = schemaAssistUrl ? 'url' : 'supabase-function';
const hasAiAssist = schemaAssistFunction.length > 0 || schemaAssistUrl.length > 0;
const aiAssistModel = config?.aiAssistModel || 'gpt-4.1-mini';
const portalBuild = '20260415-schema-clear';

window.__schemaAssistDebug = {
  portalBuild,
  hasAiAssist,
  schemaAssistMode,
  schemaAssistFunction,
  aiAssistModel,
};
console.info('Schema assist config', window.__schemaAssistDebug);

function setSchemaImageStatus(message, state = '') {
  if (!schemaImageStatusText) return;
  schemaImageStatusText.textContent = message || '';
  schemaImageStatusText.classList.toggle('is-working', state === 'working');
  schemaImageStatusText.classList.toggle('is-success', state === 'success');
  schemaImageStatusText.classList.toggle('is-error', state === 'error');
}

function showImageDropLoaded(images) {
  if (!schemaImageDrop) return;
  schemaImageThumbnails.replaceChildren();
  for (const [index, image] of images.entries()) {
    const img = document.createElement('img');
    img.className = 'schema-image-thumbnail';
    img.src = image.dataUrl;
    img.alt = `Selected label image ${index + 1}`;
    img.title = image.name || `Image ${index + 1}`;
    schemaImageThumbnails.appendChild(img);
  }
  schemaImageDropEmpty.hidden = true;
  schemaImageDropLoaded.hidden = false;
}

function resetImageDrop() {
  if (!schemaImageDrop) return;
  schemaImageThumbnails.replaceChildren();
  schemaImageDropEmpty.hidden = false;
  schemaImageDropLoaded.hidden = true;
  schemaImageInput.value = '';
  setSchemaImageStatus('');
}

function setSchemaMode(mode) {
  if (!schemaModeTabs) return;
  schemaModeTabs.querySelectorAll('.schema-mode-tab').forEach((btn) => {
    const isActive = btn.dataset.mode === mode;
    btn.classList.toggle('active', isActive);
    btn.setAttribute('aria-selected', String(isActive));
  });
  if (schemaImageDrop) {
    schemaImageDrop.hidden = mode !== 'image';
  }
}

function readFileAsDataUrl(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result);
    reader.onerror = () => reject(reader.error || new Error('Could not read file.'));
    reader.readAsDataURL(file);
  });
}

async function resizeImageDataUrl(dataUrl) {
  return new Promise((resolve) => {
    const img = new Image();
    img.onload = () => {
      const { width, height } = img;
      const largestSide = Math.max(width, height);
      if (!width || !height || largestSide <= SCHEMA_ASSIST_IMAGE_MAX_DIMENSION) {
        resolve(dataUrl);
        return;
      }

      const scale = SCHEMA_ASSIST_IMAGE_MAX_DIMENSION / largestSide;
      const canvas = document.createElement('canvas');
      canvas.width = Math.max(1, Math.round(width * scale));
      canvas.height = Math.max(1, Math.round(height * scale));
      const ctx = canvas.getContext('2d', { alpha: false });
      if (!ctx) {
        resolve(dataUrl);
        return;
      }
      ctx.fillStyle = '#FFFFFF';
      ctx.fillRect(0, 0, canvas.width, canvas.height);
      ctx.imageSmoothingEnabled = true;
      ctx.imageSmoothingQuality = 'high';
      ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
      resolve(canvas.toDataURL('image/jpeg', SCHEMA_ASSIST_IMAGE_QUALITY));
    };
    img.onerror = () => resolve(dataUrl);
    img.src = dataUrl;
  });
}

function withTimeout(promise, timeoutMs) {
  let timeoutId;
  const timeoutPromise = new Promise((_, reject) => {
    timeoutId = window.setTimeout(() => {
      reject(new Error('Automatic schema generation timed out. Try a clearer cropped image, or enter fields manually.'));
    }, timeoutMs);
  });
  return Promise.race([promise, timeoutPromise]).finally(() => {
    window.clearTimeout(timeoutId);
  });
}

async function handleSchemaImageFiles(fileList) {
  const files = Array.from(fileList || []).filter(Boolean);
  if (!files.length) return;
  if (files.length > MAX_SCHEMA_ASSIST_IMAGES) {
    setSchemaImageStatus(`Choose up to ${MAX_SCHEMA_ASSIST_IMAGES} images for one schema.`, 'error');
    return;
  }
  for (const file of files) {
    if (!file.type || !file.type.startsWith('image/')) {
      setSchemaImageStatus('Please choose image files only.', 'error');
      return;
    }
    if (file.size > MAX_IMAGE_BYTES) {
      setSchemaImageStatus(`"${file.name || 'Image'}" is larger than 10 MB.`, 'error');
      return;
    }
  }

  let images;
  try {
    images = await Promise.all(files.map(async (file) => ({
      name: file.name || '',
      dataUrl: await readFileAsDataUrl(file),
    })));
  } catch (err) {
    setSchemaImageStatus('Could not read one of the files.', 'error');
    return;
  }

  showImageDropLoaded(images);

  if (!hasAiAssist) {
    setSchemaImageStatus('Images selected. Automatic schema generation is not configured in this deployment, so add fields manually or use Load example.', 'error');
    return;
  }

  const countLabel = images.length === 1 ? 'image' : `${images.length} images`;
  setSchemaImageStatus(`Optimizing ${countLabel} and analyzing label schema…`, 'working');

  try {
    const optimizedDataUrls = await Promise.all(
      images.map((image) => resizeImageDataUrl(image.dataUrl)),
    );
    const suggestion = await withTimeout(
      analyzeImagesForSchema(optimizedDataUrls),
      SCHEMA_ASSIST_TIMEOUT_MS,
    );
    populateSchemaForm(suggestion);
    const fieldCount = Array.isArray(suggestion?.fields) ? suggestion.fields.length : 0;
    setSchemaImageStatus(
      `Suggested schema from ${countLabel} with ${fieldCount} field${fieldCount === 1 ? '' : 's'}. Review and edit, then Save.`,
      'success',
    );
  } catch (err) {
    console.error('Schema image analysis failed:', err);
    setSchemaImageStatus(
      schemaAssistUserMessage(err?.message || 'Analysis failed. Try another image or switch to Manual.'),
      'error',
    );
  }
}

async function analyzeImagesForSchema(dataUrls) {
  if (!supabase) {
    throw new Error('Supabase client is not initialized.');
  }
  if (schemaAssistUrl) {
    return invokeSchemaAssistUrl(dataUrls);
  }
  if (!schemaAssistFunction) {
    throw new Error('Automatic schema generation is not configured.');
  }

  let result;
  try {
    result = await supabase.functions.invoke(schemaAssistFunction, {
      body: {
        // image_data_url keeps older deployed Edge Functions working for
        // single-image schema generation. image_data_urls is the new multi-
        // image contract used after redeploying supabase/functions/schema-assist.
        image_data_url: dataUrls[0],
        image_data_urls: dataUrls,
        model: aiAssistModel,
      },
    });
  } catch (err) {
    console.error('Schema assist function call failed:', err);
    throw new Error('Automatic schema generation is unavailable. You can still enter the schema manually.');
  }

  const { data, error } = result;

  if (error) {
    let detail = error.message || 'Schema assist failed.';
    try {
      if (error.context && typeof error.context.json === 'function') {
        const body = await error.context.json();
        detail = body?.error || body?.message || body?.detail || detail;
      }
    } catch (_) {
      // Keep the original function error message.
    }
    if (/failed to fetch|failed to send|networkerror|function not found|404/i.test(detail)) {
      detail = 'Automatic schema generation is unavailable. You can still enter the schema manually.';
    }
    throw new Error(schemaAssistUserMessage(detail));
  }

  if (!data || typeof data !== 'object') {
    throw new Error('Automatic schema generation returned an empty result.');
  }
  return data;
}

async function invokeSchemaAssistUrl(dataUrls) {
  let response;
  try {
    response = await fetch(schemaAssistUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        apikey: config.supabaseAnonKey,
        Authorization: `Bearer ${config.supabaseAnonKey}`,
      },
      body: JSON.stringify({
        // Keep backward compatibility with older local/deployed functions.
        image_data_url: dataUrls[0],
        image_data_urls: dataUrls,
        model: aiAssistModel,
      }),
    });
  } catch (err) {
    console.error('Schema assist URL call failed:', err);
    throw new Error('Automatic schema generation is unavailable. You can still enter the schema manually.');
  }

  let body = null;
  try {
    body = await response.json();
  } catch (_) {
    // Non-JSON failures are converted into the same safe UI message below.
  }

  if (!response.ok) {
    const detail = body?.error || body?.message || '';
    throw new Error(schemaAssistUserMessage(detail));
  }

  if (!body || typeof body !== 'object') {
    throw new Error('Automatic schema generation returned an empty result.');
  }
  return body;
}

function populateSchemaForm(suggestion) {
  if (!suggestion || typeof suggestion !== 'object') return;

  if (typeof suggestion.label_type_name === 'string' && suggestion.label_type_name.trim()) {
    schemaDisplayName.value = suggestion.label_type_name.trim();
    const key = normalizeSchemaName(suggestion.label_type_name);
    if (key) {
      schemaNameInput.value = key;
      schemaNameInput.dataset.touched = 'false';
    }
  }

  if (typeof suggestion.description === 'string' && suggestion.description.trim()) {
    schemaDescription.value = suggestion.description.trim();
  }

  const fields = Array.isArray(suggestion.fields) ? suggestion.fields : [];
  if (!schemaFieldsList) return;

  schemaFieldsList.replaceChildren();
  const seen = new Set();
  let added = 0;
  for (const entry of fields) {
    if (!entry || typeof entry !== 'object') continue;
    const rawName = typeof entry.name === 'string' ? entry.name : '';
    const key = normalizeSchemaName(rawName);
    if (!key || seen.has(key)) continue;
    seen.add(key);
    createSchemaFieldRow({
      name: key,
      description:
        typeof entry.description === 'string' ? entry.description.trim() : '',
      mandatory: entry.mandatory === true,
    });
    added++;
  }
  if (added === 0) {
    createSchemaFieldRow();
  }
}

function loadExampleSchema() {
  populateSchemaForm({
    label_type_name: 'Valve Tag',
    description: 'Industrial valve tag or valve equipment label with identifiers and operating details.',
    fields: [
      {
        name: 'tag_no',
        description: 'Primary valve tag or asset identifier printed on the label.',
        mandatory: true,
      },
      {
        name: 'manufacturer',
        description: 'Manufacturer or brand name.',
        mandatory: false,
      },
      {
        name: 'model_no',
        description: 'Model number or valve series.',
        mandatory: true,
      },
      {
        name: 'serial_no',
        description: 'Serial number if present.',
        mandatory: true,
      },
      {
        name: 'size',
        description: 'Valve size or nominal pipe size.',
        mandatory: false,
      },
      {
        name: 'pressure_rating',
        description: 'Pressure class, MAWP, or rated pressure.',
        mandatory: true,
      },
      {
        name: 'material',
        description: 'Body or wetted-part material.',
        mandatory: false,
      },
      {
        name: 'connection_type',
        description: 'Flanged, threaded, welded, or other connection type.',
        mandatory: false,
      },
      {
        name: 'flow_direction',
        description: 'Flow direction marking if visible.',
        mandatory: false,
      },
      {
        name: 'made_in',
        description: 'Country of manufacture.',
        mandatory: false,
      },
    ],
  });
  setSchemaMode('manual');
  setSchemaMessage('Loaded a sample Valve Tag schema. Review/edit it, then Save Schema.', 'success');
}

function clearSchemaForm({ message = 'Schema form cleared.' } = {}) {
  customSchemaForm.reset();
  schemaNameInput.dataset.touched = 'false';
  resetSchemaFieldRows();
  resetImageDrop();
  setSchemaMode('image');
  setSchemaMessage(message, 'success');
  schemaDisplayName.focus();
}

function renderSchemaList() {
  if (!schemaList) return;
  const schemas = Object.values(SCHEMAS).sort((a, b) => {
    if (a.is_system !== b.is_system) return a.is_system ? -1 : 1;
    return String(a.display_name || '').localeCompare(String(b.display_name || ''));
  });
  if (currentView === 'schemas') {
    recordCount.textContent = `${schemas.length} schema${schemas.length !== 1 ? 's' : ''}`;
  }

  // Preserve which cards were expanded so re-render (manual refresh,
  // schema save, etc.) does not collapse the user's open inspection.
  const expandedKeys = new Set(
    Array.from(schemaList.querySelectorAll('.schema-card[data-expanded="true"]'))
      .map((el) => el.dataset.schemaKey)
      .filter(Boolean),
  );

  if (!schemas.length) {
    schemaList.innerHTML = '<div class="empty"><p>No schema templates found.</p></div>';
    return;
  }

  schemaList.innerHTML = schemas.map(schema => {
    const fields = (schema.fields || []).filter(Boolean);
    const descriptions = schema.field_descriptions || {};
    const mandatorySet = new Set(schema.mandatory_fields || []);
    const schemaKey = schema.schema_name || schema.equipment_type || '';
    const wasExpanded = expandedKeys.has(schemaKey);

    const chips = fields.length
      ? fields.map((field) => {
          const desc = descriptions[field] || '';
          const isMandatory = mandatorySet.has(field);
          const classes = ['schema-field-chip'];
          if (isMandatory) classes.push('is-mandatory');
          const infoIcon = desc
            ? `<button type="button" class="schema-field-chip-info" aria-label="${esc(desc)}" title="${esc(desc)}" tabindex="0">
                 <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                   <circle cx="12" cy="12" r="10"/>
                   <path d="M12 16v-4M12 8h.01"/>
                 </svg>
               </button>`
            : '';
          const mandatoryMark = isMandatory
            ? '<span class="schema-field-chip-required" aria-label="Mandatory field" title="Mandatory field">*</span>'
            : '';
          return `
            <li class="${classes.join(' ')}">
              <span class="schema-field-chip-name">${esc(field)}${mandatoryMark}</span>
              ${infoIcon}
            </li>`;
        }).join('')
      : '<li class="schema-field-empty">No fields defined.</li>';

    return `
      <article class="schema-card" data-schema-key="${esc(schemaKey)}" data-expanded="${wasExpanded ? 'true' : 'false'}">
        <div class="schema-card-summary" role="button" tabindex="0" aria-expanded="${wasExpanded ? 'true' : 'false'}">
          <div class="schema-card-head">
            <div class="schema-card-title">
              <h4>${esc(schema.display_name || schemaKey)}</h4>
              <p class="schema-desc">${esc(schema.description || 'No description.')}</p>
            </div>
            <div class="schema-card-head-meta">
              <svg class="schema-card-chevron" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                <path d="M6 9l6 6 6-6"/>
              </svg>
            </div>
          </div>
          <div class="schema-meta">
            <span class="schema-pill">${fields.length} field${fields.length === 1 ? '' : 's'}</span>
          </div>
        </div>
        <div class="schema-card-body"${wasExpanded ? '' : ' hidden'}>
          <ul class="schema-field-chips">${chips}</ul>
        </div>
      </article>
    `;
  }).join('');
}

function toggleSchemaCard(card) {
  if (!card) return;
  const expanded = card.dataset.expanded === 'true';
  const next = !expanded;
  card.dataset.expanded = next ? 'true' : 'false';
  const summary = card.querySelector('.schema-card-summary');
  const body = card.querySelector('.schema-card-body');
  if (summary) summary.setAttribute('aria-expanded', next ? 'true' : 'false');
  if (body) body.hidden = !next;
}

/**
 * Show the schema confirmation modal and resolve with the user's choice.
 * Returns true when the user clicks the primary action, false when cancelled
 * (via the Cancel button, the backdrop, or the Escape key).
 */
function showSchemaConfirm({ title, bodyHtml, actionLabel, actionClass = '' }) {
  if (!schemaConfirmModal) return Promise.resolve(true);

  schemaConfirmTitle.textContent = title;
  schemaConfirmBody.innerHTML = bodyHtml;
  schemaConfirmAction.textContent = actionLabel;
  schemaConfirmAction.className = 'btn-primary schema-confirm-action';
  if (actionClass) schemaConfirmAction.classList.add(actionClass);
  schemaConfirmModal.hidden = false;

  return new Promise((resolve) => {
    const cleanup = (result) => {
      schemaConfirmModal.hidden = true;
      schemaConfirmAction.removeEventListener('click', onAction);
      schemaConfirmCancel.removeEventListener('click', onCancel);
      schemaConfirmModal.removeEventListener('click', onBackdrop);
      document.removeEventListener('keydown', onKey);
      resolve(result);
    };
    const onAction = () => cleanup(true);
    const onCancel = () => cleanup(false);
    const onBackdrop = (event) => {
      if (event.target === schemaConfirmModal) cleanup(false);
    };
    const onKey = (event) => {
      if (event.key === 'Escape') cleanup(false);
    };
    schemaConfirmAction.addEventListener('click', onAction);
    schemaConfirmCancel.addEventListener('click', onCancel);
    schemaConfirmModal.addEventListener('click', onBackdrop);
    document.addEventListener('keydown', onKey);
    // Focus the cancel button so Enter doesn't accidentally confirm.
    window.requestAnimationFrame(() => schemaConfirmCancel.focus());
  });
}

function findDisplayNameCollision(normalizedName, targetSchemaName) {
  const needle = String(normalizedName || '').trim().toLowerCase();
  if (!needle) return null;
  for (const key of Object.keys(SCHEMAS)) {
    if (key === targetSchemaName) continue;
    const existing = SCHEMAS[key];
    const existingDisplay = String(existing?.display_name || '').trim().toLowerCase();
    if (existingDisplay && existingDisplay === needle) return existing;
  }
  return null;
}

/**
 * Detect an existing schema whose field list is identical to the one the
 * user is about to save. "Identical" means: same count, same set of field
 * names (order-independent). System schemas are included in the scan so we
 * catch the "I just recreated Motor Nameplate" case too.
 */
function findContentDuplicateSchema(newFields, targetSchemaName) {
  const needle = (newFields || []).map((f) => String(f || '').trim()).filter(Boolean);
  if (needle.length === 0) return null;
  const needleSet = new Set(needle);
  if (needleSet.size !== needle.length) return null;

  for (const key of Object.keys(SCHEMAS)) {
    if (key === targetSchemaName) continue;
    const existing = SCHEMAS[key];
    const existingFields = Array.isArray(existing?.fields)
      ? existing.fields.map((f) => String(f || '').trim()).filter(Boolean)
      : [];
    if (existingFields.length !== needle.length) continue;
    let match = true;
    for (const field of existingFields) {
      if (!needleSet.has(field)) { match = false; break; }
    }
    if (match) return existing;
  }
  return null;
}

async function saveCustomSchema(event) {
  event.preventDefault();
  setSchemaMessage('');

  const displayName = schemaDisplayName.value.trim();
  const schemaName = normalizeSchemaName(schemaNameInput.value);
  const description = schemaDescription.value.trim();
  const { fields, descriptions, mandatoryFields } = readSchemaFieldsFromRows();

  if (!displayName) {
    setSchemaMessage('Display name is required.', 'error');
    return;
  }
  if (!schemaName || schemaName !== schemaNameInput.value.trim()) {
    setSchemaMessage('Schema name must use lowercase letters, numbers, and underscores only.', 'error');
    return;
  }
  if (!fields.length) {
    setSchemaMessage('Add at least one field.', 'error');
    return;
  }
  if (SCHEMAS[schemaName]?.is_system) {
    setSchemaMessage('That name is reserved for a system schema. Choose another schema name.', 'error');
    return;
  }

  // Pre-save check A: exact internal-key match on an existing custom schema.
  // Silent overwrites would clobber another operator's work, so require an
  // explicit "Overwrite" confirmation before the upsert runs.
  const existingByKey = SCHEMAS[schemaName];
  if (existingByKey && existingByKey.is_system !== true) {
    const existingFields = Array.isArray(existingByKey.fields)
      ? existingByKey.fields.length
      : 0;
    const confirmed = await showSchemaConfirm({
      title: 'Schema already exists',
      bodyHtml:
        `A custom schema with the key <strong>${esc(schemaName)}</strong> already exists ` +
        `(<strong>${esc(existingByKey.display_name || schemaName)}</strong>, ` +
        `${existingFields} field${existingFields === 1 ? '' : 's'}).<br><br>` +
        'Saving will overwrite its fields and mandatory list. The old version cannot be recovered.',
      actionLabel: 'Overwrite',
      actionClass: 'is-danger',
    });
    if (!confirmed) {
      setSchemaMessage('Save cancelled.', '');
      return;
    }
  } else {
    // Pre-save check B: display-name collision on a different internal key.
    // The user is about to create a second schema that will look identical in
    // the dropdown. Warn but allow — legitimate if two equipment types share
    // a label in practice.
    const collision = findDisplayNameCollision(displayName, schemaName);
    if (collision) {
      const confirmed = await showSchemaConfirm({
        title: 'Similar schema already exists',
        bodyHtml:
          `Another schema named <strong>${esc(displayName)}</strong> already exists ` +
          `(key: <strong>${esc(collision.schema_name || collision.equipment_type || '')}</strong>).<br><br>` +
          `This new schema will be saved as a separate template with key ` +
          `<strong>${esc(schemaName)}</strong> and both will appear in the dropdown.`,
        actionLabel: 'Save as new',
      });
      if (!confirmed) {
        setSchemaMessage('Save cancelled.', '');
        return;
      }
    } else {
      // Pre-save check C: content duplicate — same field set as an existing
      // schema even though names/keys differ. Catches the "Military Forklift"
      // vs "U.S. Military Forklift" case where both carry identical fields.
      const contentDup = findContentDuplicateSchema(fields, schemaName);
      if (contentDup) {
        const kindLabel = contentDup.is_system ? 'system' : 'custom';
        const confirmed = await showSchemaConfirm({
          title: 'Same fields as an existing schema',
          bodyHtml:
            `A ${kindLabel} schema with the same ${fields.length} fields already exists: ` +
            `<strong>${esc(contentDup.display_name || contentDup.schema_name || '')}</strong> ` +
            `(key: <strong>${esc(contentDup.schema_name || contentDup.equipment_type || '')}</strong>).<br><br>` +
            'Saving will create a second template with identical fields. Consider editing ' +
            'the existing schema instead if this is the same equipment type.',
          actionLabel: 'Save as new',
        });
        if (!confirmed) {
          setSchemaMessage('Save cancelled.', '');
          return;
        }
      }
    }
  }

  try {
    saveSchemaBtn.disabled = true;
    setSchemaMessage('Saving schema...');

    const { data: sessionData } = await supabase.auth.getSession();
    const userEmail = sessionData?.session?.user?.email || sessionEmail.textContent || null;

    const { data: promptRows, error: promptLoadError } = await supabase
      .from('prompt_templates')
      .select('template_body')
      .eq('prompt_key', 'custom_default')
      .eq('version', '1.0')
      .eq('is_active', true)
      .limit(1);
    if (promptLoadError) throw promptLoadError;
    const templateBody = promptRows?.[0]?.template_body;
    if (!templateBody) {
      throw new Error('Schema setup is incomplete. Please contact your administrator.');
    }

    const now = new Date().toISOString();
    const { error: promptError } = await supabase
      .from('prompt_templates')
      .upsert({
        prompt_key: schemaName,
        version: '1.0',
        prompt_name: `${displayName} prompt`,
        description: `Client-created prompt for ${displayName}.`,
        template_body: templateBody,
        is_system: false,
        is_active: true,
        updated_at: now,
      }, { onConflict: 'prompt_key,version' });
    if (promptError) throw promptError;

    const schemaPayload = {
      schema_name: schemaName,
      display_name: displayName,
      description: description || null,
      fields,
      field_descriptions: descriptions,
      mandatory_fields: mandatoryFields,
      prompt_key: schemaName,
      prompt_version: '1.0',
      schema_version: '1.0',
      is_system: false,
      is_active: true,
      client_email: null,
      created_by: userEmail,
      updated_at: now,
    };

    let { error: schemaError } = await supabase
      .from('schema_templates')
      .upsert(schemaPayload, { onConflict: 'schema_name' });

    // Older PoC databases used always_review before the field was renamed to
    // mandatory_fields. Retry once so dashboard schema creation still works
    // before the full SQL setup is re-run.
    if (schemaError && String(schemaError.message || '').toLowerCase().includes('mandatory_fields')) {
      const legacyPayload = { ...schemaPayload, always_review: mandatoryFields };
      delete legacyPayload.mandatory_fields;
      ({ error: schemaError } = await supabase
        .from('schema_templates')
        .upsert(legacyPayload, { onConflict: 'schema_name' }));
    }
    if (schemaError) throw schemaError;

    customSchemaForm.reset();
    resetSchemaFieldRows();
    schemaNameInput.dataset.touched = 'false';
    if (hasAiAssist) resetImageDrop();
    await loadSchemas();
    buildTypeFilter(allRecords);
    setSchemaMessage(`Saved "${displayName}". It is now available as a label type.`, 'success');
  } catch (error) {
    console.error('Schema save failed:', error);
    setSchemaMessage(error?.message || String(error), 'error');
  } finally {
    saveSchemaBtn.disabled = false;
  }
}

// ── Init ──────────────────────────────────────────────────────

if (!config?.supabaseUrl || !config?.supabaseAnonKey) {
  authMessage.textContent = 'Portal is not configured.';
} else {
  if (config.appTitle) {
    appTitle.textContent = config.appTitle;
    document.title = config.appTitle;
  }
  supabase = createClient(config.supabaseUrl, config.supabaseAnonKey);
  if (config.allowMagicLink) magicLinkBtn.hidden = false;
  boot();
}

// ── Auth ──────────────────────────────────────────────────────

async function boot() {
  // Load DB-backed schema templates before touching any records so rendering
  // decisions (field order, wide/narrow) have them available.
  await loadSchemas();

  // Sync the direction toggle button with the default state before the
  // first render so it doesn't flash "Desc" → real value.
  updateBasketSortDirButton();

  const { data } = await supabase.auth.getSession();
  setSessionUI(data.session ?? null);
  if (data.session) {
    setupRealtimeRefresh();
    await loadSchemas();
    await refreshCurrentView();
  }

  supabase.auth.onAuthStateChange(async (_event, session) => {
    setSessionUI(session);
    if (session) {
      setupRealtimeRefresh();
      await loadSchemas();
      await refreshCurrentView();
    } else {
      await teardownRealtimeRefresh();
      allRecords = [];
      renderTable();
      clearDetail();
    }
  });
}

function setSessionUI(session) {
  const loggedIn = !!session;
  authPanel.hidden = loggedIn;
  mainApp.hidden = !loggedIn;
  sessionEmail.textContent = session?.user?.email || '';
}

loginForm.addEventListener('submit', async (e) => {
  e.preventDefault();
  authMessage.textContent = '';
  const email = document.getElementById('email').value.trim();
  const password = document.getElementById('password').value;
  if (!password) { authMessage.textContent = 'Enter your password.'; return; }
  try {
    loginForm.querySelectorAll('input,button').forEach(el => el.disabled = true);
    const { data, error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) throw error;
    // Explicitly switch UI and load records (don't rely solely on onAuthStateChange)
    if (data?.session) {
      setSessionUI(data.session);
      setupRealtimeRefresh();
      await loadSchemas();
      await refreshCurrentView();
    }
  } catch (err) {
    const msg = (err?.message || '').toLowerCase();
    if (msg.includes('invalid login')) authMessage.textContent = 'Invalid email or password.';
    else if (msg.includes('not confirmed')) authMessage.textContent = 'Account not confirmed yet.';
    else authMessage.textContent = err?.message || String(err);
  } finally {
    loginForm.querySelectorAll('input,button').forEach(el => el.disabled = false);
  }
});

magicLinkBtn.addEventListener('click', async () => {
  const email = document.getElementById('email').value.trim();
  if (!email) { authMessage.textContent = 'Enter an email first.'; return; }
  const { error } = await supabase.auth.signInWithOtp({ email });
  authMessage.textContent = error ? error.message : 'Magic link sent. Check your email.';
  if (!error) authMessage.classList.add('success');
});

// ── Events ────────────────────────────────────────────────────

refreshBtn.addEventListener('click', refreshCurrentView);
logoutBtn.addEventListener('click', () => supabase.auth.signOut());
searchInput.addEventListener('input', renderTable);
typeFilter.addEventListener('change', renderTable);
dateFrom.addEventListener('change', renderTable);
dateTo.addEventListener('change', renderTable);
clearFilters.addEventListener('click', () => {
  searchInput.value = '';
  typeFilter.value = '';
  dateFrom.value = '';
  dateTo.value = '';
  renderTable();
});
exportBtn.addEventListener('click', exportCurrentView);
detailClose.addEventListener('click', clearDetail);

schemaDisplayName.addEventListener('input', () => {
  if (schemaNameInput.dataset.touched === 'true') return;
  schemaNameInput.value = normalizeSchemaName(schemaDisplayName.value);
});
schemaNameInput.addEventListener('input', () => {
  schemaNameInput.dataset.touched = 'true';
});
customSchemaForm.addEventListener('submit', saveCustomSchema);
schemaAddFieldBtn?.addEventListener('click', () => {
  createSchemaFieldRow({ focus: true });
});
schemaLoadExampleBtn?.addEventListener('click', loadExampleSchema);
schemaClearFormBtn?.addEventListener('click', () => clearSchemaForm());
// Seed the Fields list with one empty row so the form is usable on first load.
if (schemaFieldsList && schemaFieldsList.children.length === 0) {
  createSchemaFieldRow();
}

// ── AI schema assist wiring ──────────────────────────────────
// Always show the upload/manual tabs. If AI assist is not configured, image
// selection still previews the file and explains why auto-generation cannot run.
if (schemaModeTabs) {
  setSchemaMode('image');

  schemaModeTabs.addEventListener('click', (event) => {
    const btn = event.target.closest('.schema-mode-tab');
    if (!btn) return;
    setSchemaMode(btn.dataset.mode || 'manual');
  });

  // Drop zone drag + drop
  ['dragenter', 'dragover'].forEach((ev) => {
    schemaImageDrop.addEventListener(ev, (event) => {
      event.preventDefault();
      event.stopPropagation();
      schemaImageDrop.classList.add('is-dragover');
    });
  });
  ['dragleave', 'dragend', 'drop'].forEach((ev) => {
    schemaImageDrop.addEventListener(ev, (event) => {
      event.preventDefault();
      event.stopPropagation();
      schemaImageDrop.classList.remove('is-dragover');
    });
  });
  schemaImageDrop.addEventListener('drop', (event) => {
    handleSchemaImageFiles(event.dataTransfer?.files);
  });

  // Click-to-browse (but not on the clear button)
  schemaImageDrop.addEventListener('click', (event) => {
    if (event.target.closest('.schema-image-clear')) return;
    if (schemaImageDropLoaded && !schemaImageDropLoaded.hidden) return;
    schemaImageInput.click();
  });

  schemaImageInput.addEventListener('change', (event) => {
    handleSchemaImageFiles(event.target.files);
  });

  schemaImageClear?.addEventListener('click', (event) => {
    event.stopPropagation();
    resetImageDrop();
  });
}

// Expand / collapse schema cards when the user clicks or keys on them.
schemaList?.addEventListener('click', (event) => {
  const summary = event.target.closest('.schema-card-summary');
  if (!summary) return;
  toggleSchemaCard(summary.closest('.schema-card'));
});
schemaList?.addEventListener('keydown', (event) => {
  if (event.key !== 'Enter' && event.key !== ' ') return;
  const summary = event.target.closest('.schema-card-summary');
  if (!summary) return;
  event.preventDefault();
  toggleSchemaCard(summary.closest('.schema-card'));
});

// View switcher tabs (Records / Paint Basket / Schemas)
viewTabs.addEventListener('click', (e) => {
  const btn = e.target.closest('.view-tab');
  if (!btn) return;
  const next = btn.dataset.view;
  if (next && next !== currentView) switchView(next);
});

// Paint basket filter wiring
basketSearch.addEventListener('input', renderBasket);
basketSort.addEventListener('change', () => {
  currentBasketSort = basketSort.value;
  // Reset direction to the column's natural default (counts/dates → desc,
  // text → asc). User can still toggle afterwards.
  currentBasketSortDir = BASKET_SORT_DEFAULT_DIR[currentBasketSort] || 'asc';
  updateBasketSortDirButton();
  renderBasket();
});
basketSortDir.addEventListener('click', () => {
  currentBasketSortDir = currentBasketSortDir === 'asc' ? 'desc' : 'asc';
  updateBasketSortDirButton();
  renderBasket();
});

window.addEventListener('focus', () => {
  if (currentView === 'schemas') return;
  schedulePortalDataRefresh('window focus');
});

document.addEventListener('visibilitychange', () => {
  if (currentView === 'schemas') return;
  schedulePortalDataRefresh('visibility change');
});

window.setInterval(() => {
  // Schemas tab stays stable on auto-refresh so expanded cards aren't
  // collapsed mid-read. Records and Inventory Lookup still auto-refresh.
  if (currentView === 'schemas') return;
  schedulePortalDataRefresh('polling interval');
}, config.refreshIntervalMs || 10000);

// ── Lightbox (fullscreen zoom view with prev/next nav) ───────

function openLightbox(index) {
  if (!currentImageUrls.length) return;
  currentImageIndex = Math.max(0, Math.min(index ?? currentImageIndex, currentImageUrls.length - 1));
  updateLightboxImage();
  lightbox.hidden = false;
  document.body.style.overflow = 'hidden';
  document.addEventListener('keydown', lightboxKeyHandler);
}

function closeLightbox() {
  lightbox.hidden = true;
  document.body.style.overflow = '';
  document.removeEventListener('keydown', lightboxKeyHandler);
}

function lightboxPrev() {
  if (currentImageUrls.length < 2) return;
  currentImageIndex = (currentImageIndex - 1 + currentImageUrls.length) % currentImageUrls.length;
  setMainImage(currentImageIndex);
}

function lightboxNext() {
  if (currentImageUrls.length < 2) return;
  currentImageIndex = (currentImageIndex + 1) % currentImageUrls.length;
  setMainImage(currentImageIndex);
}

function updateLightboxImage() {
  if (!currentImageUrls.length) return;
  const imageIndex = currentImageIndex;
  const url = currentImageUrls[imageIndex];
  const storagePath = currentImagePaths[imageIndex];
  if (storagePath) {
    setImageFromStoragePath(lightboxImg, storagePath, {
      initialUrl: url,
      onUrl: (nextUrl) => {
        currentImageUrls[imageIndex] = nextUrl;
        if (currentImageIndex === imageIndex) {
          lightboxNewtab.href = nextUrl;
        }
      },
    });
  } else {
    lightboxImg.src = url;
  }
  lightboxNewtab.href = url;

  const multi = currentImageUrls.length > 1;
  lightboxCounter.hidden = !multi;
  lightboxPrevBtn.hidden = !multi;
  lightboxNextBtn.hidden = !multi;
  if (multi) {
    lightboxCounter.textContent = `${currentImageIndex + 1} / ${currentImageUrls.length}`;
  }
}

function lightboxKeyHandler(e) {
  if (e.key === 'Escape') { closeLightbox(); e.preventDefault(); }
  else if (e.key === 'ArrowLeft') { lightboxPrev(); e.preventDefault(); }
  else if (e.key === 'ArrowRight') { lightboxNext(); e.preventDefault(); }
}

// Open lightbox from the inline preview (zoom button or image click)
function openImageLightbox() {
  if (!currentImageUrls.length) return;
  openLightbox(currentImageIndex);
}

imgZoomBtn.addEventListener('click', openImageLightbox);
detailImage.addEventListener('click', openImageLightbox);

lightboxClose.addEventListener('click', closeLightbox);
lightboxPrevBtn.addEventListener('click', (e) => { e.stopPropagation(); lightboxPrev(); });
lightboxNextBtn.addEventListener('click', (e) => { e.stopPropagation(); lightboxNext(); });
// "Open in new tab" should also close the overlay in this tab — otherwise
// it's still sitting on top of the portal when the user comes back.
// preventDefault is NOT called, so target=_blank still opens the image tab.
lightboxNewtab.addEventListener('click', () => { closeLightbox(); });
// Click on the dark overlay (but not on the image, buttons, or links) closes
lightbox.addEventListener('click', (e) => {
  if (e.target === lightbox) closeLightbox();
});

// ── Data ──────────────────────────────────────────────────────

async function loadRecords(options = {}) {
  const keepDetailOpen = options.quiet === true || options.preserveDetail === true;
  const isBackground = options.background === true || options.quiet === true;
  const selectedRecordIdAtStart = selectedRecord?.record_id;

  const { data, error } = await supabase
    .from(config.approvedView || 'approved_records_flat')
    .select('*')
    .order('approved_at', { ascending: false });

  if (error) { authMessage.textContent = `Load failed: ${error.message}`; return; }

  const nextRows = data || [];
  const nextSnapshot = JSON.stringify(nextRows);
  if (isBackground && nextSnapshot === recordsSnapshot) {
    retryPendingImages();
    return;
  }

  allRecords = nextRows.map(normalizeRecord);
  recordsSnapshot = nextSnapshot;
  buildTypeFilter(allRecords);
  if (keepDetailOpen && selectedRecordIdAtStart) {
    const selectionUnchanged =
      selectedRecord &&
      String(selectedRecord.record_id) === String(selectedRecordIdAtStart);
    if (selectionUnchanged) {
      selectedRecord = allRecords.find(
        r => String(r.record_id) === String(selectedRecordIdAtStart)
      ) || selectedRecord;
    }
  }
  if (currentView === 'records') {
    renderTable();
    if (!keepDetailOpen) {
      clearDetail();
    }
  }
}

function normalizeRecord(row) {
  // Prefer the whole approved_fields JSONB from the new view; fall back to
  // the flattened columns if the migration has not been applied yet.
  const approvedFields = (row.approved_fields && typeof row.approved_fields === 'object')
    ? row.approved_fields
    : null;

  const fields = {};

  if (approvedFields) {
    // Copy every non-empty key, regardless of schema whitelist
    for (const [key, value] of Object.entries(approvedFields)) {
      if (value !== null && value !== undefined && String(value).trim() !== '') {
        fields[key] = value;
      }
    }
  } else {
    // Legacy fallback — before migration 02_schema_aware.sql has been applied
    const legacyKeys = [
      'manufacturer', 'model_no', 'serial_no', 'type', 'form', 'description',
      'location', 'country', 'made_in',
      'volts', 'hz', 'amp', 'hp', 'rpm', 'poles', 'frame_no', 'duty',
      'ins_class', 'nema_des', 'nema_code', 'service_factor', 'nom_fl_eff', 'max_amb_c',
      'bearing_ls', 'bearing_os',
      'temp_device_type', 'csa_temp_code', 'hazardous_locations', 'usable_208v_amp',
      'part_no', 'configuration_no', 'date_code', 'series', 'max_wpr_psi_bar',
      'connection_info', 'notes',
    ];
    for (const key of legacyKeys) {
      const value = row[key];
      if (value !== null && value !== undefined && String(value).trim() !== '') {
        fields[key] = value;
      }
    }
  }

  // Resolve extras: prefer new approved_extra_fields, then legacy extra_fields
  const extras = (row.approved_extra_fields && typeof row.approved_extra_fields === 'object')
    ? row.approved_extra_fields
    : (row.extra_fields && typeof row.extra_fields === 'object' ? row.extra_fields : {});

  // Display name: prefer description/product_name > manufacturer+model > model > type
  const mfr = fields.manufacturer || row.manufacturer || '';
  const model = fields.model_no || fields.part_no || fields.product_code || row.model_no || '';
  const productName = fields.product_name || '';
  const desc = fields.description || row.description || '';

  let displayName = '';
  if (productName) displayName = productName;
  else if (desc && mfr) displayName = desc;
  else if (mfr && model) displayName = `${mfr} ${model}`;
  else if (model) displayName = model;
  else if (desc) displayName = desc;
  else displayName = getDisplayName(row.schema_name || row.record_type) || 'Record';

  // Key specs line — schema-aware: pick a few high-signal fields that exist in `fields`
  const specs = [
    fields.hp ? `${fields.hp} HP` : null,
    fields.kva ? `${fields.kva} kVA` : null,
    fields.volts ? `${fields.volts}V` : null,
    fields.rpm ? `${fields.rpm} RPM` : null,
    fields.hz ? `${fields.hz}Hz` : null,
    fields.amp ? `${fields.amp}A` : null,
    fields.size ? fields.size : null,
    fields.color_name ? fields.color_name : null,
  ].filter(Boolean).slice(0, 4).join(' / ');

  return {
    ...row,
    _fields: fields,
    _extra: extras,
    _displayName: displayName,
    _specs: specs,
    manufacturer: mfr,
    _model: model,
  };
}

// ── Filters ───────────────────────────────────────────────────

function buildTypeFilter(records) {
  const current = typeFilter.value;
  // Use all schemas we loaded plus any extra record_type values found in data
  const dataTypes = records.map(r => r.schema_name || r.record_type).filter(Boolean);
  const allTypes = [...new Set([...SCHEMA_NAMES, ...dataTypes])].sort();
  typeFilter.innerHTML = '<option value="">All Types</option>';
  for (const type of allTypes) {
    const opt = document.createElement('option');
    opt.value = type;
    opt.textContent = getDisplayName(type);
    typeFilter.appendChild(opt);
  }
  typeFilter.value = current;
}

function filteredRecords() {
  const term = searchInput.value.trim().toLowerCase();
  const type = typeFilter.value;
  const from = dateFrom.value ? new Date(dateFrom.value) : null;
  const to = dateTo.value ? new Date(dateTo.value + 'T23:59:59') : null;

  return allRecords.filter(r => {
    if (type && (r.schema_name || r.record_type) !== type) return false;

    // Date range filter
    if (from || to) {
      const d = new Date(recordScannedAt(r));
      if (from && d < from) return false;
      if (to && d > to) return false;
    }

    // Text search
    if (term) {
      const hay = [
        r._displayName, r.manufacturer, r._model, r.serial_no,
        r.record_type, r.schema_name, r._specs, JSON.stringify(r._fields),
      ].join(' ').toLowerCase();
      if (!hay.includes(term)) return false;
    }

    return true;
  });
}

// ── Table ─────────────────────────────────────────────────────

function renderTable() {
  const rows = filteredRecords();
  emptyState.hidden = true;
  recordCount.textContent = `${rows.length} record${rows.length !== 1 ? 's' : ''}`;

  if (!rows.length) {
    recordsBody.replaceChildren();
    emptyState.hidden = false;
    return;
  }

  const fragment = document.createDocumentFragment();
  for (const record of rows) {
    const tr = document.createElement('tr');
    if (selectedRecord?.record_id === record.record_id) tr.classList.add('active');
    const thumbId = `t-${record.record_id}`;

    tr.innerHTML = `
      <td class="col-thumb"><img id="${thumbId}" class="thumb" alt="" /></td>
      <td><span class="equip-type">${esc(getDisplayName(record.schema_name || record.record_type))}</span></td>
      <td>${esc(record.manufacturer || '—')}</td>
      <td>${esc(record._model || '—')}</td>
      <td class="cell-specs">${esc(record._specs || '—')}</td>
      <td class="col-extra">${esc(record._fields?.location || '—')}</td>
      <td class="col-extra">${esc(recordIdentifier(record) || '—')}</td>
      <td class="cell-date">${formatShortDate(recordScannedAt(record))}</td>
    `;

    tr.addEventListener('click', () => showDetail(record, tr));
    fragment.appendChild(tr);
  }
  recordsBody.replaceChildren(fragment);

  for (const record of rows) {
    if (record.preview_image_path) loadThumb(`t-${record.record_id}`, record.preview_image_path);
  }
}

// ── Detail ────────────────────────────────────────────────────

async function showDetail(record, clickedRow = null) {
  // Highlight active row
  document.querySelectorAll('tbody tr.active').forEach(el => el.classList.remove('active'));
  clickedRow?.classList.add('active');

  selectedRecord = record;
  detailPanel.hidden = false;
  document.querySelector('.layout').classList.add('has-detail');
  detailTitle.textContent = record._displayName;
  detailSchemaLabel.textContent = `${getDisplayName(record.schema_name || record.record_type)} · Fields`;

  // Walk the record's own schema for field order and empty placeholders.
  // Anything in _fields that is NOT in the schema gets appended as "out-of-schema"
  // so nothing silently disappears if the LLM returns an unexpected key.
  const schemaFields = getSchemaFields(record);
  const schemaFieldSet = new Set(schemaFields);
  const orderedFields = {};

  for (const key of schemaFields) {
    orderedFields[key] = record._fields[key] ?? null;
  }
  // Append any non-schema keys that came from the extraction
  for (const [key, value] of Object.entries(record._fields)) {
    if (!schemaFieldSet.has(key)) {
      orderedFields[key] = value;
    }
  }

  renderFieldGrid(detailFields, orderedFields, {
    showEmpty: true,
    fieldOrder: schemaFields,
  });

  // Render extra fields (from approved_extra_fields JSONB)
  const extraEntries = Object.entries(record._extra || {}).filter(
    ([key, v]) => v !== null &&
      v !== undefined &&
      String(v).trim() !== '' &&
      !isDuplicateExtraField(key, v, record._fields)
  );
  if (extraEntries.length) {
    detailExtraSection.hidden = false;
    renderFieldGrid(detailExtraFields, Object.fromEntries(extraEntries));
  } else {
    detailExtraSection.hidden = true;
  }

  loadPreviewImage(record.record_id, record.preview_image_path); // load image async (don't block UI)
}

function clearDetail() {
  selectedRecord = null;
  detailPanel.hidden = true;
  document.querySelector('.layout').classList.remove('has-detail');
  detailFields.innerHTML = '';
  detailExtraFields.innerHTML = '';
  detailImageWrap.hidden = true;
  detailImage.src = '';
  detailImageThumbs.innerHTML = '';
  detailImageThumbs.hidden = true;
  currentImageUrls = [];
  currentImagePaths = [];
  currentImageIndex = 0;
  if (!lightbox.hidden) closeLightbox();
}

function renderFieldGrid(target, data, options = {}) {
  target.innerHTML = '';
  const showEmpty = options.showEmpty === true;
  // Prefer an explicit per-schema field order when provided; otherwise use
  // the order in which `data`'s own keys appear.
  const order = Array.isArray(options.fieldOrder) && options.fieldOrder.length
    ? options.fieldOrder
    : Object.keys(data);

  const seen = new Set();
  const entries = [];

  for (const key of order) {
    if (data[key] === undefined) continue;
    entries.push([key, data[key]]);
    seen.add(key);
  }
  // Append any keys present in data but not in the explicit order (unknown fields)
  for (const [key, value] of Object.entries(data)) {
    if (!seen.has(key)) entries.push([key, value]);
  }

  // Sort: filled first, then empty (preserve order within each group)
  entries.sort(([, a], [, b]) => {
    const aFilled = a !== null && a !== undefined && String(a).trim() !== '';
    const bFilled = b !== null && b !== undefined && String(b).trim() !== '';
    if (aFilled === bFilled) return 0;
    return aFilled ? -1 : 1;
  });

  const visible = showEmpty
    ? entries
    : entries.filter(([, v]) => v !== null && v !== undefined && String(v).trim() !== '');

  if (!visible.length) {
    target.innerHTML = '<div style="padding:16px;color:var(--text-tertiary)">No data</div>';
    return;
  }

  for (const [key, value] of visible) {
    const isEmpty = value === null || value === undefined || String(value).trim() === '';
    const wide = isWideField(key, value);
    const item = document.createElement('div');
    item.className = `field-item${wide ? ' full-width' : ''}`;
    item.innerHTML = `
      <div class="field-label">${esc(formatKey(key))}</div>
      <div class="field-value${isEmpty ? ' empty' : ''}">${esc(isEmpty ? '—' : String(value))}</div>
    `;
    target.appendChild(item);
  }
}

// ── Images ────────────────────────────────────────────────────

async function loadPreviewImage(recordId, fallbackPreviewPath = null) {
  const loadSeq = ++detailImageLoadSeq;
  const isCurrentRequest = () => (
    loadSeq === detailImageLoadSeq &&
    (!recordId || String(selectedRecord?.record_id) === String(recordId))
  );

  // Reset gallery state (both inline preview and lightbox state)
  detailImageWrap.hidden = true;
  detailImage.src = '';
  delete detailImage.dataset.storagePath;
  delete detailImage.dataset.loaded;
  detailImageThumbs.innerHTML = '';
  detailImageThumbs.hidden = true;
  imgCounter.hidden = true;
  imgCounter.textContent = '';
  currentImageUrls = [];
  currentImagePaths = [];
  currentImageIndex = 0;

  // Show the row's denormalised preview immediately. This is the same path
  // used by the table thumbnail, so tab-switch/background refresh latency in
  // record_images cannot leave the detail panel blank.
  let fallbackShown = false;
  if (fallbackPreviewPath) {
    fallbackShown = await renderDetailImages(
      [{ storage_path: fallbackPreviewPath, image_order: 1 }],
      loadSeq,
      recordId
    );
  }
  if (!isCurrentRequest()) return;

  // Fetch ALL images for this record, ordered by image_order.
  // Previously this used .limit(1) which silently hid multi-image records.
  let rows = [];
  if (recordId) {
    try {
      const { data, error } = await supabase
        .from('record_images')
        .select('storage_path, image_order')
        .eq('record_id', recordId)
        .order('image_order', { ascending: true });
      if (!isCurrentRequest()) return; // stale
      rows = error ? [] : (data || []);
    } catch (_) {
      rows = [];
    }
  }

  // Fallback to the denormalised preview_image_path if the query returned nothing.
  // This is the same path used by the table thumbnail, so the detail image should
  // still render even if record_images is blocked by RLS or temporarily unavailable.
  if (!rows.length) {
    const record = recordId
      ? allRecords.find(r => String(r.record_id) === String(recordId))
      : null;
    const previewPath = fallbackPreviewPath || record?.preview_image_path;
    if (previewPath) {
      rows = [{ storage_path: previewPath, image_order: 1 }];
    }
  }

  if (!rows.length || (fallbackShown && rows.length === 1 && rows[0].storage_path === fallbackPreviewPath)) {
    return;
  }

  await renderDetailImages(rows, loadSeq, recordId);
}

async function renderDetailImages(rows, loadSeq, recordId) {
  const imageRows = rows.filter(row => row?.storage_path);
  if (!imageRows.length) return false;

  const isCurrentRequest =
    loadSeq === detailImageLoadSeq &&
    (!recordId || String(selectedRecord?.record_id) === String(recordId));
  if (!isCurrentRequest) return false; // stale request

  currentImageUrls = imageRows.map(() => '');
  currentImagePaths = imageRows.map(row => row.storage_path);
  detailImageThumbs.innerHTML = '';
  detailImageThumbs.hidden = true;
  imgCounter.hidden = true;
  imgCounter.textContent = '';

  // Show the first image, then render thumbs if there are more
  setMainImage(0);
  detailImageWrap.hidden = false;

  if (imageRows.length > 1) {
    detailImageThumbs.hidden = false;
    detailImageThumbs.innerHTML = '';
    imageRows.forEach(({ storage_path: storagePath }, idx) => {
      const thumb = document.createElement('button');
      thumb.type = 'button';
      thumb.className = 'detail-thumb';
      thumb.dataset.index = String(idx);
      const thumbImg = document.createElement('img');
      thumbImg.alt = `Image ${idx + 1}`;
      thumb.appendChild(thumbImg);
      setImageFromStoragePath(thumbImg, storagePath, {
        onUrl: (nextUrl) => {
          currentImageUrls[idx] = nextUrl;
        },
      });
      thumb.addEventListener('click', () => setMainImage(idx));
      detailImageThumbs.appendChild(thumb);
    });
  }

  return true;
}

function setMainImage(index) {
  if (!currentImageUrls.length) return;
  currentImageIndex = Math.max(0, Math.min(index, currentImageUrls.length - 1));
  const imageIndex = currentImageIndex;
  const storagePath = currentImagePaths[imageIndex];
  if (storagePath) {
    setImageFromStoragePath(detailImage, storagePath, {
      initialUrl: currentImageUrls[imageIndex],
      onUrl: (nextUrl) => {
        currentImageUrls[imageIndex] = nextUrl;
      },
    });
  } else {
    detailImage.src = currentImageUrls[imageIndex];
  }

  if (currentImageUrls.length > 1) {
    imgCounter.hidden = false;
    imgCounter.textContent = `${currentImageIndex + 1} / ${currentImageUrls.length}`;
    markActiveThumb(currentImageIndex);
  } else {
    imgCounter.hidden = true;
    imgCounter.textContent = '';
  }

  // If the lightbox is open, keep it in sync
  if (!lightbox.hidden) {
    updateLightboxImage();
  }
}

function markActiveThumb(index) {
  const thumbs = detailImageThumbs.querySelectorAll('.detail-thumb');
  thumbs.forEach((el, i) => {
    el.classList.toggle('active', i === index);
  });
}

async function loadThumb(imgId, storagePath) {
  const img = document.getElementById(imgId);
  if (!img) return;
  setImageFromStoragePath(img, storagePath);
}

async function getSignedImageUrl(storagePath, options = {}) {
  if (!storagePath) return null;
  const now = Date.now();
  const cached = imageUrlCache.get(storagePath);
  if (!options.force && cached && cached.expiresAt > now) {
    return cached.url;
  }

  const signed = await supabase.storage
    .from(config.imageBucket || 'scans')
    .createSignedUrl(storagePath, IMAGE_SIGN_SECONDS);

  if (signed.error || !signed.data?.signedUrl) {
    imageUrlCache.delete(storagePath);
    return null;
  }

  const url = signed.data.signedUrl;
  imageUrlCache.set(storagePath, {
    url,
    expiresAt: now + IMAGE_CACHE_MS,
  });
  return url;
}

function setImageFromStoragePath(img, storagePath, options = {}) {
  if (!img || !storagePath) return;

  const maxAttempts = options.maxAttempts ?? 2;
  img.dataset.storagePath = storagePath;
  img.dataset.loaded = 'false';

  const attemptLoad = async (attempt) => {
    let url = null;
    try {
      url = attempt === 0 && options.initialUrl
        ? options.initialUrl
        : await getSignedImageUrl(storagePath, { force: attempt > 0 });
    } catch (_) {
      imageUrlCache.delete(storagePath);
      if (attempt < maxAttempts) {
        window.setTimeout(() => attemptLoad(attempt + 1), 300 * (attempt + 1));
      }
      return;
    }

    if (!url) {
      if (attempt < maxAttempts && img.dataset.storagePath === storagePath) {
        window.setTimeout(() => attemptLoad(attempt + 1), 300 * (attempt + 1));
      }
      return;
    }
    if (img.dataset.storagePath !== storagePath) return;
    options.onUrl?.(url);

    img.onerror = () => {
      if (img.dataset.storagePath !== storagePath || attempt >= maxAttempts) return;
      imageUrlCache.delete(storagePath);
      window.setTimeout(() => attemptLoad(attempt + 1), 300 * (attempt + 1));
    };
    img.onload = () => {
      if (img.dataset.storagePath === storagePath) {
        img.dataset.loaded = 'true';
      }
    };
    img.src = url;
  };

  attemptLoad(0);
}

function retryPendingImages() {
  document.querySelectorAll('img[data-storage-path]').forEach((img) => {
    const storagePath = img.dataset.storagePath;
    if (storagePath && img.dataset.loaded !== 'true') {
      setImageFromStoragePath(img, storagePath, { maxAttempts: 1 });
    }
  });
}

// ── View switching (Records vs Paint Basket vs Schemas) ────────

function switchView(next) {
  currentView = next;
  for (const btn of viewTabs.querySelectorAll('.view-tab')) {
    btn.classList.toggle('active', btn.dataset.view === next);
  }

  const showRecords = next === 'records';
  const showBasket = next === 'paint-basket';
  const showSchemas = next === 'schemas';
  recordsView.hidden = !showRecords;
  recordsFilters.hidden = !showRecords;
  basketView.hidden = !showBasket;
  basketFilters.hidden = !showBasket;
  schemasView.hidden = !showSchemas;

  if (showBasket) {
    if (basketRows.length) renderBasket();
    loadPaintBasket();
  } else if (showSchemas) {
    clearDetail();
    renderSchemaList();
    recordCount.textContent = `${Object.keys(SCHEMAS).length} schema${Object.keys(SCHEMAS).length !== 1 ? 's' : ''}`;
    loadSchemas();
  } else {
    renderTable();
    loadRecords({ quiet: true, preserveDetail: true });
  }
}

async function refreshCurrentView(options = {}) {
  if (currentView === 'paint-basket') {
    await loadPaintBasket(options);
    return;
  }
  if (currentView === 'schemas') {
    await loadSchemas();
    recordCount.textContent = `${Object.keys(SCHEMAS).length} schema${Object.keys(SCHEMAS).length !== 1 ? 's' : ''}`;
    return;
  }

  await loadRecords(options);
  // Keep the basket cache warm so a newly submitted paint scan is visible
  // without requiring "Refresh" plus a tab toggle. This does not re-render
  // the hidden basket view or change the active Records UI.
  await loadPaintBasket({ ...options, render: false });
}

function exportCurrentView() {
  if (currentView === 'schemas') {
    exportSchemasCsv();
    return;
  }
  if (currentView === 'paint-basket') exportBasketCsv();
  else exportRecordsCsv();
}

function updateRecordCount(n) {
  recordCount.textContent = `${n} record${n !== 1 ? 's' : ''}`;
}

// ── Paint basket (loads from paint_basket_view) ────────────────

async function loadPaintBasket(options = {}) {
  const shouldRender = options.render !== false;
  const isBackground = options.background === true || options.quiet === true;

  if (shouldRender && !isBackground) {
    basketEmpty.hidden = true;
  }

  // Order: most-scanned first, then most recent, then UPC as stable
  // tiebreaker. Same order is baked into the view so this explicit
  // chain just mirrors the intent client-side.
  const { data, error } = await supabase
    .from('paint_basket_view')
    .select('*')
    .order('scanned_qty',     { ascending: false })
    .order('last_scanned_at', { ascending: false })
    .order('upc',             { ascending: true });

  if (error) {
    console.warn('paint_basket_view load failed:', error);
    if (shouldRender && currentView === 'paint-basket' && !basketRows.length) {
      basketEmpty.hidden = false;
      basketEmpty.querySelector('p').textContent =
        `Could not load basket: ${error.message}. Make sure 01_complete_setup.sql has been re-run.`;
      updateRecordCount(0);
    }
    return;
  }

  const nextRows = data || [];
  if (isBackground && JSON.stringify(nextRows) === JSON.stringify(basketRows)) {
    basketLastLoadedAt = Date.now();
    retryPendingImages();
    return;
  }

  basketRows = nextRows;
  basketLastLoadedAt = Date.now();

  if (shouldRender && currentView !== 'paint-basket') {
    return;
  }

  if (shouldRender && !isBackground) {
    renderBasket();
  } else if (shouldRender && isBackground) {
    window.requestAnimationFrame(() => renderBasket());
  }
}

function filteredBasketRows() {
  const term = basketSearch.value.trim().toLowerCase();
  const filtered = term
    ? basketRows.filter(row => {
        const hay = [
          row.product_name, row.brand, row.color_name,
          row.upc, row.product_code, row.size, row.stock_status,
          stockStatusLabel(row.stock_status), row.available_qty,
        ].filter(Boolean).join(' ').toLowerCase();
        return hay.includes(term);
      })
    : basketRows;

  return sortBasketRows(filtered, currentBasketSort, currentBasketSortDir);
}

function renderBasket() {
  const rows = filteredBasketRows();

  // Summary across the full (unfiltered) basket
  const totalScanned = basketRows.reduce((s, r) => s + (r.scanned_qty || 0), 0);
  const uniqueProducts = basketRows.length;
  const matchedProducts = basketRows.filter(r => r.matched_inventory).length;
  const inStockProducts = basketRows.filter(r => r.stock_status === 'in_stock').length;
  const lowStockProducts = basketRows.filter(r => r.stock_status === 'low_stock').length;
  const outOfStockProducts = basketRows.filter(r => r.stock_status === 'out_of_stock').length;
  const missingProducts = basketRows.filter(r => r.stock_status === 'not_in_inventory').length;
  const attentionProducts = lowStockProducts + outOfStockProducts + missingProducts;
  basketKpis.innerHTML = `
    <article class="kpi-card kpi-primary">
      <span class="kpi-label">Total scans</span>
      <strong>${totalScanned}</strong>
      <small>Paint cans counted onsite</small>
    </article>
    <article class="kpi-card">
      <span class="kpi-label">Product codes</span>
      <strong>${uniqueProducts}</strong>
      <small>Unique scanned UPCs</small>
    </article>
    <article class="kpi-card">
      <span class="kpi-label">Matched in inventory</span>
      <strong>${matchedProducts}</strong>
      <small>${inStockProducts} in stock, ${lowStockProducts} low</small>
    </article>
    <article class="kpi-card ${attentionProducts ? 'kpi-attention' : ''}">
      <span class="kpi-label">Need attention</span>
      <strong>${attentionProducts}</strong>
      <small>${outOfStockProducts} out, ${missingProducts} not in inventory</small>
    </article>
  `;

  updateRecordCount(rows.length);

  if (!rows.length) {
    basketTableBody.replaceChildren();
    basketEmpty.hidden = false;
    return;
  }
  basketEmpty.hidden = true;

  const fragment = document.createDocumentFragment();
  for (const row of rows) {
    const tr = document.createElement('tr');
    tr.className = `basket-row row-${row.stock_status || 'unknown'}`;
    const colorSize = [row.color_name, row.size].filter(Boolean).join(' / ');
    const available = row.available_qty === null || row.available_qty === undefined
      ? '—'
      : row.available_qty;

    tr.innerHTML = `
      <td>
        <div class="basket-product-cell">
          ${row.preview_image_path
            ? `<img id="${esc(basketThumbId(row))}" class="basket-thumb" alt="${esc(row.product_name || 'Product scan')}" loading="lazy" />`
            : '<div class="basket-thumb basket-thumb-empty" aria-hidden="true">IMG</div>'}
          <div>
            <div class="basket-product-name">${esc(row.product_name || '(unknown product)')}</div>
            ${colorSize ? `<div class="basket-product-sub">${esc(colorSize)}</div>` : ''}
          </div>
        </div>
      </td>
      <td><code>${esc(row.upc || '—')}</code></td>
      <td>${esc(row.product_code || '—')}</td>
      <td>${esc(row.brand || '—')}</td>
      <td>${esc(colorSize || '—')}</td>
      <td class="num metric-strong">${row.scanned_qty ?? 0}</td>
      <td class="num metric-strong">${esc(available)}</td>
      <td><span class="${esc(stockStatusClass(row.stock_status))}">${esc(stockStatusLabel(row.stock_status))}</span></td>
      <td>${esc(formatShortDate(row.last_scanned_at))}</td>
    `;
    fragment.appendChild(tr);
  }
  basketTableBody.replaceChildren(fragment);
  loadBasketThumbs(rows);
}

function loadBasketThumbs(rows) {
  for (const row of rows) {
    if (row.preview_image_path) {
      loadThumb(basketThumbId(row), row.preview_image_path);
    }
  }
}

// ── CSV Export ─────────────────────────────────────────────────

function exportRecordsCsv() {
  const rows = filteredRecords();

  // Union of all schema fields (ordered, loaded once at init from Supabase).
  // Mixed-equipment rows will leave unrelated columns empty.
  const headers = ['record_type', 'schema_name', 'scanned_at', 'approved_at', ...UNION_FIELDS];
  const lines = [headers];

  for (const record of rows) {
    lines.push([
      record.record_type || '',
      record.schema_name || '',
      recordScannedAt(record),
      recordApprovedAt(record),
      ...UNION_FIELDS.map(k => record._fields?.[k] ?? ''),
    ]);
  }

  downloadCsv(lines, `extraction_records_${new Date().toISOString().slice(0, 10)}.csv`);
}

function exportBasketCsv() {
  const rows = filteredBasketRows();
  const headers = [
    'product_name', 'brand', 'upc', 'product_code', 'color_name', 'size',
    'scanned_qty', 'available_qty', 'reorder_level', 'stock_status', 'matched_inventory',
    'first_scanned_at', 'last_scanned_at',
  ];
  const lines = [headers];
  for (const row of rows) {
    lines.push(headers.map(h => row[h] ?? ''));
  }
  downloadCsv(lines, `paint_basket_${new Date().toISOString().slice(0, 10)}.csv`);
}

function exportSchemasCsv() {
  const headers = [
    'schema_name',
    'display_name',
    'description',
    'fields',
    'prompt_key',
    'prompt_version',
    'schema_version',
    'is_system',
    'client_email',
  ];
  const lines = [headers];
  for (const schema of Object.values(SCHEMAS)) {
    lines.push([
      schema.schema_name || schema.equipment_type || '',
      schema.display_name || '',
      schema.description || '',
      (schema.fields || []).join('|'),
      schema.prompt_key || '',
      schema.prompt_version || '',
      schema.schema_version || '',
      schema.is_system ? 'true' : 'false',
      schema.client_email || '',
    ]);
  }
  downloadCsv(lines, `schema_templates_${new Date().toISOString().slice(0, 10)}.csv`);
}

function downloadCsv(lines, filename) {
  const csv = lines
    .map(line => line.map(v => `"${String(v ?? '').replace(/"/g, '""')}"`).join(','))
    .join('\n');
  const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = filename;
  a.click();
  URL.revokeObjectURL(a.href);
}

// ── Helpers ───────────────────────────────────────────────────

function formatKey(key) {
  return key.replace(/_/g, ' ');
}

function formatShortDate(value) {
  if (!value) return '';
  const d = new Date(value);
  if (isNaN(d)) return '';
  const date = d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
  const time = d.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', hour12: true });
  return `${date}, ${time}`;
}

function esc(value) {
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}
