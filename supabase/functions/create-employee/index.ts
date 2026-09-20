import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type' }

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  try {
    const token = request.headers.get('Authorization')?.replace('Bearer ', '')
    if (!token) throw new Error('Sesi administrator tidak ditemukan.')
    const url = Deno.env.get('SUPABASE_URL')!
    const serviceRole = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const internalAuthDomain = Deno.env.get('COMPANY_INTERNAL_AUTH_DOMAIN') || 'accounts.hma.internal'
    const admin = createClient(url, serviceRole)
    const { data: authData, error: authError } = await admin.auth.getUser(token)
    if (authError || !authData.user) throw new Error('Sesi administrator tidak valid.')
    const { data: requester } = await admin.from('profiles').select('role').eq('id', authData.user.id).maybeSingle()
    if (!requester || !['admin', 'hr'].includes(requester.role)) {
      throw new Error('Hanya Admin atau HR yang dapat membuat akun karyawan.')
    }
    const body = await request.json()
    if (!body.fullName || !body.password) throw new Error('Nama dan kata sandi awal wajib diisi.')
    if (String(body.password).length < 8) throw new Error('Kata sandi awal minimal 8 karakter.')
    const role = ['employee', 'hr', 'finance', 'admin'].includes(body.role) ? body.role : 'employee'
    if (role !== 'employee' && requester.role !== 'admin') throw new Error('Hanya Super Admin yang dapat membuat akun dengan role HR, Finance, atau Super Admin.')
    const temporaryEmail = `pending-${crypto.randomUUID()}@${internalAuthDomain}`
    const { data: created, error: createError } = await admin.auth.admin.createUser({
      email: temporaryEmail, password: body.password, email_confirm: true, user_metadata: { full_name: body.fullName }
    })
    if (createError || !created.user) throw createError || new Error('Akun tidak dapat dibuat.')
    try {
      const { data: profile, error: profileError } = await admin.from('profiles').select('employee_code').eq('id', created.user.id).single()
      if (profileError || !profile?.employee_code) throw profileError || new Error('ID karyawan tidak dapat dibuat.')
      const internalEmail = `${profile.employee_code.toLowerCase()}@${internalAuthDomain}`
      const { error: authUpdateError } = await admin.auth.admin.updateUserById(created.user.id, { email: internalEmail, email_confirm: true })
      if (authUpdateError) throw authUpdateError
      const { error: profileUpdateError } = await admin.from('profiles').update({
        email: internalEmail, position: body.position || null, phone: null, role
      }).eq('id', created.user.id)
      if (profileUpdateError) throw profileUpdateError
      const roleLabel = { employee: 'Karyawan', hr: 'HR', finance: 'Finance', admin: 'Super Admin' }[role]
      return Response.json({ userId: created.user.id, employeeCode: profile.employee_code, roleLabel }, { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    } catch (error) {
      await admin.auth.admin.deleteUser(created.user.id)
      throw error
    }
  } catch (error) {
    return Response.json({ error: error.message || 'Terjadi kesalahan.' }, { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  }
})
