# Panduan Clone Aplikasi untuk Perusahaan Baru

Arsitektur yang dipakai adalah **satu instalasi terpisah untuk setiap perusahaan**. Dengan pola ini, data, akun, domain, dan deployment perusahaan baru tidak bercampur dengan HMA.

## Yang perlu dibuat terpisah

| Layanan | Perlu terpisah? | Catatan |
|---|---:|---|
| Supabase project | Ya | Wajib; berisi database, Auth, Storage, RPC, dan Edge Function perusahaan tersebut. |
| Vercel project | Ya | Wajib; menghubungkan repo, environment, deployment, dan domain perusahaan tersebut. |
| GitHub repository | Ya | Disarankan; clone/fork repo HMA agar riwayat perubahan tiap perusahaan tidak bercampur. |
| GitHub account | Tidak wajib | Gunakan akun/organization yang sama. Buat akun/organization baru hanya bila kepemilikan akses harus diberikan kepada perusahaan klien. |
| Domain/subdomain | Ya | Contoh `ops.perusahaanbaru.co.id`; pasangkan hanya ke project Vercel perusahaan tersebut. |

## 1. Clone repository

1. Buat repository privat baru dari kode ini.
2. Pastikan file konfigurasi Supabase produksi HMA tidak disalin sebagai kredensial perusahaan baru.
3. Pertahankan struktur file dan riwayat migrasi agar pembaruan berikutnya mudah dibandingkan.

## 2. Ganti identitas di satu tempat

Edit `company-config.js`:

- `legalName`: nama resmi perusahaan.
- `shortName`: singkatan perusahaan.
- `appName` dan `employeeAppName`: judul aplikasi.
- `employeeCodePrefix`: awalan ID, misalnya `CTJ` untuk `CTJ001`.
- `internalAuthDomain`: domain email internal unik, misalnya `accounts.ctj.internal`.
- `authStorageKey`: kunci sesi unik, misalnya `ctj_operations_auth`.
- `logos`: lokasi logo perusahaan.
- `theme`: warna utama perusahaan.

Ganti file logo di folder `assets` atau ubah jalurnya pada `company-config.js`. Jangan memakai `authStorageKey` dan `internalAuthDomain` yang sama bila dua aplikasi dapat dibuka pada domain yang sama.

## 3. Siapkan Supabase baru

1. Buat project Supabase baru di organisasi yang sesuai.
2. Jalankan `supabase/schema.sql` di SQL Editor.
3. Jalankan file dalam `supabase/migrations` menurut urutan nama file.
4. Salin `supabase/company-identity.example.sql`, ganti seluruh `ABC` dengan `employeeCodePrefix`, lalu jalankan **sebelum membuat karyawan pertama**.
5. Deploy Edge Function `create-employee` dari `supabase/functions/create-employee`.
6. Tambahkan secret Edge Function:

   ```text
   COMPANY_INTERNAL_AUTH_DOMAIN=accounts.ctj.internal
   ```

   Nilainya harus sama dengan `internalAuthDomain` pada `company-config.js`.
7. Siapkan akun Super Admin pertama dan profil `admin` sesuai prosedur bootstrap internal.

Catatan penting: publishable/anon key aman digunakan frontend. Jangan pernah memasukkan `service_role` key ke file JavaScript atau GitHub.

## 4. Hubungkan frontend ke Supabase

1. Salin `supabase-config.example.js` menjadi `supabase-config.js`.
2. Isi URL project dan publishable key perusahaan baru.
3. Jangan mengubah nama `window.COMPANY_SUPABASE_CONFIG` pada clone baru.

## 5. Deploy Vercel baru

1. Buat project Vercel baru dari repository perusahaan baru.
2. Deploy dan uji dahulu lewat URL preview Vercel.
3. Tambahkan domain/subdomain perusahaan.
4. Buat record DNS yang diminta Vercel.
5. Setelah status domain valid, uji HTTPS, kamera, GPS, login, dan logout.

## 6. Checklist uji sebelum digunakan

- Judul browser, logo, nama perusahaan, warna, dan copyright sudah benar.
- Login Super Admin berhasil.
- Pembuatan karyawan menghasilkan prefix yang benar, misalnya `CTJ001`.
- Login karyawan berhasil memakai ID tersebut.
- Role Admin, HR, Finance, dan Karyawan hanya melihat menu yang diizinkan.
- Absensi memvalidasi radius, GPS, kamera, dan waktu server.
- Arus kas masuk/keluar, Excel import/export, arsip, pulihkan, dan hapus tervalidasi.
- BBM/KM, laporan tugas, pengajuan, payroll, serta unduhan laporan bekerja.
- Data perusahaan baru tidak muncul di HMA dan sebaliknya.
- Backup database dan daftar pemilik akses sudah ditetapkan.

## Urutan paling aman

Repository baru → konfigurasi identitas → Supabase baru → schema dan migrasi → konfigurasi frontend → uji lokal → Vercel baru → domain → uji produksi.

Jangan menghubungkan clone ke Supabase HMA walaupun hanya untuk percobaan, karena aksi hapus, import, dan perubahan role akan menyentuh data produksi HMA.
