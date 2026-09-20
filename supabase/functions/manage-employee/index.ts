import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type' }

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  try {
    const token = request.headers.get('Authorization')?.replace('Bearer ', '')
    if (!token) throw new Error('Sesi administrator tidak ditemukan.')
    const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!)
    const { data: authData, error: authError } = await admin.auth.getUser(token)
    if (authError || !authData.user) throw new Error('Sesi administrator tidak valid.')
    const { data: requester } = await admin.from('profiles').select('role').eq('id', authData.user.id).maybeSingle()
    if (!requester || requester.role !== 'admin') throw new Error('Hanya Super Admin yang dapat mengelola akun karyawan.')

    const body = await request.json()
    if (!body.employeeId || !['reset_password', 'delete'].includes(body.action)) throw new Error('Permintaan pengelolaan akun tidak valid.')
    if (body.employeeId === authData.user.id) throw new Error('Akun administrator aktif tidak dapat diubah dari menu karyawan.')
    const { data: target, error: targetError } = await admin.from('profiles').select('role,employee_code').eq('id', body.employeeId).single()
    if (targetError || !target) throw new Error('Akun karyawan tidak ditemukan.')
    if (target.role !== 'employee') throw new Error('Hanya akun karyawan yang dapat dikelola dari menu ini.')

    if (body.action === 'reset_password') {
      if (!body.password || String(body.password).length < 8) throw new Error('Kata sandi baru minimal 8 karakter.')
      const { error } = await admin.auth.admin.updateUserById(body.employeeId, { password: body.password })
      if (error) throw error
      return Response.json({ message: `Kata sandi ${target.employee_code} berhasil diperbarui.` }, { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    const { error: deleteError } = await admin.auth.admin.deleteUser(body.employeeId)
    if (deleteError) throw deleteError
    return Response.json({ message: `Akun ${target.employee_code} berhasil dihapus.` }, { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  } catch (error) {
    return Response.json({ error: error.message || 'Terjadi kesalahan.' }, { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  }
})
