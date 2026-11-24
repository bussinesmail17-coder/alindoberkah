/* Super-admin courier backup entry. Uses the existing report dialog. */
let backupReportSaving=false;
const backupReportButton=document.createElement('button');
backupReportButton.id='openBackupReport';backupReportButton.type='button';backupReportButton.className='outline-button';
backupReportButton.textContent='Input laporan kurir';backupReportButton.hidden=true;
const reportDownloadButton=document.getElementById('downloadReport');
const backupReportActions=document.createElement('div');backupReportActions.className='hero-actions';
reportDownloadButton.before(backupReportActions);backupReportActions.append(backupReportButton,reportDownloadButton);
function updateBackupReportAccess(){
  const button=document.getElementById('openBackupReport');
  if(button)button.hidden=!isSuperAdmin();
}
function validateBackupReport(form){
  if(!form.reportValidity())throw new Error('Lengkapi data laporan terlebih dahulu.');
  for(const id of ['reportSuccess','reportFailed','reportCod','reportDfod']){
    const value=Number(document.getElementById(id).value);
    if(!Number.isFinite(value)||value<0||((id==='reportSuccess'||id==='reportFailed')&&!Number.isSafeInteger(value)))throw new Error('Jumlah tugas harus bilangan bulat dan nominal tidak boleh negatif.');
  }
  const file=document.getElementById('reportEvidence').files[0];
  if(file&&(!['image/jpeg','image/png','image/webp','image/heic','image/heif'].includes(file.type)||file.size>5242880))throw new Error('Bukti harus berupa foto JPG, PNG, WebP, HEIC/HEIF maksimal 5 MB.');
  if(!document.getElementById('reportBackupReason').value.trim())throw new Error('Isi alasan input cadangan.');
  return file;
}
async function saveBackupReport(event){
  event.preventDefault();
  const form=event.currentTarget,submit=form.querySelector('[type="submit"]');
  if(backupReportSaving)return;
  backupReportSaving=true;submit.disabled=true;submit.textContent='Menyimpan…';
  try{
    if(!await ensureAdminSession()||!isSuperAdmin())throw new Error('Input cadangan hanya untuk Super Admin. Silakan periksa sesi Anda.');
    const file=validateBackupReport(form),client=window.hmaSupabase;
    const {data:{user},error:authError}=await client.auth.getUser();
    if(authError)throw authError;
    if(!user)throw new Error('Sesi berakhir. Silakan masuk kembali.');
    const requestId=form.dataset.requestId||(form.dataset.requestId=crypto.randomUUID());
    let evidencePath=form.dataset.evidencePath||null;
    if(file&&!evidencePath){
      const extension={'image/jpeg':'jpg','image/png':'png','image/webp':'webp','image/heic':'heic','image/heif':'heif'}[file.type];
      evidencePath=`${user.id}/backup/${requestId}.${extension}`;
      const upload=await client.storage.from('report-evidence').upload(evidencePath,file,{contentType:file.type,upsert:false});
      if(upload.error)throw upload.error;
      form.dataset.evidencePath=evidencePath;
    }
    const {error}=await client.rpc('create_super_admin_backup_report',{
      p_request_id:requestId,p_employee_id:document.getElementById('reportDriver').value,
      p_report_date:document.getElementById('reportDate').value,p_title:document.getElementById('reportRoute').value.trim(),
      p_description:document.getElementById('reportNotes').value.trim(),p_reason:document.getElementById('reportBackupReason').value.trim(),
      p_success_count:Number(document.getElementById('reportSuccess').value),p_failed_count:Number(document.getElementById('reportFailed').value),
      p_cod_amount:Number(document.getElementById('reportCod').value),p_dfod_amount:Number(document.getElementById('reportDfod').value),p_evidence_path:evidencePath
    });
    if(error)throw error;
    const date=document.getElementById('reportDate').value;
    closeReportModal();
    delete form.dataset.requestId;delete form.dataset.evidencePath;
    const from=document.getElementById('reportFrom'),to=document.getElementById('reportTo');
    if(from.value&&date<from.value)from.value=date;
    if(to.value&&date>to.value)to.value=date;
    notify('Laporan cadangan berhasil disimpan atas nama kurir dan menunggu peninjauan.');
    await loadReports();
  }catch(error){
    // Keep the request ID and uploaded evidence for safe retries after uncertain network outcomes.
    notify(['PGRST202','42883'].includes(error.code)?'Fitur input cadangan belum aktif di database. Jalankan migrasi laporan cadangan terlebih dahulu.':(error.message||'Laporan belum dapat disimpan.'));
  }finally{backupReportSaving=false;submit.disabled=false;submit.textContent='Simpan laporan cadangan'}
}
document.getElementById('reportForm').addEventListener('submit',saveBackupReport);
document.getElementById('openBackupReport').addEventListener('click',openReportModal);
new MutationObserver(updateBackupReportAccess).observe(document.body,{attributes:true,attributeFilter:['data-workspace-role']});
updateBackupReportAccess();
