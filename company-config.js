/*
 * Identitas perusahaan untuk satu deployment.
 * Saat aplikasi di-clone, ubah nilai di file ini dan ganti aset logo yang
 * dirujuk di bawah. Nilai HMA dipertahankan sebagai default untuk produksi.
 */
window.COMPANY_CONFIG = Object.freeze({
  legalName: 'PT Hazard Maju Abadi',
  shortName: 'HMA',
  operationsLabel: 'OPERATIONS',
  employeeLabel: 'KARYAWAN',
  appName: 'HMA Operations',
  employeeAppName: 'HMA Karyawan',
  employeeCodePrefix: 'HMA',
  internalAuthDomain: 'accounts.hma.internal',
  authStorageKey: 'hma_operations_auth',
  developerName: 'Movetra.id',
  logos: {
    favicon: 'assets/hma-logo.png',
    sidebar: 'assets/hma-logo-white.png',
    primary: 'assets/hma-logo-color-transparent.png',
    employeeLogin: 'assets/hma-app-logo.png'
  },
  theme: {
    navy: '#082d60',
    accent: '#c8102e',
    blue: '#285a9c'
  }
});
