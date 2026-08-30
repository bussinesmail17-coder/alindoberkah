/**
 * HMA Operations — Google Sheets Sync API
 *
 * Tambahkan file ini ke proyek Apps Script yang terikat pada Spreadsheet HMA.
 * Jangan menyimpan password aplikasi di Sheet. Autentikasi ditangani Supabase.
 * Set Script Property HMA_SYNC_TOKEN dengan token acak panjang sebelum deploy.
 */

const HMA_SYNC_SHEETS = {
  Employees: { idColumn: 'ID' },
  Transactions: { idColumn: 'ID' },
  Fleets: { idColumn: 'Plat' },
  Attendance: { idColumn: 'ID' },
  WorkReports: { idColumn: 'ID' },
  Payroll: { idColumn: 'ID' }
};

function doPost(e) {
  try {
    const request = parseSyncRequest_(e);
    assertSyncToken_(request.token);
    ensureSyncColumns_();

    if (request.action === 'pull') {
      return json_(readOperationalSheets_());
    }
    if (request.action === 'upsert') {
      return json_(upsertOperationalRow_(request.sheet, request.record || {}, request.source || 'app'));
    }
    return json_({ ok: false, error: 'Aksi sinkronisasi tidak dikenal.' });
  } catch (error) {
    return json_({ ok: false, error: error.message || String(error) });
  }
}

/** Memungkinkan API baru tanpa menghapus halaman web app lama. */
function hmaSyncHealthCheck() {
  ensureSyncColumns_();
  return { ok: true, sheets: Object.keys(HMA_SYNC_SHEETS), updatedAt: new Date().toISOString() };
}

function parseSyncRequest_(e) {
  if (!e || !e.postData || !e.postData.contents) throw new Error('Payload JSON wajib dikirim.');
  return JSON.parse(e.postData.contents);
}

function assertSyncToken_(token) {
  const expected = PropertiesService.getScriptProperties().getProperty('HMA_SYNC_TOKEN');
  if (!expected) throw new Error('HMA_SYNC_TOKEN belum diatur pada Script Properties.');
  if (!token || token !== expected) throw new Error('Token sinkronisasi tidak valid.');
}

function ensureSyncColumns_() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  Object.keys(HMA_SYNC_SHEETS).forEach(name => {
    const sheet = ss.getSheetByName(name);
    if (!sheet) return;
    const headers = sheet.getRange(1, 1, 1, Math.max(sheet.getLastColumn(), 1)).getValues()[0].map(String);
    ['Updated_At', 'Source'].forEach(column => {
      if (headers.indexOf(column) === -1) {
        sheet.getRange(1, headers.length + 1).setValue(column);
        headers.push(column);
      }
    });
  });
}

function readOperationalSheets_() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const tables = {};
  Object.keys(HMA_SYNC_SHEETS).forEach(name => {
    const sheet = ss.getSheetByName(name);
    if (!sheet || sheet.getLastRow() < 2) {
      tables[name] = [];
      return;
    }
    const values = sheet.getDataRange().getValues();
    const headers = values[0].map(String);
    tables[name] = values.slice(1).filter(row => row.some(value => value !== '')).map(row => rowToObject_(headers, row));
  });
  return { ok: true, pulledAt: new Date().toISOString(), tables };
}

function upsertOperationalRow_(sheetName, record, source) {
  const rule = HMA_SYNC_SHEETS[sheetName];
  if (!rule) throw new Error('Sheet tidak diizinkan untuk sinkronisasi: ' + sheetName);
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const sheet = ss.getSheetByName(sheetName);
  if (!sheet) throw new Error('Sheet tidak ditemukan: ' + sheetName);
  const lock = LockService.getScriptLock();
  lock.waitLock(10000);
  try {
    const values = sheet.getDataRange().getValues();
    const headers = values[0].map(String);
    const idIndex = headers.indexOf(rule.idColumn);
    if (idIndex === -1) throw new Error('Kolom ID tidak ditemukan: ' + rule.idColumn);
    const identifier = String(record[rule.idColumn] || '').trim();
    if (!identifier) throw new Error('Nilai ' + rule.idColumn + ' wajib diisi.');
    const updatedIndex = headers.indexOf('Updated_At');
    const sourceIndex = headers.indexOf('Source');
    const existing = values.slice(1).findIndex(row => String(row[idIndex]).trim() === identifier);
    const targetRow = existing === -1 ? sheet.getLastRow() + 1 : existing + 2;
    const row = headers.map((header, index) => {
      if (header === 'Updated_At') return new Date().toISOString();
      if (header === 'Source') return source;
      if (Object.prototype.hasOwnProperty.call(record, header)) return record[header];
      return existing === -1 ? '' : values[existing + 1][index];
    });
    sheet.getRange(targetRow, 1, 1, headers.length).setValues([row]);
    SpreadsheetApp.flush();
    return { ok: true, action: existing === -1 ? 'inserted' : 'updated', sheet: sheetName, record: rowToObject_(headers, row) };
  } finally {
    lock.releaseLock();
  }
}

function rowToObject_(headers, row) {
  return headers.reduce((object, header, index) => {
    const value = row[index];
    object[header] = value instanceof Date ? value.toISOString() : value;
    return object;
  }, {});
}

function json_(payload) {
  return ContentService.createTextOutput(JSON.stringify(payload)).setMimeType(ContentService.MimeType.JSON);
}
