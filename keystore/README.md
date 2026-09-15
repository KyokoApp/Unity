Keystore untuk menandatangani APK release, supaya aplikasi bisa **di-update**
tanpa uninstall dulu.

    berkas   : release.keystore (PKCS12)
    alias    : yuki   (friendlyName di dalam file = AndroidKeyaliasName)
    storepass: yuki123
    keypass  : yuki123
    sertifikat: RSA 2048, subject CN=yuki OU=natsuki O=yuki L=Jakarta C=ID, berlaku s/d 2051

Kenapa file ini ikut di repo: repo ini PRIVAT. Kalau repo jadi publik,
pindahkan ke secret dan isi ANDROID_KEYSTORE_BASE64 + _PASS + KEYALIAS_NAME +
_KEYALIAS_PASS -- langkah "Siapkan keystore tetap" memprioritaskan secret.

Dua hal yang pernah bikin APK tidak bisa dipasang, dan bagaimana file ini
mengatasinya:

1. Tanpa keystore, Unity menandatangani dengan debug keystore yang dibangkitkan
   runner -- BERBEDA TIAP BUILD. Android melihatnya sebagai aplikasi lain, jadi
   install timpa gagal ("app not installed") dan satu-satunya jalan adalah
   uninstall (data hilang). Kunci tetap = update biasa.

2. Versi lama file ini dibuat dengan `PBE-SHA1-3DES` (algoritma legacy). JDK
   yang dipakai Unity 6 menolak/mengeluh soal itu, dan kegagalannya muncul di
   ujung build (Gradle), setelah ~12 menit. Sekarang dibuat dengan
   PBES2 + AES-256-CBC + HMAC-SHA256 -- format default PKCS12 modern:

       python3 - <<'PY'
       from cryptography.hazmat.primitives.asymmetric import rsa
       from cryptography.hazmat.primitives import hashes
       from cryptography.hazmat.primitives.serialization import pkcs12, BestAvailableEncryption
       # ... x509 self-signed, name=b"yuki" (= alias), lalu tulis ke berkas ini
       PY

   Diverifikasi dengan: openssl pkcs12 -info -in release.keystore -passin pass:yuki123
