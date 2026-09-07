(()=>{
  const form=document.getElementById('transactionForm');
  if(!form)return;
  const toast=message=>{const node=document.getElementById('toast');node.textContent=message;node.classList.add('show');setTimeout(()=>node.classList.remove('show'),4200)};
  const amount=value=>Number(String(value??'').replace(/[^0-9]/g,''))||0;
  let saving=false;
  async function saveTransaction(){
    if(saving)return;
    const type=document.getElementById('transactionType').value,choice=document.getElementById('transactionCategory').value,category=choice==='other'?document.getElementById('transactionCustomCategory').value.trim():choice,description=document.getElementById('transactionDescription').value.trim(),nominal=amount(document.getElementById('transactionAmount').value),date=document.getElementById('transactionDate').value,employeeId=document.getElementById('transactionEmployee').value||null,editId=form.dataset.editId||'',button=form.querySelector('[type="submit"]');
    if(!date||!type||!category||!description||nominal<1){toast(!category?'Pilih kategori dana terlebih dahulu.':!description?'Keterangan transaksi wajib diisi.':'Lengkapi tanggal dan nominal transaksi.');return}
    const {data:{user},error:userError}=await window.hmaSupabase.auth.getUser();
    if(userError||!user){toast('Sesi admin berakhir. Silakan masuk kembali.');return}
    saving=true;button.disabled=true;button.textContent='Menyimpan…';
    try{
      let response=editId?await window.hmaSupabase.from('cash_transactions').update({transaction_date:date,type,category,description,amount:nominal,employee_id:employeeId}).eq('id',editId):await window.hmaSupabase.rpc('record_cash_transaction',{p_transaction_date:date,p_type:type,p_category:category,p_description:description,p_amount:nominal,p_employee_id:employeeId});
      if(!editId&&response.error&&['42883','PGRST202'].includes(response.error.code))response=await window.hmaSupabase.from('cash_transactions').insert({transaction_date:date,type,category,description,amount:nominal,employee_id:employeeId});
      if(response.error)throw response.error;
      form.closest('dialog')?.close();document.getElementById('modalBackdrop')?.classList.remove('show');delete form.dataset.editId;document.querySelector('#transactionModal h2').textContent='Catat uang masuk atau keluar';toast(editId?'Revisi transaksi berhasil disimpan. Ringkasan diperbarui otomatis.':`${type==='income'?'Pemasukan':'Pengeluaran'} berhasil disimpan. Ringkasan diperbarui otomatis.`);
      document.getElementById('transactionRefresh')?.click();
    }catch(error){toast(`Transaksi belum tersimpan: ${error.message||'periksa izin akun dan koneksi database.'}`)}finally{saving=false;button.disabled=false;button.textContent=editId?'Simpan revisi':'Simpan arus kas'}
  }
  form.addEventListener('submit',event=>{event.preventDefault();event.stopImmediatePropagation();saveTransaction()},{capture:true});
  form.querySelector('[type="submit"]')?.addEventListener('click',event=>{event.preventDefault();event.stopImmediatePropagation();saveTransaction()},{capture:true});
})();
