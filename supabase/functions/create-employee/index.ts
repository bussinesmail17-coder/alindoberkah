import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type' }

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  try {
    const token = request.headers.get('Authorization')?.replace('Bearer ', '')
    if (!token) throw new Error('Sesi administrator tidak ditemukan.')
    const url = Deno.env.get('SUPABASE_URL')!
    const serviceRole = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const admin = createClient(url, serviceRole)
    const { data: authData, error: authError } = await admin.auth.getUser(token)
    if (authError || !authData.user) throw new Error('Sesi administrator tidak valid.')
    const { data: requester } = await admin.from('profiles').select('role').eq('id', authData.user.id).maybeSingle()
    const primaryAdmin = authData.user.email?.toLowerCase() === 'bussinesmail17@gmail.com'
    if (!primaryAdmin && (!requester || !['admin', 'hr'].includes(requester.role))) {
      throw new Error('Hanya Admin atau HR yang dapat membuat akun karyawan.')
    }
    const body = await request.json()
    if (!body.fullName || !body.email || !body.password) throw new Error('Nama, email, dan kata sandi awal wajib diisi.')
    const { data: created, error: createError } = await admin.auth.admin.createUser({
      email: body.email, password: body.password, email_confirm: true, user_metadata: { full_name: body.fullName }
    })
    if (createError || !created.user) throw createError || new Error('Akun tidak dapat dibuat.')
    const { data: profile, error: profileError } = await admin.from('profiles').update({
      position: body.position || null, phone: body.phone || null, base_salary: Number(body.baseSalary) || 0
    }).eq('id', created.user.id).select('employee_code').single()
    if (profileError) throw profileError
    return Response.json({ employeeCode: profile.employee_code }, { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  } catch (error) {
    return Response.json({ error: error.message || 'Terjadi kesalahan.' }, { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  }
})
