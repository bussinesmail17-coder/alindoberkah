(function () {
  const config = window.COMPANY_CONFIG || {};
  const shortName = config.shortName || 'HMA';
  const prefix = String(config.employeeCodePrefix || shortName).toUpperCase();
  const logos = config.logos || {};

  const textValues = {
    legalName: config.legalName || shortName,
    shortName,
    operationsLabel: config.operationsLabel || 'OPERATIONS',
    employeeLabel: config.employeeLabel || 'KARYAWAN',
    appName: config.appName || `${shortName} Operations`,
    employeeAppName: config.employeeAppName || `${shortName} Karyawan`,
    developerName: config.developerName || '',
    employeeExample: `${prefix}001`
  };

  document.querySelectorAll('[data-company-text]').forEach((element) => {
    const value = textValues[element.dataset.companyText];
    if (value !== undefined) element.textContent = value;
  });

  document.querySelectorAll('[data-company-logo]').forEach((image) => {
    const source = logos[image.dataset.companyLogo];
    if (source) image.src = source;
    image.alt = `Logo ${textValues.legalName}`;
  });

  document.querySelectorAll('[data-company-placeholder="employee-id"]').forEach((input) => {
    input.placeholder = input.dataset.placeholderPrefix
      ? `${input.dataset.placeholderPrefix} ${textValues.employeeExample}`
      : textValues.employeeExample;
  });

  const favicon = document.querySelector('link[rel="icon"]');
  if (favicon && logos.favicon) favicon.href = logos.favicon;
  const page = document.body.dataset.companyPage;
  document.title = page === 'employee' ? textValues.employeeAppName : textValues.appName;

  const root = document.documentElement;
  if (config.theme?.navy) root.style.setProperty('--navy', config.theme.navy);
  if (config.theme?.accent) {
    root.style.setProperty('--teal', config.theme.accent);
    root.style.setProperty('--red', config.theme.accent);
  }
  if (config.theme?.blue) root.style.setProperty('--blue', config.theme.blue);

  window.companyIdentity = Object.freeze({
    ...textValues,
    employeeCodePrefix: prefix,
    internalAuthDomain: config.internalAuthDomain || 'accounts.hma.internal',
    employeeCodePattern: new RegExp(`^${prefix.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\d{3,}$`, 'i'),
    internalAuthEmail(employeeCode) {
      return `${String(employeeCode).trim().toLowerCase()}@${this.internalAuthDomain}`;
    }
  });

  // Employee data is rendered after authentication; keep the company suffix
  // in sync when those fields are updated asynchronously.
  ['employeeProfileRole', 'profileDataPosition'].forEach((id) => {
    const element = document.getElementById(id);
    if (!element) return;
    const normalize = () => {
      const next = element.textContent.replace(/·\s*[^·]+$/, `· ${shortName}`);
      if (next !== element.textContent) element.textContent = next;
    };
    normalize();
    new MutationObserver(normalize).observe(element, { childList: true, characterData: true, subtree: true });
  });
})();
