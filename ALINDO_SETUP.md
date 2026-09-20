# Setup Alindo — 19 September 2026

- Project Supabase: xydnmspjhsaciyhqestv
- Repo target: https://github.com/bussinesmail17-coder/alindoberkah
- Identitas: PT Alindo Berkah Sekumpul / ABS
- Prefix karyawan: ABS; domain akun: accounts.alindo.internal
- Bootstrap database: supabase/bootstrap-alindo.sql, untuk database kosong saja.
- Terverifikasi: 14 tabel public, seluruhnya RLS aktif; 3 bucket privat; prefix ABS aktif.
- Bootstrap sengaja melewati repair_auth_profiles lama (promosi admin berdasarkan email HMA) dan seed lokasi J&T.
- Migrasi attendance_zones dijalankan sebelum attendance_auto_photo_lateness karena dependensi tipe tabel.
- Lokasi absensi belum diisi. Isi lokasi Alindo sebelum digunakan.
- Email admin yang diminta: bussinesmail17@gmail.com. Akun dan password belum dibuat.
- Git remote lokal masih menunjuk repo HMA lama; belum ada push ke repo baru.
- Logo masih aset HMA; perlu diganti sebelum publikasi.

Jangan jalankan ulang bootstrap setelah database terisi. Gunakan migrasi terpisah untuk perubahan berikutnya.
