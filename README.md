# HMA Operations

Antarmuka operasional PT Hazard Maju Abadi untuk administrator dan karyawan. Administrator memakai `index.html`; karyawan memakai `employee.html` dengan tampilan mobile-first.

## Menjalankan secara lokal

Di PowerShell, dari folder ini jalankan:

```powershell
npx serve .
```

Lalu buka alamat yang ditampilkan (umumnya `http://localhost:3000`).

## Backend Supabase

Project Supabase telah disiapkan untuk data karyawan, absensi, laporan kerja, BBM/KM, arus kas, payroll, dan foto selfie privat. Definisi database tersimpan di `supabase/schema.sql`.

- `employee.html` akan mengunggah selfie ke bucket privat dan membuat data absensi setelah pengguna masuk dengan Supabase Auth.
- Administrator masuk melalui tombol **Masuk** di panel admin. Form **Tim & Akses → Tambah karyawan** memanggil Edge Function `create-employee`; fungsi ini memverifikasi peran Admin/HR di server sebelum membuat akun.
- Setiap akun karyawan baru mendapat ID internal berurutan dari database: `HMA001`, `HMA002`, dan seterusnya. Password awal hanya diproses oleh server dan tidak disimpan di tabel aplikasi.
- Waktu absensi ditetapkan ulang oleh database (bukan jam perangkat) dan satu karyawan hanya dapat check-in sekali per hari WIB.
- Lokasi serta akurasi GPS tersimpan bersama absensi. HTTPS wajib untuk kamera dan GPS.
- Kunci browser di `supabase-config.js` adalah publishable key; jangan pernah menaruh `service_role` key di frontend.

Sebelum operasional, buat akun admin dan akun karyawan melalui Supabase Authentication, lalu masukkan profilnya pada tabel `profiles`. Aplikasi admin masih memakai data demo untuk tabel/rekapan; tahap berikutnya adalah mengganti sumber data demo tersebut dengan query Supabase per modul.
