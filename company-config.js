/*
 * Identitas perusahaan untuk satu deployment.
 * Saat aplikasi di-clone, ubah nilai di file ini dan ganti aset logo yang
 * dirujuk di bawah.
 */
window.COMPANY_CONFIG = Object.freeze({
  legalName: 'PT Alindo Berkah Sekumpul',
  shortName: 'ABS',
  operationsLabel: 'OPERATIONS',
  employeeLabel: 'KARYAWAN',
  appName: 'ABS Operations',
  employeeAppName: 'ABS Karyawan',
  employeeCodePrefix: 'ABS',
  internalAuthDomain: 'accounts.alindo.internal',
  authStorageKey: 'alindo_operations_auth',
  developerName: 'Movetra.id',
  logos: {
    favicon: 'assets/abs-logo.png',
    sidebar: 'assets/abs-logo.png',
    primary: 'assets/abs-logo.png',
    employeeLogin: 'assets/abs-logo.png'
  },
  theme: {
    navy: '#006b2d',
    accent: '#17a84b',
    blue: '#0b8f43'
  }
});
