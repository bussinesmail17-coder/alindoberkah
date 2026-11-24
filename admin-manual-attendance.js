/* Super-admin manual attendance entry. */
(function(){
  const actions=document.querySelector('#attendance .page-intro .hero-actions');
  if(!actions)return;
  const button=document.createElement('button');
  button.id='openManualAttendance';button.type='button';button.className='outline-button';
  button.textContent='Input absensi manual';button.hidden=true;actions.prepend(button);
  const dialog=document.createElement('dialog');dialog.id='manualAttendanceModal';
  dialog.innerHTML='<form id="manualAttendanceForm"><div class="modal-head"><div><p>KHUSUS SUPER ADMIN</p><h2>Input absensi manual</h2></div><button type="button" class="close-button" data-close-manual-attendance aria-label="Tutup">×</button></div><p class="muted">Gunakan hanya jika karyawan tidak dapat melakukan absensi dari aplikasi. Data akan tercatat sebagai input manual admin.</p><div class="form-grid"><label>Karyawan<select id="manualAttendanceEmployee" required><option value="">Pilih karyawan</option></select></label><label>Tanggal<input id="manualAttendanceDate" type="date" required></label><label>Jam masuk<input id="manualAttendanceIn" type="datetime-local" required></label><label>Jam pulang<input id="manualAttendanceOut" type="datetime-local"></label><label class="full">Status<select id="manualAttendanceStatus"><option value="submitted">Hadir</option><option value="verified">Terverifikasi</option><option value="rejected">Ditolak</option></select></label><label class="full">Catatan<input id="manualAttendanceNote" maxlength="500" placeholder="Alasan input manual"></label></div><div class="modal-actions"><button type="button" class="outline-button" data-close-manual-attendance>Batal</button><button class="primary-button" type="submit">Simpan absensi</button></div></form>';
  document.body.append(dialog);
  const form=dialog.querySelector('#manualAttendanceForm'),select=dialog.querySelector('#manualAttendanceEmployee');
  function access(){button.hidden=!isSuperAdmin()}
  async function open(){
    if(!await ensureAdminSession()){openAdminLogin();return}
    if(!isSuperAdmin()){notify('Input absensi manual hanya untuk Super Admin.');return}
    const today=jakartaDate();form.reset();dialog.querySelector('#manualAttendanceDate').value=today;
    dialog.querySelector('#manualAttendanceIn').value=today+'T08:00';dialog.querySelector('#manualAttendanceOut').value=today+'T17:00';
    select.disabled=true;
    try{const {data,error}=await window.hmaSupabase.from('profiles').select('id,employee_code,full_name').eq('role','employee').order('full_name');if(error)throw error;select.innerHTML='<option value="">Pilih karyawan</option>'+(data||[]).map(row=>'<option value="'+escapeHtml(row.id)+'">'+escapeHtml(row.employee_code||'—')+' · '+escapeHtml(row.full_name)+'</option>').join('');dialog.showModal();backdrop.classList.add('show')}catch(error){notify(error.message||'Daftar karyawan belum dapat dimuat.')}finally{select.disabled=false}
  }
  function close(){dialog.close();backdrop.classList.remove('show')}
  button.addEventListener('click',open);dialog.querySelectorAll('[data-close-manual-attendance]').forEach(x=>x.addEventListener('click',close));
  form.addEventListener('submit',async event=>{
    event.preventDefault();if(!isSuperAdmin()){notify('Input absensi manual hanya untuk Super Admin.');return}
    const submit=form.querySelector('[type="submit"]'),employee=select.value,date=dialog.querySelector('#manualAttendanceDate').value,checkIn=dialog.querySelector('#manualAttendanceIn').value,checkOut=dialog.querySelector('#manualAttendanceOut').value;
    if(!employee||!date||!checkIn){notify('Karyawan, tanggal, dan jam masuk wajib diisi.');return}
    if(checkOut&&new Date(checkOut)<new Date(checkIn)){notify('Jam pulang tidak boleh sebelum jam masuk.');return}
    submit.disabled=true;submit.textContent='Menyimpan…';
    try{const {error}=await window.hmaSupabase.rpc('create_super_admin_manual_attendance',{p_request_id:crypto.randomUUID(),p_employee_id:employee,p_check_in_at:new Date(checkIn).toISOString(),p_check_out_at:checkOut?new Date(checkOut).toISOString():null,p_verification_status:dialog.querySelector('#manualAttendanceStatus').value,p_note:dialog.querySelector('#manualAttendanceNote').value.trim()||null});if(error)throw error;close();await loadAttendance();notify('Absensi manual berhasil disimpan.')}catch(error){notify(error.code==='23505'?'Absensi karyawan pada tanggal tersebut sudah ada.':error.message||'Absensi manual belum dapat disimpan.')}finally{submit.disabled=false;submit.textContent='Simpan absensi'}
  });
  new MutationObserver(access).observe(document.body,{attributes:true,attributeFilter:['data-workspace-role']});access();
})();
