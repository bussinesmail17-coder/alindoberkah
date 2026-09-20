const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const source=fs.readFileSync('app.js','utf8');
const handler=source.slice(source.indexOf('let transactionSaving=false;'),source.indexOf("document.getElementById('transactionForm').addEventListener('submit',saveCashTransaction);"));
const session=source.split('\n').find(line=>line.startsWith('async function ensureAdminSession()'));
function fixture(role,{edit=false,error=null,sessionError=false}={}){
  const button={},form={dataset:edit?{editId:'existing-id'}:{},querySelector:()=>button};
  const values={transactionType:'expense',transactionCategory:'Biaya BBM Operasional',transactionDescription:'test',transactionAmount:'350.000',transactionDate:'2026-09-19',transactionEmployee:'employee-id'};
  const calls=[],messages=[];
  let closed=0,refreshed=0;
  const context=vm.createContext({document:{getElementById:id=>({value:values[id]})},window:{hmaSupabase:{auth:{getUser:async()=>{if(sessionError)throw Error('Network unavailable');return {data:{user:{id:'user-id',email:'test@example.com'}}}}},from:()=>({select:()=>({eq:()=>({maybeSingle:async()=>({data:{role}})})})}),rpc:async(name,payload)=>{calls.push({name,payload});return {error}}}},parseRupiah:value=>Number(value.replaceAll('.','')),notify:message=>messages.push(message),closeModal:()=>closed++,loadTransactions:async()=>refreshed++});
  vm.runInContext(session+'\n'+handler,context);
  const submit=()=>{const event={currentTarget:form,preventDefault(){}};const pending=context.saveCashTransaction(event);event.currentTarget=null;return pending};
  return {submit,form,button,calls,messages,get closed(){return closed},get refreshed(){return refreshed}};
}
for(const role of ['finance','hr','admin']){
  test(`${role}: save survives event cleanup during async session check`,async()=>{const f=fixture(role);await f.submit();assert.equal(f.calls.length,1);assert.equal(f.calls[0].name,'record_cash_transaction');assert.equal(f.calls[0].payload.p_amount,350000);assert.equal(f.closed,1);assert.equal(f.refreshed,1);assert.equal(f.button.disabled,false)});
  test(`${role}: revision uses only revision RPC`,async()=>{const f=fixture(role,{edit:true});await f.submit();assert.equal(f.calls.length,1);assert.equal(f.calls[0].name,'revise_cash_transaction');assert.equal(f.calls[0].payload.p_transaction_id,'existing-id')});
}
test('double submit sends one write',async()=>{const f=fixture('finance');await Promise.all([f.submit(),f.submit()]);assert.equal(f.calls.length,1)});
test('employee cannot write',async()=>{const f=fixture('employee');await f.submit();assert.equal(f.calls.length,0);assert.equal(f.closed,0)});
test('database denial preserves form and allows retry',async()=>{const f=fixture('hr',{edit:true,error:{code:'42501'}});await f.submit();assert.equal(f.closed,0);assert.equal(f.form.dataset.editId,'existing-id');assert.equal(f.button.disabled,false);assert.match(f.messages[0],/akses Finance dan HR/)});
test('auth network failure is caught and button restored',async()=>{const f=fixture('finance',{sessionError:true});await f.submit();assert.equal(f.calls.length,0);assert.equal(f.closed,0);assert.equal(f.button.disabled,false);assert.match(f.messages[0],/Network unavailable/)});
test('transaction form and save handler are unique',()=>{const html=fs.readFileSync('index.html','utf8');assert.equal((html.match(/id="transactionForm"/g)||[]).length,1);assert.equal((html.match(/id="transactionModal"/g)||[]).length,1);assert.equal((source.match(/getElementById\('transactionForm'\)\.addEventListener\('submit'/g)||[]).length,1)});
test('Petty Cash is available for incoming and outgoing cash',()=>{const match=source.match(/const transactionCategories=\{expense:\[(.*?)\],income:\[(.*?)\]\}/);assert.ok(match);assert.match(match[1],/'Petty Cash'/);assert.match(match[2],/'Petty Cash'/)});
test('cash import template and export use employee names',()=>{assert.match(source,/nama_karyawan:'Contoh Nama Karyawan'/);assert.match(source,/\['Tanggal','Keterangan','Kategori','Jenis','Nominal','Nama Karyawan'\]/);assert.match(source,/cashEmployeeNames\.get\(row\.employeeId\)/)});
